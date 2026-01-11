import importlib.util
import json
import os
from pathlib import Path

import pytest


def _load_module():
    os.environ["AGENT_BACKEND_DISABLE_STARTUP"] = "1"

    path = Path(__file__).resolve().parents[1] / "main.py"
    spec = importlib.util.spec_from_file_location("agent_backend_main", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.asyncio
async def test_get_cex_klines_success(monkeypatch):
    mod = _load_module()

    class _Resp:
        def raise_for_status(self):
            return None

        def json(self):
            return [
                [
                    1,
                    "1.0",
                    "2.0",
                    "0.5",
                    "1.5",
                    "10",
                    2,
                ],
                [
                    2,
                    "1.5",
                    "2.5",
                    "1.0",
                    "2.0",
                    "11",
                    3,
                ],
            ]

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def get(self, url, params=None):
            assert "/api/v3/klines" in url
            assert params["symbol"] == "BTCUSDT"
            return _Resp()

    monkeypatch.setattr(mod.httpx, "AsyncClient", _Client)

    tr = await mod.get_cex_klines(
        symbol="BTC",
        interval="1h",
        limit=2,
        base_url="https://api.binance.com",
        timeout_s=1.0,
        default_quote="USDT",
        default_interval="1h",
        default_limit=200,
    )

    text = mod._tool_response_to_output(tr)
    obj = json.loads(text)
    assert obj["ok"] is True
    assert obj["source"] == "cex_binance"
    assert obj["symbol"] == "BTCUSDT"
    assert obj["interval"] == "1h"
    assert obj["limit"] == 2
    assert isinstance(obj["klines"], list)
    assert obj["klines"][0]["open"] == "1.0"


def test_extract_cex_symbol_from_text_basic_cases():
    mod = _load_module()

    assert (
        mod._extract_cex_symbol_from_text(
            "给BTC一个策略",
            default_quote="USDT",
            default_symbol="BTCUSDT",
        )
        == "BTCUSDT"
    )

    assert (
        mod._extract_cex_symbol_from_text(
            "给 ETH 一个策略",
            default_quote="USDT",
            default_symbol="BTCUSDT",
        )
        == "ETHUSDT"
    )

    assert (
        mod._extract_cex_symbol_from_text(
            "ETH/USDT 适合什么策略",
            default_quote="USDT",
            default_symbol="BTCUSDT",
        )
        == "ETHUSDT"
    )

    assert (
        mod._extract_cex_symbol_from_text(
            "随便聊聊",
            default_quote="USDT",
            default_symbol="BTCUSDT",
        )
        == "BTCUSDT"
    )


@pytest.mark.asyncio
async def test_fetch_cex_market_snapshot_uses_normalized_symbol(monkeypatch):
    mod = _load_module()

    class _Resp:
        def raise_for_status(self):
            return None

        def json(self):
            # 20 klines, each with at least OHLCV columns.
            rows = []
            for i in range(20):
                # open_time, open, high, low, close, volume, close_time
                rows.append([
                    1700000000000 + i * 60000,
                    "1.0",
                    "2.0",
                    "0.5",
                    str(1.0 + i * 0.1),
                    "10.0",
                    1700000000000 + (i + 1) * 60000,
                ])
            return rows

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def get(self, url, params=None):
            assert "/api/v3/klines" in url
            assert params is not None
            assert params["symbol"] == "ETHUSDT"
            return _Resp()

    monkeypatch.setattr(mod.httpx, "AsyncClient", _Client)

    snap = await mod.fetch_cex_market_snapshot(
        base_url="https://api.binance.com",
        timeout_s=1.0,
        symbol="eth",
        interval="1h",
        limit=20,
        default_quote="USDT",
    )

    assert isinstance(snap, dict)
    assert snap.get("ok") is True
    assert snap.get("symbol") == "ETHUSDT"


@pytest.mark.asyncio
async def test_get_cex_klines_error_structured(monkeypatch):
    mod = _load_module()

    class _Resp:
        def raise_for_status(self):
            raise RuntimeError("boom")

        def json(self):
            return None

    class _Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def get(self, url, params=None):
            return _Resp()

    monkeypatch.setattr(mod.httpx, "AsyncClient", _Client)

    tr = await mod.get_cex_klines(
        symbol="BTC",
        interval="1h",
        limit=2,
        base_url="https://api.binance.com",
        timeout_s=1.0,
        default_quote="USDT",
        default_interval="1h",
        default_limit=200,
    )

    text = mod._tool_response_to_output(tr)
    obj = json.loads(text)
    assert obj["ok"] is False
    assert obj["source"] == "cex_binance"
    assert "error" in obj
    assert obj["error"]["type"]
