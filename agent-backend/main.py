import asyncio
import collections.abc
import decimal
import inspect
import contextlib
import json
import logging
import math
import os
import re
import statistics
import time
import uuid
from enum import Enum
from typing import Any

import numpy as np
import talib

import agentscope
import httpx
from agentscope.message import Msg, TextBlock, ToolResultBlock, ToolUseBlock
from agentscope.memory import InMemoryMemory
from agentscope.model import ChatModelBase
from agentscope.tool import ToolResponse, Toolkit
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field
from web3 import Web3

app = FastAPI()
logger = logging.getLogger("agent-backend")

# Placeholder for AgentScope Initialization
def init_agents():
    load_dotenv()
    agentscope.init(
        project=os.getenv("AGENT_BACKEND_PROJECT", "paix"),
        name=os.getenv("AGENT_BACKEND_RUN_NAME", "agent-backend"),
        logging_path=os.getenv("AGENT_BACKEND_LOG_PATH"),
        logging_level=os.getenv("AGENT_BACKEND_LOG_LEVEL", "INFO"),
        studio_url=os.getenv("AGENT_BACKEND_STUDIO_URL"),
        tracing_url=os.getenv("AGENT_BACKEND_TRACING_URL"),
    )


class Action(BaseModel):
    type: str
    params: dict[str, Any] = Field(default_factory=dict)


_DEMO_ACTION_TYPES: set[str] = {
    "start_dca",
    "start_grid",
    "start_mean_reversion",
    "start_martingale",
    "none",
}


def _normalize_demo_action_type(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None

    s = raw.strip().lower()
    if not s:
        return None

    s = s.replace("-", "_").replace(" ", "_")

    if s in _DEMO_ACTION_TYPES:
        return s

    # Common variants / aliases
    if s in {"dca", "smart_dca", "intelligent_dca", "ai_dca", "start_smart_dca"}:
        return "start_dca"
    if s in {"grid", "grid_trading", "start_grid_trading"}:
        return "start_grid"
    if s in {"mean_reversion", "meanreversion", "start_meanreversion"}:
        return "start_mean_reversion"
    if s in {"martingale", "start_martingale_strategy"}:
        return "start_martingale"
    if s in {"wait", "hold", "no_trade", "observe", "none_strategy"}:
        return "none"

    return None


def _demo_strategy_label(action_type: str | None) -> str:
    t = action_type or "none"
    if t == "start_dca":
        return "智能DCA"
    if t == "start_grid":
        return "网格"
    if t == "start_mean_reversion":
        return "均值回归"
    if t == "start_martingale":
        return "马丁格尔"
    return "暂时观望"


class ChatRequest(BaseModel):
    user_input: str
    session_id: str | None = None


class ChatResponse(BaseModel):
    session_id: str
    assistant_text: str
    actions: list[Action] = Field(default_factory=list)
    execution_preview: dict[str, Any] | None = None
    execution_plan: dict[str, Any] | None = None
    strategy_type: str | None = None
    strategy_label: str | None = None


_BUY_PAS_TOKEN_RE = re.compile(
    r"(?:^|\s)(?:给我|帮我)?(?:买|购买|buy)\s*(?P<amount>\d+(?:\.\d+)?)\s*PAS\s*(?:的)?\s*(?P<token>[A-Za-z][A-Za-z0-9_\-]{1,63})(?:\b|$)"
    r"|(?:^|\s)(?:用|拿)\s*(?P<amount2>\d+(?:\.\d+)?)\s*PAS\s*(?:去|来)?\s*(?:买|购买|buy)\s*(?P<token2>[A-Za-z][A-Za-z0-9_\-]{1,63})(?:\b|$)",
    re.IGNORECASE,
)


def _extract_buy_pas_token_intent(user_input: str) -> tuple[str, str] | None:
    text = (user_input or "").strip()
    if not text:
        return None

    m = _BUY_PAS_TOKEN_RE.search(text)
    if not m:
        return None

    amount = (m.group("amount") or m.group("amount2") or "").strip()
    token = (m.group("token") or m.group("token2") or "").strip()
    if not amount or not token:
        return None

    try:
        amt = decimal.Decimal(amount)
    except Exception:
        return None

    if amt <= 0:
        return None

    normalized = format(amt.normalize(), "f")
    if "." in normalized:
        normalized = normalized.rstrip("0").rstrip(".")
    return (normalized, token)


def _build_buy_execution_plan(amount_in_pas: str, token_out_symbol: str) -> dict[str, Any]:
    router = os.getenv("AGENT_BACKEND_UNISWAP_V2_ROUTER", _DEFAULT_UNISWAP_ROUTER).strip()
    weth = os.getenv("AGENT_BACKEND_WETH9", _DEFAULT_UNISWAP_WETH9).strip()
    token_demo = os.getenv("AGENT_BACKEND_TOKENDEMO", _DEFAULT_TOKENDEMO).strip()

    return {
        "type": "buy_token",
        "version": 1,
        "amount_in_pas": amount_in_pas,
        "token_out": {"symbol": token_out_symbol, "address": token_demo or None},
        "origin": {
            "chain": "asset_hub_paseo",
            "parachain_id": 1000,
            "substrate_ws": "wss://sys.ibp.network/asset-hub-paseo",
            "asset": "PAS",
        },
        "destination": {
            "chain": "passet_hub",
            "parachain_id": 1111,
            "evm_rpc": "https://testnet-passet-hub-eth-rpc.polkadot.io",
        },
        "risk_controls": {"slippage_bps": 100, "deadline_seconds": 600},
        "requires_user_confirmation": True,
        "steps": [
            {
                "id": "xcm_bridge_pas",
                "kind": "xcm_transfer",
                "requires_local_signature": True,
                "from_parachain_id": 1000,
                "to_parachain_id": 1111,
                "asset": "PAS",
                "amount": amount_in_pas,
            },
            {
                "id": "swap_pas_to_token",
                "kind": "uniswap_v2_swap",
                "requires_local_signature": True,
                "evm_rpc": "https://testnet-passet-hub-eth-rpc.polkadot.io",
                "router": router or None,
                "weth": weth or None,
                "token_out": {"symbol": token_out_symbol, "address": token_demo or None},
            },
        ],
    }


class CrossChainConnectorType(str, Enum):
    xcm = "xcm"
    hyperbridge_ismp = "hyperbridge_ismp"


class CrossChainGoalType(str, Enum):
    deposit = "deposit"
    withdraw = "withdraw"
    path_c_roundtrip = "path_c_roundtrip"


class CrossChainAssetKind(str, Enum):
    native = "native"
    erc20 = "erc20"


class CrossChainLifecycleState(str, Enum):
    created = "created"
    pending = "pending"
    settled = "settled"
    failed = "failed"
    cancelled = "cancelled"
    refunded = "refunded"


class CrossChainTarget(BaseModel):
    connector: CrossChainConnectorType
    destination: str


class CrossChainAsset(BaseModel):
    kind: CrossChainAssetKind
    amount: str
    token_address: str | None = None


class CrossChainIntentCreateRequest(BaseModel):
    client_request_id: str | None = None
    session_id: str | None = None
    goal: CrossChainGoalType
    target: CrossChainTarget
    asset: CrossChainAsset
    timeout_seconds: int | None = None


class CrossChainIntentEvent(BaseModel):
    timestamp_unix_s: float
    state: CrossChainLifecycleState
    detail: str | None = None
    message_id: str | None = None


class CrossChainIntentRecord(BaseModel):
    intent_id: str
    client_request_id: str | None = None
    session_id: str | None = None
    goal: CrossChainGoalType
    target: CrossChainTarget
    asset: CrossChainAsset
    state: CrossChainLifecycleState
    dispatch_id: str | None = None
    created_unix_s: float
    expires_unix_s: float | None = None
    events: list[CrossChainIntentEvent] = Field(default_factory=list)


class CrossChainInboundRequest(BaseModel):
    connector: CrossChainConnectorType
    intent_id: str
    message_id: str
    status: str
    verified: bool = False
    detail: str | None = None


class _CrossChainConnector:
    def __init__(self, connector_type: CrossChainConnectorType) -> None:
        self.connector_type = connector_type

    async def dispatch(self, intent: CrossChainIntentRecord) -> str:
        _ = intent
        return uuid.uuid4().hex

    async def verify_inbound(self, inbound: CrossChainInboundRequest) -> bool:
        return bool(inbound.verified)


class _CrossChainIntentStore:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._intents: dict[str, CrossChainIntentRecord] = {}
        self._client_request_index: dict[str, str] = {}
        self._applied_message_ids: set[str] = set()

    def _apply_timeout_if_needed(self, intent: CrossChainIntentRecord) -> None:
        if intent.state != CrossChainLifecycleState.pending:
            return
        if intent.expires_unix_s is None:
            return
        if time.time() < intent.expires_unix_s:
            return
        intent.state = CrossChainLifecycleState.failed
        intent.events.append(
            CrossChainIntentEvent(
                timestamp_unix_s=time.time(),
                state=CrossChainLifecycleState.failed,
                detail="timeout",
            )
        )

    async def create_intent(self, req: CrossChainIntentCreateRequest) -> CrossChainIntentRecord:
        async with self._lock:
            if req.client_request_id and req.client_request_id in self._client_request_index:
                existing_id = self._client_request_index[req.client_request_id]
                existing = self._intents.get(existing_id)
                if existing is not None:
                    self._apply_timeout_if_needed(existing)
                    return existing

            now = time.time()
            intent_id = uuid.uuid4().hex
            expires = None
            if req.timeout_seconds is not None:
                expires = now + float(max(1, int(req.timeout_seconds)))

            intent = CrossChainIntentRecord(
                intent_id=intent_id,
                client_request_id=req.client_request_id,
                session_id=req.session_id,
                goal=req.goal,
                target=req.target,
                asset=req.asset,
                state=CrossChainLifecycleState.created,
                dispatch_id=None,
                created_unix_s=now,
                expires_unix_s=expires,
                events=[CrossChainIntentEvent(timestamp_unix_s=now, state=CrossChainLifecycleState.created)],
            )
            self._intents[intent_id] = intent
            if req.client_request_id:
                self._client_request_index[req.client_request_id] = intent_id
            return intent

    async def set_dispatched(self, intent_id: str, dispatch_id: str) -> CrossChainIntentRecord:
        async with self._lock:
            intent = self._intents.get(intent_id)
            if intent is None:
                raise KeyError("intent_not_found")
            self._apply_timeout_if_needed(intent)
            if intent.state == CrossChainLifecycleState.created:
                intent.state = CrossChainLifecycleState.pending
                intent.dispatch_id = dispatch_id
                intent.events.append(
                    CrossChainIntentEvent(timestamp_unix_s=time.time(), state=CrossChainLifecycleState.pending)
                )
            return intent

    async def get_intent(self, intent_id: str) -> CrossChainIntentRecord | None:
        async with self._lock:
            intent = self._intents.get(intent_id)
            if intent is None:
                return None
            self._apply_timeout_if_needed(intent)
            return intent

    async def cancel_intent(self, intent_id: str) -> CrossChainIntentRecord:
        async with self._lock:
            intent = self._intents.get(intent_id)
            if intent is None:
                raise KeyError("intent_not_found")
            self._apply_timeout_if_needed(intent)
            if intent.state not in {CrossChainLifecycleState.created, CrossChainLifecycleState.pending}:
                raise ValueError("cannot_cancel")
            intent.state = CrossChainLifecycleState.cancelled
            intent.events.append(
                CrossChainIntentEvent(timestamp_unix_s=time.time(), state=CrossChainLifecycleState.cancelled)
            )
            return intent

    async def refund_intent(self, intent_id: str) -> CrossChainIntentRecord:
        async with self._lock:
            intent = self._intents.get(intent_id)
            if intent is None:
                raise KeyError("intent_not_found")
            self._apply_timeout_if_needed(intent)
            if intent.state != CrossChainLifecycleState.failed:
                raise ValueError("cannot_refund")
            intent.state = CrossChainLifecycleState.refunded
            intent.events.append(
                CrossChainIntentEvent(timestamp_unix_s=time.time(), state=CrossChainLifecycleState.refunded)
            )
            return intent

    async def apply_inbound(self, inbound: CrossChainInboundRequest) -> tuple[CrossChainIntentRecord, bool]:
        async with self._lock:
            dedupe_key = f"{inbound.connector.value}:{inbound.message_id}"
            if dedupe_key in self._applied_message_ids:
                existing = self._intents.get(inbound.intent_id)
                if existing is None:
                    raise KeyError("intent_not_found")
                self._apply_timeout_if_needed(existing)
                return existing, False

            intent = self._intents.get(inbound.intent_id)
            if intent is None:
                raise KeyError("intent_not_found")
            self._apply_timeout_if_needed(intent)

            now = time.time()
            status = (inbound.status or "").strip().lower()
            terminal_states = {
                CrossChainLifecycleState.settled,
                CrossChainLifecycleState.cancelled,
                CrossChainLifecycleState.refunded,
            }
            intent.events.append(
                CrossChainIntentEvent(
                    timestamp_unix_s=now,
                    state=intent.state,
                    detail=inbound.detail or status,
                    message_id=inbound.message_id,
                )
            )

            if intent.state not in terminal_states:
                if status in {"execution_completed"}:
                    pass
                elif status in {"return_completed", "settled"}:
                    intent.state = CrossChainLifecycleState.settled
                    intent.events.append(
                        CrossChainIntentEvent(
                            timestamp_unix_s=now,
                            state=CrossChainLifecycleState.settled,
                            detail=inbound.detail or status,
                            message_id=inbound.message_id,
                        )
                    )
                elif status in {"failed"}:
                    intent.state = CrossChainLifecycleState.failed
                    intent.events.append(
                        CrossChainIntentEvent(
                            timestamp_unix_s=now,
                            state=CrossChainLifecycleState.failed,
                            detail=inbound.detail or status,
                            message_id=inbound.message_id,
                        )
                    )

            self._applied_message_ids.add(dedupe_key)
            return intent, True


class _CrossChainService:
    def __init__(self) -> None:
        self.store = _CrossChainIntentStore()
        self.connectors: dict[CrossChainConnectorType, _CrossChainConnector] = {
            CrossChainConnectorType.xcm: _CrossChainConnector(CrossChainConnectorType.xcm),
            CrossChainConnectorType.hyperbridge_ismp: _CrossChainConnector(CrossChainConnectorType.hyperbridge_ismp),
        }

    def _connector(self, connector_type: CrossChainConnectorType) -> _CrossChainConnector:
        c = self.connectors.get(connector_type)
        if c is None:
            raise ValueError("unsupported_connector")
        return c

    async def create_and_dispatch(self, req: CrossChainIntentCreateRequest) -> CrossChainIntentRecord:
        intent = await self.store.create_intent(req)
        if intent.state == CrossChainLifecycleState.created:
            connector = self._connector(intent.target.connector)
            dispatch_id = await connector.dispatch(intent)
            intent = await self.store.set_dispatched(intent.intent_id, dispatch_id)
        return intent

    async def apply_verified_inbound(self, inbound: CrossChainInboundRequest) -> tuple[CrossChainIntentRecord, bool]:
        connector = self._connector(inbound.connector)
        ok = await connector.verify_inbound(inbound)
        if not ok:
            raise ValueError("unverified_inbound")
        return await self.store.apply_inbound(inbound)


class _AssistantTextJsonExtractor:
    def __init__(self) -> None:
        self._key = '"assistant_text"'
        self._buf = ""
        self._found_key = False
        self._saw_colon = False
        self._in_string = False
        self._escape = False
        self._unicode_buf: str | None = None
        self._done = False

    def feed(self, raw: str) -> str:
        if self._done or not raw:
            return ""

        self._buf += raw
        out_chars: list[str] = []

        i = 0
        while i < len(self._buf):
            ch = self._buf[i]

            if not self._found_key:
                idx = self._buf.find(self._key, i)
                if idx == -1:
                    keep = max(0, len(self._buf) - (len(self._key) - 1))
                    self._buf = self._buf[keep:]
                    return "".join(out_chars)
                i = idx + len(self._key)
                self._found_key = True
                continue

            if not self._saw_colon:
                if ch == ":":
                    self._saw_colon = True
                i += 1
                continue

            if not self._in_string:
                if ch == '"':
                    self._in_string = True
                i += 1
                continue

            if self._unicode_buf is not None:
                self._unicode_buf += ch
                i += 1
                if len(self._unicode_buf) >= 4:
                    try:
                        out_chars.append(chr(int(self._unicode_buf[:4], 16)))
                    except Exception:
                        pass
                    self._unicode_buf = None
                continue

            if self._escape:
                self._escape = False
                if ch == "n":
                    out_chars.append("\n")
                elif ch == "t":
                    out_chars.append("\t")
                elif ch == "r":
                    out_chars.append("\r")
                elif ch == '"':
                    out_chars.append('"')
                elif ch == "\\":
                    out_chars.append("\\")
                elif ch == "u":
                    self._unicode_buf = ""
                else:
                    out_chars.append(ch)
                i += 1
                continue

            if ch == "\\":
                self._escape = True
                i += 1
                continue

            if ch == '"':
                self._done = True
                i += 1
                self._buf = self._buf[i:]
                return "".join(out_chars)

            out_chars.append(ch)
            i += 1

        self._buf = ""
        return "".join(out_chars)


def _sse_event(event: str, payload: dict[str, Any]) -> str:
    data = json.dumps(payload, ensure_ascii=False)
    return f"event: {event}\ndata: {data}\n\n"


def _chunk_text(text: str, chunk_size: int) -> list[str]:
    if chunk_size <= 0:
        return [text]
    if not text:
        return [""]
    return [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]


class _SessionEntry(BaseModel):
    memory_state: dict[str, Any]
    last_access_unix_s: float


class _InMemorySessionStore:
    def __init__(self, ttl_seconds: int) -> None:
        self._ttl_seconds = ttl_seconds
        self._entries: dict[str, _SessionEntry] = {}
        self._locks: dict[str, asyncio.Lock] = {}
        self._global_lock = asyncio.Lock()

    async def _get_lock(self, session_id: str) -> asyncio.Lock:
        async with self._global_lock:
            lock = self._locks.get(session_id)
            if lock is None:
                lock = asyncio.Lock()
                self._locks[session_id] = lock
            return lock

    async def get_session_lock(self, session_id: str) -> asyncio.Lock:
        return await self._get_lock(session_id)

    async def load_memory(self, session_id: str) -> InMemoryMemory:
        await self.cleanup_expired()
        entry = self._entries.get(session_id)
        memory = InMemoryMemory()
        if entry is not None:
            memory.load_state_dict(entry.memory_state)
        return memory

    async def save_memory(self, session_id: str, memory: InMemoryMemory) -> None:
        self._entries[session_id] = _SessionEntry(
            memory_state=memory.state_dict(),
            last_access_unix_s=time.time(),
        )

    async def cleanup_expired(self) -> None:
        now = time.time()
        expired: list[str] = []
        for sid, entry in self._entries.items():
            if now - entry.last_access_unix_s > self._ttl_seconds:
                expired.append(sid)
        for sid in expired:
            self._entries.pop(sid, None)
            self._locks.pop(sid, None)


class _ModelBundle(BaseModel):
    model: ChatModelBase
    formatter: Any

    class Config:
        arbitrary_types_allowed = True


_DEFAULT_EVM_RPC_URL = "https://testnet-passet-hub-eth-rpc.polkadot.io"
_DEFAULT_UNISWAP_WETH9 = "0x4042196503b0C1E1f4188277bFfA46373FCf3576"
_DEFAULT_UNISWAP_FACTORY = "0xdCB1Bc3F7b806E553FC79E48768c809c051734Ef"
_DEFAULT_UNISWAP_ROUTER = "0x9aeAf6995b64A490fe1c2a8c06Dc2E912a487710"
_DEFAULT_TOKENDEMO = "0xDD128D3998Ca3DfACEbbC4218F7101B10aC8b09F"
_DEFAULT_TOKEN_A = "0x252Fdde220E559f4c88B458CD67A7841256F87Fa"
_DEFAULT_TOKEN_B = "0x03b0875d24782055C28BE0ba558F0626A19DC68f"
_DEFAULT_PAIR = "0x7849dBD762857A7Bdc37766255d97E0f3C8B9e89"

_DEFAULT_BINANCE_BASE_URL = "https://api.binance.com"
_DEFAULT_CEX_DEFAULT_QUOTE = "USDT"


_ERC20_ABI = [
    {
        "constant": True,
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "symbol",
        "outputs": [{"name": "", "type": "string"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
]


_UNISWAP_V2_ROUTER_ABI = [
    {
        "constant": True,
        "inputs": [
            {"name": "amountIn", "type": "uint256"},
            {"name": "path", "type": "address[]"},
        ],
        "name": "getAmountsOut",
        "outputs": [{"name": "amounts", "type": "uint256[]"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    }
]


_UNISWAP_V2_PAIR_ABI = [
    {
        "constant": True,
        "inputs": [],
        "name": "getReserves",
        "outputs": [
            {"name": "_reserve0", "type": "uint112"},
            {"name": "_reserve1", "type": "uint112"},
            {"name": "_blockTimestampLast", "type": "uint32"},
        ],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "token0",
        "outputs": [{"name": "", "type": "address"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "token1",
        "outputs": [{"name": "", "type": "address"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
]


def _load_amm_config() -> dict[str, str]:
    return {
        "rpc_url": os.getenv("AGENT_BACKEND_EVM_RPC_URL", _DEFAULT_EVM_RPC_URL).strip(),
        "router": os.getenv("AGENT_BACKEND_UNISWAP_V2_ROUTER", _DEFAULT_UNISWAP_ROUTER).strip(),
        "factory": os.getenv("AGENT_BACKEND_UNISWAP_V2_FACTORY", _DEFAULT_UNISWAP_FACTORY).strip(),
        "weth": os.getenv("AGENT_BACKEND_WETH9", _DEFAULT_UNISWAP_WETH9).strip(),
        "token_a": os.getenv("AGENT_BACKEND_DEFAULT_TOKEN_A", _DEFAULT_TOKEN_A).strip(),
        "token_b": os.getenv("AGENT_BACKEND_DEFAULT_TOKEN_B", _DEFAULT_TOKEN_B).strip(),
        "pair": os.getenv("AGENT_BACKEND_DEFAULT_PAIR", _DEFAULT_PAIR).strip(),
    }


def _load_cex_config() -> dict[str, Any]:
    return {
        "binance_base_url": os.getenv("AGENT_BACKEND_BINANCE_BASE_URL", _DEFAULT_BINANCE_BASE_URL).strip(),
        "default_quote": os.getenv("AGENT_BACKEND_CEX_DEFAULT_QUOTE", _DEFAULT_CEX_DEFAULT_QUOTE).strip().upper(),
        "timeout_s": float(os.getenv("AGENT_BACKEND_CEX_TIMEOUT_SECONDS", "10")),
        "kline_interval": os.getenv("AGENT_BACKEND_CEX_KLINE_INTERVAL", "1h").strip(),
        "kline_limit": int(os.getenv("AGENT_BACKEND_CEX_KLINE_LIMIT", "200")),
    }


def _w3(rpc_url: str) -> Web3:
    timeout_s = float(os.getenv("AGENT_BACKEND_EVM_RPC_TIMEOUT_SECONDS", "10"))
    return Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": timeout_s}))


def _to_wei(amount: str, decimals: int) -> int:
    ctx = decimal.Context(prec=60)
    d = ctx.create_decimal(amount)
    scale = ctx.create_decimal(10) ** ctx.create_decimal(decimals)
    return int((d * scale).to_integral_value(rounding=decimal.ROUND_DOWN))


def _from_wei(amount_wei: int, decimals: int) -> str:
    ctx = decimal.Context(prec=60)
    d = ctx.create_decimal(amount_wei)
    scale = ctx.create_decimal(10) ** ctx.create_decimal(decimals)
    return format(d / scale, "f")


async def get_amm_market_snapshot(
    amount_in: str,
    token_in: str | None = None,
    token_out: str | None = None,
    rpc_url: str = "",
    router: str = "",
    pair: str = "",
    default_token_a: str = "",
    default_token_b: str = "",
) -> ToolResponse:
    """Get an on-chain AMM (Uniswap V2) market snapshot and quote.

    Args:
        amount_in (str): Amount in human-readable units (e.g. "1.5").
        token_in (str | None): Optional ERC20 address. If omitted, uses default TokenA.
        token_out (str | None): Optional ERC20 address. If omitted, uses default TokenB.
    """

    try:
        if not rpc_url or not router or not pair or not default_token_a or not default_token_b:
            raise ValueError("missing preset configuration")

        token_in_addr = token_in or default_token_a
        token_out_addr = token_out or default_token_b

        w3 = _w3(rpc_url)
        router_c = w3.eth.contract(address=Web3.to_checksum_address(router), abi=_UNISWAP_V2_ROUTER_ABI)
        pair_c = w3.eth.contract(address=Web3.to_checksum_address(pair), abi=_UNISWAP_V2_PAIR_ABI)

        token0 = pair_c.functions.token0().call()
        token1 = pair_c.functions.token1().call()
        reserves = pair_c.functions.getReserves().call()
        reserve0 = int(reserves[0])
        reserve1 = int(reserves[1])

        token_in_c = w3.eth.contract(address=Web3.to_checksum_address(token_in_addr), abi=_ERC20_ABI)
        token_out_c = w3.eth.contract(address=Web3.to_checksum_address(token_out_addr), abi=_ERC20_ABI)
        decimals_in = int(token_in_c.functions.decimals().call())
        decimals_out = int(token_out_c.functions.decimals().call())

        try:
            symbol_in = str(token_in_c.functions.symbol().call())
        except Exception:
            symbol_in = ""

        try:
            symbol_out = str(token_out_c.functions.symbol().call())
        except Exception:
            symbol_out = ""

        amount_in_wei = _to_wei(amount_in, decimals_in)
        amounts_out = router_c.functions.getAmountsOut(amount_in_wei, [token_in_addr, token_out_addr]).call()
        amount_out_wei = int(amounts_out[-1])

        snapshot = {
            "ok": True,
            "source": "amm_uniswap_v2",
            "network": {"rpc_url": rpc_url},
            "contracts": {
                "router": router,
                "pair": pair,
            },
            "pair": {
                "token0": token0,
                "token1": token1,
                "reserve0": str(reserve0),
                "reserve1": str(reserve1),
            },
            "trade": {
                "token_in": token_in_addr,
                "token_out": token_out_addr,
                "symbol_in": symbol_in,
                "symbol_out": symbol_out,
                "decimals_in": decimals_in,
                "decimals_out": decimals_out,
                "amount_in": amount_in,
                "amount_in_wei": str(amount_in_wei),
                "amount_out_wei": str(amount_out_wei),
                "amount_out": _from_wei(amount_out_wei, decimals_out),
            },
            "timestamp_unix_s": time.time(),
        }

        return ToolResponse(content=[TextBlock(text=json.dumps(snapshot, ensure_ascii=False))])

    except Exception as e:
        err = {
            "ok": False,
            "error": {"type": type(e).__name__, "message": str(e)},
        }
        return ToolResponse(content=[TextBlock(text=json.dumps(err, ensure_ascii=False))])


async def preview_execution(
    action_type: str,
    amount_in: str,
    token_in: str | None = None,
    token_out: str | None = None,
) -> ToolResponse:
    """Create a preview-only execution payload.

    Args:
        action_type (str): Action type (e.g. "swap").
        amount_in (str): Amount in human-readable units.
        token_in (str | None): Optional ERC20 address.
        token_out (str | None): Optional ERC20 address.
    """

    preview = {
        "mode": "preview",
        "action_type": action_type,
        "token_in": token_in,
        "token_out": token_out,
        "amount_in": amount_in,
        "requires_confirmation": True,
    }
    return ToolResponse(content=[TextBlock(text=json.dumps(preview, ensure_ascii=False))])


def _normalize_cex_symbol(symbol: str, default_quote: str) -> str:
    s = (symbol or "").strip().upper()
    if not s:
        raise ValueError("symbol is required")
    if "/" in s:
        s = s.replace("/", "")
    if s.endswith(default_quote):
        return s
    if len(s) <= len(default_quote) + 1:
        return f"{s}{default_quote}"
    return s


def _infer_intent_hint(user_input: str) -> str:
    text = (user_input or "").strip().lower()
    if not text:
        return "chat"

    keywords = [
        "策略",
        "网格",
        "dca",
        "定投",
        "买入",
        "卖出",
        "做多",
        "做空",
        "交易",
        "开仓",
        "加仓",
        "止损",
        "止盈",
        "指标",
        "技术指标",
        "技术分析",
        "分析",
        "行情",
        "k线",
        "kline",
        "rsi",
        "macd",
        "boll",
        "bollinger",
        "布林",
        "strategy",
        "grid",
        "long",
        "short",
        "buy",
        "sell",
        "technical",
        "indicator",
        "ta",
    ]
    if any(k in text for k in keywords):
        return "strategy"
    return "chat"


def _extract_cex_symbol_from_text(user_input: str, default_quote: str, default_symbol: str) -> str:
    text = (user_input or "").strip()
    if not text:
        return default_symbol

    upper = text.upper()

    def _has_token(tok: str) -> bool:
        # Avoid \b because Chinese characters are treated as \w in Python regex.
        return re.search(rf"(?<![A-Z0-9]){re.escape(tok)}(?![A-Z0-9])", upper) is not None

    # Minimal alias support
    if "以太坊" in text or _has_token("ETH"):
        try:
            return _normalize_cex_symbol("ETH", default_quote)
        except Exception:
            return default_symbol
    if "比特币" in text or _has_token("BTC"):
        try:
            return _normalize_cex_symbol("BTC", default_quote)
        except Exception:
            return default_symbol

    # Match pairs like ETH/USDT, eth usdt, ETHUSDT
    m = re.search(r"(?<![A-Z0-9])([A-Z]{2,10})\s*(?:/|\s)?\s*(USDT|USDC|USD)(?![A-Z0-9])", upper)
    if m:
        try:
            base = m.group(1)
            quote = m.group(2)
            return _normalize_cex_symbol(f"{base}{quote}", default_quote)
        except Exception:
            return default_symbol

    # Match bare base assets like SOL, ETH, BTC
    m2 = re.search(r"(?<![A-Z0-9])([A-Z]{2,10})(?![A-Z0-9])", upper)
    if m2:
        try:
            token = m2.group(1)
            # Ignore indicator keywords that commonly appear in TA questions.
            if token in {"RSI", "MACD", "BOLL", "MA", "EMA", "SMA", "VWAP"}:
                return default_symbol
            return _normalize_cex_symbol(token, default_quote)
        except Exception:
            return default_symbol

    return default_symbol


async def get_cex_klines(
    symbol: str,
    interval: str | None = None,
    limit: int | None = None,
    base_url: str = "",
    timeout_s: float = 10.0,
    default_quote: str = "USDT",
    default_interval: str = "1h",
    default_limit: int = 200,
) -> ToolResponse:
    """Fetch recent klines from Binance public API.

    Args:
        symbol (str): Trading symbol, e.g. "BTCUSDT" or "BTC" (defaults to USDT quote).
        interval (str | None): Kline interval, e.g. "1m", "5m", "1h", "1d".
        limit (int | None): Number of klines.
    """

    try:
        if not base_url:
            raise ValueError("missing preset configuration")

        symbol_norm = _normalize_cex_symbol(symbol, default_quote)
        interval_norm = (interval or default_interval).strip()
        limit_norm = int(limit or default_limit)
        if limit_norm <= 0 or limit_norm > 1000:
            raise ValueError("limit must be between 1 and 1000")

        url = base_url.rstrip("/") + "/api/v3/klines"
        params = {"symbol": symbol_norm, "interval": interval_norm, "limit": limit_norm}

        async with httpx.AsyncClient(timeout=timeout_s) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()

        if not isinstance(data, list):
            raise ValueError("unexpected response")

        klines: list[dict[str, Any]] = []
        for row in data:
            if not isinstance(row, list) or len(row) < 7:
                continue
            klines.append(
                {
                    "open_time_ms": int(row[0]),
                    "open": str(row[1]),
                    "high": str(row[2]),
                    "low": str(row[3]),
                    "close": str(row[4]),
                    "volume": str(row[5]),
                    "close_time_ms": int(row[6]),
                }
            )

        snapshot = {
            "ok": True,
            "source": "cex_binance",
            "symbol": symbol_norm,
            "interval": interval_norm,
            "limit": limit_norm,
            "klines": klines,
            "timestamp_unix_s": time.time(),
        }

        return ToolResponse(content=[TextBlock(text=json.dumps(snapshot, ensure_ascii=False))])

    except Exception as e:
        err = {
            "ok": False,
            "source": "cex_binance",
            "symbol": symbol,
            "interval": interval,
            "limit": limit,
            "error": {"type": type(e).__name__, "message": str(e)},
        }
        return ToolResponse(content=[TextBlock(text=json.dumps(err, ensure_ascii=False))])


async def fetch_cex_market_snapshot(
    base_url: str = "",
    timeout_s: float = 10.0,
    symbol: str = "BTCUSDT",
    interval: str = "1h",
    limit: int = 100,
    default_quote: str = "USDT",
) -> dict[str, Any]:
    """Pre-fetch CEX klines and calculate technical indicators for prompt enrichment."""
    try:
        if not base_url:
            base_url = os.getenv("AGENT_BACKEND_BINANCE_BASE_URL", "https://api.binance.com")

        symbol_norm = _normalize_cex_symbol(symbol, default_quote)

        params = {"symbol": symbol_norm, "interval": interval, "limit": limit}

        async def _fetch(base: str):
            url = base.rstrip("/") + "/api/v3/klines"
            async with httpx.AsyncClient(timeout=timeout_s) as client:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
                return resp.json()

        data = None
        last_err: Exception | None = None
        try:
            data = await _fetch(base_url)
        except Exception as e:
            last_err = e
            # Fallback for regions where api.binance.com is blocked
            if "api.binance.com" in (base_url or ""):
                try:
                    data = await _fetch("https://data-api.binance.vision")
                    last_err = None
                except Exception as e2:
                    last_err = e2
            if data is None:
                raise last_err

        if not isinstance(data, list) or len(data) < 20:
            return {"ok": False, "error": "insufficient data"}

        # Extract OHLCV arrays
        opens = np.array([float(row[1]) for row in data], dtype=np.float64)
        highs = np.array([float(row[2]) for row in data], dtype=np.float64)
        lows = np.array([float(row[3]) for row in data], dtype=np.float64)
        closes = np.array([float(row[4]) for row in data], dtype=np.float64)
        volumes = np.array([float(row[5]) for row in data], dtype=np.float64)
        
        # Calculate technical indicators
        macd, macd_signal, macd_hist = talib.MACD(closes, fastperiod=12, slowperiod=26, signalperiod=9)
        rsi = talib.RSI(closes, timeperiod=14)
        ema_12 = talib.EMA(closes, timeperiod=12)
        ema_26 = talib.EMA(closes, timeperiod=26)
        upper_band, middle_band, lower_band = talib.BBANDS(closes, timeperiod=20)
        
        # Get latest values (last element, skip NaN)
        current_price = float(closes[-1])
        price_24h_ago = float(closes[0]) if len(closes) >= 24 else float(closes[0])
        price_change_pct = ((current_price - price_24h_ago) / price_24h_ago * 100) if price_24h_ago > 0 else 0
        
        avg_volume = float(np.mean(volumes[-24:])) if len(volumes) >= 24 else float(np.mean(volumes))
        current_volume = float(volumes[-1])
        volume_ratio = current_volume / avg_volume if avg_volume > 0 else 1.0
        
        # Build snapshot
        snapshot = {
            "ok": True,
            "symbol": symbol_norm,
            "interval": interval,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
            "price": {
                "current": round(current_price, 2),
                "high_24h": round(float(np.max(highs[-24:])), 2) if len(highs) >= 24 else round(float(np.max(highs)), 2),
                "low_24h": round(float(np.min(lows[-24:])), 2) if len(lows) >= 24 else round(float(np.min(lows)), 2),
                "change_24h_pct": round(price_change_pct, 2),
            },
            "volume": {
                "current": round(current_volume, 2),
                "avg_24h": round(avg_volume, 2),
                "ratio": round(volume_ratio, 2),
            },
            "indicators": {
                "rsi_14": round(float(rsi[-1]), 2) if not np.isnan(rsi[-1]) else None,
                "macd": round(float(macd[-1]), 4) if not np.isnan(macd[-1]) else None,
                "macd_signal": round(float(macd_signal[-1]), 4) if not np.isnan(macd_signal[-1]) else None,
                "macd_histogram": round(float(macd_hist[-1]), 4) if not np.isnan(macd_hist[-1]) else None,
                "ema_12": round(float(ema_12[-1]), 2) if not np.isnan(ema_12[-1]) else None,
                "ema_26": round(float(ema_26[-1]), 2) if not np.isnan(ema_26[-1]) else None,
                "bollinger_upper": round(float(upper_band[-1]), 2) if not np.isnan(upper_band[-1]) else None,
                "bollinger_middle": round(float(middle_band[-1]), 2) if not np.isnan(middle_band[-1]) else None,
                "bollinger_lower": round(float(lower_band[-1]), 2) if not np.isnan(lower_band[-1]) else None,
            },
        }
        return snapshot
        
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}: {str(e)}"}


async def fetch_btc_market_snapshot(
    base_url: str = "",
    timeout_s: float = 10.0,
    symbol: str = "BTCUSDT",
    interval: str = "1h",
    limit: int = 100,
) -> dict[str, Any]:
    return await fetch_cex_market_snapshot(
        base_url=base_url,
        timeout_s=timeout_s,
        symbol=symbol,
        interval=interval,
        limit=limit,
    )


async def compute_kline_features(
    klines: list[dict[str, Any]],
    lookback: int | None = None,
) -> ToolResponse:
    """Compute minimal trend/volatility features from kline list.

    Args:
        klines (list[dict]): Kline list produced by get_cex_klines.
        lookback (int | None): Use last N klines.
    """

    try:
        if not isinstance(klines, list) or not klines:
            raise ValueError("klines is required")

        lb = int(lookback or min(len(klines), 200))
        if lb <= 1:
            raise ValueError("lookback too small")

        tail = klines[-lb:]
        closes: list[float] = []
        for k in tail:
            if not isinstance(k, dict):
                continue
            c = k.get("close")
            try:
                closes.append(float(c))
            except Exception:
                continue

        if len(closes) <= 1:
            raise ValueError("not enough close values")

        first = closes[0]
        last = closes[-1]
        pct_change = (last - first) / first if first != 0 else 0.0

        log_returns: list[float] = []
        for i in range(1, len(closes)):
            if closes[i - 1] <= 0 or closes[i] <= 0:
                continue
            log_returns.append(math.log(closes[i] / closes[i - 1]))

        vol = float(statistics.pstdev(log_returns)) if len(log_returns) >= 2 else 0.0

        features = {
            "ok": True,
            "lookback": lb,
            "first_close": first,
            "last_close": last,
            "pct_change": pct_change,
            "volatility_logret": vol,
        }

        return ToolResponse(content=[TextBlock(text=json.dumps(features, ensure_ascii=False))])

    except Exception as e:
        err = {
            "ok": False,
            "error": {"type": type(e).__name__, "message": str(e)},
        }
        return ToolResponse(content=[TextBlock(text=json.dumps(err, ensure_ascii=False))])


def _tool_response_to_output(tr: ToolResponse) -> str:
    parts: list[str] = []
    for b in tr.content:
        if isinstance(b, dict):
            if isinstance(b.get("text"), str):
                parts.append(b["text"])
                continue
            parts.append(str(b))
            continue

        if getattr(b, "type", None) == "text":
            parts.append(str(getattr(b, "text", "")))
            continue

        text_attr = getattr(b, "text", None)
        if isinstance(text_attr, str) and text_attr:
            parts.append(text_attr)
            continue

        if hasattr(b, "model_dump"):
            dumped = b.model_dump()
            if isinstance(dumped, dict) and isinstance(dumped.get("text"), str):
                parts.append(dumped["text"])
                continue

        parts.append(str(b))
    return "\n".join([p for p in parts if p])


def _load_json_file(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _load_model_bundle() -> _ModelBundle:
    config_path = os.getenv("AGENT_BACKEND_MODEL_CONFIG_PATH")
    file_cfg: dict[str, Any] = {}
    if config_path:
        file_cfg = _load_json_file(config_path)

    provider = str(file_cfg.get("provider") or os.getenv("AGENT_BACKEND_MODEL_PROVIDER", "deepseek")).strip().lower()
    model_name = str(file_cfg.get("model_name") or os.getenv("AGENT_BACKEND_MODEL_NAME") or "").strip()
    if not model_name and provider == "deepseek":
        model_name = "deepseek-chat"
    if not model_name:
        raise RuntimeError("Missing required env: AGENT_BACKEND_MODEL_NAME")

    if provider == "deepseek":
        if not os.getenv("DEEPSEEK_API_KEY"):
            raise RuntimeError("Missing required env: DEEPSEEK_API_KEY")

        deepseek_base_url = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1").strip()
        upstream_timeout_s = float(os.getenv("AGENT_BACKEND_UPSTREAM_TIMEOUT_SECONDS", "60"))

        try:
            from agentscope.formatter import OpenAIChatFormatter
            from agentscope.model import OpenAIChatModel
        except Exception as e:
            raise RuntimeError(
                "DeepSeek provider requires AgentScope OpenAI-compatible dependencies. "
                "Install with agentscope[full] or install the OpenAI client dependencies."
            ) from e

        upstream_streaming = os.getenv("AGENT_BACKEND_UPSTREAM_STREAMING", "1").strip().lower() not in {"0", "false", "no"}

        stream_total_timeout_s = float(os.getenv("AGENT_BACKEND_STREAM_TOTAL_TIMEOUT_SECONDS", "75"))
        upstream_streaming_timeout_s = float(
            os.getenv(
                "AGENT_BACKEND_UPSTREAM_STREAMING_TIMEOUT_SECONDS",
                str(stream_total_timeout_s + 30.0),
            )
        )
        client_timeout_s = upstream_timeout_s
        if upstream_streaming:
            client_timeout_s = max(upstream_timeout_s, upstream_streaming_timeout_s)

        return _ModelBundle(
            model=OpenAIChatModel(
                model_name=model_name,
                api_key=os.getenv("DEEPSEEK_API_KEY"),
                stream=upstream_streaming,
                client_args={"base_url": deepseek_base_url, "timeout": client_timeout_s},
            ),
            formatter=OpenAIChatFormatter(),
        )

    if provider == "openai":
        if not os.getenv("OPENAI_API_KEY"):
            raise RuntimeError("Missing required env: OPENAI_API_KEY")

        try:
            from agentscope.formatter import OpenAIChatFormatter
            from agentscope.model import OpenAIChatModel
        except Exception as e:
            raise RuntimeError(
                "OpenAI provider requires AgentScope OpenAI dependencies. "
                "Install with agentscope[full] or install the OpenAI client dependencies."
            ) from e

        return _ModelBundle(
            model=OpenAIChatModel(model_name=model_name, stream=False),
            formatter=OpenAIChatFormatter(),
        )

    if provider == "dashscope":
        if not os.getenv("DASHSCOPE_API_KEY"):
            raise RuntimeError("Missing required env: DASHSCOPE_API_KEY")

        try:
            from agentscope.formatter import DashScopeChatFormatter
            from agentscope.model import DashScopeChatModel
        except Exception as e:
            raise RuntimeError(
                "DashScope provider requires AgentScope DashScope dependencies. "
                "Install with agentscope[full] or install dashscope-related dependencies."
            ) from e

        return _ModelBundle(
            model=DashScopeChatModel(model_name=model_name, api_key=os.getenv("DASHSCOPE_API_KEY"), stream=False),
            formatter=DashScopeChatFormatter(),
        )

    if provider == "anthropic":
        if not os.getenv("ANTHROPIC_API_KEY"):
            raise RuntimeError("Missing required env: ANTHROPIC_API_KEY")

        try:
            from agentscope.formatter import AnthropicChatFormatter
            from agentscope.model import AnthropicChatModel
        except Exception as e:
            raise RuntimeError(
                "Anthropic provider requires AgentScope Anthropic dependencies. "
                "Install with agentscope[full] or install anthropic-related dependencies."
            ) from e

        return _ModelBundle(
            model=AnthropicChatModel(model_name=model_name, api_key=os.getenv("ANTHROPIC_API_KEY"), stream=False),
            formatter=AnthropicChatFormatter(),
        )

    raise RuntimeError(f"Unsupported AGENT_BACKEND_MODEL_PROVIDER: {provider}")


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "code": "validation_error",
            "message": "Invalid request",
            "details": exc.errors(),
        },
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    detail = exc.detail
    if isinstance(detail, dict) and ("code" in detail or "message" in detail):
        payload = {
            "code": detail.get("code", "http_error"),
            "message": detail.get("message", "Request failed"),
        }
        if "details" in detail:
            payload["details"] = detail["details"]
        return JSONResponse(status_code=exc.status_code, content=payload)

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "code": "http_error",
            "message": str(detail) if detail is not None else "Request failed",
        },
    )


def _extract_text_from_chat_response(chat_response: Any) -> str:
    content = getattr(chat_response, "content", None)
    if not isinstance(content, list):
        return str(chat_response)

    texts: list[str] = []
    for block in content:
        if isinstance(block, dict):
            if block.get("type") == "text" and isinstance(block.get("text"), str):
                texts.append(block["text"])
        else:
            block_type = getattr(block, "type", None)
            if block_type == "text":
                texts.append(str(getattr(block, "text", "")))

    return "\n".join([t for t in texts if t])


def _text_deltas_from_chat_response(res: Any) -> list[str]:
    content = getattr(res, "content", None)
    if not isinstance(content, list):
        s = str(res)
        return [s] if s else []
    texts: list[str] = []
    for b in content:
        if isinstance(b, dict):
            if b.get("type") == "text" and isinstance(b.get("text"), str):
                texts.append(b["text"])
        else:
            if getattr(b, "type", None) == "text":
                t = getattr(b, "text", None)
                if isinstance(t, str) and t:
                    texts.append(t)
    return [t for t in texts if t]


def _extract_json_object(text: str) -> dict[str, Any] | None:
    stripped = text.strip()
    if not stripped:
        return None
    if stripped.startswith("```"):
        parts = stripped.split("```")
        for part in parts:
            candidate = part.strip()
            if not candidate:
                continue

            # Handle fenced blocks like ```json\n{...}\n```
            if candidate.lower().startswith("json"):
                brace_idx = candidate.find("{")
                if brace_idx != -1:
                    candidate = candidate[brace_idx:].strip()

            if candidate.startswith("{") and candidate.endswith("}"):
                try:
                    return json.loads(candidate)
                except Exception:
                    continue
    if stripped.startswith("{") and stripped.endswith("}"):
        try:
            return json.loads(stripped)
        except Exception:
            return None
    return None


async def _maybe_await(value: Any) -> Any:
    if asyncio.iscoroutine(value):
        return await value
    return value


async def _get_memory_msgs(memory: InMemoryMemory) -> list[Msg]:
    msgs = await _maybe_await(memory.get_memory())
    return msgs if isinstance(msgs, list) else []


def _is_async_iterable(obj: Any) -> bool:
    try:
        return isinstance(obj, collections.abc.AsyncIterable) or inspect.isasyncgen(obj)
    except Exception:
        return False


def _tool_calls_from_chat_response(res: Any) -> list[ToolUseBlock]:
    content = getattr(res, "content", None)
    if not isinstance(content, list):
        return []
    calls: list[ToolUseBlock] = []
    for b in content:
        if isinstance(b, dict):
            if b.get("type") == "tool_use":
                if isinstance(b.get("id"), str) and isinstance(b.get("name"), str) and isinstance(b.get("input"), dict):
                    calls.append(b)  # ToolUseBlock is a TypedDict-like mapping
        else:
            if getattr(b, "type", None) == "tool_use":
                calls.append(b)
    return calls


def _text_from_chat_response(res: Any) -> str:
    content = getattr(res, "content", None)
    if not isinstance(content, list):
        return str(res)
    texts: list[str] = []
    for b in content:
        if isinstance(b, dict):
            if b.get("type") == "text" and isinstance(b.get("text"), str):
                texts.append(b["text"])
        else:
            if getattr(b, "type", None) == "text":
                texts.append(str(getattr(b, "text", "")))
    return "\n".join([t for t in texts if t])


async def _call_model(
    bundle: _ModelBundle,
    msgs: list[Msg],
    toolkit: Toolkit | None,
    tool_choice: str | None = None,
    on_text_delta: collections.abc.Callable[[str], collections.abc.Awaitable[None]] | None = None,
) -> Any:
    formatted = await _maybe_await(bundle.formatter.format(msgs))
    tools = toolkit.get_json_schemas() if toolkit is not None else None
    res = await bundle.model(messages=formatted, tools=tools, tool_choice=tool_choice)
    if _is_async_iterable(res):
        last = None
        prev_accumulated = ""
        chunk_count = 0
        async for chunk in res:
            last = chunk
            chunk_count += 1
            if on_text_delta is not None:
                accumulated = _text_from_chat_response(chunk)
                if len(accumulated) > len(prev_accumulated):
                    delta = accumulated[len(prev_accumulated):]
                    prev_accumulated = accumulated
                    if delta:
                        logger.debug("_call_model delta #%d: %r", chunk_count, delta[:30] if len(delta) > 30 else delta)
                        await on_text_delta(delta)
        logger.info("_call_model streaming done: %d chunks, accumulated_len=%d", chunk_count, len(prev_accumulated))
        return last
    if on_text_delta is not None:
        for d in _text_deltas_from_chat_response(res):
            await on_text_delta(d)
    return res


def _ensure_demo_strategy_params(
    plan: dict[str, Any],
    requested_symbol: str | None,
    market_snapshot: dict[str, Any] | None,
) -> None:
    if not isinstance(plan, dict):
        return

    if not isinstance(plan.get("params"), dict):
        plan["params"] = {}
    params: dict[str, Any] = plan["params"]

    actions_raw = plan.get("actions")
    actions_list: list[Any] = actions_raw if isinstance(actions_raw, list) else []
    first_action: dict[str, Any] | None = actions_list[0] if actions_list and isinstance(actions_list[0], dict) else None
    action_type_raw = first_action.get("type") if isinstance(first_action, dict) else None
    action_type_norm = _normalize_demo_action_type(action_type_raw) if isinstance(action_type_raw, str) else None

    if requested_symbol and (not isinstance(params.get("symbol"), str) or not params.get("symbol")):
        params["symbol"] = requested_symbol
    if first_action is not None:
        if not isinstance(first_action.get("params"), dict):
            first_action["params"] = {}
        action_params: dict[str, Any] = first_action["params"]
        if requested_symbol and (not isinstance(action_params.get("symbol"), str) or not action_params.get("symbol")):
            action_params["symbol"] = requested_symbol

    snapshot = market_snapshot if isinstance(market_snapshot, dict) else None
    price_obj = snapshot.get("price") if isinstance(snapshot, dict) else None
    indicators_obj = snapshot.get("indicators") if isinstance(snapshot, dict) else None

    current_price: float | None = None
    if isinstance(price_obj, dict) and isinstance(price_obj.get("current"), (int, float)):
        current_price = float(price_obj["current"])

    def _set_if_missing(key: str, value: Any) -> None:
        if value is None:
            return
        if key not in params or params.get(key) in (None, ""):
            params[key] = value

    def _set_action_if_missing(key: str, value: Any) -> None:
        if first_action is None or value is None:
            return
        ap = first_action.get("params")
        if not isinstance(ap, dict):
            return
        if key not in ap or ap.get(key) in (None, ""):
            ap[key] = value

    # Use Bollinger bands as a reasonable default trading range when available.
    bb_upper = None
    bb_lower = None
    if isinstance(indicators_obj, dict):
        u = indicators_obj.get("bollinger_upper")
        l = indicators_obj.get("bollinger_lower")
        if isinstance(u, (int, float)):
            bb_upper = float(u)
        if isinstance(l, (int, float)):
            bb_lower = float(l)

    entry_range: list[float] | None = None
    if bb_lower is not None and bb_upper is not None and bb_lower > 0 and bb_upper > bb_lower:
        entry_range = [round(bb_lower, 2), round(bb_upper, 2)]
    elif current_price is not None and current_price > 0:
        # Fallback: +/- 2% around current.
        entry_range = [round(current_price * 0.98, 2), round(current_price * 1.02, 2)]

    # Defaults tuned for demo UI rendering. If the model already provided values we keep them.
    if action_type_norm == "start_grid":
        _set_if_missing("entry_price_range", entry_range)
        _set_if_missing("grid_levels", 10)
        _set_if_missing("take_profit_percent", 3)
        _set_if_missing("stop_loss_percent", 8)
    elif action_type_norm == "start_dca":
        _set_if_missing("entry_price_range", entry_range)
        _set_if_missing("take_profit_percent", 4)
        _set_if_missing("stop_loss_percent", 10)
    elif action_type_norm == "start_mean_reversion":
        _set_if_missing("entry_price_range", entry_range)
        _set_if_missing("take_profit_percent", 3)
        _set_if_missing("stop_loss_percent", 6)
    elif action_type_norm == "start_martingale":
        _set_if_missing("entry_price_range", entry_range)
        _set_if_missing("take_profit_percent", 2)
        _set_if_missing("stop_loss_percent", 12)

    # Also mirror key params into the first action params for clients that read them there.
    for k in ("entry_price_range", "grid_levels", "take_profit_percent", "stop_loss_percent"):
        if k in params:
            _set_action_if_missing(k, params.get(k))


async def _strategy_plan_simple(
    bundle: _ModelBundle,
    memory_msgs: list[Msg],
    user_input: str,
    market_snapshot: dict[str, Any] | None = None,
    intent_hint: str = "strategy",
    requested_symbol: str | None = None,
    on_text_delta: collections.abc.Callable[[str], collections.abc.Awaitable[None]] | None = None,
) -> dict[str, Any]:
    """Simple strategy planning without tool calling - uses pre-fetched market data."""
    
    # Build market context for the prompt
    market_context = ""
    if market_snapshot and market_snapshot.get("ok"):
        price = market_snapshot.get("price", {})
        volume = market_snapshot.get("volume", {})
        indicators = market_snapshot.get("indicators", {})
        market_context = f"""
当前市场数据 ({market_snapshot.get('symbol', 'BTCUSDT')}, {market_snapshot.get('timestamp', '')}):
- 价格: ${price.get('current', 'N/A')} (24h变化: {price.get('change_24h_pct', 0):.2f}%)
- 24h高/低: ${price.get('high_24h', 'N/A')} / ${price.get('low_24h', 'N/A')}
- 成交量比率: {volume.get('ratio', 1):.2f}x (当前/24h均值)
- RSI(14): {indicators.get('rsi_14', 'N/A')}
- MACD: {indicators.get('macd', 'N/A')} (信号线: {indicators.get('macd_signal', 'N/A')}, 柱状图: {indicators.get('macd_histogram', 'N/A')})
- EMA(12/26): {indicators.get('ema_12', 'N/A')} / {indicators.get('ema_26', 'N/A')}
- 布林带: 上轨 ${indicators.get('bollinger_upper', 'N/A')} / 中轨 ${indicators.get('bollinger_middle', 'N/A')} / 下轨 ${indicators.get('bollinger_lower', 'N/A')}
"""

    if intent_hint == "strategy":
        sys_prompt = f"""You are StrategyAgent for a crypto trading assistant.
{market_context}
Based on the above market data, provide trading strategy recommendations.
When the user asks for a trading strategy for a pair, you MUST choose exactly one strategy from this DEMO set:
- start_dca (智能DCA)
- start_grid (网格)
- start_mean_reversion (均值回归)
- start_martingale (马丁格尔)
- none (暂时观望)
If you are unsure or market data is insufficient, choose none.
Always output a single JSON object with fields:
- assistant_text (string): Your response to the user in Chinese
- intent (string): "strategy_recommendation" or "chat"
- params (object): Strategy parameters including the market data summary. It MUST include:
  - symbol (string, e.g. "ETHUSDT")
  - entry_price_range (array of 2 numbers, e.g. [2400, 2520])
  - take_profit_percent (number)
  - stop_loss_percent (number)
  - grid_levels (number, only for start_grid)
- rationale (string): Reasoning for your recommendation
- risk_notes (array of strings): Risk warnings
- actions (array of {{type, params}}): MUST contain 0 or 1 item. If intent is strategy_recommendation, include exactly 1 item. The first action params MUST also include symbol and the above key fields when applicable.
IMPORTANT: Start by outputting assistant_text as early as possible.
If the user is not requesting a trading action, set intent='chat' and actions=[].
Return JSON only."""
    else:
        sym = (requested_symbol or "").strip() or "N/A"
        sys_prompt = f"""You are a crypto assistant.
The user may ask either for a trading strategy or a general question.
If the user is asking for a strategy, you MUST choose exactly one strategy from this DEMO set:
- start_dca (智能DCA)
- start_grid (网格)
- start_mean_reversion (均值回归)
- start_martingale (马丁格尔)
- none (暂时观望)
If you are unsure or market data is insufficient, choose none.
The requested symbol (if any) is: {sym}
Always output a single JSON object with fields:
- assistant_text (string): Your response to the user in Chinese
- intent (string): "strategy_recommendation" or "chat"
- params (object)
- rationale (string)
- risk_notes (array of strings)
- actions (array of {{type, params}})
IMPORTANT: Start by outputting assistant_text as early as possible.
Return JSON only."""

    msgs: list[Msg] = [
        Msg(name="system", role="system", content=sys_prompt),
        *memory_msgs,
        Msg(name="user", role="user", content=user_input),
    ]

    llm_timeout_s = float(os.getenv("AGENT_BACKEND_LLM_TIMEOUT_SECONDS", "60"))
    llm_stream_timeout_s = float(os.getenv("AGENT_BACKEND_LLM_STREAM_TIMEOUT_SECONDS", "0"))
    
    effective_timeout_s = llm_stream_timeout_s if on_text_delta is not None else llm_timeout_s

    try:
        t0 = time.monotonic()
        if effective_timeout_s > 0:
            res = await asyncio.wait_for(
                _call_model(bundle=bundle, msgs=msgs, toolkit=None, tool_choice=None, on_text_delta=on_text_delta),
                timeout=effective_timeout_s,
            )
        else:
            res = await _call_model(bundle=bundle, msgs=msgs, toolkit=None, tool_choice=None, on_text_delta=on_text_delta)
        print(f"[LLM] strategy call done ms={int((time.monotonic() - t0) * 1000)}", flush=True)
    except asyncio.TimeoutError as e:
        raise RuntimeError("llm_timeout") from e

    text = _text_from_chat_response(res)
    plan = _extract_json_object(text)
    if plan is None:
        if not text.strip():
            raise RuntimeError("model_empty_response")
        return {"intent": "chat", "params": {}, "assistant_text": text, "rationale": "", "risk_notes": [], "actions": []}
    
    # Embed market snapshot in params
    if market_snapshot and market_snapshot.get("ok"):
        if not isinstance(plan.get("params"), dict):
            plan["params"] = {}
        plan["params"]["market_snapshot"] = market_snapshot

    _ensure_demo_strategy_params(plan, requested_symbol=requested_symbol, market_snapshot=market_snapshot)
    
    return plan


async def _strategy_plan_with_tools(
    bundle: _ModelBundle,
    toolkit: Toolkit | None,
    memory_msgs: list[Msg],
    user_input: str,
    on_text_delta: collections.abc.Callable[[str], collections.abc.Awaitable[None]] | None = None,
    on_tool_start: collections.abc.Callable[[str], collections.abc.Awaitable[None]] | None = None,
) -> dict[str, Any]:
    sys_prompt = (
        "You are StrategyAgent for a crypto trading assistant. "
        "You MAY use tools to query on-chain AMM quotes and CEX klines, and produce an execution preview. "
        "If you call the AMM quote tool, you MUST include its parsed JSON output in params.market_snapshot. "
        "If you call the CEX kline tool, you MUST include its parsed JSON output in params.kline_snapshot. "
        "If you call the kline feature tool, you MUST include its parsed JSON output in params.kline_features. "
        "When recommending an automated strategy, you MUST produce actions with type one of: start_dca, start_grid, start_mean_reversion. "
        "Always output a single JSON object with fields in this order: "
        "assistant_text (string), intent (string), params (object), rationale (string), "
        "risk_notes (array of strings), actions (array of {type, params}). "
        "IMPORTANT: When streaming, start by outputting assistant_text as early as possible, then fill the remaining fields. "
        "If the user is not requesting a trading action, set intent='chat' and actions=[]. "
        "Return JSON only."
    )

    msgs: list[Msg] = [
        Msg(name="system", role="system", content=sys_prompt),
        *memory_msgs,
        Msg(name="user", role="user", content=user_input),
    ]

    max_iters = int(os.getenv("AGENT_BACKEND_TOOL_MAX_ITERS", "6"))
    llm_timeout_s = float(
        os.getenv(
            "AGENT_BACKEND_LLM_TIMEOUT_SECONDS",
            os.getenv("AGENT_BACKEND_UPSTREAM_TIMEOUT_SECONDS", "60"),
        )
    )
    llm_stream_timeout_s = float(os.getenv("AGENT_BACKEND_LLM_STREAM_TIMEOUT_SECONDS", "0"))
    tool_timeout_s = float(os.getenv("AGENT_BACKEND_TOOL_TIMEOUT_SECONDS", "20"))

    async def _collect_tool(gen: Any) -> Any:
        last = None
        async for tr in gen:
            last = tr
        return last

    for iter_num in range(max_iters):
        print(f"[STRATEGY] iter={iter_num} msgs_count={len(msgs)}", flush=True)
        logger.info("strategy_loop iter=%d msgs_count=%d", iter_num, len(msgs))
        try:
            t0 = time.monotonic()
            effective_timeout_s = llm_timeout_s
            if on_text_delta is not None:
                effective_timeout_s = llm_stream_timeout_s

            if effective_timeout_s > 0:
                res = await asyncio.wait_for(
                    _call_model(
                        bundle=bundle,
                        msgs=msgs,
                        toolkit=toolkit,
                        tool_choice="auto",
                        on_text_delta=on_text_delta,
                    ),
                    timeout=effective_timeout_s,
                )
            else:
                res = await _call_model(
                    bundle=bundle,
                    msgs=msgs,
                    toolkit=toolkit,
                    tool_choice="auto",
                    on_text_delta=on_text_delta,
                )
            print(f"[LLM] call done ms={int((time.monotonic() - t0) * 1000)}", flush=True)
        except asyncio.TimeoutError as e:
            raise RuntimeError("llm_timeout") from e

        tool_calls = _tool_calls_from_chat_response(res)
        print(f"[LLM] tool_calls={len(tool_calls) if tool_calls else 0}", flush=True)
        if tool_calls and toolkit is not None:
            msgs.append(Msg(name="assistant", role="assistant", content=list(tool_calls)))

            for tc in tool_calls:
                output_text = ""
                tool_name = str(tc.get("name") or "tool")
                if on_tool_start is not None:
                    await on_tool_start(tool_name)
                try:
                    t0 = time.monotonic()
                    print(f"[TOOL] starting {tc.get('name')}", flush=True)
                    gen = await toolkit.call_tool_function(tc)
                    print(f"[TOOL] got generator {tc.get('name')} type={type(gen).__name__}", flush=True)
                    if tool_timeout_s > 0:
                        last_tr = await asyncio.wait_for(_collect_tool(gen), timeout=tool_timeout_s)
                    else:
                        last_tr = await _collect_tool(gen)
                    if last_tr is not None:
                        output_text = _tool_response_to_output(last_tr)
                    print(f"[TOOL] done {tc.get('name')} ms={int((time.monotonic() - t0) * 1000)} len={len(output_text)}", flush=True)
                except asyncio.TimeoutError:
                    output_text = json.dumps(
                        {
                            "ok": False,
                            "error": {"type": "TimeoutError", "message": "tool_timeout"},
                            "tool": str(tc.get("name") or ""),
                        },
                        ensure_ascii=False,
                    )
                except Exception as e:
                    output_text = json.dumps({"ok": False, "error": {"type": type(e).__name__, "message": str(e)}}, ensure_ascii=False)

                msgs.append(
                    Msg(
                        name="tool",
                        role="system",
                        content=[
                            {
                                "type": "tool_result",
                                "id": tc["id"],
                                "name": tc["name"],
                                "output": output_text,
                            }
                        ],
                    )
                )

            logger.info("tool_loop: continuing to next LLM call after %d tool(s)", len(tool_calls))
            continue

        text = _text_from_chat_response(res)
        plan = _extract_json_object(text)
        if plan is None:
            if not text.strip():
                raise RuntimeError("model_empty_response")
            return {
                "intent": "chat",
                "params": {},
                "assistant_text": text,
                "rationale": text,
                "risk_notes": [],
                "actions": [],
            }
        return plan

    raise RuntimeError("tool_call_limit_exceeded")


def _execution_preview(plan: dict[str, Any]) -> tuple[str, list[Action], dict[str, Any] | None]:
    intent = str(plan.get("intent") or "chat")
    actions_raw = plan.get("actions")
    actions: list[Action] = []
    if isinstance(actions_raw, list):
        for item in actions_raw:
            if isinstance(item, dict) and isinstance(item.get("type"), str):
                norm_type = _normalize_demo_action_type(item.get("type"))
                if norm_type is None:
                    continue
                params = item.get("params")
                actions.append(Action(type=norm_type, params=params if isinstance(params, dict) else {}))

    # Enforce demo constraints
    if intent != "chat":
        if not actions:
            actions = [Action(type="none", params={})]
        if len(actions) > 1:
            actions = actions[:1]

    if intent == "chat" and not actions:
        assistant_text = str(plan.get("assistant_text") or plan.get("rationale") or "")
        return assistant_text, actions, None

    preview = {
        "mode": "preview",
        "intent": intent if intent != "chat" else "strategy_recommendation",
        "params": plan.get("params") if isinstance(plan.get("params"), dict) else {},
        "requires_confirmation": True,
    }
    preview["actions"] = [a.model_dump() for a in actions]

    rationale = str(plan.get("rationale") or "")
    risk_notes = plan.get("risk_notes")
    if isinstance(risk_notes, list):
        risk_text = "\n".join([f"- {x}" for x in risk_notes if isinstance(x, str) and x.strip()])
    else:
        risk_text = ""

    assistant_text = rationale
    if risk_text:
        assistant_text = f"{assistant_text}\n\nRisk notes:\n{risk_text}".strip()

    if not assistant_text:
        assistant_text = "I created an execution preview. Please confirm before proceeding."

    return assistant_text, actions, preview


def _routing_stub(market_snapshot: dict[str, Any] | None) -> dict[str, Any]:
    if not market_snapshot or not isinstance(market_snapshot, dict):
        return {"route": "AMM", "reason": "default_route", "stub": True}
    if market_snapshot.get("ok") is False:
        return {"route": "AMM", "reason": "market_snapshot_error", "stub": True}
    return {"route": "AMM", "reason": "amm_quote_available", "stub": False}


MODEL_BUNDLE: _ModelBundle | None = None
SESSION_STORE: _InMemorySessionStore | None = None
TOOLKIT: Toolkit | None = None
CROSS_CHAIN: _CrossChainService | None = None

@app.on_event("startup")
async def startup_event():
    init_agents()
    global MODEL_BUNDLE
    global SESSION_STORE
    global TOOLKIT
    global CROSS_CHAIN

    if os.getenv("AGENT_BACKEND_DISABLE_STARTUP", "").strip() == "1":
        return

    MODEL_BUNDLE = _load_model_bundle()
    ttl_seconds = int(os.getenv("AGENT_BACKEND_SESSION_TTL_SECONDS", "1800"))
    SESSION_STORE = _InMemorySessionStore(ttl_seconds=ttl_seconds)
    CROSS_CHAIN = _CrossChainService()

    amm = _load_amm_config()
    cex = _load_cex_config()
    toolkit = Toolkit()
    toolkit.register_tool_function(
        get_amm_market_snapshot,
        preset_kwargs={
            "rpc_url": amm["rpc_url"],
            "router": amm["router"],
            "pair": amm["pair"],
            "default_token_a": amm["token_a"],
            "default_token_b": amm["token_b"],
        },
    )
    toolkit.register_tool_function(preview_execution)
    toolkit.register_tool_function(
        get_cex_klines,
        preset_kwargs={
            "base_url": cex["binance_base_url"],
            "timeout_s": cex["timeout_s"],
            "default_quote": cex["default_quote"],
            "default_interval": cex["kline_interval"],
            "default_limit": cex["kline_limit"],
        },
    )
    toolkit.register_tool_function(compute_kline_features)
    TOOLKIT = toolkit


@app.get("/health")
async def health():
    return {"status": "ok"}


def _cross_chain_service() -> _CrossChainService:
    global CROSS_CHAIN
    if CROSS_CHAIN is None:
        CROSS_CHAIN = _CrossChainService()
    return CROSS_CHAIN


@app.post("/cross-chain/intents")
async def cross_chain_create_intent(req: CrossChainIntentCreateRequest):
    svc = _cross_chain_service()
    try:
        intent = await svc.create_and_dispatch(req)
    except ValueError as e:
        code = str(e)
        if code == "unsupported_connector":
            raise HTTPException(status_code=400, detail={"code": "unsupported_connector", "message": "Unsupported connector"})
        raise
    return intent


@app.get("/cross-chain/intents/{intent_id}")
async def cross_chain_get_intent(intent_id: str):
    svc = _cross_chain_service()
    intent = await svc.store.get_intent(intent_id)
    if intent is None:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "intent not found"})
    return intent


@app.post("/cross-chain/intents/{intent_id}/cancel")
async def cross_chain_cancel_intent(intent_id: str):
    svc = _cross_chain_service()
    try:
        return await svc.store.cancel_intent(intent_id)
    except KeyError:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "intent not found"})
    except ValueError:
        raise HTTPException(status_code=409, detail={"code": "cannot_cancel", "message": "intent cannot be cancelled"})


@app.post("/cross-chain/intents/{intent_id}/refund")
async def cross_chain_refund_intent(intent_id: str):
    svc = _cross_chain_service()
    try:
        return await svc.store.refund_intent(intent_id)
    except KeyError:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "intent not found"})
    except ValueError:
        raise HTTPException(status_code=409, detail={"code": "cannot_refund", "message": "intent cannot be refunded"})


@app.post("/cross-chain/inbound")
async def cross_chain_inbound(http_request: Request, inbound: CrossChainInboundRequest):
    token = http_request.headers.get("x-crosschain-auth", "")
    expected = os.getenv("AGENT_BACKEND_CROSSCHAIN_INBOUND_TOKEN", "").strip()
    if not expected:
        raise HTTPException(status_code=503, detail={"code": "not_ready", "message": "Inbound token not configured"})
    if token != expected:
        raise HTTPException(status_code=401, detail={"code": "unauthorized", "message": "Invalid inbound auth"})

    svc = _cross_chain_service()
    try:
        intent, applied = await svc.apply_verified_inbound(inbound)
    except KeyError:
        raise HTTPException(status_code=404, detail={"code": "not_found", "message": "intent not found"})
    except ValueError as e:
        if str(e) == "unverified_inbound":
            raise HTTPException(status_code=400, detail={"code": "unverified_inbound", "message": "Inbound message not verified"})
        if str(e) == "unsupported_connector":
            raise HTTPException(status_code=400, detail={"code": "unsupported_connector", "message": "Unsupported connector"})
        raise

    return {"applied": applied, "intent": intent}

@app.post("/chat")
async def chat(request: ChatRequest):
    if MODEL_BUNDLE is None or SESSION_STORE is None:
        raise HTTPException(status_code=503, detail={"code": "not_ready", "message": "Service not initialized"})

    user_input = request.user_input
    if not isinstance(user_input, str) or not user_input.strip():
        raise HTTPException(status_code=400, detail={"code": "invalid_input", "message": "user_input is required"})

    max_chars = int(os.getenv("AGENT_BACKEND_MAX_INPUT_CHARS", "2000"))
    if len(user_input) > max_chars:
        raise HTTPException(status_code=413, detail={"code": "input_too_large", "message": "user_input too large"})

    session_id = request.session_id or uuid.uuid4().hex
    lock = await SESSION_STORE.get_session_lock(session_id)

    buy_intent = _extract_buy_pas_token_intent(user_input)
    if buy_intent is not None:
        amount_in_pas, token_out_symbol = buy_intent
        execution_plan = _build_buy_execution_plan(amount_in_pas=amount_in_pas, token_out_symbol=token_out_symbol)
        assistant_text = (
            f"我已为你生成购买计划：用 {amount_in_pas} PAS 购买 {token_out_symbol}。\n\n"
            "下一步：请在 App 内确认并分别签名执行跨链（XCM）与 swap 交易。"
        )
        actions: list[Action] = []
        preview = {
            "mode": "preview",
            "intent": "buy_token",
            "params": {
                "amount_in_pas": amount_in_pas,
                "token_out": token_out_symbol,
                "slippage_bps": execution_plan["risk_controls"]["slippage_bps"],
                "deadline_seconds": execution_plan["risk_controls"]["deadline_seconds"],
            },
            "requires_confirmation": True,
        }

        async with lock:
            memory = await SESSION_STORE.load_memory(session_id)
            await _maybe_await(memory.add(Msg(name="user", role="user", content=user_input)))
            await _maybe_await(memory.add(Msg(name="assistant", role="assistant", content=assistant_text)))
            await SESSION_STORE.save_memory(session_id, memory)

        return ChatResponse(
            session_id=session_id,
            assistant_text=assistant_text,
            actions=actions,
            execution_preview=preview,
            execution_plan=execution_plan,
            strategy_type=None,
            strategy_label=None,
        )

    async with lock:
        memory = await SESSION_STORE.load_memory(session_id)
        memory_msgs = await _get_memory_msgs(memory)

        try:
            plan = await _strategy_plan_with_tools(MODEL_BUNDLE, TOOLKIT, memory_msgs, user_input)
        except Exception as e:
            message = str(e)
            msg_lower = message.lower()
            type_lower = type(e).__name__.lower()
            if (
                "timeout" in msg_lower
                or "timed out" in msg_lower
                or "connecttimeout" in msg_lower
                or "timeout" in type_lower
            ):
                raise HTTPException(
                    status_code=504,
                    detail={
                        "code": "llm_timeout" if msg_lower.strip() == "llm_timeout" else "upstream_timeout",
                        "message": "Upstream LLM request timed out. Check network/proxy and DEEPSEEK_BASE_URL.",
                    },
                )
            if (
                "connection reset" in msg_lower
                or "incomplete envelope" in msg_lower
                or "protocol error" in msg_lower
                or "read: connection reset" in msg_lower
            ):
                raise HTTPException(
                    status_code=502,
                    detail={
                        "code": "upstream_network_error",
                        "message": "Upstream connection was reset. Check network/proxy and DEEPSEEK_BASE_URL.",
                    },
                )
            raise

        assistant_text, actions, preview = _execution_preview(plan)

        if plan.get("intent") != "chat" and preview is None:
            params = plan.get("params") if isinstance(plan.get("params"), dict) else {}
            amount_in = str(params.get("amount_in") or params.get("amount") or "1")
            token_in = params.get("token_in")
            token_out = params.get("token_out")
            tr = await preview_execution(action_type=str(plan.get("intent")), amount_in=amount_in, token_in=token_in, token_out=token_out)
            preview_text = _tool_response_to_output(tr)
            preview_obj = _extract_json_object(preview_text)
            preview = preview_obj if isinstance(preview_obj, dict) else {"mode": "preview", "requires_confirmation": True}

        if isinstance(preview, dict) and "routing" not in preview:
            snapshot_obj: dict[str, Any] | None = None
            if isinstance(plan.get("params"), dict) and isinstance(plan["params"].get("market_snapshot"), dict):
                snapshot_obj = plan["params"]["market_snapshot"]
            preview["routing"] = _routing_stub(snapshot_obj)

        await _maybe_await(memory.add(Msg(name="user", role="user", content=user_input)))
        await _maybe_await(memory.add(Msg(name="assistant", role="assistant", content=assistant_text)))
        await SESSION_STORE.save_memory(session_id, memory)

    return ChatResponse(
        session_id=session_id,
        assistant_text=assistant_text,
        actions=actions,
        execution_preview=preview,
        execution_plan=None,
        strategy_type=actions[0].type if actions else None,
        strategy_label=_demo_strategy_label(actions[0].type if actions else None),
    )

@app.post("/chat/stream")
async def chat_stream(http_request: Request, request: ChatRequest):
    if MODEL_BUNDLE is None or SESSION_STORE is None:
        raise HTTPException(status_code=503, detail={"code": "not_ready", "message": "Service not initialized"})

    user_input = request.user_input
    if not isinstance(user_input, str) or not user_input.strip():
        raise HTTPException(status_code=400, detail={"code": "invalid_input", "message": "user_input is required"})

    max_chars = int(os.getenv("AGENT_BACKEND_MAX_INPUT_CHARS", "2000"))
    if len(user_input) > max_chars:
        raise HTTPException(status_code=413, detail={"code": "input_too_large", "message": "user_input too large"})

    session_id = request.session_id or uuid.uuid4().hex

    chunk_size = int(os.getenv("AGENT_BACKEND_STREAM_CHUNK_SIZE", "12"))
    delay_ms = int(os.getenv("AGENT_BACKEND_STREAM_DELAY_MS", "15"))
    keepalive_s = float(os.getenv("AGENT_BACKEND_STREAM_KEEPALIVE_SECONDS", "2"))
    total_timeout_s = float(os.getenv("AGENT_BACKEND_STREAM_TOTAL_TIMEOUT_SECONDS", "75"))
    upstream_streaming = os.getenv("AGENT_BACKEND_UPSTREAM_STREAMING", "1").strip().lower() not in {"0", "false", "no"}

    q: asyncio.Queue[str] | None = None
    extractor: _AssistantTextJsonExtractor | None = None
    if upstream_streaming:
        q = asyncio.Queue()
        extractor = _AssistantTextJsonExtractor()

        async def _on_delta(d: str) -> None:
            if extractor is None or q is None:
                return
            new_text = extractor.feed(d)
            if new_text:
                logger.info("SSE delta push: %r", new_text[:50] if len(new_text) > 50 else new_text)
                await q.put(new_text)

        on_text_delta = _on_delta
    else:
        on_text_delta = None

    # Pre-fetch market data before LLM call (non-blocking for simple prompts)
    use_simple_strategy = os.getenv("AGENT_BACKEND_USE_SIMPLE_STRATEGY", "1").strip().lower() not in {"0", "false", "no"}
    cex_cfg = _load_cex_config()
    default_symbol = os.getenv("AGENT_BACKEND_DEFAULT_SYMBOL", "BTCUSDT").strip().upper() or "BTCUSDT"

    buy_intent = _extract_buy_pas_token_intent(user_input)

    async def compute_final():
        if SESSION_STORE is None:
            raise RuntimeError("not_ready")
        lock = await SESSION_STORE.get_session_lock(session_id)
        async with lock:
            memory = await SESSION_STORE.load_memory(session_id)
            memory_msgs = await _get_memory_msgs(memory)

            if buy_intent is not None:
                amount_in_pas, token_out_symbol = buy_intent
                execution_plan = _build_buy_execution_plan(amount_in_pas=amount_in_pas, token_out_symbol=token_out_symbol)
                assistant_text = (
                    f"我已为你生成购买计划：用 {amount_in_pas} PAS 购买 {token_out_symbol}。\n\n"
                    "下一步：请在 App 内确认并分别签名执行跨链（XCM）与 swap 交易。"
                )
                await _maybe_await(memory.add(Msg(name="user", role="user", content=user_input)))
                await _maybe_await(memory.add(Msg(name="assistant", role="assistant", content=assistant_text)))
                await SESSION_STORE.save_memory(session_id, memory)

                preview = {
                    "mode": "preview",
                    "intent": "buy_token",
                    "params": {
                        "amount_in_pas": amount_in_pas,
                        "token_out": token_out_symbol,
                        "slippage_bps": execution_plan["risk_controls"]["slippage_bps"],
                        "deadline_seconds": execution_plan["risk_controls"]["deadline_seconds"],
                    },
                    "requires_confirmation": True,
                }

                return assistant_text, [], preview, execution_plan

            try:
                if use_simple_strategy:
                    intent_hint = _infer_intent_hint(user_input)
                    symbol = _extract_cex_symbol_from_text(
                        user_input,
                        default_quote=cex_cfg["default_quote"],
                        default_symbol=default_symbol,
                    )
                    market_snapshot: dict[str, Any] | None = None
                    if intent_hint == "strategy":
                        print(f"[MARKET] Fetching market snapshot symbol={symbol}...", flush=True)
                        market_snapshot = await fetch_cex_market_snapshot(
                            base_url=cex_cfg["binance_base_url"],
                            timeout_s=cex_cfg["timeout_s"],
                            symbol=symbol,
                            interval=cex_cfg["kline_interval"],
                            limit=min(cex_cfg["kline_limit"], 200),
                            default_quote=cex_cfg["default_quote"],
                        )
                        print(f"[MARKET] Snapshot ok={market_snapshot.get('ok') if isinstance(market_snapshot, dict) else None}", flush=True)

                    plan = await _strategy_plan_simple(
                        MODEL_BUNDLE,
                        memory_msgs,
                        user_input,
                        market_snapshot=market_snapshot,
                        intent_hint=intent_hint,
                        requested_symbol=symbol,
                        on_text_delta=on_text_delta,
                    )
                else:
                    symbol = None
                    plan = await _strategy_plan_with_tools(
                        MODEL_BUNDLE,
                        TOOLKIT,
                        memory_msgs,
                        user_input,
                        on_text_delta=on_text_delta,
                        on_tool_start=None,
                    )

                snapshot_for_params: dict[str, Any] | None = None
                if isinstance(plan, dict) and isinstance(plan.get("params"), dict) and isinstance(plan["params"].get("market_snapshot"), dict):
                    snapshot_for_params = plan["params"]["market_snapshot"]
                _ensure_demo_strategy_params(plan, requested_symbol=symbol, market_snapshot=snapshot_for_params)

                assistant_text, actions, preview = _execution_preview(plan)
            except Exception as e:
                message = str(e)
                msg_lower = message.lower()
                type_lower = type(e).__name__.lower()
                if (
                    "timeout" in msg_lower
                    or "timed out" in msg_lower
                    or "connecttimeout" in msg_lower
                    or "timeout" in type_lower
                ):
                    raise HTTPException(
                        status_code=504,
                        detail={
                            "code": "llm_timeout" if msg_lower.strip() == "llm_timeout" else "upstream_timeout",
                            "message": "Upstream LLM request timed out. Check network/proxy and DEEPSEEK_BASE_URL.",
                        },
                    )
                if (
                    "connection reset" in msg_lower
                    or "incomplete envelope" in msg_lower
                    or "protocol error" in msg_lower
                    or "read: connection reset" in msg_lower
                ):
                    raise HTTPException(
                        status_code=502,
                        detail={
                            "code": "upstream_network_error",
                            "message": "Upstream connection was reset. Check network/proxy and DEEPSEEK_BASE_URL.",
                        },
                    )
                raise

            if plan.get("intent") != "chat" and preview is None:
                params = plan.get("params") if isinstance(plan.get("params"), dict) else {}
                amount_in = str(params.get("amount_in") or params.get("amount") or "1")
                token_in = params.get("token_in")
                token_out = params.get("token_out")
                tr = await preview_execution(
                    action_type=str(plan.get("intent")),
                    amount_in=amount_in,
                    token_in=token_in,
                    token_out=token_out,
                )
                preview_text = _tool_response_to_output(tr)
                preview_obj = _extract_json_object(preview_text)
                preview = (
                    preview_obj
                    if isinstance(preview_obj, dict)
                    else {"mode": "preview", "requires_confirmation": True}
                )

            if isinstance(preview, dict) and "routing" not in preview:
                snapshot_obj: dict[str, Any] | None = None
                if isinstance(plan.get("params"), dict) and isinstance(plan["params"].get("market_snapshot"), dict):
                    snapshot_obj = plan["params"]["market_snapshot"]
                preview["routing"] = _routing_stub(snapshot_obj)

            await _maybe_await(memory.add(Msg(name="user", role="user", content=user_input)))
            await _maybe_await(memory.add(Msg(name="assistant", role="assistant", content=assistant_text)))
            await SESSION_STORE.save_memory(session_id, memory)

            return assistant_text, actions, preview, None

    async def gen():
        task = asyncio.create_task(compute_final())
        last_keepalive = time.time()
        start_time = last_keepalive
        emitted_any = False
        seq = 0
        yield ": connected\n\n"
        try:
            while True:
                now = time.time()
                if total_timeout_s > 0 and now - start_time >= total_timeout_s:
                    task.cancel()
                    yield _sse_event(
                        "error",
                        {
                            "session_id": session_id,
                            "code": "upstream_timeout",
                            "message": "Timed out while generating strategy. Check upstream LLM/network and try again.",
                        },
                    )
                    return
                if keepalive_s > 0 and now - last_keepalive >= keepalive_s:
                    last_keepalive = now
                    yield ": keep-alive\n\n"

                if q is not None:
                    while True:
                        try:
                            delta = q.get_nowait()
                        except asyncio.QueueEmpty:
                            break
                        emitted_any = True
                        yield _sse_event("chunk", {"session_id": session_id, "sequence": seq, "delta_text": delta})
                        seq += 1

                try:
                    assistant_text, actions, preview, execution_plan = await asyncio.wait_for(asyncio.shield(task), timeout=0.25)
                    break
                except asyncio.TimeoutError:
                    continue

            if q is not None:
                while True:
                    try:
                        delta = q.get_nowait()
                    except asyncio.QueueEmpty:
                        break
                    emitted_any = True
                    yield _sse_event("chunk", {"session_id": session_id, "sequence": seq, "delta_text": delta})
                    seq += 1

            if not upstream_streaming or not emitted_any:
                for part in _chunk_text(assistant_text, chunk_size):
                    yield _sse_event("chunk", {"session_id": session_id, "sequence": seq, "delta_text": part})
                    seq += 1
                    if delay_ms > 0:
                        await asyncio.sleep(delay_ms / 1000.0)

            done_payload: dict[str, Any] = {
                "session_id": session_id,
                "assistant_text": assistant_text,
                "actions": [a.model_dump() for a in actions],
                "execution_preview": preview,
            }
            if execution_plan is not None:
                done_payload["execution_plan"] = execution_plan
            strategy_type = actions[0].type if actions else None
            done_payload["strategy_type"] = strategy_type
            done_payload["strategy_label"] = _demo_strategy_label(strategy_type)
            yield _sse_event("done", done_payload)
        except HTTPException as e:
            detail = e.detail
            if isinstance(detail, dict):
                code = str(detail.get("code") or "http_error")
                message = str(detail.get("message") or "Request failed")
            else:
                code = "http_error"
                message = str(detail)
            yield _sse_event("error", {"session_id": session_id, "code": code, "message": message})
        except asyncio.CancelledError:
            return
        except Exception as e:
            yield _sse_event("error", {"session_id": session_id, "code": "stream_error", "message": str(e)})
        finally:
            if not task.done():
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await task

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
