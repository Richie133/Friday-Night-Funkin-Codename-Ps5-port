package funkin.ps5;

import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Everything the PS5 port needs to know about where it runs.
 *
 * The port's features (mod browser, mod menu, on-screen keyboard, the warning,
 * the PS5 options) are compiled in with `PS5_PORT`, both on the console (`ps5`)
 * and in the Linux test build, so they can be tried on a PC.
 */
class PS5 {
	/** The port's own version, shown in the warning and the options. */
	public static inline var VERSION:String = "0.1.0-beta";
	/** Title ID of the native PS5 app. */
	public static inline var TITLE_ID:String = "PPSA52210";
	/** Where the port's source lives. */
	public static inline var REPO_URL:String = "https://github.com/Richie133/Friday-Night-Funkin-Codename-Ps5-port";
	/** Codename Engine's own pages, where people can support its developers. */
	public static inline var CODENAME_URL:String = "https://codename-engine.com/";
	public static inline var CODENAME_GAMEBANANA_URL:String = "https://gamebanana.com/mods/598553";
	public static inline var FUNKIN_URL:String = "https://ninja-muffin24.itch.io/funkin";

	/** True on the console itself. */
	public static var isConsole(get, never):Bool;
	static inline function get_isConsole():Bool return #if ps5 true #else false #end;

	/**
	 * The writable folder that holds mods, addons, saves, downloads and logs.
	 * On the console it is `/data/codename-ps5/`; on a PC it is the working folder.
	 */
	public static var dataRoot(default, null):String = #if ps5 "/data/codename-ps5/" #else "./" #end;

	/** The read-only folder with the engine's own assets (`assets/`, `manifest/`). */
	public static var appRoot(default, null):String = #if ps5 "/app0/" #else "./" #end;

	/** Downloaded archives wait here until they are installed. */
	public static var downloadsPath(get, never):String;
	static inline function get_downloadsPath():String return dataRoot + "downloads/";

	/** Thumbnails of online mods are cached here. */
	public static var cachePath(get, never):String;
	static inline function get_cachePath():String return dataRoot + "cache/";

	static var initialized:Bool = false;

	/**
	 * Called first thing in `Main.preInit`: makes the data folders and moves into
	 * the data folder so the engine's relative paths (`./mods/`, `./.temp/`) are writable.
	 */
	public static function preInit() {
		if (initialized) return;
		initialized = true;
		#if sys
		#if ps5
		for (dir in ["", "mods", "addons", "downloads", "cache", "logs", "saves"])
			ensureDir(dataRoot + dir);
		try Sys.setCwd(dataRoot) catch (e) {}
		#else
		for (dir in ["downloads", "cache"]) ensureDir(dataRoot + dir);
		#end
		#end
	}

	public static function ensureDir(path:String) {
		#if sys
		if (path == null || path == "") return;
		try {
			if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
		} catch (e) {}
		#end
	}

	/** Removes a folder and everything in it. Quietly does nothing if it is missing. */
	public static function deleteDir(path:String) {
		#if sys
		if (!FileSystem.exists(path)) return;
		if (!FileSystem.isDirectory(path)) {
			try FileSystem.deleteFile(path) catch (e) {}
			return;
		}
		for (entry in FileSystem.readDirectory(path)) {
			var full = Path.join([path, entry]);
			if (FileSystem.isDirectory(full)) deleteDir(full);
			else try FileSystem.deleteFile(full) catch (e) {}
		}
		try FileSystem.deleteDirectory(path) catch (e) {}
		#end
	}

	/** Size of a folder in bytes, walking every file in it. */
	public static function folderSize(path:String):Float {
		var total:Float = 0;
		#if sys
		if (!FileSystem.exists(path)) return 0;
		if (!FileSystem.isDirectory(path)) return FileSystem.stat(path).size;
		for (entry in FileSystem.readDirectory(path)) total += folderSize(Path.join([path, entry]));
		#end
		return total;
	}

	public static function formatBytes(bytes:Float):String {
		if (bytes < 1024) return Std.int(bytes) + " B";
		var units = ["KB", "MB", "GB"];
		var value = bytes / 1024;
		var unit = 0;
		while (value >= 1024 && unit < units.length - 1) {
			value /= 1024;
			unit++;
		}
		return (Math.round(value * 10) / 10) + " " + units[unit];
	}

	/**
	 * Opens a web page in the PS5's browser, or the PC's browser in the test build.
	 */
	public static function openURL(url:String) {
		#if ps5
		PS5Native.openBrowser(url);
		#else
		CoolUtil.openURL(url);
		#end
	}

	/** A safe folder name for a mod: letters, digits, spaces, dashes and underscores only. */
	public static function safeFolderName(name:String):String {
		if (name == null) return "mod";
		var buf = new StringBuf();
		for (i in 0...name.length) {
			var c = name.charCodeAt(i);
			if ((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code)
				|| c == " ".code || c == "-".code || c == "_".code || c == ".".code || c == "(".code || c == ")".code)
				buf.addChar(c);
			else if (c == "'".code || c == "&".code || c == "!".code) continue;
			else buf.add("_");
		}
		var result = StringTools.trim(buf.toString());
		while (result.endsWith(".")) result = result.substr(0, result.length - 1);
		if (result.length > 64) result = result.substr(0, 64);
		return result == "" ? "mod" : result;
	}
}
