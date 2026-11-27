package funkin.ps5.mods;

import funkin.ps5.PS5;
import funkin.ps5.mods.OnlineMod;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** What was found inside a downloaded archive. */
typedef FoundMod = {
	var path:String;
	var engine:ModEngine;
	var name:String;
}

/**
 * Turns an unpacked archive into folders under mods/.
 *
 *  - Codename Engine mods are moved in as they are.
 *  - Psych Engine and V-Slice mods are recognised but not installed: this version of
 *    the port does not run them, and the player is told so.
 *  - Whole Codename Engine builds (an .exe with an assets/ folder) have the mods in
 *    their mods/ folder installed, or their assets/ as a mod when that folder is empty.
 *
 * Runs on a worker thread; reports progress through `log`.
 */
class ModInstaller {
	public static var modsPath(get, never):String;
	static function get_modsPath():String return funkin.backend.assets.ModsFolder.modsPath;

	/**
	 * @param source the folder the archive was unpacked into
	 * @param info where the mod came from, written into ps5-mod.json
	 * @return the folder names the mods were installed as
	 */
	public static function install(source:String, info:Null<OnlineMod>, log:String->Void):Array<String> {
		var all = findMods(source, 0);
		if (all.length == 0) throw "This archive has no mod in it that the engine can read (no songs, data or charts were found).";
		var found = [for (mod in all) if (mod.engine.supported()) mod];
		for (mod in all) if (!mod.engine.supported()) log('Skipping "${mod.name}": ${mod.engine.label()} mods are not supported in this version');
		if (found.length == 0) throw unsupportedMessage(all[0].engine);
		var installed:Array<String> = [];
		var baseName = info != null ? PS5.safeFolderName(info.name) : null;
		for (i => mod in found) {
			var name = baseName != null ? (found.length > 1 ? '$baseName - ${PS5.safeFolderName(mod.name)}' : baseName) : PS5.safeFolderName(mod.name);
			var target = uniqueFolder(modsPath + name);
			log('Installing "${Path.withoutDirectory(target)}" (${mod.engine.label()})');
			moveFolder(mod.path, target);
			InstalledMods.writeInfo(target, info, mod.engine);
			installed.push(Path.withoutDirectory(target));
		}
		return installed;
	}

	static function unsupportedMessage(engine:ModEngine):String {
		return switch (engine) {
			case EXECUTABLE: "This is a whole game build with no Codename Engine mod in it. This version of the port installs Codename Engine mods only.";
			default: 'This is a ${engine.label()} mod. This version of the port installs Codename Engine mods only; Psych Engine and V-Slice support is switched off for now.';
		}
	}

	/** Walks the unpacked folder looking for mod roots, up to a few levels deep. */
	public static function findMods(dir:String, depth:Int):Array<FoundMod> {
		var result:Array<FoundMod> = [];
		#if sys
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return result;
		var engine = detect(dir);
		if (engine == EXECUTABLE) return findInBuild(dir);
		if (engine != UNKNOWN) {
			result.push({path: dir, engine: engine, name: modName(dir, engine)});
			return result;
		}
		if (depth >= 4) return result;
		var entries = FileSystem.readDirectory(dir);
		// an archive that is just "mods/<name>/" is unwrapped as well
		for (entry in entries) {
			var full = Path.join([dir, entry]);
			if (FileSystem.isDirectory(full) && !entry.startsWith(".") && entry != "__MACOSX")
				for (m in findMods(full, depth + 1)) result.push(m);
		}
		#end
		return result;
	}

	/**
	 * A build of an engine: its mods/ folder holds the mods. A build of another engine
	 * (or a source mod's own assets/) is reported as that engine, which is not installed.
	 */
	static function findInBuild(dir:String):Array<FoundMod> {
		var result:Array<FoundMod> = [];
		#if sys
		var mods = Path.join([dir, "mods"]);
		var buildEngine = detectBuildEngine(dir);
		if (FileSystem.exists(mods) && FileSystem.isDirectory(mods)) {
			var looseEngine = detect(mods);
			if (looseEngine != UNKNOWN && looseEngine != EXECUTABLE)
				result.push({path: mods, engine: looseEngine, name: Path.withoutDirectory(dir)});
			else for (entry in FileSystem.readDirectory(mods)) {
				var full = Path.join([mods, entry]);
				if (!FileSystem.isDirectory(full)) continue;
				var e = detect(full);
				if (e != UNKNOWN && e != EXECUTABLE) result.push({path: full, engine: e, name: entry});
			}
		}
		if (result.length == 0) {
			var assets = Path.join([dir, "assets"]);
			if (buildEngine == CODENAME && FileSystem.exists(Path.join([assets, "data"])))
				result.push({path: assets, engine: CODENAME, name: Path.withoutDirectory(dir)}); // a source mod's own build
			else
				result.push({path: dir, engine: buildEngine == CODENAME ? EXECUTABLE : buildEngine, name: Path.withoutDirectory(dir)});
		}
		#end
		return result;
	}

	/** Which engine a folder was made for, from the files only that engine has. */
	public static function detect(dir:String):ModEngine {
		#if sys
		inline function has(p:String) return FileSystem.exists(Path.join([dir, p]));
		inline function isDir(p:String) {
			var f = Path.join([dir, p]);
			return FileSystem.exists(f) && FileSystem.isDirectory(f);
		}
		var entries = try FileSystem.readDirectory(dir) catch (e:Dynamic) [];
		for (e in entries) if (e.toLowerCase().endsWith(".exe") && isDir("assets")) return EXECUTABLE;
		if (has("_polymod_meta.json") || isDir("data/songs") && containsSuffix(Path.join([dir, "data/songs"]), "-metadata.json", 2)) return VSLICE;
		if (has("data/config/modpack.ini") || isDir("songs") && containsPath(Path.join([dir, "songs"]), "charts", 1)
			|| has("data/global.hx") || isDir("data/characters") && containsSuffix(Path.join([dir, "data/characters"]), ".xml", 0)
			|| isDir("data/stages") && containsSuffix(Path.join([dir, "data/stages"]), ".xml", 0))
			return CODENAME;
		if (has("pack.json") || isDir("weeks") && containsSuffix(Path.join([dir, "weeks"]), ".json", 0)
			|| isDir("characters") && containsSuffix(Path.join([dir, "characters"]), ".json", 0)
			|| isDir("custom_events") || isDir("custom_notetypes")
			|| isDir("data") && isPsychChartFolder(Path.join([dir, "data"])))
			return PSYCH;
		if (isDir("data/characters") && containsSuffix(Path.join([dir, "data/characters"]), ".json", 0)) return VSLICE;
		#end
		return UNKNOWN;
	}

	static function detectBuildEngine(dir:String):ModEngine {
		#if sys
		var assets = Path.join([dir, "assets"]);
		if (FileSystem.exists(Path.join([assets, "data/config"])) || FileSystem.exists(Path.join([assets, "songs"])) && containsPath(Path.join([assets, "songs"]), "charts", 1))
			return CODENAME;
		if (FileSystem.exists(Path.join([assets, "preload/data/songs"])) || FileSystem.exists(Path.join([assets, "data/songs"])) && containsSuffix(Path.join([assets, "data/songs"]), "-metadata.json", 2))
			return VSLICE;
		#end
		return PSYCH; // most FNF builds are Psych Engine ones
	}

	/** Psych keeps charts in data/<song>/<song>.json. */
	static function isPsychChartFolder(data:String):Bool {
		#if sys
		for (song in FileSystem.readDirectory(data)) {
			var folder = Path.join([data, song]);
			if (!FileSystem.isDirectory(folder)) continue;
			for (f in FileSystem.readDirectory(folder)) if (f.toLowerCase().endsWith(".json") && f.toLowerCase().startsWith(song.toLowerCase())) return true;
		}
		#end
		return false;
	}

	static function modName(dir:String, engine:ModEngine):String {
		#if sys
		try {
			switch (engine) {
				case CODENAME:
					var ini = Path.join([dir, "data/config/modpack.ini"]);
					if (FileSystem.exists(ini)) {
						var conf = IniUtil.parseString(File.getContent(ini));
						if (conf.exists("Common") && conf["Common"].exists("NAME") && conf["Common"]["NAME"] != "YOUR MOD NAME HERE")
							return conf["Common"]["NAME"];
					}
				default:
			}
		} catch (e:Dynamic) {}
		#end
		return Path.withoutDirectory(dir);
	}

	// file helpers

	public static function uniqueFolder(path:String):String {
		#if sys
		if (!FileSystem.exists(path)) return path;
		var i = 2;
		while (FileSystem.exists('$path ($i)')) i++;
		return '$path ($i)';
		#else
		return path;
		#end
	}

	/** Moves a folder; falls back to copying when it is on another drive (a USB drive). */
	public static function moveFolder(from:String, to:String) {
		#if sys
		Archive.mkdirs(Path.directory(to));
		try {
			FileSystem.rename(from, to);
			return;
		} catch (e:Dynamic) {}
		copyFolder(from, to);
		PS5.deleteDir(from);
		#end
	}

	public static function copyFolder(from:String, to:String) {
		#if sys
		Archive.mkdirs(to);
		for (entry in FileSystem.readDirectory(from)) {
			var src = Path.join([from, entry]);
			var dst = Path.join([to, entry]);
			if (FileSystem.isDirectory(src)) copyFolder(src, dst);
			else File.copy(src, dst);
		}
		#end
	}

	static function containsSuffix(dir:String, suffix:String, depth:Int):Bool {
		#if sys
		if (!FileSystem.exists(dir)) return false;
		for (e in FileSystem.readDirectory(dir)) {
			var full = Path.join([dir, e]);
			if (e.toLowerCase().endsWith(suffix)) return true;
			if (depth > 0 && FileSystem.isDirectory(full) && containsSuffix(full, suffix, depth - 1)) return true;
		}
		#end
		return false;
	}

	static function containsPath(dir:String, name:String, depth:Int):Bool {
		#if sys
		if (!FileSystem.exists(dir)) return false;
		for (e in FileSystem.readDirectory(dir)) {
			var full = Path.join([dir, e]);
			if (!FileSystem.isDirectory(full)) continue;
			if (e.toLowerCase() == name) return true;
			if (depth > 0 && containsPath(full, name, depth - 1)) return true;
		}
		#end
		return false;
	}
}
