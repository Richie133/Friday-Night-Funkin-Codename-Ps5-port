package funkin.ps5.mods;

import funkin.backend.assets.ModsFolder;
import funkin.ps5.PS5;
import funkin.ps5.mods.OnlineMod;
import haxe.Json;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/** What the mod menu shows about an installed mod. */
typedef InstalledMod = {
	var folder:String;
	var name:String;
	var description:String;
	var engine:ModEngine;
	var ?author:String;
	var ?source:ModSource;
	var ?sourceId:String;
	var ?version:String;
	var ?installed:Float;
	var ?icon:String;
	var ?thumbnailUrl:String;
	var ?profileUrl:String;
	var ?songs:Int;
	var ?isZip:Bool;
}

/**
 * Reads and writes ps5-mod.json, the note the port leaves in every mod it installs
 * (where it came from, which engine it was made for), and lists mods for the mod menu.
 * Mods copied in by hand (FTP, USB) are listed too; their engine is detected.
 */
class InstalledMods {
	public static inline var INFO_FILE:String = "ps5-mod.json";

	public static function writeInfo(folder:String, ?online:OnlineMod, engine:ModEngine) {
		#if sys
		var info:Dynamic = {
			engine: engine,
			installed: Date.now().getTime(),
			port: PS5.VERSION
		};
		if (online != null) {
			info.name = online.name;
			info.author = online.author;
			info.source = online.source;
			info.sourceId = online.id;
			info.version = online.version;
			info.thumbnailUrl = online.thumbnail;
			info.profileUrl = online.profileUrl;
		}
		try File.saveContent(Path.join([folder, INFO_FILE]), Json.stringify(info, null, "\t")) catch (e:Dynamic) {}
		#end
	}

	public static function list():Array<InstalledMod> {
		var result:Array<InstalledMod> = [];
		#if sys
		for (name in ModsFolder.getModsList()) {
			var m = read(name);
			if (m != null) result.push(m);
		}
		result.sort((a, b) -> Reflect.compare(a.name.toLowerCase(), b.name.toLowerCase()));
		#end
		return result;
	}

	public static function read(name:String):Null<InstalledMod> {
		#if sys
		var folder = ModsFolder.modsPath + name;
		var isZip = !FileSystem.exists(folder) || !FileSystem.isDirectory(folder);
		var conf = ModsFolder.getModConfig(name);
		var common = conf.exists("Common") ? conf.get("Common") : new Map<String, String>();
		var title = common.exists("NAME") && common.get("NAME") != "YOUR MOD NAME HERE" ? common.get("NAME") : name;
		var desc = common.exists("DESCRIPTION") && common.get("DESCRIPTION") != "YOUR MOD DESCRIPTION HERE" ? common.get("DESCRIPTION") : "";
		var mod:InstalledMod = {
			folder: name,
			name: title,
			description: desc,
			engine: isZip ? CODENAME : ModInstaller.detect(folder),
			isZip: isZip
		};
		if (!isZip) {
			if (FileSystem.exists(Path.join([folder, "data/config/ps5-psych.txt"]))) mod.engine = PSYCH;
			var infoPath = Path.join([folder, INFO_FILE]);
			if (FileSystem.exists(infoPath)) try {
				var info:Dynamic = Json.parse(File.getContent(infoPath));
				if (info.engine != null) mod.engine = info.engine;
				if (info.name != null && mod.name == name) mod.name = info.name;
				mod.author = info.author;
				mod.source = info.source;
				mod.sourceId = info.sourceId;
				mod.version = info.version;
				mod.installed = info.installed;
				mod.thumbnailUrl = info.thumbnailUrl;
				mod.profileUrl = info.profileUrl;
			} catch (e:Dynamic) {}
			for (icon in ["images/ps5-mod-icon.png", "pack.png", "_polymod_icon.png", "icon.png"]) {
				var p = Path.join([folder, icon]);
				if (FileSystem.exists(p)) {
					mod.icon = p;
					break;
				}
			}
			var songs = Path.join([folder, "songs"]);
			if (FileSystem.exists(songs) && FileSystem.isDirectory(songs))
				mod.songs = [for (s in FileSystem.readDirectory(songs)) if (FileSystem.isDirectory(Path.join([songs, s]))) s].length;
		}
		return mod;
		#else
		return null;
		#end
	}

	/** True if a mod with this GameBanana / Game Jolt id is already installed. */
	public static function findBySource(source:ModSource, id:String):Null<InstalledMod> {
		for (m in list()) if (m.source == source && m.sourceId == id) return m;
		return null;
	}

	public static function delete(mod:InstalledMod) {
		#if sys
		var folder = ModsFolder.modsPath + mod.folder;
		if (mod.isZip) {
			for (ext in Flags.ALLOWED_ZIP_EXTENSIONS) {
				var p = '$folder.$ext';
				if (FileSystem.exists(p)) FileSystem.deleteFile(p);
			}
		} else PS5.deleteDir(folder);
		if (ModsFolder.currentModFolder == mod.folder) Options.lastLoadedMod = null;
		#end
	}
}
