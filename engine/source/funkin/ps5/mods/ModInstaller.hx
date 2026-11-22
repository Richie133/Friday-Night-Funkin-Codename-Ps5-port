package funkin.ps5.mods;

import funkin.ps5.PS5;
import funkin.ps5.mods.OnlineMod;
import haxe.Json;
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
 *  - Psych Engine and V-Slice mods are converted (PsychConverter, VSliceConverter); the
 *    original files are kept next to the converted ones, so scripts that load
 *    them by their old paths still find them.
 *  - Whole game builds (an .exe with an assets/ folder) have their mods/ folders and
 *    their assets imported as a mod of the engine they were built with.
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
		var found = findMods(source, 0);
		if (found.length == 0) throw "This archive has no mod in it that the engine can read (no songs, data or charts were found).";
		var installed:Array<String> = [];
		var baseName = info != null ? PS5.safeFolderName(info.name) : null;
		for (i => mod in found) {
			var name = baseName != null ? (found.length > 1 ? '$baseName - ${PS5.safeFolderName(mod.name)}' : baseName) : PS5.safeFolderName(mod.name);
			var target = uniqueFolder(modsPath + name);
			log('Installing "${Path.withoutDirectory(target)}" (${mod.engine.label()})');
			switch (mod.engine) {
				case PSYCH: PsychConverter.convert(mod.path, target, log);
				case VSLICE: VSliceConverter.convert(mod.path, target, log);
				default: moveFolder(mod.path, target);
			}
			InstalledMods.writeInfo(target, info, mod.engine);
			installed.push(Path.withoutDirectory(target));
		}
		return installed;
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

	/** A build of an engine: its mods/ folder holds the mods; its assets/ is the mod itself. */
	static function findInBuild(dir:String):Array<FoundMod> {
		var result:Array<FoundMod> = [];
		#if sys
		var assets = Path.join([dir, "assets"]);
		var mods = Path.join([dir, "mods"]);
		var buildEngine = detectBuildEngine(dir);
		if (FileSystem.exists(mods) && FileSystem.isDirectory(mods)) {
			// a Psych "mods" folder can hold loose files (the mod itself) or one folder per mod
			var looseEngine = detect(mods);
			if (looseEngine != UNKNOWN && looseEngine != EXECUTABLE)
				result.push({path: mods, engine: looseEngine, name: Path.withoutDirectory(dir)});
			else for (entry in FileSystem.readDirectory(mods)) {
				var full = Path.join([mods, entry]);
				if (!FileSystem.isDirectory(full)) continue;
				var e = detect(full);
				if (e != UNKNOWN && e != EXECUTABLE && !isTemplateMod(full)) result.push({path: full, engine: e, name: entry});
			}
		}
		if (FileSystem.exists(assets) && FileSystem.isDirectory(assets) && hasCustomContent(assets)) {
			// assets of a source-modded build: imported as a mod for the engine it was built with
			var root = flattenBuildAssets(assets, buildEngine);
			if (root != null) result.push({path: root, engine: buildEngine == UNKNOWN ? PSYCH : buildEngine, name: Path.withoutDirectory(dir)});
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
		return PSYCH;
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

	/** A Psych build ships an empty "introMod" or "readme" template under mods/. */
	static function isTemplateMod(dir:String):Bool {
		var name = Path.withoutDirectory(dir).toLowerCase();
		return name == "intromod" || name == "readme" || name == "template";
	}

	/** True if a build's assets folder has anything besides the base game's weeks. */
	static function hasCustomContent(assets:String):Bool {
		#if sys
		for (p in ["data", "shared/data", "preload/data", "songs"]) if (FileSystem.exists(Path.join([assets, p]))) return true;
		#end
		return false;
	}

	/**
	 * Psych and V-Slice builds split their assets into libraries (preload/, shared/,
	 * week1/...). They are merged into one tree that looks like a mod folder.
	 */
	static function flattenBuildAssets(assets:String, engine:ModEngine):Null<String> {
		#if sys
		var out = assets + "-merged";
		if (FileSystem.exists(out)) PS5.deleteDir(out);
		Archive.mkdirs(out);
		var libraries = ["preload", "shared"];
		for (entry in FileSystem.readDirectory(assets)) {
			var full = Path.join([assets, entry]);
			if (!FileSystem.isDirectory(full)) continue;
			if (libraries.contains(entry) || ~/^week\d+$/.match(entry) || entry == "videos" || entry == "fonts" || entry == "songs" || entry == "music" || entry == "sounds" || entry == "images" || entry == "data") {
				if (libraries.contains(entry) || ~/^week\d+$/.match(entry)) mergeInto(full, out);
				else mergeInto(full, Path.join([out, entry]));
			}
		}
		return out;
		#else
		return null;
		#end
	}

	static function modName(dir:String, engine:ModEngine):String {
		#if sys
		try {
			switch (engine) {
				case PSYCH:
					var pack = Path.join([dir, "pack.json"]);
					if (FileSystem.exists(pack)) {
						var data:Dynamic = Json.parse(File.getContent(pack));
						if (data.name != null && Std.string(data.name).trim() != "") return Std.string(data.name);
					}
				case VSLICE:
					var meta = Path.join([dir, "_polymod_meta.json"]);
					if (FileSystem.exists(meta)) {
						var data:Dynamic = Json.parse(File.getContent(meta));
						if (data.title != null) return Std.string(data.title);
					}
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

	/** Copies `from` over `to`, keeping files that are already there unless overwritten. */
	public static function mergeInto(from:String, to:String) {
		#if sys
		Archive.mkdirs(to);
		for (entry in FileSystem.readDirectory(from)) {
			var src = Path.join([from, entry]);
			var dst = Path.join([to, entry]);
			if (FileSystem.isDirectory(src)) mergeInto(src, dst);
			else {
				if (FileSystem.exists(dst)) try FileSystem.deleteFile(dst) catch (e:Dynamic) {}
				try FileSystem.rename(src, dst) catch (e:Dynamic) File.copy(src, dst);
			}
		}
		#end
	}

	public static function copyFile(from:String, to:String) {
		#if sys
		if (!FileSystem.exists(from)) return;
		Archive.mkdirs(Path.directory(to));
		File.copy(from, to);
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

	/** Lists files under `dir` (relative paths), for converters. */
	public static function listFiles(dir:String, ?prefix:String = ""):Array<String> {
		var out:Array<String> = [];
		#if sys
		if (!FileSystem.exists(dir)) return out;
		for (e in FileSystem.readDirectory(dir)) {
			var full = Path.join([dir, e]);
			var rel = prefix == "" ? e : '$prefix/$e';
			if (FileSystem.isDirectory(full)) for (f in listFiles(full, rel)) out.push(f);
			else out.push(rel);
		}
		#end
		return out;
	}
}
