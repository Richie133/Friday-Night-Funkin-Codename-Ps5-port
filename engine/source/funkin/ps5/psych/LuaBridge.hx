package funkin.ps5.psych;

/**
 * The C++ side of the Psych Lua layer: Lua 5.1 states, and values passed between Lua
 * and Haxe.
 *
 * A Lua state is known to Haxe by a number (its handle). Haxe functions are given to
 * Lua with `register(handle, name, id)`: calling `name` in Lua calls
 * `dispatch(handle, id, args)` here, which hands the call to the script that owns the
 * state. Haxe errors in those functions become Lua errors, and Lua errors in calls
 * from Haxe end up in `lastError`.
 *
 * Values: nil, booleans, numbers and strings map both ways; Lua tables become Haxe
 * arrays (keys 1..n) or anonymous objects, and Haxe arrays and anonymous objects
 * become tables. Other Haxe objects reach Lua as nil.
 */
@:build(funkin.ps5.psych.LuaBuild.addLua())
@:cppFileCode('
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <string.h>
#include <stdint.h>
#include <vector>

namespace cne_lua {

static std::vector<lua_State *> states;

static const char *HANDLE_KEY = "cne_ps5_handle";

static void push(lua_State *L, ::Dynamic value, int depth);
static ::Dynamic toHaxe(lua_State *L, int index, int depth);

static void pushString(lua_State *L, const ::String &s) {
	if (s.raw_ptr() == 0) { lua_pushnil(L); return; }
	int bytes = 0;
	const char *utf8 = s.utf8_str(0, false, &bytes);
	lua_pushlstring(L, utf8, bytes);
}

static void push(lua_State *L, ::Dynamic value, int depth) {
	if (value.mPtr == 0) { lua_pushnil(L); return; }
	switch (value->__GetType()) {
		case vtBool: lua_pushboolean(L, (bool)value ? 1 : 0); return;
		case vtInt: lua_pushnumber(L, (double)(int)value); return;
		case vtInt64: lua_pushnumber(L, (double)value); return;
		case vtFloat: lua_pushnumber(L, (double)value); return;
		case vtString: pushString(L, value->toString()); return;
		case vtArray: {
			if (depth > 16) { lua_pushnil(L); return; }
			int n = value->__length();
			lua_createtable(L, n, 0);
			for (int i = 0; i < n; i++) {
				push(L, value->__GetItem(i), depth + 1);
				lua_rawseti(L, -2, i + 1);
			}
			return;
		}
		case vtObject: {
			if (depth > 16) { lua_pushnil(L); return; }
			::Array< ::String > fields = ::Array_obj< ::String >::__new(0, 0);
			value->__GetFields(fields);
			lua_createtable(L, 0, fields->length);
			for (int i = 0; i < fields->length; i++) {
				::String key = fields[i];
				::Dynamic item = value->__Field(key, ::hx::paccDynamic);
				pushString(L, key);
				push(L, item, depth + 1);
				lua_rawset(L, -3);
			}
			return;
		}
		default: lua_pushnil(L); return;
	}
}

static ::Dynamic toHaxe(lua_State *L, int index, int depth) {
	if (index < 0 && index > LUA_REGISTRYINDEX) index = lua_gettop(L) + index + 1;
	switch (lua_type(L, index)) {
		case LUA_TBOOLEAN: return ::Dynamic(lua_toboolean(L, index) != 0);
		case LUA_TNUMBER: {
			double d = lua_tonumber(L, index);
			if (d == (double)(int)d && d >= -2147483648.0 && d <= 2147483647.0) return ::Dynamic((int)d);
			return ::Dynamic(d);
		}
		case LUA_TSTRING: {
			size_t len = 0;
			const char *s = lua_tolstring(L, index, &len);
			return ::Dynamic(::String::create(s, (int)len));
		}
		case LUA_TTABLE: {
			if (depth > 16) return ::Dynamic();
			// an array when its keys are exactly 1..n
			int n = (int)lua_objlen(L, index);
			int count = 0;
			bool isArray = true;
			lua_pushnil(L);
			while (lua_next(L, index) != 0) {
				count++;
				if (lua_type(L, -2) != LUA_TNUMBER) isArray = false;
				lua_pop(L, 1);
			}
			if (isArray && count == n) {
				::Array< ::Dynamic > array = ::Array_obj< ::Dynamic >::__new(0, n);
				for (int i = 1; i <= n; i++) {
					lua_rawgeti(L, index, i);
					array->push(toHaxe(L, -1, depth + 1));
					lua_pop(L, 1);
				}
				return array;
			}
			::hx::Anon object = ::hx::Anon_obj::Create();
			lua_pushnil(L);
			while (lua_next(L, index) != 0) {
				// lua_tostring would change a number key in place and confuse lua_next
				lua_pushvalue(L, -2);
				size_t len = 0;
				const char *key = lua_tolstring(L, -1, &len);
				if (key != 0) object->__SetField(::String::create(key, (int)len), toHaxe(L, -2, depth + 1), ::hx::paccDynamic);
				lua_pop(L, 2);
			}
			return object;
		}
		default: return ::Dynamic();
	}
}

static int handleOf(lua_State *L) {
	lua_getfield(L, LUA_REGISTRYINDEX, HANDLE_KEY);
	int handle = (int)lua_tointeger(L, -1);
	lua_pop(L, 1);
	return handle;
}

static int dispatch(lua_State *L) {
	int id = (int)lua_tointeger(L, lua_upvalueindex(1));
	int handle = handleOf(L);
	int n = lua_gettop(L);
	::Array< ::Dynamic > args = ::Array_obj< ::Dynamic >::__new(0, n);
	for (int i = 1; i <= n; i++) args->push(toHaxe(L, i, 0));
	::Dynamic result;
	::String error;
	bool failed = false;
	try {
		result = ::funkin::ps5::psych::LuaBridge_obj::dispatch(handle, id, args);
	} catch (::Dynamic e) {
		failed = true;
		error = e.mPtr ? e->toString() : ::String("error");
	}
	if (failed) {
		pushString(L, error);
		return lua_error(L);
	}
	push(L, result, 0);
	return 1;
}

// LuaJIT\'s bit library, which Psych scripts may use
static int32_t bitArg(lua_State *L, int i) { return (int32_t)(int64_t)luaL_checknumber(L, i); }
static int bitTobit(lua_State *L) { lua_pushnumber(L, bitArg(L, 1)); return 1; }
static int bitBnot(lua_State *L) { lua_pushnumber(L, ~bitArg(L, 1)); return 1; }
static int bitBand(lua_State *L) { int32_t r = bitArg(L, 1); for (int i = 2; i <= lua_gettop(L); i++) r &= bitArg(L, i); lua_pushnumber(L, r); return 1; }
static int bitBor(lua_State *L) { int32_t r = bitArg(L, 1); for (int i = 2; i <= lua_gettop(L); i++) r |= bitArg(L, i); lua_pushnumber(L, r); return 1; }
static int bitBxor(lua_State *L) { int32_t r = bitArg(L, 1); for (int i = 2; i <= lua_gettop(L); i++) r ^= bitArg(L, i); lua_pushnumber(L, r); return 1; }
static int bitLshift(lua_State *L) { lua_pushnumber(L, (int32_t)((uint32_t)bitArg(L, 1) << (bitArg(L, 2) & 31))); return 1; }
static int bitRshift(lua_State *L) { lua_pushnumber(L, (int32_t)((uint32_t)bitArg(L, 1) >> (bitArg(L, 2) & 31))); return 1; }
static int bitArshift(lua_State *L) { lua_pushnumber(L, bitArg(L, 1) >> (bitArg(L, 2) & 31)); return 1; }
static int bitTohex(lua_State *L) {
	char buf[16];
	int digits = lua_isnoneornil(L, 2) ? 8 : (int)luaL_checknumber(L, 2);
	if (digits < 1 || digits > 8) digits = 8;
	snprintf(buf, sizeof(buf), "%0*x", digits, (unsigned)bitArg(L, 1) & (digits == 8 ? 0xffffffffu : ((1u << (digits * 4)) - 1)));
	lua_pushstring(L, buf);
	return 1;
}
static const luaL_Reg bitFunctions[] = {
	{"tobit", bitTobit}, {"bnot", bitBnot}, {"band", bitBand}, {"bor", bitBor}, {"bxor", bitBxor},
	{"lshift", bitLshift}, {"rshift", bitRshift}, {"arshift", bitArshift}, {"tohex", bitTohex}, {0, 0}
};

static lua_State *state(int handle) {
	if (handle < 0 || handle >= (int)states.size()) return 0;
	return states[handle];
}

static int newState() {
	lua_State *L = luaL_newstate();
	if (L == 0) return -1;
	luaL_openlibs(L);
	luaL_register(L, "bit", bitFunctions);
	lua_pop(L, 1);
	int handle = -1;
	for (int i = 0; i < (int)states.size(); i++) if (states[i] == 0) { handle = i; break; }
	if (handle < 0) { handle = (int)states.size(); states.push_back(0); }
	states[handle] = L;
	lua_pushinteger(L, handle);
	lua_setfield(L, LUA_REGISTRYINDEX, HANDLE_KEY);
	return handle;
}

static void close(int handle) {
	lua_State *L = state(handle);
	if (L == 0) return;
	states[handle] = 0;
	lua_close(L);
}

static void setError(lua_State *L) {
	size_t len = 0;
	const char *message = lua_tolstring(L, -1, &len);
	::funkin::ps5::psych::LuaBridge_obj::lastError = message ? ::String::create(message, (int)len) : ::String("unknown Lua error");
	lua_pop(L, 1);
}

static bool run(int handle, ::String code, ::String chunkName) {
	lua_State *L = state(handle);
	if (L == 0) return false;
	int bytes = 0;
	const char *source = code.utf8_str(0, false, &bytes);
	::String name = ::String("@") + chunkName;
	if (luaL_loadbuffer(L, source, bytes, name.utf8_str()) != 0 || lua_pcall(L, 0, 0, 0) != 0) {
		setError(L);
		return false;
	}
	return true;
}

static void registerFunction(int handle, ::String name, int id) {
	lua_State *L = state(handle);
	if (L == 0) return;
	lua_pushinteger(L, id);
	lua_pushcclosure(L, dispatch, 1);
	lua_setglobal(L, name.utf8_str());
}

static bool hasFunction(int handle, ::String name) {
	lua_State *L = state(handle);
	if (L == 0) return false;
	lua_getglobal(L, name.utf8_str());
	bool found = lua_isfunction(L, -1);
	lua_pop(L, 1);
	return found;
}

/** Calls a global Lua function; `found` is false when there is no such function. */
static ::Dynamic call(int handle, ::String name, ::Dynamic args) {
	lua_State *L = state(handle);
	::funkin::ps5::psych::LuaBridge_obj::found = false;
	if (L == 0) return ::Dynamic();
	lua_getglobal(L, name.utf8_str());
	if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return ::Dynamic(); }
	::funkin::ps5::psych::LuaBridge_obj::found = true;
	int n = 0;
	if (args.mPtr != 0) {
		n = args->__length();
		luaL_checkstack(L, n + 4, "too many arguments");
		for (int i = 0; i < n; i++) push(L, args->__GetItem(i), 0);
	}
	if (lua_pcall(L, n, 1, 0) != 0) {
		setError(L);
		::funkin::ps5::psych::LuaBridge_obj::failed = true;
		return ::Dynamic();
	}
	::Dynamic result = toHaxe(L, -1, 0);
	lua_pop(L, 1);
	return result;
}

static void setGlobal(int handle, ::String name, ::Dynamic value) {
	lua_State *L = state(handle);
	if (L == 0) return;
	push(L, value, 0);
	lua_setglobal(L, name.utf8_str());
}

static ::Dynamic getGlobal(int handle, ::String name) {
	lua_State *L = state(handle);
	if (L == 0) return ::Dynamic();
	lua_getglobal(L, name.utf8_str());
	::Dynamic result = toHaxe(L, -1, 0);
	lua_pop(L, 1);
	return result;
}

static int memoryKB(int handle) {
	lua_State *L = state(handle);
	return L == 0 ? 0 : lua_gc(L, LUA_GCCOUNT, 0);
}

} // namespace cne_lua
')
class LuaBridge {
	/** The message of the last Lua error (a failed `run` or `call`). */
	public static var lastError:String = null;
	/** Whether the last `call` found the function. */
	public static var found:Bool = false;
	/** Whether the last `call` ended in an error. */
	public static var failed:Bool = false;

	/** Who answers `dispatch` for each state: set by PsychLuaScript. */
	public static var owners:Map<Int, (id:Int, args:Array<Dynamic>) -> Dynamic> = [];

	public static function newState():Int
		return untyped __cpp__("cne_lua::newState()");

	public static function close(handle:Int):Void {
		owners.remove(handle);
		untyped __cpp__("cne_lua::close({0})", handle);
	}

	/** Runs a chunk of Lua code. False (and `lastError`) when it fails. */
	public static function run(handle:Int, code:String, chunkName:String):Bool
		return untyped __cpp__("cne_lua::run({0}, {1}, {2})", handle, code, chunkName);

	public static function register(handle:Int, name:String, id:Int):Void
		untyped __cpp__("cne_lua::registerFunction({0}, {1}, {2})", handle, name, id);

	public static function hasFunction(handle:Int, name:String):Bool
		return untyped __cpp__("cne_lua::hasFunction({0}, {1})", handle, name);

	public static function call(handle:Int, name:String, args:Array<Dynamic>):Dynamic {
		failed = false;
		return untyped __cpp__("cne_lua::call({0}, {1}, {2})", handle, name, args);
	}

	public static function setGlobal(handle:Int, name:String, value:Dynamic):Void
		untyped __cpp__("cne_lua::setGlobal({0}, {1}, {2})", handle, name, value);

	public static function getGlobal(handle:Int, name:String):Dynamic
		return untyped __cpp__("cne_lua::getGlobal({0}, {1})", handle, name);

	public static function memoryKB(handle:Int):Int
		return untyped __cpp__("cne_lua::memoryKB({0})", handle);

	@:keep static function dispatch(handle:Int, id:Int, args:Dynamic):Dynamic {
		var owner = owners.get(handle);
		if (owner == null) return null;
		return owner(id, cast args);
	}
}
