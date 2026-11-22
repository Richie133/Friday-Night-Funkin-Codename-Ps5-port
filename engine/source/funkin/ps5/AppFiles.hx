package funkin.ps5;

#if sys
import sys.FileSystem;
#end

using StringTools;

/**
 * Directory listing for the app's own folder.
 *
 * A PS5 title cannot list the folders of /app0 (readDirectory returns nothing
 * there), so the build writes the app's file list to /app0/ps5-files.txt and
 * listings under /app0 are answered from it. Everywhere else, and on other
 * platforms, this is sys.FileSystem.
 */
class AppFiles {
	#if ps5
	static var dirs:Map<String, Array<String>> = null;
	static var folders:Map<String, Bool> = null;

	static function load() {
		if (dirs != null) return;
		dirs = [];
		folders = ["" => true];
		var text = try sys.io.File.getContent(PS5.appRoot + "ps5-files.txt") catch (e) "";
		for (raw in text.split("\n")) {
			var line = raw.trim();
			if (line.startsWith("./")) line = line.substr(2);
			if (line == "") continue;
			var parts = line.split("/");
			var parent = "";
			for (i in 0...parts.length) {
				var entry = parts[i];
				var list = dirs.get(parent);
				if (list == null) dirs.set(parent, list = []);
				if (!list.contains(entry)) list.push(entry);
				var path = parent == "" ? entry : '$parent/$entry';
				if (i < parts.length - 1) folders.set(path, true);
				parent = path;
			}
		}
	}

	/** The path inside /app0 ("" for /app0 itself), or null for other places. */
	static function inApp(path:String):String {
		if (path == null) return null;
		var p = haxe.io.Path.normalize(path);
		var root = haxe.io.Path.removeTrailingSlashes(PS5.appRoot);
		if (p == root) return "";
		if (!p.startsWith(root + "/")) return null;
		return haxe.io.Path.removeTrailingSlashes(p.substr(root.length + 1));
	}
	#end

	public static function readDirectory(path:String):Array<String> {
		#if ps5
		var rel = inApp(path);
		if (rel != null) {
			load();
			var list = dirs.get(rel);
			return list == null ? [] : list.copy();
		}
		#end
		#if sys
		return FileSystem.readDirectory(path);
		#else
		return [];
		#end
	}

	public static function isDirectory(path:String):Bool {
		#if ps5
		var rel = inApp(path);
		if (rel != null) {
			load();
			return folders.exists(rel);
		}
		#end
		#if sys
		return FileSystem.isDirectory(path);
		#else
		return false;
		#end
	}
}
