package funkin.ps5.mods;

import funkin.backend.chart.Chart;
import funkin.backend.chart.ChartData;
import funkin.backend.chart.VSliceParser;
import funkin.ps5.mods.ModInstaller.copyFile;
import funkin.ps5.mods.PsychConverter.fmt;
import funkin.ps5.mods.PsychConverter.prettyXml;
import haxe.Json;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Converts a V-Slice (Friday Night Funkin' 0.3+ / Polymod) mod folder for Codename Engine.
 *
 *  - data/songs/<song>/<song>-metadata[-variation].json + -chart[-variation].json
 *      → songs/<song>/charts/[<variation>/]<difficulty>.json and meta[-variation].json,
 *        through Codename's own VSliceParser
 *  - songs/<song>/Inst*.ogg, Voices-*.ogg → songs/<song>/song/
 *  - data/characters/<name>.json → data/characters/<name>.xml
 *  - data/stages/<name>.json → data/stages/<name>.xml
 *  - data/levels/<name>.json → data/weeks/weeks/<name>.xml
 *  - _polymod_meta.json → data/config/modpack.ini
 *  - files under the base game's libraries (shared/, preload/, week1/...) are merged in
 *
 * Polymod .hxc scripts are kept but do not run: they are written against V-Slice's classes.
 */
class VSliceConverter {
	public static function convert(source:String, target:String, log:String->Void) {
		#if sys
		ModInstaller.moveFolder(source, target);
		var root = target;
		for (lib in ["shared", "preload"]) {
			var dir = Path.join([root, lib]);
			if (FileSystem.exists(dir) && FileSystem.isDirectory(dir)) ModInstaller.mergeInto(dir, root);
		}
		for (entry in FileSystem.readDirectory(root)) if (~/^week\d+$/.match(entry) && FileSystem.isDirectory(Path.join([root, entry])))
			ModInstaller.mergeInto(Path.join([root, entry]), root);

		convertMeta(root);
		var songs = convertSongs(root, log);
		var chars = convertCharacters(root, log);
		var stages = convertStages(root, log);
		var weeks = convertLevels(root, log);
		var scripts = 0;
		for (f in ModInstaller.listFiles(root)) if (f.endsWith(".hxc")) scripts++;
		log('V-Slice mod converted: $songs songs, $chars characters, $stages stages, $weeks weeks'
			+ (scripts > 0 ? ' ($scripts Polymod scripts kept, but they are not run)' : ""));
		#end
	}

	static function convertMeta(root:String) {
		#if sys
		var name = Path.withoutDirectory(root);
		var desc = "A V-Slice mod.";
		var metaPath = Path.join([root, "_polymod_meta.json"]);
		if (FileSystem.exists(metaPath)) try {
			var m:Dynamic = Json.parse(File.getContent(metaPath));
			if (m.title != null) name = m.title;
			if (m.description != null) desc = m.description;
		} catch (e:Dynamic) {}
		var ini = Path.join([root, "data/config/modpack.ini"]);
		if (!FileSystem.exists(ini)) {
			Archive.mkdirs(Path.directory(ini));
			File.saveContent(ini, '[Common]\nNAME=${name.replace("\n", " ")}\nDESCRIPTION=${desc.replace("\n", " ")}\nAPI_VERSION=1\n');
		}
		var icon = Path.join([root, "_polymod_icon.png"]);
		if (FileSystem.exists(icon)) copyFile(icon, Path.join([root, "images/ps5-mod-icon.png"]));
		#end
	}

	static function convertSongs(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "data/songs"]);
		if (!FileSystem.exists(dir)) return 0;
		for (song in FileSystem.readDirectory(dir)) {
			var folder = Path.join([dir, song]);
			if (!FileSystem.isDirectory(folder)) continue;
			var variations:Array<String> = [""];
			for (f in FileSystem.readDirectory(folder)) {
				var prefix = '$song-metadata-';
				if (f.startsWith(prefix) && f.endsWith(".json")) variations.push(f.substr(prefix.length, f.length - prefix.length - 5));
			}
			var out = Path.join([root, "songs", song]);
			var converted = false;
			for (variation in variations) {
				var suffix = variation == "" ? "" : '-$variation';
				var metaFile = Path.join([folder, '$song-metadata$suffix.json']);
				var chartFile = Path.join([folder, '$song-chart$suffix.json']);
				if (!FileSystem.exists(metaFile) || !FileSystem.exists(chartFile)) continue;
				try {
					var metaJson:Dynamic = Json.parse(File.getContent(metaFile));
					var chartJson:Dynamic = Json.parse(File.getContent(chartFile));
					var meta:ChartMetaData = {name: song};
					var charts:Array<ChartDataWithInfo> = [];
					if (variation != "") meta.vocalsSuffix = '-$variation';
					VSliceParser.parse(metaJson, chartJson, meta, charts, song);
					if (variation != "") meta.instSuffix = '-$variation';
					var chartDir = Path.join([out, "charts"].concat(variation == "" ? [] : [variation]));
					Archive.mkdirs(chartDir);
					var diffs = [];
					for (c in charts) {
						c.chart.meta = meta;
						var saved = Chart.filterChartForSaving(c.chart, false, true, true);
						File.saveContent(Path.join([chartDir, '${c.diffName}.json']), Json.stringify(saved));
						diffs.push(c.diffName);
					}
					meta.difficulties = PsychConverter.sortDifficulties(diffs);
					var icon = metaJson.playData != null && metaJson.playData.characters != null ? metaJson.playData.characters.opponent : null;
					if (icon != null) meta.icon = iconFor(root, icon);
					File.saveContent(Path.join([out, 'meta$suffix.json']), Chart.makeMetaSaveable(meta));
					converted = true;
				} catch (e:Dynamic) {
					log('  song $song${variation == "" ? "" : " (" + variation + ")"} could not be converted: $e');
				}
			}
			if (!converted) continue;
			var audio = Path.join([out, "song"]);
			Archive.mkdirs(audio);
			if (FileSystem.exists(out)) for (f in FileSystem.readDirectory(out)) {
				var lower = f.toLowerCase();
				if ((lower.startsWith("inst") || lower.startsWith("voices")) && (lower.endsWith(".ogg") || lower.endsWith(".mp3")))
					FileSystem.rename(Path.join([out, f]), Path.join([audio, f]));
			}
			count++;
		}
		#end
		return count;
	}

	static function iconFor(root:String, character:String):String {
		#if sys
		var path = Path.join([root, "data/characters", '$character.json']);
		if (FileSystem.exists(path)) try {
			var c:Dynamic = Json.parse(File.getContent(path));
			if (c.healthIcon != null && c.healthIcon.id != null) return c.healthIcon.id;
		} catch (e:Dynamic) {}
		#end
		return character;
	}

	static function convertCharacters(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "data/characters"]);
		if (!FileSystem.exists(dir)) return 0;
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.endsWith(".json")) continue;
			var name = f.substr(0, f.length - 5);
			var out = Path.join([dir, '$name.xml']);
			if (FileSystem.exists(out)) continue;
			try {
				var c:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				File.saveContent(out, characterXml(root, name, c));
				count++;
			} catch (e:Dynamic) log('  character $name could not be converted: $e');
		}
		// health icons: V-Slice uses images/icons/icon-<id>.png like Psych
		var icons = Path.join([root, "images/icons"]);
		if (FileSystem.exists(icons)) for (f in FileSystem.readDirectory(icons))
			if (f.startsWith("icon-") && f.endsWith(".png") && !FileSystem.exists(Path.join([icons, f.substr(5)])))
				copyFile(Path.join([icons, f]), Path.join([icons, f.substr(5)]));
		#end
		return count;
	}

	public static function characterXml(root:String, name:String, c:Dynamic):String {
		var xml = Xml.createElement("character");
		var asset = stripLibrary(c.assetPath != null ? Std.string(c.assetPath) : 'characters/$name');
		var sprite = asset.startsWith("characters/") ? asset.substr("characters/".length) : asset.replace("/", "_");
		if (!asset.startsWith("characters/")) copySheet(root, asset, sprite);
		xml.set("sprite", sprite);
		// V-Slice places a character by the bottom middle of its first frame, Codename by its corner
		var size = firstFrameSize(root, asset);
		var off:Array<Float> = c.offsets;
		var ox = off != null && off.length > 0 ? off[0] : 0.0;
		var oy = off != null && off.length > 1 ? off[1] : 0.0;
		var scale:Float = c.scale != null ? c.scale : 1;
		xml.set("x", fmt(ox - size.w * scale / 2));
		xml.set("y", fmt(oy - size.h * scale));
		var cam:Array<Float> = c.cameraOffsets;
		if (cam != null && cam.length >= 2) {
			xml.set("camx", fmt(cam[0]));
			xml.set("camy", fmt(cam[1]));
		}
		var playable = name.startsWith("bf") || name.indexOf("playable") >= 0 || name.startsWith("pico-player");
		var flip = c.flipX == true;
		xml.set("flipX", (playable ? !flip : flip) ? "true" : "false");
		if (playable) xml.set("isPlayer", "true");
		if (c.healthIcon != null && c.healthIcon.id != null) xml.set("icon", Std.string(c.healthIcon.id));
		if (scale != 1) xml.set("scale", fmt(scale));
		if (c.singTime != null) xml.set("holdTime", fmt(c.singTime));
		if (c.isPixel == true) xml.set("antialiasing", "false");
		var anims:Array<Dynamic> = c.animations;
		if (anims != null) for (a in anims) {
			var node = Xml.createElement("anim");
			node.set("name", Std.string(a.name));
			node.set("anim", Std.string(a.prefix));
			var o:Array<Float> = a.offsets;
			node.set("x", fmt(o != null && o.length > 0 ? o[0] : 0));
			node.set("y", fmt(o != null && o.length > 1 ? o[1] : 0));
			node.set("fps", fmt(a.frameRate != null ? a.frameRate : 24));
			node.set("loop", a.looped == true ? "true" : "false");
			var idx:Array<Int> = a.frameIndices;
			if (idx != null && idx.length > 0) node.set("indices", idx.join(","));
			xml.addChild(node);
		}
		return '<!DOCTYPE codename-engine-character>\n' + prettyXml(xml);
	}

	static function stripLibrary(path:String):String {
		var colon = path.indexOf(":");
		return colon >= 0 ? path.substr(colon + 1) : path;
	}

	static function copySheet(root:String, asset:String, flat:String) {
		#if sys
		for (ext in ["png", "xml", "txt"]) {
			var src = Path.join([root, "images", '$asset.$ext']);
			if (FileSystem.exists(src)) copyFile(src, Path.join([root, "images/characters", '$flat.$ext']));
		}
		var atlas = Path.join([root, "images", asset]);
		if (FileSystem.exists(atlas) && FileSystem.isDirectory(atlas)) ModInstaller.copyFolder(atlas, Path.join([root, "images/characters", flat]));
		#end
	}

	/** Size of the first frame of a Sparrow sheet, read from its XML; a guess if there is none. */
	static function firstFrameSize(root:String, asset:String):{w:Float, h:Float} {
		#if sys
		var candidates = [Path.join([root, "images", '$asset.xml'])];
		// base game characters the mod reuses: the engine's own copies
		candidates.push(funkin.ps5.PS5.appRoot + 'assets/images/$asset.xml');
		for (path in candidates) if (FileSystem.exists(path)) try {
			var x = Xml.parse(File.getContent(path)).firstElement();
			for (st in x.elementsNamed("SubTexture")) {
				var w = Std.parseFloat(st.get("frameWidth") != null ? st.get("frameWidth") : st.get("width"));
				var h = Std.parseFloat(st.get("frameHeight") != null ? st.get("frameHeight") : st.get("height"));
				if (!Math.isNaN(w) && !Math.isNaN(h)) return {w: w, h: h};
			}
		} catch (e:Dynamic) {}
		#end
		return {w: 400, h: 400};
	}

	static function convertStages(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "data/stages"]);
		if (!FileSystem.exists(dir)) return 0;
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.endsWith(".json")) continue;
			var name = f.substr(0, f.length - 5);
			var out = Path.join([dir, '$name.xml']);
			if (FileSystem.exists(out)) continue;
			try {
				var s:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				File.saveContent(out, stageXml(name, s));
				count++;
			} catch (e:Dynamic) log('  stage $name could not be converted: $e');
		}
		#end
		return count;
	}

	public static function stageXml(name:String, s:Dynamic):String {
		var xml = Xml.createElement("stage");
		xml.set("name", s.name != null ? Std.string(s.name) : name);
		xml.set("zoom", fmt(s.cameraZoom != null ? s.cameraZoom : 1));
		xml.set("folder", "");
		var items:Array<{z:Float, node:Xml}> = [];
		var props:Array<Dynamic> = s.props;
		if (props != null) for (p in props) {
			var node = Xml.createElement(p.assetPath != null && Std.string(p.assetPath).startsWith("#") ? "solid" : "sprite");
			node.set("name", Std.string(p.name));
			var pos:Array<Float> = p.position;
			node.set("x", fmt(pos != null ? pos[0] : 0));
			node.set("y", fmt(pos != null && pos.length > 1 ? pos[1] : 0));
			if (node.nodeName == "solid") {
				node.set("color", Std.string(p.assetPath));
				var sc:Dynamic = p.scale;
				node.set("width", Std.string(Std.int(Std.isOfType(sc, Array) ? sc[0] : (sc != null ? sc : 1))));
				node.set("height", Std.string(Std.int(Std.isOfType(sc, Array) ? sc[1] : (sc != null ? sc : 1))));
			} else {
				node.set("sprite", stripLibrary(Std.string(p.assetPath)));
				var sc:Dynamic = p.scale;
				if (Std.isOfType(sc, Array)) {
					var a:Array<Float> = sc;
					if (a[0] != 1 || a[1] != 1) {
						node.set("scalex", fmt(a[0]));
						node.set("scaley", fmt(a[1]));
					}
				} else if (sc != null && sc != 1) node.set("scale", fmt(sc));
			}
			var scroll:Array<Float> = p.scroll;
			if (scroll != null && scroll.length >= 2) {
				node.set("scrollx", fmt(scroll[0]));
				node.set("scrolly", fmt(scroll[1]));
			}
			if (p.alpha != null && p.alpha != 1) node.set("alpha", fmt(p.alpha));
			if (p.isPixel == true) node.set("antialiasing", "false");
			if (p.flipX == true) node.set("flipX", "true");
			if (p.flipY == true) node.set("flipY", "true");
			var anims:Array<Dynamic> = p.animations;
			if (anims != null) for (a in anims) {
				var an = Xml.createElement("anim");
				an.set("name", Std.string(a.name));
				an.set("anim", Std.string(a.prefix));
				an.set("fps", fmt(a.frameRate != null ? a.frameRate : 24));
				an.set("loop", a.looped == true ? "true" : "false");
				var idx:Array<Int> = a.frameIndices;
				if (idx != null && idx.length > 0) an.set("indices", idx.join(","));
				node.addChild(an);
			}
			if (p.startingAnimation != null) node.set("playOnStart", Std.string(p.startingAnimation));
			items.push({z: p.zIndex != null ? p.zIndex : 0, node: node});
		}
		var chars:Dynamic = s.characters;
		for (pair in [["bf", "boyfriend"], ["dad", "dad"], ["gf", "girlfriend"]]) {
			var c:Dynamic = chars != null ? Reflect.field(chars, pair[0]) : null;
			var node = Xml.createElement(pair[1]);
			var z:Float = pair[0] == "gf" ? 100 : 200;
			if (c != null) {
				var pos:Array<Float> = c.position;
				if (pos != null && pos.length >= 2) {
					node.set("x", fmt(pos[0]));
					node.set("y", fmt(pos[1]));
				}
				var cam:Array<Float> = c.cameraOffsets;
				if (cam != null && cam.length >= 2) {
					node.set("camxoffset", fmt(cam[0]));
					node.set("camyoffset", fmt(cam[1]));
				}
				if (c.zIndex != null) z = c.zIndex;
			}
			items.push({z: z, node: node});
		}
		items.sort((a, b) -> a.z < b.z ? -1 : (a.z > b.z ? 1 : 0));
		for (i in items) xml.addChild(i.node);
		return '<!DOCTYPE codename-engine-stage>\n' + prettyXml(xml);
	}

	static function convertLevels(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "data/levels"]);
		if (!FileSystem.exists(dir)) return 0;
		var outDir = Path.join([root, "data/weeks/weeks"]);
		Archive.mkdirs(outDir);
		var order = [];
		var files = FileSystem.readDirectory(dir).filter(f -> f.endsWith(".json"));
		files.sort(Reflect.compare);
		for (f in files) {
			var name = f.substr(0, f.length - 5);
			try {
				var l:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				var xml = Xml.createElement("week");
				xml.set("name", Std.string(l.name != null ? l.name : name));
				xml.set("sprite", name);
				var songs:Array<String> = l.songs;
				if (songs != null) for (s in songs) {
					var node = Xml.createElement("song");
					node.addChild(Xml.createPCData(s));
					xml.addChild(node);
				}
				File.saveContent(Path.join([outDir, '$name.xml']), '<!DOCTYPE codename-engine-week>\n' + prettyXml(xml));
				if (l.titleAsset != null) {
					var title = stripLibrary(Std.string(l.titleAsset));
					copyFile(Path.join([root, "images", '$title.png']), Path.join([root, "images/menus/storymenu/weeks", '$name.png']));
				}
				if (l.visible != false) order.push(name);
				count++;
			} catch (e:Dynamic) log('  level $name could not be converted: $e');
		}
		var list = Path.join([root, "data/weeks/weeks.txt"]);
		if (order.length > 0 && !FileSystem.exists(list)) File.saveContent(list, order.join("\n"));
		#end
		return count;
	}
}
