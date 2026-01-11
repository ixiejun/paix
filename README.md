# Paix Demo README（MVP）

## 1. 一句话介绍

Paix 是一个 **AI First & Mobile First** 的 DEX ：用户用自然语言对话表达交易/策略意图，系统在移动端提供“结果导向”的交易体验，并支持链上 AMM（Uniswap V2 Fork）与策略中心的演示闭环。

## 2. Demo 目标（你要向观众证明什么）

- **AI First**：交易即对话（自然语言 -> 意图识别 -> 生成可执行卡片）。
- **Mobile First**：无需跳转第三方钱包的移动端体验（本地非托管钱包 + 生物识别签名）。
- **Results Oriented**：用户不是在“下单”，而是在“启动策略/执行动作”。
- **链上可验证**：演示路径包含链上 AMM 报价/Swap 预览与执行确认。

## 3. 功能范围（对应 PRD）

- **AI 交易助手（AgentScope）**
  - 通过 `agent-backend` 提供对话接口（SSE 流式）。
  - 将用户自然语言解析为：
    - 策略建议（DCA / Grid / Mean Reversion 等）
    - 或交易执行计划（Execution Plan）

- **混合交易路由引擎（MVP 仅演示 AMM/预览）**
  - PRD 描述：合约 AMM / 链上 CLOB / 外部流动性聚合。
  - 当前仓库 MVP：
    - 后端可读取链上 Uniswap V2 Router/Pair 做报价与储备查询。

- **自动化策略中心（MVP 展示/卡片交互）**
  - 网格 / 定投 / 均值回归等策略的展示与执行确认 UI。

- **隐形钱包系统（MVP）**
  - App 内置非托管钱包。
  - 签名通过系统生物识别（FaceID/指纹）保护（以 `WalletState.authenticateForSigningDetailed()` 为入口）。

## 4. Demo 运行前准备

### 4.1 依赖

- **Python**：3.10+
- **Flutter**：与本机 SDK 配套（建议使用稳定版）

### 4.2 必要密钥（后端）

- 默认模型 provider 为 DeepSeek，需要：
  - `DEEPSEEK_API_KEY`

> 注意：密钥写入 `.env`，不要提交到 Git。

## 5. 启动方式

### 5.1 启动 agent-backend

从仓库根目录：

1. 安装依赖

```bash
python -m pip install -r agent-backend/requirements.txt
```

2. 配置环境变量

```bash
cp agent-backend/.env.example .env
```

编辑 `.env`，至少填写：

- `DEEPSEEK_API_KEY=...`

3. 运行（任选一种）

```bash
python agent-backend/main.py
```

或：

```bash
uvicorn agent-backend.main:app --host 0.0.0.0 --port 8000
```

4. 健康检查

```bash
curl -s http://127.0.0.1:8000/health
```

期望：

```json
{"status":"ok"}
```

### 5.2 启动 mobile（Flutter）

移动端默认连接：

- `http://127.0.0.1:8000`

如果需要覆盖：

```bash
flutter run --dart-define=AGENT_BACKEND_BASE_URL=http://127.0.0.1:8000
```

> iOS Simulator / Android Emulator 可能需要 host 映射（例如用局域网 IP 替换 127.0.0.1）。

## 6. Demo 流程脚本（推荐 8-12 分钟）

### 6.1 开场（30s）

- 目标用户：Web2 用户。
- 痛点：传统 CEX/DEX 门槛高。
- Paix 的定位：**用对话完成交易和策略启动**，并把复杂链上动作隐藏在移动端 UX 里。

### 6.2 钱包（1-2min）

1. 打开 App，进入 Wallet。
2. 说明：
   - 钱包为 **非托管**。
   - 签名需要生物识别确认（模拟 Web2 体验）。

演示点：
- 能看到资产列表（例如 PAS / 以及演示用资产）。

### 6.3 AI 对话 -> 生成策略卡片（2-3min）

1. 进入 Chat。
2. 输入示例（策略类）：

- `帮我看 BTC 最近 200 根 1 小时 K 线走势和波动，推荐适合的策略（DCA/网格/均值回归），并给出可执行的 action 参数。`

预期：
- AI 返回文本解释
- 并生成一个带 **Execute/Observe** 的策略卡片（MVP 预览/确认链路）

### 6.4 AI 对话 -> 生成交易/执行卡片（2-4min）

输入示例（交易类，按你当前环境可用资产调整）：

- `用 200U 买 BTC`
- 或者演示链上 AMM：`帮我查询链上 AMM：用 TokenA 换 TokenB，输入 1 个 TokenA，给我报价和池子 reserve。输出简短中文。`

预期：
- AI 返回报价/储备信息
- UI 出现执行确认入口（Bottom Sheet），展示关键参数

### 6.5 执行确认 + 生物识别（1-2min）

1. 点击卡片的执行按钮。
2. 说明确认弹窗（Bottom Sheet）的信息结构：
   - 交易对 / 金额 / 风险控制（slippage, deadline）
   - 路由信息（MVP 可展示）
3. 点击确认后触发生物识别授权（或系统提示）。

> 如果当前 Demo 不希望真实链上成交，可以只演示到确认页（preview-only）。

## 7. Demo 常见问题（FAQ）

### 7.1 后端启动了，但 App 没有流式返回

- 检查 `agent-backend` 是否在 `8000` 端口。
- 检查 App 的 `AGENT_BACKEND_BASE_URL` 是否指向正确地址。
- 若使用真机：`127.0.0.1` 需要换成本机局域网 IP。

### 7.2 `/chat` 返回 `504 upstream_timeout`

- 检查 `.env` 是否填了 `DEEPSEEK_API_KEY`。
- 检查 `DEEPSEEK_BASE_URL`（默认 `https://api.deepseek.com`）。
- 可调整 `AGENT_BACKEND_UPSTREAM_TIMEOUT_SECONDS`。

### 7.3 链上 AMM 工具失败

- 检查 `.env` 里的：
  - `AGENT_BACKEND_EVM_RPC_URL`
  - `AGENT_BACKEND_UNISWAP_V2_ROUTER`
  - `AGENT_BACKEND_WETH9`
- 检查 `AGENT_BACKEND_EVM_RPC_TIMEOUT_SECONDS`。

## 8. 备注：当前实现与 PRD 的差异

- PRD 的“混合路由引擎”包含 CLOB / Hyperliquid / Hyperbridge 等多路径。
- 当前仓库的 MVP 更聚焦于：
  - **移动端 UX**（钱包、卡片、确认、执行状态）
  - **AI -> 可执行结构化输出**（策略/执行计划）
  - **链上 AMM（报价/预览/部分执行能力）**

