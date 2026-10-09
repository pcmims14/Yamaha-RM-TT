# Runs a Lua test script against a compiled .qplug in a real Lua 5.3 runtime.
# usage: python run_lua_test.py <test.lua> <plugin.qplug>
import sys
import lupa.lua53 as lua53

test_path, qplug_path = sys.argv[1], sys.argv[2]
lua = lua53.LuaRuntime(unpack_returned_tuples=True)
lua.globals().QPLUG = qplug_path.replace("\\", "/")
with open(test_path, "r", encoding="utf-8") as handle:
    source = handle.read()
try:
    lua.execute(source)
except Exception as error:  # a Lua error anywhere is a failed run
    print("LUA ERROR:", error)
    sys.exit(1)
