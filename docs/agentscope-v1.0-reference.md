# AgentScope v1.0 Developer Reference (Paix)

> Source: https://doc.agentscope.io/ (Version: **Stable v1.0**)
>
> Local check in this repo: `python -c "import agentscope; print(agentscope.__version__)"` → **1.0.7**
>
> This note is a *developer-oriented* extraction of the official docs, focused on building `agent-backend`.

## 0. Installation
- Requirement: **Python 3.10+**
- Install:
  - `pip install agentscope`
  - Extras:
    - `pip install agentscope\[full\]` (Mac/Linux)
    - `pip install agentscope[full]` (Windows)

## 1. Core Mental Model (Key Concepts)
AgentScope centers around these primitives:

- **Message**
  - Unified data structure for:
    - agent↔agent exchange
    - UI rendering
    - memory storage
    - adapting to different model providers
- **Tool**
  - Any callable can be a tool: function / method / callable instance.
  - Can be sync/async and streaming/non-streaming.
- **Agent**
  - Core behavior in `AgentBase`:
    - `reply(msg)` produce response
    - `observe(msg)` receive without responding
    - `print(msg)` display
    - `handle_interrupt()` optional interruption handling
  - `ReActAgentBase` adds:
    - `_reasoning()` (LLM “think + tool call planning”)
    - `_acting()` (execute tools)
- **State**
  - Stateful objects support:
    - `state_dict()` snapshot
    - `load_state_dict()` restore
  - Supports nested state (agent includes memory + toolkit state).
- **Formatter**
  - Converts `Msg` into provider-specific payloads.
  - Note: “multi-agent in formatter” means multiple identities inside a single prompt; it is **not** multi-agent orchestration.

## 2. Message (`agentscope.message`)
### 2.1 `Msg` basics
A message has:
- `name`: sender identity label
- `role`: typically `system` / `user` / `assistant`
- `content`: either a string or a list of typed blocks

Example (text):
```python
from agentscope.message import Msg
msg = Msg(name="Jarvis", role="assistant", content="Hi! How can I help you?")
```

### 2.2 Content blocks (multimodal + reasoning + tools)
Common blocks:
- `TextBlock(type="text", text=...)`
- `ImageBlock` / `AudioBlock` / `VideoBlock` with `URLSource` or `Base64Source`
- `ThinkingBlock(type="thinking", thinking=...)` for reasoning models
- `ToolUseBlock(type="tool_use", id=..., name=..., input={...})`
- `ToolResultBlock(type="tool_result", id=..., name=..., output=...)`

Tool-use message pattern:
- assistant emits `ToolUseBlock`
- system returns `ToolResultBlock`

### 2.3 Serialization
- `Msg.to_dict()` → JSON-serializable dict
- `Msg.from_dict(d)` → restore

Helper methods:
- `get_text_content()` gather all `TextBlock` text joined by `\n`
- `get_content_blocks(block_type=...)`
- `has_content_blocks(block_type=...)`

## 3. Models (`agentscope.model`)
### 3.1 Model base
- `ChatModelBase(model_name: str, stream: bool)`
- Call style: `await model(messages=[...], tools=[...], tool_choice=..., structured_model=...)`
- Return:
  - `ChatResponse` (non-stream)
  - `AsyncGenerator[ChatResponse]` (stream)

`ChatResponse.content` is a list of blocks (Text/ToolUse/Thinking/Audio, etc.).

### 3.2 Reasoning support
- Reasoning models can produce `ThinkingBlock` when `enable_thinking=True` (provider-specific, e.g. DashScope Qwen).

### 3.3 Tools API (unified)
Providers have different tool formats; AgentScope unifies them via:
- `ToolUseBlock` / `ToolResultBlock`
- Model `__call__` accepts a list of **tools JSON schema**:
```python
json_schemas = [
  {
    "type": "function",
    "function": {
      "name": "google_search",
      "description": "Search for a query on Google.",
      "parameters": {
        "type": "object",
        "properties": {"query": {"type": "string", "description": "The search query."}},
        "required": ["query"],
      },
    },
  },
]
```

### 3.4 Structured output (`structured_model`)
Some model wrappers support:
- `structured_model: Type[pydantic.BaseModel]`

Behavior:
- AgentScope converts the BaseModel schema into a tool function and forces the model to call it.
- **When `structured_model` is set, `tools` and `tool_choice` are ignored**.

### 3.5 Provider wrappers (common knobs)
AgentScope provides wrappers like:
- **OpenAI**: reads `OPENAI_API_KEY` and optionally `OPENAI_ORGANIZATION` from env if not passed.
  - supports `client_type` = `openai` / `azure`
  - supports `tool_choice` (`auto`/`none`/`required` or tool name)
- **DashScope**: `DashScopeChatModel(model_name, api_key, stream, enable_thinking=...)`
  - note: DashScope tool_choice supports only `auto` and `none` (docs indicate `required` will be converted to `auto`)
- **Anthropic**: has `thinking` config for Claude reasoning (when supported)

#### DeepSeek (OpenAI-compatible)
`agent-backend` uses AgentScope `OpenAIChatModel` in **OpenAI-compatible mode** to connect to DeepSeek:

- **Required env**:
  - `DEEPSEEK_API_KEY`
  - `DEEPSEEK_BASE_URL` (optional, default `https://api.deepseek.com`)
  - `AGENT_BACKEND_MODEL_PROVIDER=deepseek` (default)
  - `AGENT_BACKEND_MODEL_NAME=deepseek-chat` (optional; default is `deepseek-chat` when provider is deepseek)

- **Implementation detail**:
  - Use `OpenAIChatModel(..., api_key=DEEPSEEK_API_KEY, client_args={"base_url": DEEPSEEK_BASE_URL})`

## 4. Tools (`agentscope.tool`) + `Toolkit`
### 4.1 Tool function contract
In AgentScope, a tool function:
- returns `ToolResponse` or a generator yielding `ToolResponse`
- should have a **docstring** describing function + args

Template:
```python
def tool_function(a: int, b: str) -> ToolResponse:
    """{description}

    Args:
        a (int): ...
        b (str): ...
    """
```

Notes:
- instance/class methods can be tools; `self`/`cls` are ignored.
- built-ins include `execute_python_code`, `execute_shell_command`, file read/write, etc.

### 4.2 Register tools and get JSON schemas
```python
from agentscope.tool import Toolkit

toolkit = Toolkit()
# toolkit.register_tool_function(my_search)
# toolkit.get_json_schemas()
```

### 4.3 Preset kwargs (hide secrets from LLM)
When registering tools you can preset args (e.g., API keys) so they do not appear in JSON schema:
```python
toolkit.register_tool_function(my_search, preset_kwargs={"api_key": "xxx"})
```

### 4.4 Execute tools via `ToolUseBlock`
`Toolkit.call_tool_function(...)`:
- input: `ToolUseBlock`
- output: async generator of `ToolResponse`

### 4.5 Tool interruption (async cancellation)
Toolkit supports interruption for **async** tools via asyncio cancellation:
- yields a `ToolResponse` with `is_interrupted=True` and a system-info message.
- sync tools cannot be canceled by asyncio; handle at agent level.

### 4.6 Tool groups + automatic tool management
Toolkit supports groups (e.g. `browser_use`):
- only active groups are exposed via `toolkit.get_json_schemas()`
- default group `basic` is always active
- `toolkit.update_tool_groups(group_names=[...], active=True)`
- meta tool `reset_equipped_tools` can switch active groups.

## 5. Memory (`agentscope.memory`)
- Base: `MemoryBase`
- Built-in: `InMemoryMemory`

To implement custom memory, implement:
- `add`, `delete`, `size`, `clear`, `get_memory`
- `state_dict`, `load_state_dict`

## 6. State & Session Management (`agentscope.session` / tutorial)
### 6.1 `StateModule`
`StateModule` supports:
- `register_state(attr_name, custom_to_json=None, custom_from_json=None)`
- `state_dict()`
- `load_state_dict(state_dict, strict=...)`

Nested state is automatic for attributes inheriting `StateModule`.

Stateful objects include: `AgentBase`, `MemoryBase`, `LongTermMemoryBase`, `Toolkit`.

### 6.2 Sessions (multiple stateful objects)
A session is a collection of `StateModule` objects in an application.

- Base: `SessionBase` with:
  - `save_session_state(session_id=..., **objects)`
  - `load_session_state(session_id=..., **objects)`
- Built-in: `JSONSession(save_dir=...)` which saves a `session_id.json`

Example pattern:
- request comes with `session_id`
- load agent state
- run agent
- save updated state

## 7. MCP integration (`agentscope.mcp`)
### 7.1 MCP clients
Two types:
- **Stateful client**: persistent session; must call `connect()` and `close()`
- **Stateless client**: creates session per call; lighter

Notes:
- StdIO MCP server: only stateful client (connect starts local server).
- When multiple stateful clients are connected, close in **LIFO** order.

Common methods:
- `list_tools()`
- `get_callable_function(func_name, wrap_tool_result=True|False)`

### 7.2 Register MCP tools into `Toolkit` (server-level)
- `await toolkit.register_mcp_client(client, group_name=...)`
- remove:
  - `toolkit.remove_tool_function(name)`
  - `await toolkit.remove_mcp_clients(client_names=[...])`

### 7.3 Function-level MCP tool usage
You can get a callable function object and:
- call directly
- wrap into your own tool
- choose whether to wrap results as `ToolResponse`

## 8. Agent construction patterns (backend-oriented)
### 8.1 ReAct agent constructor knobs (common)
ReAct agent takes:
- `name`, `sys_prompt`
- `model` (a `ChatModelBase` implementation)
- `formatter`
- optional: `toolkit`, `memory`, `long_term_memory` (+ mode)
- `enable_meta_tool`, `parallel_tool_calls`, `max_iters`, etc.

### 8.2 Build-from-scratch agent
Implement `AgentBase.reply()`:
- append to memory
- format prompt: `[system msg, memory msgs...]`
- call model
- create `Msg` response
- store response

## 9. Practical guidance for `agent-backend`
### 9.1 Recommended minimal integration architecture
- One `ReActAgent` per user `session_id` (state persisted)
- Use `JSONSession` (MVP) or replace `SessionBase` with Redis/DB implementation
- Use `Toolkit.preset_kwargs` for API keys and secrets
- Use structured output (`structured_model`) for:
  - intent extraction
  - action plans

### 9.2 Key invariants
- Keep `Msg` objects as the only persisted conversational unit (serializable)
- Do not leak secrets into tool schemas; keep secrets in preset kwargs + env vars
- Separate “agent orchestration state” from “external app state” (orders, balances, etc.)

### 9.3 Agent-backend model configuration (current)
`agent-backend/main.py` loads model config in this priority order:
- `AGENT_BACKEND_MODEL_CONFIG_PATH` JSON file: `{ "provider": "...", "model_name": "..." }`
- fallback env vars:
  - `AGENT_BACKEND_MODEL_PROVIDER` (default: `deepseek`)
  - `AGENT_BACKEND_MODEL_NAME` (required unless provider=deepseek)

Secrets MUST be passed via env vars:
- DeepSeek: `DEEPSEEK_API_KEY` (and `DEEPSEEK_BASE_URL` optionally)
- OpenAI: `OPENAI_API_KEY`
- DashScope: `DASHSCOPE_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`

---

## References
- Home: https://doc.agentscope.io/
- Tutorial index: https://doc.agentscope.io/tutorial/
- API: https://doc.agentscope.io/api/agentscope.html
- API (model): https://doc.agentscope.io/api/agentscope.model.html
- Tutorial (message): https://doc.agentscope.io/tutorial/quickstart_message.html
- Tutorial (tool): https://doc.agentscope.io/tutorial/task_tool.html
- Tutorial (state/session): https://doc.agentscope.io/tutorial/task_state.html
- Tutorial (mcp): https://doc.agentscope.io/tutorial/task_mcp.html
