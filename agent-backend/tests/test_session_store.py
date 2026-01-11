import importlib.util
import os
import time
from pathlib import Path


def _load_module():
    os.environ["AGENT_BACKEND_DISABLE_STARTUP"] = "1"

    path = Path(__file__).resolve().parents[1] / "main.py"
    spec = importlib.util.spec_from_file_location("agent_backend_main", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_session_ttl_cleanup_expires_entry():
    mod = _load_module()

    store = mod._InMemorySessionStore(ttl_seconds=1)

    memory = mod.InMemoryMemory()
    sid = "s"

    import asyncio

    async def run():
        await store.save_memory(sid, memory)
        store._entries[sid] = mod._SessionEntry(memory_state=memory.state_dict(), last_access_unix_s=time.time() - 10)
        await store.cleanup_expired()

    asyncio.run(run())

    assert sid not in store._entries
