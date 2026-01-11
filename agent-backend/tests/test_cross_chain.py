import importlib.util
import os
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


async def _client_for_app(app):
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://test")


@pytest.mark.asyncio
async def test_cross_chain_create_intent_idempotent_by_client_request_id():
    mod = _load_module()

    req = {
        "client_request_id": "req-1",
        "session_id": "s",
        "goal": "deposit",
        "target": {"connector": "xcm", "destination": "para-2000"},
        "asset": {"kind": "native", "amount": "1"},
        "timeout_seconds": 60,
    }

    async with await _client_for_app(mod.app) as client:
        r1 = await client.post("/cross-chain/intents", json=req)
        assert r1.status_code == 200
        b1 = r1.json()

        r2 = await client.post("/cross-chain/intents", json=req)
        assert r2.status_code == 200
        b2 = r2.json()

    assert b1["intent_id"] == b2["intent_id"]
    assert b1["state"] == "pending"
    assert b1["dispatch_id"]


@pytest.mark.asyncio
async def test_cross_chain_inbound_requires_auth_and_verified(monkeypatch):
    mod = _load_module()

    create_req = {
        "client_request_id": "req-2",
        "session_id": "s",
        "goal": "deposit",
        "target": {"connector": "hyperbridge_ismp", "destination": "evm:11155111"},
        "asset": {"kind": "erc20", "amount": "10", "token_address": "0x0000000000000000000000000000000000000001"},
    }

    monkeypatch.setenv("AGENT_BACKEND_CROSSCHAIN_INBOUND_TOKEN", "secret")

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/cross-chain/intents", json=create_req)
        assert r.status_code == 200
        intent_id = r.json()["intent_id"]

        r_unauth = await client.post(
            "/cross-chain/inbound",
            json={
                "connector": "hyperbridge_ismp",
                "intent_id": intent_id,
                "message_id": "m1",
                "status": "settled",
                "verified": True,
            },
        )
        assert r_unauth.status_code == 401

        r_unverified = await client.post(
            "/cross-chain/inbound",
            headers={"x-crosschain-auth": "secret"},
            json={
                "connector": "hyperbridge_ismp",
                "intent_id": intent_id,
                "message_id": "m1",
                "status": "settled",
                "verified": False,
            },
        )
        assert r_unverified.status_code == 400
        assert r_unverified.json()["code"] == "unverified_inbound"

        r_ok = await client.post(
            "/cross-chain/inbound",
            headers={"x-crosschain-auth": "secret"},
            json={
                "connector": "hyperbridge_ismp",
                "intent_id": intent_id,
                "message_id": "m1",
                "status": "settled",
                "verified": True,
            },
        )
        assert r_ok.status_code == 200
        body = r_ok.json()
        assert body["applied"] is True
        assert body["intent"]["state"] == "settled"


@pytest.mark.asyncio
async def test_cross_chain_inbound_replay_is_deduped(monkeypatch):
    mod = _load_module()

    monkeypatch.setenv("AGENT_BACKEND_CROSSCHAIN_INBOUND_TOKEN", "secret")

    create_req = {
        "client_request_id": "req-3",
        "session_id": "s",
        "goal": "path_c_roundtrip",
        "target": {"connector": "xcm", "destination": "para-2000"},
        "asset": {"kind": "native", "amount": "5"},
    }

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/cross-chain/intents", json=create_req)
        assert r.status_code == 200
        intent_id = r.json()["intent_id"]

        inbound = {
            "connector": "xcm",
            "intent_id": intent_id,
            "message_id": "m-replay",
            "status": "execution_completed",
            "verified": True,
        }

        r1 = await client.post("/cross-chain/inbound", headers={"x-crosschain-auth": "secret"}, json=inbound)
        assert r1.status_code == 200
        assert r1.json()["applied"] is True

        r2 = await client.post("/cross-chain/inbound", headers={"x-crosschain-auth": "secret"}, json=inbound)
        assert r2.status_code == 200
        assert r2.json()["applied"] is False


@pytest.mark.asyncio
async def test_cross_chain_cancel_and_refund_flow(monkeypatch):
    mod = _load_module()

    create_req = {
        "client_request_id": "req-4",
        "session_id": "s",
        "goal": "withdraw",
        "target": {"connector": "xcm", "destination": "para-2000"},
        "asset": {"kind": "native", "amount": "1"},
    }

    monkeypatch.setenv("AGENT_BACKEND_CROSSCHAIN_INBOUND_TOKEN", "secret")

    async with await _client_for_app(mod.app) as client:
        r = await client.post("/cross-chain/intents", json=create_req)
        assert r.status_code == 200
        intent_id = r.json()["intent_id"]

        r_cancel = await client.post(f"/cross-chain/intents/{intent_id}/cancel")
        assert r_cancel.status_code == 200
        assert r_cancel.json()["state"] == "cancelled"

        r_fail_inbound = await client.post(
            "/cross-chain/inbound",
            headers={"x-crosschain-auth": "secret"},
            json={
                "connector": "xcm",
                "intent_id": intent_id,
                "message_id": "m-fail",
                "status": "failed",
                "verified": True,
            },
        )
        assert r_fail_inbound.status_code == 200
        assert r_fail_inbound.json()["intent"]["state"] == "cancelled"

        r_refund = await client.post(f"/cross-chain/intents/{intent_id}/refund")
        assert r_refund.status_code == 409
        assert r_refund.json()["code"] == "cannot_refund"
