# Lua 5.1.5

Unmodified source of [Lua 5.1.5](https://www.lua.org/) (MIT license, see `COPYRIGHT`),
taken from the `third-party/lua51` folder of the lupa 2.4 source package. The
standalone interpreter and compiler (`lua.c`, `luac.c`, `print.c`) are left out.

The PS5 port runs Psych Engine `.lua` scripts with it (`source/funkin/ps5/psych`).
Psych Engine itself uses LuaJIT, which speaks the same Lua 5.1 language; LuaJIT's
`bit` library is provided by the port's bridge.

`onelua.cpp` builds all of it as one C++ file.
