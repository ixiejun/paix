import importlib.util
import json
import os
from types import SimpleNamespace
from pathlib import Path

import httpx
import pytest


def _load_module():
    os.environ["AGENT_BACKEND_DISABLE_STARTUP"] = "1"

    path = Path(__file__).resolve().parents[1] / "main.py"
    spec = importlib.util.spec_from_file_location("agent_backend_main", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class _FakeFormatter:
    async def format(self, msgs, **kwargs):
        out = []
        for m in msgs:
            out.append({"role": m.role, "content": m.content})
        return out


def _fake_model(mod):
    class FakeModel(mod.ChatModelBase):
        def __init__(self):
            super().__init__(model_name="fake", stream=False)

        async def __call__(self, messages, tools=None, tool_choice=None, structured_model=None, **kwargs):
            plan = {
                "intent": "chat",
                "params": {},
                "assistant_text": "ok",
                "rationale": "ok",
                "risk_notes": [],
                "actions": [],
            }
            # Return a minimal object compatible with agent-backend parsing:
            # it only relies on a `.content` list of blocks.
            return SimpleNamespace(content=[{"type": "text", "text": json.dumps(plan)}])

    return FakeModel()


def _fake_model_with_actions(mod):
    class FakeModel(mod.ChatModelBase):
        def __init__(self):
            super().__init__(model_name="fake", stream=False)

        async def __call__(self, messages, tools=None, tool_choice=None, structured_model=None, **kwargs):
            plan = {
                "intent": "chat",
                "params": {"symbol": "BTCUSDT"},
                "assistant_text": "ok",
                "rationale": "ok",
                "risk_notes": [],
                "actions": [{"type": "start_dca", "params": {"symbol": "BTCUSDT", "quote": "USDT"}}],
            }
            return SimpleNamespace(content=[{"type": "text", "text": json.dumps(plan)}])

    return FakeModel()


async def _client_for_app(app):
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://test")


@pytest.mark.asyncio
async def test_health_ok():
    mod = _load_module()

    async with await _client_for_app(mod.app) as client:
        r = await client.get("/health")
        assert r.status_code == 200
        assert r.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_chat_happy_path_without_network():
    mod = _load_module()

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/chat", json={"user_input": "hello", "session_id": "t"})
        assert r.status_code == 200
        body = r.json()
        assert body["session_id"] == "t"
        assert body["assistant_text"] == "ok"
        assert body["actions"] == []


@pytest.mark.asyncio
async def test_chat_actions_produce_execution_preview():
    mod = _load_module()

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model_with_actions(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/chat", json={"user_input": "recommend", "session_id": "t2"})
        assert r.status_code == 200
        body = r.json()
        assert body["actions"] and body["actions"][0]["type"] == "start_dca"
        assert body["execution_preview"] is not None
        assert body["execution_preview"]["requires_confirmation"] is True
        assert body["execution_preview"]["actions"][0]["type"] == "start_dca"


@pytest.mark.asyncio
async def test_chat_buy_intent_returns_execution_plan():
    mod = _load_module()

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/chat", json={"user_input": "给我买 200 PAS 的 TokenDemo", "session_id": "buy1"})
        assert r.status_code == 200
        body = r.json()
        assert body["session_id"] == "buy1"
        assert body["execution_preview"]["intent"] == "buy_token"
        assert body["execution_plan"]["type"] == "buy_token"
        assert body["execution_plan"]["amount_in_pas"] == "200"
        assert body["execution_plan"]["token_out"]["symbol"] == "TokenDemo"


@pytest.mark.asyncio
async def test_chat_stream_buy_intent_includes_execution_plan(monkeypatch):
    mod = _load_module()

    monkeypatch.setenv("AGENT_BACKEND_STREAM_CHUNK_SIZE", "1000")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_DELAY_MS", "0")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_KEEPALIVE_SECONDS", "0")

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    done = None
    current_event = None
    current_data = None

    async with await _client_for_app(mod.app) as client:
        async with client.stream("POST", "/chat/stream", json={"user_input": "buy 200 PAS TokenDemo", "session_id": "buy_sse"}) as resp:
            assert resp.status_code == 200

            async for line in resp.aiter_lines():
                if not line:
                    if current_event is not None and current_data is not None:
                        if current_event == "done":
                            done = json.loads(current_data)
                            break
                    current_event = None
                    current_data = None
                    continue

                if line.startswith(":"):
                    continue

                if line.startswith("event:"):
                    current_event = line.split(":", 1)[1].strip()
                    continue

                if line.startswith("data:"):
                    current_data = line.split(":", 1)[1].strip()
                    continue

    assert done is not None
    assert done["session_id"] == "buy_sse"
    assert done["execution_preview"]["intent"] == "buy_token"
    assert done["execution_plan"]["type"] == "buy_token"


@pytest.mark.asyncio
async def test_chat_stream_emits_chunk_and_done_events(monkeypatch):
    mod = _load_module()

    monkeypatch.setenv("AGENT_BACKEND_STREAM_CHUNK_SIZE", "1000")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_DELAY_MS", "0")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_KEEPALIVE_SECONDS", "0")

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    events = []
    current_event = None
    current_data = None

    async with await _client_for_app(mod.app) as client:
        async with client.stream("POST", "/chat/stream", json={"user_input": "hello", "session_id": "s1"}) as resp:
            assert resp.status_code == 200

            async for line in resp.aiter_lines():
                if not line:
                    if current_event is not None and current_data is not None:
                        events.append((current_event, json.loads(current_data)))
                        if current_event == "done":
                            break
                    current_event = None
                    current_data = None
                    continue

                if line.startswith(":"):
                    continue

                if line.startswith("event:"):
                    current_event = line.split(":", 1)[1].strip()
                    continue

                if line.startswith("data:"):
                    current_data = line.split(":", 1)[1].strip()
                    continue

    assert events and events[0][0] == "chunk"
    assert events[-1][0] == "done"
    assert events[0][1]["session_id"] == "s1"
    assert "delta_text" in events[0][1]
    assert events[-1][1]["assistant_text"] == "ok"


@pytest.mark.asyncio
async def test_chat_stream_eth_query_prefetches_eth_snapshot(monkeypatch):
    mod = _load_module()

    monkeypatch.setenv("AGENT_BACKEND_USE_SIMPLE_STRATEGY", "1")
    monkeypatch.setenv("AGENT_BACKEND_DEFAULT_SYMBOL", "BTCUSDT")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_CHUNK_SIZE", "1000")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_DELAY_MS", "0")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_KEEPALIVE_SECONDS", "0")
    monkeypatch.setenv("AGENT_BACKEND_BINANCE_BASE_URL", "https://api.binance.com")

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    seen = {"symbol": None}

    async def _fake_fetch_cex_market_snapshot(
        base_url: str = "",
        timeout_s: float = 10.0,
        symbol: str = "BTCUSDT",
        interval: str = "1h",
        limit: int = 100,
        default_quote: str = "USDT",
    ):
        seen["symbol"] = symbol
        return {
            "ok": True,
            "symbol": symbol,
            "interval": interval,
            "timestamp": "test",
            "price": {"current": 1.0, "high_24h": 1.0, "low_24h": 1.0, "change_24h_pct": 0.0},
            "volume": {"current": 1.0, "avg_24h": 1.0, "ratio": 1.0},
            "indicators": {
                "rsi_14": 50.0,
                "macd": 0.0,
                "macd_signal": 0.0,
                "macd_histogram": 0.0,
                "ema_12": 1.0,
                "ema_26": 1.0,
                "bollinger_upper": 1.0,
                "bollinger_middle": 1.0,
                "bollinger_lower": 1.0,
            },
        }

    monkeypatch.setattr(mod, "fetch_cex_market_snapshot", _fake_fetch_cex_market_snapshot)

    # Triggers intent_hint=strategy and symbol extraction ETHUSDT
    async with await _client_for_app(mod.app) as client:
        async with client.stream("POST", "/chat/stream", json={"user_input": "给 ETH 一个策略", "session_id": "s_eth"}) as resp:
            assert resp.status_code == 200
            async for line in resp.aiter_lines():
                if line.startswith("event: done"):
                    break

    assert seen["symbol"] == "ETHUSDT"


@pytest.mark.asyncio
async def test_chat_stream_indicator_query_prefetches_eth_snapshot(monkeypatch):
    mod = _load_module()

    monkeypatch.setenv("AGENT_BACKEND_USE_SIMPLE_STRATEGY", "1")
    monkeypatch.setenv("AGENT_BACKEND_DEFAULT_SYMBOL", "BTCUSDT")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_CHUNK_SIZE", "1000")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_DELAY_MS", "0")
    monkeypatch.setenv("AGENT_BACKEND_STREAM_KEEPALIVE_SECONDS", "0")

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    seen = {"symbol": None}

    async def _fake_fetch_cex_market_snapshot(
        base_url: str = "",
        timeout_s: float = 10.0,
        symbol: str = "BTCUSDT",
        interval: str = "1h",
        limit: int = 100,
        default_quote: str = "USDT",
    ):
        seen["symbol"] = symbol
        return {"ok": False, "error": "stub"}

    monkeypatch.setattr(mod, "fetch_cex_market_snapshot", _fake_fetch_cex_market_snapshot)

    user_input = "请提供ETH/USDT的最新技术指标（如价格、RSI、MACD、布林带）"
    async with await _client_for_app(mod.app) as client:
        async with client.stream("POST", "/chat/stream", json={"user_input": user_input, "session_id": "s_eth_ind"}) as resp:
            assert resp.status_code == 200
            async for line in resp.aiter_lines():
                if line.startswith("event: done"):
                    break

    assert seen["symbol"] == "ETHUSDT"


@pytest.mark.asyncio
async def test_chat_validation_error():
    mod = _load_module()

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/chat", json={"session_id": "t"})
        assert r.status_code == 422
        j = r.json()
        assert j["code"] == "validation_error"


@pytest.mark.asyncio
async def test_chat_input_too_large():
    mod = _load_module()

    os.environ["AGENT_BACKEND_MAX_INPUT_CHARS"] = "5"

    mod.MODEL_BUNDLE = mod._ModelBundle(model=_fake_model(mod), formatter=_FakeFormatter())
    mod.SESSION_STORE = mod._InMemorySessionStore(ttl_seconds=60)
    mod.TOOLKIT = mod.Toolkit()

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/chat", json={"user_input": "012345", "session_id": "t"})
        assert r.status_code == 413
        j = r.json()
        assert j["code"] == "input_too_large"
