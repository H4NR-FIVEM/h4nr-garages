"""Lua 5.4 syntax check of the resource and the offline server spec (liblua5.4 via ctypes)."""
import ctypes, ctypes.util, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lua = ctypes.CDLL(ctypes.util.find_library('lua5.4'))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_pushstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.lua_setglobal.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.lua_close.argtypes = [ctypes.c_void_p]


def run(source, name, execute):
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    lua.lua_pushstring(state, str(root).encode())
    lua.lua_setglobal(state, b'ROOT')
    data = re.sub(r'`[^`\n]+`', '0', source).encode() if not execute else source.encode()
    status = lua.luaL_loadbufferx(state, data, len(data), ('@' + str(name)).encode(), None)
    if not status and execute:
        status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if status:
        message = lua.lua_tolstring(state, -1, None).decode()
        lua.lua_close(state)
        sys.exit(message)
    lua.lua_close(state)


files = [p for p in root.rglob('*.lua') if '.git' not in p.parts]
for path in files:
    run(path.read_text(), path, False)
print(f'Lua syntax: {len(files)} files passed', flush=True)
for spec in sorted((root / 'tests').glob('*_spec.lua')):
    run(spec.read_text(), spec, True)
