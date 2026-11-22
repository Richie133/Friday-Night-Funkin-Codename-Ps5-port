package funkin.ps5.mods;

import funkin.ps5.PS5;
import funkin.ps5.mods.ModInstaller.copyFile;
import haxe.Json;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Converts a Psych Engine mod folder (0.6, 0.7 and 1.0 layouts) into one Codename Engine reads.
 *
 * | Psych                                  | Codename                                   |
 * |----------------------------------------|--------------------------------------------|
 * | data/<song>/<song>[-diff].json         | songs/<song>/charts/<diff>.json (as is: Codename reads Psych charts) |
 * | events (events.json and in the charts) | songs/<song>/events.json, Codename events  |
 * | songs/<song>/Inst.ogg, Voices*.ogg     | songs/<song>/song/                          |
 * | characters/<name>.json                 | data/characters/<name>.xml                 |
 * | stages/<name>.json                     | data/stages/<name>.xml                     |
 * | weeks/<name>.json                      | data/weeks/weeks/<name>.xml + weeks.txt    |
 * | images/icons/icon-<name>.png           | images/icons/<name>.png                    |
 * | images/storymenu/<week>.png            | images/menus/storymenu/weeks/<week>.png    |
 * | pack.json                              | data/config/modpack.ini                    |
 *
 * | scripts/*.lua                          | songs/*.lua (every song)                   |
 * | data/<song>/*.lua                      | songs/<song>/scripts/*.lua                 |
 * | stages/<name>.lua                      | data/stages/<name>.lua                     |
 * | custom_events/<name>.lua + .txt        | data/events/<name>.lua + .json             |
 * | custom_notetypes/<name>.lua            | data/notes/<name>.lua                      |
 *
 * The Psych Lua layer (funkin.ps5.psych) runs the .lua scripts, and plays Psych's
 * built-in events.
 */
class PsychConverter {
	public static function convert(source:String, target:String, log:String->Void) {
		#if sys
		ModInstaller.moveFolder(source, target);
		var root = target;
		var report = new Array<String>();

		convertPack(root);
		var songs = convertSongs(root, log);
		var chars = convertCharacters(root, log);
		var stages = convertStages(root, log);
		var weeks = convertWeeks(root, log);
		convertIcons(root);
		relocateScripts(root);
		writeMarker(root);

		report.push('$songs songs, $chars characters, $stages stages, $weeks weeks');
		var luaCount = 0;
		for (f in ModInstaller.listFiles(root)) if (f.toLowerCase().endsWith(".lua")) luaCount++;
		if (luaCount > 0) report.push('$luaCount Lua scripts (run by the Psych Lua layer)');
		log("Psych Engine mod converted: " + report.join(", "));
		#end
	}

	/** Notes where the mod came from (the mod menu shows converted mods as Psych mods). */
	static function writeMarker(root:String) {
		#if sys
		File.saveContent(Path.join([root, "data/config/ps5-psych.txt"]),
			"This mod was converted from a Psych Engine mod folder by the PS5 port.\n"
			+ "Its .lua scripts were moved to the folders Codename loads scripts from, and the\n"
			+ "port's Psych Lua layer runs them.\n");
		#end
	}

	static function convertPack(root:String) {
		#if sys
		var name = Path.withoutDirectory(root);
		var desc = "A Psych Engine mod.";
		var pack = Path.join([root, "pack.json"]);
		if (FileSystem.exists(pack)) try {
			var data:Dynamic = Json.parse(File.getContent(pack));
			if (data.name != null) name = Std.string(data.name);
			if (data.description != null) desc = Std.string(data.description);
		} catch (e:Dynamic) {}
		var iniPath = Path.join([root, "data/config/modpack.ini"]);
		if (!FileSystem.exists(iniPath)) {
			Archive.mkdirs(Path.directory(iniPath));
			File.saveContent(iniPath, '[Common]\nNAME=${oneLine(name)}\nDESCRIPTION=${oneLine(desc)}\nAPI_VERSION=1\n');
		}
		var icon = Path.join([root, "pack.png"]);
		if (FileSystem.exists(icon)) copyFile(icon, Path.join([root, "images/ps5-mod-icon.png"]));
		#end
	}

	static function convertSongs(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var data = Path.join([root, "data"]);
		if (!FileSystem.exists(data)) return 0;
		for (song in FileSystem.readDirectory(data)) {
			var folder = Path.join([data, song]);
			if (!FileSystem.isDirectory(folder)) continue;
			if (["characters", "stages", "weeks", "config", "scripts", "global", "states", "dialogue", "notes"].contains(song.toLowerCase())) continue;
			var charts = new Map<String, String>();
			var events:Array<Dynamic> = null;
			for (f in FileSystem.readDirectory(folder)) {
				var lower = f.toLowerCase();
				if (!lower.endsWith(".json")) continue;
				var base = lower.substr(0, lower.length - 5);
				if (base == "events") {
					try events = readEvents(Path.join([folder, f])) catch (e:Dynamic) {}
					continue;
				}
				var songLower = song.toLowerCase();
				if (!base.startsWith(songLower)) continue;
				var diff = base == songLower ? "normal" : base.substr(songLower.length);
				if (diff.startsWith("-")) diff = diff.substr(1);
				else if (diff != "normal") continue;
				if (diff == "") diff = "normal";
				charts.set(diff, Path.join([folder, f]));
			}
			if (!charts.keys().hasNext()) continue;

			var out = Path.join([root, "songs", song]);
			Archive.mkdirs(Path.join([out, "charts"]));
			var firstChart:Dynamic = null;
			var diffs = [];
			for (diff => path in charts) {
				try {
					var chart:Dynamic = Json.parse(File.getContent(path));
					// before 1.0 the chart sits under "song"; 1.0 keeps it at the top with "song" as its name
					var songData:Dynamic = unwrap(chart);
					if (firstChart == null || diff == "normal") firstChart = songData;
					File.saveContent(Path.join([out, "charts", '$diff.json']), Json.stringify(chart));
					diffs.push(diff);
				} catch (e:Dynamic) {
					log('  could not read the "$diff" chart of $song: $e');
				}
			}
			if (diffs.length == 0) continue;

			// Codename reads Psych charts but not their events: those go to songs/<song>/events.json
			var psychEvents = events == null ? [] : events.copy();
			if (firstChart != null) psychEvents = psychEvents.concat(chartEvents(firstChart));
			var converted = convertEvents(psychEvents, firstChart);
			if (converted.length > 0) {
				File.saveContent(Path.join([out, "events.json"]), Json.stringify({events: converted}));
				log('  $song: ${converted.length} events');
			}

			// audio: Psych keeps it in songs/<song>/, Codename in songs/<song>/song/
			var audioDir = Path.join([out, "song"]);
			Archive.mkdirs(audioDir);
			for (f in FileSystem.readDirectory(out)) {
				var lower = f.toLowerCase();
				if ((lower.startsWith("inst") || lower.startsWith("voices")) && (lower.endsWith(".ogg") || lower.endsWith(".mp3") || lower.endsWith(".wav")))
					FileSystem.rename(Path.join([out, f]), Path.join([audioDir, f]));
			}
			writeSongMeta(root, out, song, firstChart, sortDifficulties(diffs));
			count++;
		}
		#end
		return count;
	}

	static function readEvents(path:String):Array<Dynamic> {
		#if sys
		var songData:Dynamic = unwrap(Json.parse(File.getContent(path)));
		var events:Array<Dynamic> = songData.events;
		if (events != null && events.length > 0) return events;
		// old Psych events.json kept the events as notes with a -1 data column
		var out:Array<Dynamic> = [];
		var sections:Array<Dynamic> = songData.notes;
		if (sections != null) for (s in sections) {
			var notes:Array<Dynamic> = s.sectionNotes;
			if (notes != null) for (n in notes) if (n[1] < 0) out.push([n[0], [[n[2], n[3], n[4]]]]);
		}
		return out;
		#else
		return [];
		#end
	}

	/** The events a Psych chart carries itself: an "events" list, or event notes (data column -1). */
	static function chartEvents(songData:Dynamic):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var own:Array<Dynamic> = songData.events;
		if (own != null) out = out.concat(own);
		var sections:Array<Dynamic> = songData.notes;
		if (sections != null) for (s in sections) {
			var notes:Array<Dynamic> = s.sectionNotes;
			if (notes != null) for (n in notes) if (n != null && n.length >= 3 && n[1] < 0) out.push([n[0], [[n[2], n[3], n[4]]]]);
		}
		return out;
	}

	/**
	 * Psych events ([time, [[name, value1, value2], ...]]) as Codename chart events.
	 * Three have a Codename version and are rewritten into it; the rest keep their Psych
	 * names and are played by the Psych layer (funkin.ps5.psych.PsychEvents) or the mod's
	 * own data/events scripts.
	 */
	public static function convertEvents(psych:Array<Dynamic>, songData:Dynamic):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var seen = new Map<String, Bool>();
		for (entry in psych) {
			if (entry == null || !Std.isOfType(entry, Array) || entry.length < 2) continue;
			var time:Float = Std.parseFloat(Std.string(entry[0]));
			if (Math.isNaN(time)) continue;
			var list:Array<Dynamic> = entry[1];
			if (list == null || !Std.isOfType(list, Array)) continue;
			for (e in list) {
				if (e == null || !Std.isOfType(e, Array) || e.length < 1) continue;
				var name = Std.string(e[0]);
				var v1 = e.length > 1 && e[1] != null ? Std.string(e[1]) : "";
				var v2 = e.length > 2 && e[2] != null ? Std.string(e[2]) : "";
				var key = '$time|$name|$v1|$v2';
				if (seen.exists(key)) continue;
				seen.set(key, true);
				switch (name) {
					case "Add Camera Zoom":
						var game = Std.parseFloat(v1), hud = Std.parseFloat(v2);
						out.push({time: time, name: "Add Camera Zoom", params: ([Math.isNaN(game) ? 0.015 : game, "camGame"] : Array<Dynamic>)});
						out.push({time: time, name: "Add Camera Zoom", params: ([Math.isNaN(hud) ? 0.03 : hud, "camHUD"] : Array<Dynamic>)});
					case "Change Character":
						var strum = switch (v1.trim().toLowerCase()) {
							case "gf" | "girlfriend" | "1": 2;
							case "dad" | "opponent" | "0": 0;
							default: 1;
						};
						out.push({time: time, name: "Character Change", params: ([strum, 0, v2.trim(), true, 0, 0, true, false] : Array<Dynamic>)});
					case "Play Animation":
						out.push({time: time, name: "Psych Play Animation", params: ([v1, v2] : Array<Dynamic>)});
					default:
						out.push({time: time, name: name, params: ([v1, v2] : Array<Dynamic>)});
				}
			}
		}
		out.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		return out;
	}

	/** Moves Psych's .lua scripts to the folders Codename loads scripts from. */
	static function relocateScripts(root:String) {
		#if sys
		function moveLua(fromDir:String, toDir:String) {
			if (!FileSystem.exists(fromDir) || !FileSystem.isDirectory(fromDir)) return;
			for (f in FileSystem.readDirectory(fromDir)) {
				var lower = f.toLowerCase();
				// (Psych's .hx scripts are written for Psych's own classes: left where they are)
				if (!lower.endsWith(".lua")) continue;
				Archive.mkdirs(toDir);
				var dest = Path.join([toDir, f]);
				if (!FileSystem.exists(dest)) FileSystem.rename(Path.join([fromDir, f]), dest);
			}
		}
		// global scripts: every song
		moveLua(Path.join([root, "scripts"]), Path.join([root, "songs"]));
		// song scripts
		var data = Path.join([root, "data"]);
		if (FileSystem.exists(data)) for (song in FileSystem.readDirectory(data)) {
			var folder = Path.join([data, song]);
			if (!FileSystem.isDirectory(folder) || ["characters", "stages", "weeks", "config", "events", "notes"].contains(song)) continue;
			if (!FileSystem.exists(Path.join([root, "songs", song]))) continue;
			moveLua(folder, Path.join([root, "songs", song, "scripts"]));
		}
		// stage scripts
		moveLua(Path.join([root, "stages"]), Path.join([root, "data", "stages"]));
		// note types
		moveLua(Path.join([root, "custom_notetypes"]), Path.join([root, "data", "notes"]));
		// custom events: the script, plus a .json so Codename lists the event
		var events = Path.join([root, "custom_events"]);
		if (FileSystem.exists(events)) for (f in FileSystem.readDirectory(events)) {
			var lower = f.toLowerCase();
			if (!lower.endsWith(".lua") && !lower.endsWith(".txt")) continue;
			var name = Path.withoutExtension(f);
			var json = Path.join([root, "data", "events", '$name.json']);
			Archive.mkdirs(Path.directory(json));
			if (!FileSystem.exists(json)) File.saveContent(json, Json.stringify({params: [
				{name: "Value 1", type: "TString", defaultValue: ""},
				{name: "Value 2", type: "TString", defaultValue: ""}
			]}, null, "\t"));
		}
		moveLua(events, Path.join([root, "data", "events"]));
		// Psych's built-in events, so the chart editor shows their values
		var builtIn = ["Hey!", "Set GF Speed", "Camera Follow Pos", "Alt Idle Animation", "Screen Shake", "Change Scroll Speed", "Set Property",
			"Play Sound", "Psych Play Animation"];
		var used = new Map<String, Bool>();
		var songs = Path.join([root, "songs"]);
		if (FileSystem.exists(songs)) for (song in FileSystem.readDirectory(songs)) {
			var ev = Path.join([songs, song, "events.json"]);
			if (FileSystem.exists(ev)) try {
				var data:Dynamic = Json.parse(File.getContent(ev));
				var list:Array<Dynamic> = data.events;
				for (e in list) used.set(e.name, true);
			} catch (e:Dynamic) {}
		}
		for (name in builtIn) if (used.exists(name)) {
			var json = Path.join([root, "data", "events", '$name.json']);
			Archive.mkdirs(Path.directory(json));
			if (!FileSystem.exists(json)) File.saveContent(json, Json.stringify({params: [
				{name: "Value 1", type: "TString", defaultValue: ""},
				{name: "Value 2", type: "TString", defaultValue: ""}
			]}, null, "\t"));
		}
		#end
	}

	static function unwrap(chart:Dynamic):Dynamic {
		var inner:Dynamic = Reflect.field(chart, "song");
		return inner != null && !Std.isOfType(inner, String) ? inner : chart;
	}

	public static function sortDifficulties(diffs:Array<String>):Array<String> {
		var order = ["easy", "normal", "hard", "erect", "nightmare"];
		diffs.sort((a, b) -> {
			var ia = order.indexOf(a), ib = order.indexOf(b);
			if (ia < 0) ia = 100;
			if (ib < 0) ib = 100;
			return ia != ib ? ia - ib : Reflect.compare(a, b);
		});
		return diffs;
	}

	static function writeSongMeta(root:String, out:String, song:String, chart:Dynamic, diffs:Array<String>) {
		#if sys
		var metaPath = Path.join([out, "meta.json"]);
		if (FileSystem.exists(metaPath)) return;
		var display = chart != null && chart.song != null && Std.isOfType(chart.song, String) ? chart.song : song;
		var opponent:String = chart != null && chart.player2 != null ? chart.player2 : "dad";
		var icon = opponent;
		var color = "#9271FD";
		var charJson = Path.join([root, "characters", '$opponent.json']);
		if (FileSystem.exists(charJson)) try {
			var c:Dynamic = Json.parse(File.getContent(charJson));
			if (c.healthicon != null) icon = c.healthicon;
			var hb:Array<Int> = c.healthbar_colors;
			if (hb != null && hb.length >= 3) color = "#" + StringTools.hex(hb[0], 2) + StringTools.hex(hb[1], 2) + StringTools.hex(hb[2], 2);
		} catch (e:Dynamic) {}
		var meta = {
			displayName: display,
			bpm: chart != null && chart.bpm != null ? chart.bpm : 100,
			icon: icon,
			color: color,
			difficulties: diffs,
			coopAllowed: true,
			opponentModeAllowed: true,
			needsVoices: chart == null || chart.needsVoices != false
		};
		File.saveContent(metaPath, Json.stringify(meta, null, "\t"));
		#end
	}

	static function convertCharacters(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "characters"]);
		if (!FileSystem.exists(dir)) return 0;
		var outDir = Path.join([root, "data/characters"]);
		Archive.mkdirs(outDir);
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.toLowerCase().endsWith(".json")) continue;
			var name = f.substr(0, f.length - 5);
			var xmlPath = Path.join([outDir, '$name.xml']);
			if (FileSystem.exists(xmlPath)) continue;
			try {
				var c:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				File.saveContent(xmlPath, characterXml(root, c));
				count++;
			} catch (e:Dynamic) log('  character $name could not be converted: $e');
		}
		#end
		return count;
	}

	/** Psych character JSON to a Codename character XML. */
	public static function characterXml(root:String, c:Dynamic):String {
		var xml = Xml.createElement("character");
		var image:String = c.image != null ? Std.string(c.image) : "characters/BOYFRIEND";
		var firstImage = image.split(",")[0].trim();
		var sprite = spriteFor(root, firstImage);
		xml.set("sprite", sprite);
		var pos:Array<Float> = c.position;
		if (pos != null && pos.length >= 2) {
			xml.set("x", fmt(pos[0]));
			xml.set("y", fmt(pos[1]));
		}
		var cam:Array<Float> = c.camera_position;
		if (cam != null && cam.length >= 2) {
			xml.set("camx", fmt(cam[0]));
			xml.set("camy", fmt(cam[1]));
		}
		var flip = c.flip_x == true;
		xml.set("flipX", flip ? "true" : "false");
		// Psych's flip_x marks a sprite drawn for the player's side, which Codename calls isPlayer
		if (flip || c._editor_isPlayer == true) xml.set("isPlayer", "true");
		if (c.healthicon != null) xml.set("icon", Std.string(c.healthicon));
		var hb:Array<Int> = c.healthbar_colors;
		if (hb != null && hb.length >= 3) xml.set("color", "#" + StringTools.hex(hb[0], 2) + StringTools.hex(hb[1], 2) + StringTools.hex(hb[2], 2));
		if (c.scale != null && c.scale != 1) xml.set("scale", fmt(c.scale));
		if (c.sing_duration != null) xml.set("holdTime", fmt(c.sing_duration));
		if (c.no_antialiasing == true) xml.set("antialiasing", "false");
		var anims:Array<Dynamic> = c.animations;
		if (anims != null) for (a in anims) {
			var node = Xml.createElement("anim");
			node.set("name", Std.string(a.anim));
			node.set("anim", Std.string(a.name));
			var off:Array<Float> = a.offsets;
			node.set("x", fmt(off != null && off.length > 0 ? off[0] : 0));
			node.set("y", fmt(off != null && off.length > 1 ? off[1] : 0));
			node.set("fps", fmt(a.fps != null ? a.fps : 24));
			node.set("loop", a.loop == true ? "true" : "false");
			var indices:Array<Int> = a.indices;
			if (indices != null && indices.length > 0) node.set("indices", indices.join(","));
			xml.addChild(node);
		}
		return '<!DOCTYPE codename-engine-character>\n' + prettyXml(xml);
	}

	/**
	 * Codename loads character sheets from images/characters/. A Psych sheet kept elsewhere
	 * is copied there, so the XML can name it.
	 */
	static function spriteFor(root:String, image:String):String {
		var clean = image.replace("\\", "/");
		if (clean.startsWith("characters/")) return clean.substr("characters/".length);
		#if sys
		var flat = clean.replace("/", "_");
		for (ext in ["png", "xml", "txt", "json"]) {
			var src = Path.join([root, "images", '$clean.$ext']);
			if (FileSystem.exists(src)) copyFile(src, Path.join([root, "images/characters", '$flat.$ext']));
		}
		var atlas = Path.join([root, "images", clean]);
		if (FileSystem.exists(atlas) && FileSystem.isDirectory(atlas))
			ModInstaller.copyFolder(atlas, Path.join([root, "images/characters", flat]));
		return flat;
		#else
		return clean;
		#end
	}

	static function convertStages(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "stages"]);
		if (!FileSystem.exists(dir)) return 0;
		var outDir = Path.join([root, "data/stages"]);
		Archive.mkdirs(outDir);
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.toLowerCase().endsWith(".json")) continue;
			var name = f.substr(0, f.length - 5);
			var xmlPath = Path.join([outDir, '$name.xml']);
			if (FileSystem.exists(xmlPath)) continue;
			try {
				var s:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				File.saveContent(xmlPath, stageXml(name, s));
				count++;
			} catch (e:Dynamic) log('  stage $name could not be converted: $e');
		}
		#end
		return count;
	}

	/** Psych stage JSON (with the 1.0 editor's object list, when present) to a Codename stage XML. */
	public static function stageXml(name:String, s:Dynamic):String {
		var xml = Xml.createElement("stage");
		xml.set("name", name);
		xml.set("zoom", fmt(s.defaultZoom != null ? s.defaultZoom : 0.9));
		// Psych's "directory" names an asset library of the base game; in a mod folder
		// every picture is under images/, which is where Codename looks with no folder.
		xml.set("folder", "");
		if (s.isPixelStage == true) xml.set("pixel", "true");

		function charNode(tag:String, posField:String, camField:String) {
			var node = Xml.createElement(tag);
			var pos:Array<Float> = Reflect.field(s, posField);
			if (pos != null && pos.length >= 2) {
				node.set("x", fmt(pos[0]));
				node.set("y", fmt(pos[1]));
			}
			var cam:Array<Float> = Reflect.field(s, camField);
			if (cam != null && cam.length >= 2) {
				node.set("camxoffset", fmt(cam[0]));
				node.set("camyoffset", fmt(cam[1]));
			}
			if (tag == "girlfriend" && s.hide_girlfriend == true) node.set("alpha", "0");
			return node;
		}

		var objects:Array<Dynamic> = s.objects;
		if (objects != null && objects.length > 0) {
			var placed = new Map<String, Bool>();
			for (o in objects) {
				var type:String = o.type;
				switch (type) {
					case "gf", "gfGroup":
						xml.addChild(charNode("girlfriend", "girlfriend", "camera_girlfriend"));
						placed.set("gf", true);
					case "dad", "dadGroup":
						xml.addChild(charNode("dad", "opponent", "camera_opponent"));
						placed.set("dad", true);
					case "boyfriend", "boyfriendGroup":
						xml.addChild(charNode("boyfriend", "boyfriend", "camera_boyfriend"));
						placed.set("bf", true);
					case "square":
						var node = Xml.createElement("solid");
						node.set("name", Std.string(o.name));
						node.set("x", fmt(o.x));
						node.set("y", fmt(o.y));
						var sc:Array<Float> = o.scale;
						node.set("width", Std.string(Std.int(sc != null ? sc[0] : 1)));
						node.set("height", Std.string(Std.int(sc != null && sc.length > 1 ? sc[1] : 1)));
						if (o.color != null) node.set("color", "#" + Std.string(o.color).replace("#", "").replace("0x", ""));
						addSpriteProps(node, o);
						xml.addChild(node);
					case "sprite", "animatedSprite":
						var node = Xml.createElement("sprite");
						node.set("name", Std.string(o.name));
						node.set("x", fmt(o.x));
						node.set("y", fmt(o.y));
						node.set("sprite", Std.string(o.image));
						addSpriteProps(node, o);
						var anims:Array<Dynamic> = o.animations;
						if (anims != null) for (a in anims) {
							var an = Xml.createElement("anim");
							an.set("name", Std.string(a.anim));
							an.set("anim", Std.string(a.name));
							an.set("fps", fmt(a.fps != null ? a.fps : 24));
							an.set("loop", a.loop == true ? "true" : "false");
							var idx:Array<Int> = a.indices;
							if (idx != null && idx.length > 0) an.set("indices", idx.join(","));
							var off:Array<Float> = a.offsets;
							if (off != null && off.length >= 2) {
								an.set("x", fmt(off[0]));
								an.set("y", fmt(off[1]));
							}
							node.addChild(an);
						}
						if (o.firstAnimation != null) node.set("playOnStart", Std.string(o.firstAnimation));
						xml.addChild(node);
				}
			}
			if (!placed.exists("gf")) xml.addChild(charNode("girlfriend", "girlfriend", "camera_girlfriend"));
			if (!placed.exists("dad")) xml.addChild(charNode("dad", "opponent", "camera_opponent"));
			if (!placed.exists("bf")) xml.addChild(charNode("boyfriend", "boyfriend", "camera_boyfriend"));
		} else {
			// older stages build their sprites in the stage's .lua, which the Lua layer runs
			xml.addChild(charNode("girlfriend", "girlfriend", "camera_girlfriend"));
			xml.addChild(charNode("dad", "opponent", "camera_opponent"));
			xml.addChild(charNode("boyfriend", "boyfriend", "camera_boyfriend"));
		}
		return '<!DOCTYPE codename-engine-stage>\n' + prettyXml(xml);
	}

	static function addSpriteProps(node:Xml, o:Dynamic) {
		var scale:Array<Float> = o.scale;
		if (scale != null && scale.length >= 2 && (scale[0] != 1 || scale[1] != 1) && node.nodeName != "solid") {
			if (scale[0] == scale[1]) node.set("scale", fmt(scale[0]));
			else {
				node.set("scalex", fmt(scale[0]));
				node.set("scaley", fmt(scale[1]));
			}
		}
		var scroll:Array<Float> = o.scroll;
		if (scroll != null && scroll.length >= 2) {
			if (scroll[0] == scroll[1]) node.set("scroll", fmt(scroll[0]));
			else {
				node.set("scrollx", fmt(scroll[0]));
				node.set("scrolly", fmt(scroll[1]));
			}
		}
		if (o.alpha != null && o.alpha != 1) node.set("alpha", fmt(o.alpha));
		if (o.angle != null && o.angle != 0) node.set("angle", fmt(o.angle));
		if (o.flipX == true) node.set("flipX", "true");
		if (o.flipY == true) node.set("flipY", "true");
		if (o.antialiasing == false) node.set("antialiasing", "false");
	}

	static function convertWeeks(root:String, log:String->Void):Int {
		var count = 0;
		#if sys
		var dir = Path.join([root, "weeks"]);
		if (!FileSystem.exists(dir)) return 0;
		var outDir = Path.join([root, "data/weeks/weeks"]);
		Archive.mkdirs(outDir);
		var listFile = Path.join([root, "data/weeks/weeks.txt"]);
		var order = [];
		var files = FileSystem.readDirectory(dir).filter(f -> f.toLowerCase().endsWith(".json"));
		files.sort(Reflect.compare);
		var listPath = Path.join([root, "weeks/weekList.txt"]);
		if (FileSystem.exists(listPath)) {
			var listed = [for (l in File.getContent(listPath).split("\n")) if (l.trim() != "") l.trim() + ".json"];
			files.sort((a, b) -> {
				var ia = listed.indexOf(a), ib = listed.indexOf(b);
				return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib);
			});
		}
		for (f in files) {
			var name = f.substr(0, f.length - 5);
			try {
				var w:Dynamic = Json.parse(File.getContent(Path.join([dir, f])));
				var xml = Xml.createElement("week");
				xml.set("name", Std.string(w.storyName != null ? w.storyName : name));
				var chars:Array<String> = w.weekCharacters;
				if (chars != null) xml.set("chars", [for (c in chars) c == null || c == "" ? "none" : c].join(","));
				xml.set("sprite", name);
				var songs:Array<Dynamic> = w.songs;
				if (songs != null) for (s in songs) {
					var node = Xml.createElement("song");
					node.addChild(Xml.createPCData(Std.string(s[0])));
					if (w.hideFreeplay == true) node.set("hide", "true");
					xml.addChild(node);
				}
				var diffs:String = w.difficulties;
				if (diffs != null && diffs.trim() != "")
					for (d in diffs.split(",")) {
						var dn = Xml.createElement("difficulty");
						dn.set("name", d.trim().toLowerCase());
						xml.addChild(dn);
					}
				File.saveContent(Path.join([outDir, '$name.xml']), '<!DOCTYPE codename-engine-week>\n' + prettyXml(xml));
				// the story menu picture
				var pic = Path.join([root, "images/storymenu", '$name.png']);
				if (FileSystem.exists(pic)) copyFile(pic, Path.join([root, "images/menus/storymenu/weeks", '$name.png']));
				if (w.hideStoryMode != true) order.push(name);
				count++;
			} catch (e:Dynamic) log('  week $name could not be converted: $e');
		}
		if (order.length > 0 && !FileSystem.exists(listFile)) File.saveContent(listFile, order.join("\n"));
		#end
		return count;
	}

	static function convertIcons(root:String) {
		#if sys
		var dir = Path.join([root, "images/icons"]);
		if (!FileSystem.exists(dir)) return;
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.startsWith("icon-") || !f.toLowerCase().endsWith(".png")) continue;
			var target = Path.join([dir, f.substr("icon-".length)]);
			if (!FileSystem.exists(target)) copyFile(Path.join([dir, f]), target);
		}
		#end
	}

	static inline function oneLine(s:String):String return s.replace("\r", " ").replace("\n", " ").trim();

	public static function fmt(v:Dynamic):String {
		if (v == null) return "0";
		var f:Float = Std.isOfType(v, String) ? Std.parseFloat(v) : v;
		if (Math.isNaN(f)) return "0";
		return Std.string(Math.round(f * 1000) / 1000);
	}

	/** Xml.toString() puts everything on one line; this indents one element per line. */
	public static function prettyXml(xml:Xml):String {
		var buf = new StringBuf();
		function write(node:Xml, indent:String) {
			if (node.nodeType == PCData) {
				buf.add(StringTools.htmlEscape(node.nodeValue));
				return;
			}
			if (node.nodeType != Element) return;
			buf.add(indent + "<" + node.nodeName);
			for (att in node.attributes()) buf.add(' $att="${StringTools.htmlEscape(node.get(att), true)}"');
			var children = [for (c in node) c];
			if (children.length == 0) {
				buf.add("/>\n");
				return;
			}
			if (children.length == 1 && children[0].nodeType == PCData) {
				buf.add(">");
				write(children[0], "");
				buf.add('</${node.nodeName}>\n');
				return;
			}
			buf.add(">\n");
			for (c in children) write(c, indent + "\t");
			buf.add(indent + '</${node.nodeName}>\n');
		}
		write(xml, "");
		return buf.toString();
	}
}
