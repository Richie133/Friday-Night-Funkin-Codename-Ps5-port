package funkin.ps5.psych;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * Adds Lua 5.1 (engine/lua) to the hxcpp build of the class it is put on, with the
 * folder's absolute path worked out here, so the build works from any checkout.
 */
class LuaBuild {
	public static function addLua():Array<Field> {
		var here = Path.directory(Context.getPosInfos(Context.currentPos()).file);
		// engine/source/funkin/ps5/psych -> engine/lua
		var dir = Path.normalize(sys.FileSystem.absolutePath(Path.join([here, "..", "..", "..", "..", "lua"])));
		if (!sys.FileSystem.exists('$dir/onelua.cpp'))
			Context.error('Lua sources not found in $dir', Context.currentPos());
		var xml = '
<files id="cne-lua">
	<compilerflag value="-I$dir"/>
	<compilerflag value="-w"/>
	<file name="$dir/onelua.cpp">
		<depend name="$dir/luaconf.h"/>
	</file>
</files>
<files id="haxe">
	<compilerflag value="-I$dir"/>
</files>
<target id="haxe">
	<files id="cne-lua"/>
</target>';
		Context.getLocalClass().get().meta.add(":buildXml", [macro $v{xml}], Context.currentPos());
		return null;
	}
}
#end
