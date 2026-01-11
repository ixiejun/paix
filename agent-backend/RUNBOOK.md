# agent-backend Runbook

## 1. Install

From repo root:

- `python -m pip install -r agent-backend/requirements.txt`

## 2. Configure

Create `.env` from template:

- `cp agent-backend/.env.example .env`

Fill required values:

- `DEEPSEEK_API_KEY=...`

Optional:

- `AGENT_BACKEND_MODEL_PROVIDER=deepseek` (default)
- `AGENT_BACKEND_MODEL_NAME=deepseek-chat` (default)

AMM defaults (Polkadot Hub TestNet / Paseo) are already in `.env.example`:

- `AGENT_BACKEND_EVM_RPC_URL`
- `AGENT_BACKEND_UNISWAP_V2_ROUTER`
- `AGENT_BACKEND_UNISWAP_V2_FACTORY`
- `AGENT_BACKEND_WETH9`
- `AGENT_BACKEND_DEFAULT_TOKEN_A`
- `AGENT_BACKEND_DEFAULT_TOKEN_B`
- `AGENT_BACKEND_DEFAULT_PAIR`

## 3. Run

From repo root:

- `python agent-backend/main.py`

Or:

- `uvicorn agent-backend.main:app --host 0.0.0.0 --port 8000`

## 4. Smoke test

### 4.1 Health

- `curl -s http://127.0.0.1:8000/health`

Expected:

- `{"status":"ok"}`

### 4.2 Chat (LLM only)

- `curl -s http://127.0.0.1:8000/chat -H 'content-type: application/json' -d '{"session_id":"smoke","user_input":"你好，介绍一下你自己"}'`

### 4.3 Chat (LLM + on-chain AMM tool)

This prompt should trigger the AMM tool (Router/Pair):

- `curl -s http://127.0.0.1:8000/chat -H 'content-type: application/json' -d '{"session_id":"amm","user_input":"帮我查询链上 AMM：用 TokenA 换 TokenB，输入 1 个 TokenA，给我报价和池子 reserve。输出简短中文。"}'`

Expected (shape):

- `assistant_text` is a normal text string
- `execution_preview` contains:
  - `requires_confirmation=true`
  - `params.market_snapshot` with AMM quote + reserves
  - `routing` object

### 4.4 Chat (LLM + Binance klines + strategy recommendation)

This prompt should trigger Binance klines and return strategy `actions` (still preview-only):

- `curl -s http://127.0.0.1:8000/chat -H 'content-type: application/json' -d '{"session_id":"strat","user_input":"帮我看 BTC 最近 200 根 1 小时 K 线走势和波动，推荐适合的策略（DCA/网格/均值回归），并给出可执行的 action 参数。"}'`

Expected (shape):

- response includes `actions` with one of:
  - `start_dca`
  - `start_grid`
  - `start_mean_reversion`
- `execution_preview.requires_confirmation=true`

## 5. Tests

Tests avoid external network by disabling startup.

From repo root:

- `pytest -q agent-backend/tests`

## 6. Troubleshooting

- If `/chat` returns `504 upstream_timeout`:
  - check `DEEPSEEK_API_KEY`
  - check `DEEPSEEK_BASE_URL` (default `https://api.deepseek.com/v1`)
  - check `AGENT_BACKEND_UPSTREAM_TIMEOUT_SECONDS`

- If AMM tool fails:
  - check `AGENT_BACKEND_EVM_RPC_URL`
  - check Router/Pair addresses
  - check `AGENT_BACKEND_EVM_RPC_TIMEOUT_SECONDS`
