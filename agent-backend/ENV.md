# agent-backend 环境变量配置

本服务使用 `python-dotenv`（`load_dotenv()`）在启动时自动加载 `.env`。

## 1. 如何使用

- 推荐方式（从仓库根目录运行）：
  - 复制模板：
    - `cp agent-backend/.env.example .env`
  - 填写 `.env` 中的值（密钥不要提交）
  - 启动服务（两种任选其一）：
    - `python agent-backend/main.py`
    - 或者 `uvicorn agent-backend.main:app --host 0.0.0.0 --port 8000`

- 如果你想把 `.env` 放在 `agent-backend/` 目录下：
  - 你需要从 `agent-backend/` 目录启动（或自己指定 dotenv path）。

## 2. 变量列表（按重要性）

### 2.1 模型 Provider（默认 DeepSeek）

- `AGENT_BACKEND_MODEL_PROVIDER`
  - 可选值：`deepseek` | `openai` | `dashscope` | `anthropic`
  - 默认值：`deepseek`

- `AGENT_BACKEND_MODEL_NAME`
  - provider=deepseek 时：不填会默认 `deepseek-chat`
  - provider!=deepseek 时：必填

### 2.2 DeepSeek（默认，OpenAI 兼容模式）

服务内部使用 AgentScope `OpenAIChatModel`，并通过 `client_args={"base_url": ...}` 指向 DeepSeek。

- `DEEPSEEK_API_KEY`（必填，默认 provider=deepseek 时）
- `DEEPSEEK_BASE_URL`（可选，默认 `https://api.deepseek.com`）

### 2.3 OpenAI（可选）

如果你要切换到 OpenAI：
- `AGENT_BACKEND_MODEL_PROVIDER=openai`
- `AGENT_BACKEND_MODEL_NAME=...`

同时需要：
- `OPENAI_API_KEY`
- `OPENAI_ORGANIZATION`（可选）

### 2.4 DashScope（可选）

切换：
- `AGENT_BACKEND_MODEL_PROVIDER=dashscope`
- `AGENT_BACKEND_MODEL_NAME=...`

需要：
- `DASHSCOPE_API_KEY`

### 2.5 Anthropic（可选）

切换：
- `AGENT_BACKEND_MODEL_PROVIDER=anthropic`
- `AGENT_BACKEND_MODEL_NAME=...`

需要：
- `ANTHROPIC_API_KEY`

### 2.6 使用 JSON 配置文件（非密钥）

- `AGENT_BACKEND_MODEL_CONFIG_PATH`
  - 指向一个 JSON 文件，格式：

```json
{"provider":"deepseek","model_name":"deepseek-chat"}
```

说明：
- 如果设置了该变量，会优先使用该文件的 provider/model_name
- 密钥仍然必须通过 env（如 `DEEPSEEK_API_KEY`）提供

## 3. Session / 安全限制

- `AGENT_BACKEND_SESSION_TTL_SECONDS`
  - 默认：`1800`
  - 说明：同一个 `session_id` 的会话上下文在内存中保留的最大时间

- `AGENT_BACKEND_MAX_INPUT_CHARS`
  - 默认：`2000`
  - 说明：单次 `user_input` 最大长度，超出返回 `413`

- `AGENT_BACKEND_TOOL_MAX_ITERS`
  - 默认：`6`
  - 说明：单次对话中允许的工具调用循环次数上限（防止模型卡在工具调用循环）

## 4. AgentScope 运行标识/日志（可选）

- `AGENT_BACKEND_PROJECT`（默认 `paix`）
- `AGENT_BACKEND_RUN_NAME`（默认 `agent-backend`）
- `AGENT_BACKEND_LOG_PATH`（可选；不设则不写文件）
- `AGENT_BACKEND_LOG_LEVEL`（默认 `INFO`）
- `AGENT_BACKEND_STUDIO_URL`（可选）
- `AGENT_BACKEND_TRACING_URL`（可选）

## 5. 快速自测

- `GET /health` 应返回：`{"status":"ok"}`
- `POST /chat` body 示例：

```json
{"user_input":"帮我定投 DOT，每周 100U，跌破 5U 停止","session_id":"test"}
```

返回字段：
- `session_id`
- `assistant_text`
- `actions`（可选）
- `execution_preview`（可选）

## 6. 链上 AMM（Uniswap V2）配置（Polkadot Hub TestNet / Paseo）

`agent-backend` 的 Market Tool 默认会用链上 Uniswap V2 Router/Pair 读取报价与储备。
默认值来自：
`openspec/changes/add-polkadot-hub-uniswap-v2/deployments-polkadot-hub-testnet.md`

- `AGENT_BACKEND_EVM_RPC_URL`
  - 默认：`https://testnet-passet-hub-eth-rpc.polkadot.io`

- `AGENT_BACKEND_EVM_RPC_TIMEOUT_SECONDS`
  - 默认：`10`

- `AGENT_BACKEND_UNISWAP_V2_ROUTER`
  - 默认：Router02 地址（Paseo 部署）

- `AGENT_BACKEND_UNISWAP_V2_FACTORY`
  - 默认：Factory 地址（Paseo 部署）

- `AGENT_BACKEND_WETH9`
  - 默认：WETH9 地址（Paseo 部署）

- `AGENT_BACKEND_DEFAULT_TOKEN_A`
- `AGENT_BACKEND_DEFAULT_TOKEN_B`
- `AGENT_BACKEND_DEFAULT_PAIR`
  - 默认：使用 smoke test 产物中的 TokenA/TokenB/Pair 作为 MVP 默认报价样例

## 6.1 CEX Kline（Binance，策略推荐 MVP）

后端可通过 Binance 公共 Kline API 拉取历史 K 线作为“走势/波动”上下文。

- `AGENT_BACKEND_BINANCE_BASE_URL`
  - 默认：`https://api.binance.com`

- `AGENT_BACKEND_CEX_DEFAULT_QUOTE`
  - 默认：`USDT`
  - 说明：当用户只输入 `BTC` 时，会自动拼为 `BTCUSDT`

- `AGENT_BACKEND_CEX_TIMEOUT_SECONDS`
  - 默认：`10`

- `AGENT_BACKEND_CEX_KLINE_INTERVAL`
  - 默认：`1h`

- `AGENT_BACKEND_CEX_KLINE_LIMIT`
  - 默认：`200`

## 7. 上游模型超时（可选）

- `AGENT_BACKEND_UPSTREAM_TIMEOUT_SECONDS`
  - 默认：`60`
  - 说明：LLM 上游请求超时秒数，超时会返回 `504 upstream_timeout`

## 8. 测试模式（避免外部网络）

- `AGENT_BACKEND_DISABLE_STARTUP`
  - 值：`1`
  - 说明：跳过 startup 初始化（不加载模型、不连链上），用于本地/CI 跑测试时避免依赖外部网络与密钥
