package funkin.ps5.psych;

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSave;
import flixel.util.FlxTimer;
import funkin.backend.FunkinSprite;
import funkin.backend.scripting.HScript;
import funkin.backend.scripting.Script;
import funkin.backend.system.Conductor;
import funkin.game.Note;
import funkin.game.PlayState;
import funkin.game.Strum;
import haxe.io.Path;
import openfl.Assets;
import openfl.display.BlendMode;

using StringTools;

/**
 * The functions Psych Engine gives Lua scripts, written against Codename's PlayState.
 *
 * Covers what Psych mods use most: sprites and texts, properties (with Psych's names
 * for PlayState's objects), tweens, timers, sounds, cameras, characters, score and
 * health, input, saves, shared variables, and runHaxeCode through Codename's HScript.
 * A function that is not here is reported once, and returns nil.
 */
class PsychFunctions {
	// what the scripts made, by tag; shared by all scripts of one PlayState
	public static var sprites:Map<String, FlxSprite> = [];
	public static var texts:Map<String, FlxText> = [];
	public static var tweens:Map<String, FlxTween> = [];
	public static var timers:Map<String, FlxTimer> = [];
	public static var sounds:Map<String, FlxSound> = [];
	public static var variables:Map<String, Dynamic> = [];
	public static var saves:Map<String, FlxSave> = [];
	public static var camOther:FlxCamera;
	static var forPlayState:PlayState;
	static var debugTexts:Array<FlxText> = [];
	static var missing:Map<String, Bool> = [];
	static var hscripts:Map<PsychLuaScript, HScript> = [];

	/** Resets the shared tables when a new PlayState starts. */
	static function checkState() {
		var game = PlayState.instance;
		if (game == forPlayState) return;
		forPlayState = game;
		for (t in tweens) t.cancel();
		for (t in timers) t.cancel();
		for (s in sounds) s.stop();
		sprites = [];
		texts = [];
		tweens = [];
		timers = [];
		sounds = [];
		variables = [];
		debugTexts = [];
		camOther = null;
		hscripts = [];
	}

	public static function scriptStopped(script:PsychLuaScript) {
		var h = hscripts.get(script);
		if (h != null) {
			hscripts.remove(script);
			h.destroy();
		}
	}

	static inline function game():PlayState
		return PlayState.instance;

	public static function isPlain(v:Dynamic):Bool
		return v == null || v is String || v is Bool || v is Int || v is Float || v is Array;

	// ------------------------------------------------------------------ globals

	public static function setGlobals(s:PsychLuaScript) {
		checkState();
		var g = game();
		var set = s.setGlobal;
		set("Function_Stop", PsychLuaScript.FUNCTION_STOP);
		set("Function_Continue", PsychLuaScript.FUNCTION_CONTINUE);
		set("Function_StopLua", PsychLuaScript.FUNCTION_STOP_LUA);
		set("Function_StopHScript", PsychLuaScript.FUNCTION_STOP_HSCRIPT);
		set("Function_StopAll", PsychLuaScript.FUNCTION_STOP_ALL);
		set("luaDebugMode", false);
		set("luaDeprecatedWarnings", false);
		set("inChartEditor", false);
		set("version", "0.7.3");
		set("psychVersion", "0.7.3");
		set("buildTarget", #if ps5 "ps5" #else "linux" #end);
		set("scriptName", s.scriptName);
		set("currentModDirectory", funkin.backend.assets.ModsFolder.currentModFolder == null ? "" : funkin.backend.assets.ModsFolder.currentModFolder);
		set("screenWidth", FlxG.width);
		set("screenHeight", FlxG.height);
		set("inGameOver", false);
		set("startedCountdown", g != null && g.startedCountdown);
		set("curBeat", 0);
		set("curStep", 0);
		set("curSection", 0);
		set("curDecBeat", 0);
		set("curDecStep", 0);
		set("score", 0);
		set("misses", 0);
		set("hits", 0);
		set("combo", 0);
		set("rating", 0);
		set("ratingName", "?");
		set("ratingFC", "");
		set("isStoryMode", PlayState.isStoryMode);
		set("difficulty", 0);
		set("difficultyName", PlayState.difficulty);
		set("difficultyPath", PlayState.difficulty.toLowerCase());
		set("seenCutscene", PlayState.seenCutscene);
		set("week", "");
		set("weekRaw", 0);
		set("playbackRate", 1);
		set("healthGainMult", 1);
		set("healthLossMult", 1);
		set("instakillOnMiss", false);
		set("botPlay", false);
		set("practice", false);
		set("downscroll", Options.downscroll);
		set("middlescroll", false);
		set("framerate", Options.framerate);
		set("ghostTapping", Options.ghostTapping);
		set("hideHud", false);
		set("timeBarType", "Disabled");
		set("scoreZoom", true);
		set("cameraZoomOnBeat", Options.camZoomOnBeat);
		set("flashingLights", Options.flashingMenu);
		set("noteOffset", Options.songOffset);
		set("healthBarAlpha", 1);
		set("noResetButton", true);
		set("lowQuality", Options.lowMemoryMode);
		set("shadersEnabled", Options.gameplayShaders);
		set("noteSkin", "");
		set("noteSkinPostfix", "");
		set("splashSkin", "");
		set("splashSkinPostfix", "");
		set("splashAlpha", 0.6);
		if (PlayState.SONG != null) {
			var meta = PlayState.SONG.meta;
			set("songName", meta.displayName != null ? meta.displayName : meta.name);
			set("songPath", meta.name);
			set("curStage", PlayState.SONG.stage);
			set("scrollSpeed", PlayState.SONG.scrollSpeed);
			set("hasVocals", meta.needsVoices != false);
			set("curBpm", meta.bpm);
			set("bpm", meta.bpm);
			set("crochet", Conductor.crochet);
			set("stepCrochet", Conductor.stepCrochet);
		}
		if (g != null) updateCharacterGlobals(s);
	}

	static function updateCharacterGlobals(s:PsychLuaScript) {
		var g = game();
		if (g == null) return;
		inline function name(c:funkin.game.Character) return c == null ? "" : c.curCharacter;
		s.setGlobal("boyfriendName", name(g.boyfriend));
		s.setGlobal("dadName", name(g.dad));
		s.setGlobal("gfName", name(g.gf));
		if (g.boyfriend != null) {
			s.setGlobal("defaultBoyfriendX", g.boyfriend.x);
			s.setGlobal("defaultBoyfriendY", g.boyfriend.y);
		}
		if (g.dad != null) {
			s.setGlobal("defaultOpponentX", g.dad.x);
			s.setGlobal("defaultOpponentY", g.dad.y);
		}
		if (g.gf != null) {
			s.setGlobal("defaultGirlfriendX", g.gf.x);
			s.setGlobal("defaultGirlfriendY", g.gf.y);
		}
		for (i in 0...4) {
			var o = strum(i), p = strum(i + 4);
			if (o != null) {
				s.setGlobal('defaultOpponentStrumX$i', o.x);
				s.setGlobal('defaultOpponentStrumY$i', o.y);
			}
			if (p != null) {
				s.setGlobal('defaultPlayerStrumX$i', p.x);
				s.setGlobal('defaultPlayerStrumY$i', p.y);
			}
		}
	}

	/** Called before onUpdate and onCreatePost. */
	public static function updateGlobals(s:PsychLuaScript) {
		var g = game();
		if (g == null) return;
		s.setGlobal("songPosition", Conductor.songPosition);
		s.setGlobal("curDecBeat", Conductor.curBeatFloat);
		s.setGlobal("curDecStep", Conductor.curStepFloat);
		s.setGlobal("curBpm", Conductor.bpm);
		s.setGlobal("crochet", Conductor.crochet);
		s.setGlobal("stepCrochet", Conductor.stepCrochet);
		s.setGlobal("score", g.songScore);
		s.setGlobal("misses", g.misses);
		s.setGlobal("combo", g.combo);
		s.setGlobal("rating", g.accuracy < 0 ? 0 : g.accuracy);
		s.setGlobal("cameraX", g.camFollow != null ? g.camFollow.x : 0);
		s.setGlobal("cameraY", g.camFollow != null ? g.camFollow.y : 0);
		s.setGlobal("startedCountdown", g.startedCountdown);
		s.setGlobal("mustHitSection", g.curCameraTarget == 1);
		s.setGlobal("gfSection", g.curCameraTarget == 2);
		if (!updatedCharacters.exists(s)) {
			updatedCharacters.set(s, true);
			updateCharacterGlobals(s);
		}
	}

	static var updatedCharacters:Map<PsychLuaScript, Bool> = [];

	public static function updateSectionGlobals(s:PsychLuaScript) {
		var g = game();
		if (g == null) return;
		s.setGlobal("mustHitSection", g.curCameraTarget == 1);
		s.setGlobal("gfSection", g.curCameraTarget == 2);
	}

	// ------------------------------------------------------------------ helpers

	/** "1,2,3" or a table of numbers as an array of ints. */
	static function intList(v:Dynamic):Array<Int> {
		if (v == null) return [];
		if (v is Array) return [for (x in (v : Array<Dynamic>)) Std.int(toFloat(x))];
		return [for (part in Std.string(v).split(",")) if (part.trim() != "") Std.parseInt(part.trim())];
	}

	static function toFloat(v:Dynamic, def:Float = 0):Float {
		if (v == null) return def;
		if (v is Int || v is Float) return v;
		var f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static function toBool(v:Dynamic, def:Bool = false):Bool {
		if (v == null) return def;
		if (v is Bool) return v;
		var s = Std.string(v).toLowerCase();
		return s == "true" || s == "1";
	}

	static function str(v:Dynamic, def:String = ""):String
		return v == null ? def : Std.string(v);

	public static function parseColor(v:Dynamic):FlxColor {
		if (v == null) return FlxColor.WHITE;
		if (v is Int) return v;
		if (v is Float) return Std.int(v);
		var s = Std.string(v).trim();
		var named = FlxColor.fromString(s);
		if (named != null && !s.startsWith("0x") && !s.startsWith("#") && !~/^[0-9a-fA-F]+$/.match(s)) return named;
		if (s.startsWith("#")) s = s.substr(1);
		if (s.startsWith("0x") || s.startsWith("0X")) s = s.substr(2);
		if (s.length <= 6) s = "FF" + StringTools.lpad(s, "0", 6);
		var parsed = Std.parseInt("0x" + s);
		return parsed == null ? FlxColor.WHITE : parsed;
	}

	public static function cameraFromString(name:Dynamic):FlxCamera {
		var g = game();
		var s = str(name).toLowerCase();
		if (g == null) return FlxG.camera;
		return switch (s) {
			case "camhud" | "hud": g.camHUD;
			case "camother" | "other": getCamOther();
			default: g.camGame;
		}
	}

	public static function getCamOther():FlxCamera {
		checkState();
		if (camOther == null || !FlxG.cameras.list.contains(camOther)) {
			camOther = new FlxCamera();
			camOther.bgColor = 0;
			FlxG.cameras.add(camOther, false);
		}
		return camOther;
	}

	public static function easeFromString(name:Dynamic):Float->Float {
		var s = str(name, "linear").toLowerCase().replace("-", "").replace("_", "");
		return switch (s) {
			case "backin": FlxEase.backIn;
			case "backinout": FlxEase.backInOut;
			case "backout": FlxEase.backOut;
			case "bouncein": FlxEase.bounceIn;
			case "bounceinout": FlxEase.bounceInOut;
			case "bounceout": FlxEase.bounceOut;
			case "circin": FlxEase.circIn;
			case "circinout": FlxEase.circInOut;
			case "circout": FlxEase.circOut;
			case "cubein": FlxEase.cubeIn;
			case "cubeinout": FlxEase.cubeInOut;
			case "cubeout": FlxEase.cubeOut;
			case "elasticin": FlxEase.elasticIn;
			case "elasticinout": FlxEase.elasticInOut;
			case "elasticout": FlxEase.elasticOut;
			case "expoin": FlxEase.expoIn;
			case "expoinout": FlxEase.expoInOut;
			case "expoout": FlxEase.expoOut;
			case "quadin": FlxEase.quadIn;
			case "quadinout": FlxEase.quadInOut;
			case "quadout": FlxEase.quadOut;
			case "quartin": FlxEase.quartIn;
			case "quartinout": FlxEase.quartInOut;
			case "quartout": FlxEase.quartOut;
			case "quintin": FlxEase.quintIn;
			case "quintinout": FlxEase.quintInOut;
			case "quintout": FlxEase.quintOut;
			case "sinein": FlxEase.sineIn;
			case "sineinout": FlxEase.sineInOut;
			case "sineout": FlxEase.sineOut;
			case "smoothstepin": FlxEase.smoothStepIn;
			case "smoothstepinout": FlxEase.smoothStepInOut;
			case "smoothstepout": FlxEase.smoothStepOut;
			case "smootherstepin": FlxEase.smootherStepIn;
			case "smootherstepinout": FlxEase.smootherStepInOut;
			case "smootherstepout": FlxEase.smootherStepOut;
			default: FlxEase.linear;
		}
	}

	/** Psych's image names, with fallbacks to where Codename keeps the base game's stage art. */
	public static function imagePath(name:String):String {
		if (name == null) return null;
		var candidates = [name];
		var base = Path.withoutDirectory(name);
		for (prefix => folder in ["philly/" => "philly", "limo/" => "limo", "christmas/" => "mall", "weeb/" => "school", "halloween" => "spooky", "tank" => "tank"])
			if (name.startsWith(prefix)) candidates.push('stages/$folder/' + (prefix.endsWith("/") ? name.substr(prefix.length) : name));
		for (folder in ["default", "spooky", "philly", "limo", "mall", "school", "tank"]) candidates.push('stages/$folder/$base');
		for (c in candidates) if (Assets.exists(Paths.image(c, null, false))) return c;
		return name;
	}

	public static function noteIndex(note:Note):Int {
		if (note == null || note.strumLine == null) return 0;
		var i = note.strumLine.notes.members.indexOf(note);
		return i < 0 ? 0 : i;
	}

	static function strumLine(i:Int):funkin.game.StrumLine {
		var g = game();
		if (g == null || g.strumLines == null) return null;
		return g.strumLines.members[i];
	}

	/** Psych's strum numbers: 0-3 the opponent's, 4-7 the player's. */
	static function strum(i:Int):Strum {
		var line = strumLine(i < 4 ? 0 : 1);
		if (line == null) return null;
		return line.members[i % 4];
	}

	/** Every note of the song, opponent's first: Psych's unspawnNotes. */
	static function allNotes():Array<Note> {
		var out:Array<Note> = [];
		var g = game();
		if (g == null) return out;
		for (line in g.strumLines.members) if (line != null) for (n in line.notes.members) if (n != null) out.push(n);
		out.sort((a, b) -> Std.int(a.strumTime - b.strumTime));
		return out;
	}

	// ------------------------------------------------------------------ objects and properties

	/** Psych's names for objects, as Codename objects. */
	static function namedObject(name:String):Dynamic {
		checkState();
		var g = game();
		if (sprites.exists(name)) return sprites.get(name);
		if (texts.exists(name)) return texts.get(name);
		if (variables.exists(name)) return variables.get(name);
		if (g == null) return null;
		switch (name) {
			case "boyfriend" | "bf" | "boyfriendGroup": return g.boyfriend;
			case "dad" | "dadGroup" | "opponent": return g.dad;
			case "gf" | "girlfriend" | "gfGroup": return g.gf;
			case "camGame": return g.camGame;
			case "camHUD": return g.camHUD;
			case "camOther": return getCamOther();
			case "game" | "this" | "instance": return g;
			case "playerStrums": return strumLine(1);
			case "opponentStrums": return strumLine(0);
			case "strumLineNotes": return [for (i in 0...8) strum(i)];
			case "unspawnNotes" | "notes": return allNotes();
			case "camFollow" | "camFollowPos": return g.camFollow;
			case "songMisses": return g.misses;
			case "ratingPercent": return g.accuracy;
			case "timeBar" | "timeBarBG" | "timeTxt" | "botplayTxt": return null;
		}
		if (g.stage != null) {
			var stageSprite = g.stage.getSprite(name);
			if (stageSprite != null) return stageSprite;
		}
		try {
			var v = Reflect.getProperty(g, name);
			if (v != null) return v;
		} catch (e) {}
		return null;
	}

	/** Splits "a.b[2].c" into ["a", "b", 2, "c"]. */
	static function splitPath(path:String):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (part in path.split(".")) {
			var bracket = part.indexOf("[");
			if (bracket < 0) {
				out.push(part);
				continue;
			}
			if (bracket > 0) out.push(part.substr(0, bracket));
			var re = ~/\[(\d+)\]/g;
			var rest = part.substr(bracket);
			while (re.match(rest)) {
				out.push(Std.parseInt(re.matched(1)));
				rest = re.matchedRight();
			}
		}
		return out;
	}

	static var noteAliases = ["ignoreNote" => "avoid", "hitByOpponent" => "wasGoodHit", "multAlpha" => "alpha"];

	static function getField(obj:Dynamic, field:Dynamic):Dynamic {
		if (obj == null) return null;
		if (field is Int) {
			var i:Int = field;
			if (obj is Array) return (obj : Array<Dynamic>)[i];
			var members:Array<Dynamic> = Reflect.getProperty(obj, "members");
			return members == null ? null : members[i];
		}
		var name:String = field;
		if (obj is Note && noteAliases.exists(name)) name = noteAliases.get(name);
		if (obj is Array && name == "length") return (obj : Array<Dynamic>).length;
		if (name == "length" && Reflect.getProperty(obj, "members") != null) return (Reflect.getProperty(obj, "members") : Array<Dynamic>).length;
		try return Reflect.getProperty(obj, name)
		catch (e) return null;
	}

	static function setField(obj:Dynamic, field:Dynamic, value:Dynamic):Bool {
		if (obj == null) return false;
		if (field is Int) {
			if (obj is Array) (obj : Array<Dynamic>)[field] = value;
			return obj is Array;
		}
		var name:String = field;
		if (obj is Note && noteAliases.exists(name)) name = noteAliases.get(name);
		// colors given as strings
		if (name == "color" && value is String) value = parseColor(value);
		try {
			Reflect.setProperty(obj, name, value);
			return true;
		} catch (e) {
			return false;
		}
	}

	public static function getProperty(path:String):Dynamic {
		if (path == null) return null;
		var parts = splitPath(path);
		if (parts.length == 0) return null;
		var first:String = Std.string(parts[0]);
		var obj:Dynamic = namedObject(first);
		if (first == "cameraSpeed" && parts.length == 1) return game() != null ? game().camGame.followLerp / 0.04 : 1;
		if (first == "isCameraOnForcedPos" && parts.length == 1) return PsychEvents.cameraForced;
		if (first == "defaultCamZoom" && parts.length == 1 && game() != null) return game().defaultCamZoom;
		for (i in 1...parts.length) obj = getField(obj, parts[i]);
		return obj;
	}

	public static function setProperty(path:String, value:Dynamic):Bool {
		if (path == null) return false;
		var parts = splitPath(path);
		if (parts.length == 0) return false;
		var first:String = Std.string(parts[0]);
		var g = game();
		if (parts.length == 1) {
			switch (first) {
				case "cameraSpeed":
					if (g != null) g.camGame.followLerp = 0.04 * toFloat(value, 1);
					return true;
				case "isCameraOnForcedPos":
					PsychEvents.forceCamera(toBool(value));
					return true;
				case "songMisses":
					if (g != null) g.misses = Std.int(toFloat(value));
					return true;
			}
			if (sprites.exists(first) || texts.exists(first)) return false;
			if (variables.exists(first)) {
				variables.set(first, value);
				return true;
			}
			return g != null && setField(g, first, value);
		}
		var obj:Dynamic = namedObject(first);
		for (i in 1...parts.length - 1) obj = getField(obj, parts[i]);
		return setField(obj, parts[parts.length - 1], value);
	}

	/** Classes as Psych scripts name them, with ClientPrefs mapped to Codename's options. */
	static function classByName(name:String):Dynamic {
		var short = name.split(".").pop();
		return switch (short) {
			case "ClientPrefs": ClientPrefs;
			case "PlayState": PlayState;
			case "Conductor": Conductor;
			case "FlxG": FlxG;
			case "Paths": Paths;
			case "CoolUtil": CoolUtil;
			case "Options": Options;
			default:
				var c = Type.resolveClass(name);
				c;
		}
	}

	static function getFromClass(className:String, path:String):Dynamic {
		var cls = classByName(className);
		if (cls == null) return null;
		if (cls == ClientPrefs) return ClientPrefs.get(path.startsWith("data.") ? path.substr(5) : path);
		var parts = splitPath(path);
		var obj:Dynamic = cls;
		for (p in parts) obj = getField(obj, p);
		return obj;
	}

	static function setFromClass(className:String, path:String, value:Dynamic):Bool {
		var cls = classByName(className);
		if (cls == null || cls == ClientPrefs) return false;
		var parts = splitPath(path);
		var obj:Dynamic = cls;
		for (i in 0...parts.length - 1) obj = getField(obj, parts[i]);
		return setField(obj, parts[parts.length - 1], value);
	}

	static function groupMember(group:String, index:Int):Dynamic {
		var obj = getProperty(group);
		return getField(obj, index);
	}

	public static function spriteOrObject(name:String):Dynamic {
		var obj = getProperty(name);
		return obj;
	}

	/** Where Psych puts sprites that are not in front: behind the characters. */
	static function addBehindCharacters(obj:FlxBasic) {
		var g = game();
		if (g == null) return;
		var index = g.members.length;
		for (c in [g.gf, g.dad, g.boyfriend]) if (c != null) {
			var i = g.members.indexOf(c);
			if (i >= 0 && i < index) index = i;
		}
		g.insert(index, obj);
	}

	// ------------------------------------------------------------------ debug output

	public static function debugPrint(script:PsychLuaScript, text:String, color:FlxColor = FlxColor.WHITE) {
		Logs.traceColored([Logs.logText('[Psych Lua] ${script == null ? "" : script.fileName}: ', CYAN), Logs.logText(text)], TRACE);
		var g = game();
		if (g == null) return;
		var cam = getCamOther();
		for (t in debugTexts) t.y += 20;
		var t = new FlxText(10, 10, FlxG.width - 20, text, 16);
		t.setFormat(Paths.font("vcr.ttf"), 16, color, LEFT, OUTLINE, FlxColor.BLACK);
		t.scrollFactor.set();
		t.cameras = [cam];
		g.add(t);
		debugTexts.push(t);
		FlxTween.tween(t, {alpha: 0}, 1, {startDelay: 5, onComplete: _ -> {
			debugTexts.remove(t);
			g.remove(t, true);
			t.destroy();
		}});
	}

	static function warnMissing(s:PsychLuaScript, name:String) {
		if (missing.exists(name)) return;
		missing.set(name, true);
		Logs.warn('[Psych Lua] ${s.fileName}: $name() is not supported on the PS5 port');
	}

	// ------------------------------------------------------------------ callbacks to scripts

	public static function callOnLuas(func:String, args:Array<Dynamic>, ?except:PsychLuaScript):Dynamic {
		var result:Dynamic = PsychLuaScript.FUNCTION_CONTINUE;
		for (s in PsychLuaScript.running.copy()) {
			if (s == except || s.closed) continue;
			var r = s.callPsych(func, args);
			if (r == PsychLuaScript.FUNCTION_STOP_LUA || r == PsychLuaScript.FUNCTION_STOP_ALL) return r;
			if (r != null && r != PsychLuaScript.FUNCTION_CONTINUE) result = r;
		}
		return result;
	}

	// ------------------------------------------------------------------ the functions

	public static function register(s:PsychLuaScript) {
		inline function add(name:String, fn:Array<Dynamic>->Dynamic) s.addFunction(name, fn);

		// output and script control
		add("debugPrint", a -> {
			debugPrint(s, [for (x in a) str(x, "nil")].join(""));
			null;
		});
		add("print", a -> {
			Logs.trace('[Psych Lua] ${s.fileName}: ' + [for (x in a) str(x, "nil")].join("\t"));
			null;
		});
		add("luaTrace", a -> {
			debugPrint(s, str(a[0]), a[3] != null ? parseColor(a[3]) : FlxColor.WHITE);
			null;
		});
		add("close", a -> {
			// stop after the current call returns
			FlxTimer.wait(0, () -> s.stop());
			true;
		});
		add("setVar", a -> {
			variables.set(str(a[0]), a[1]);
			a[1];
		});
		add("getVar", a -> variables.get(str(a[0])));
		add("removeVar", a -> variables.remove(str(a[0])));
		add("callOnLuas", a -> {
			var args:Array<Dynamic> = a[1] is Array ? a[1] : [];
			callOnLuas(str(a[0]), args, toBool(a[3]) ? null : (toBool(a[2], true) ? s : null));
		});
		add("callOnScripts", a -> callOnLuas(str(a[0]), a[1] is Array ? a[1] : []));
		add("setOnLuas", a -> {
			for (o in PsychLuaScript.running) if (o != s || !toBool(a[2], false)) o.setGlobal(str(a[0]), a[1]);
			null;
		});
		add("setOnScripts", a -> {
			for (o in PsychLuaScript.running) o.setGlobal(str(a[0]), a[1]);
			null;
		});
		add("callScript", a -> {
			var name = str(a[0]);
			for (o in PsychLuaScript.running) if (o.path.endsWith(name) || o.path.endsWith(name + ".lua")) return o.callPsych(str(a[1]), a[2] is Array ? a[2] : []);
			null;
		});
		add("isRunning", a -> {
			var name = str(a[0]);
			for (o in PsychLuaScript.running) if (o.path.endsWith(name) || o.path.endsWith(name + ".lua")) return true;
			false;
		});
		add("addLuaScript", a -> {
			var path = str(a[0]);
			if (!path.endsWith(".lua")) path += ".lua";
			var g = game();
			if (g == null || !Assets.exists(path)) return false;
			var script = Script.create(path);
			g.scripts.add(script);
			script.load();
			script.call("create");
			true;
		});
		add("removeLuaScript", a -> {
			var name = str(a[0]);
			for (o in PsychLuaScript.running.copy()) if (o.path.endsWith(name) || o.path.endsWith(name + ".lua")) o.stop();
			true;
		});

		// properties
		add("getProperty", a -> getProperty(str(a[0])));
		add("setProperty", a -> setProperty(str(a[0]), a[1]));
		add("getPropertyFromClass", a -> getFromClass(str(a[0]), str(a[1])));
		add("setPropertyFromClass", a -> setFromClass(str(a[0]), str(a[1]), a[2]));
		add("getPropertyFromGroup", a -> {
			var member = groupMember(str(a[0]), Std.int(toFloat(a[1])));
			var path = str(a[2]);
			var obj:Dynamic = member;
			for (p in splitPath(path)) obj = getField(obj, p);
			obj;
		});
		add("setPropertyFromGroup", a -> {
			var obj:Dynamic = groupMember(str(a[0]), Std.int(toFloat(a[1])));
			var parts = splitPath(str(a[2]));
			for (i in 0...parts.length - 1) obj = getField(obj, parts[i]);
			setField(obj, parts[parts.length - 1], a[3]);
		});
		add("removeFromGroup", a -> {
			var group:Dynamic = getProperty(str(a[0]));
			var member = getField(group, Std.int(toFloat(a[1])));
			if (member != null && Reflect.getProperty(group, "members") != null) {
				Reflect.callMethod(group, Reflect.getProperty(group, "remove"), [member, true]);
				if (!toBool(a[2])) (member : FlxBasic).destroy();
			}
			null;
		});
		add("callMethod", a -> {
			var path = str(a[0]);
			var dot = path.lastIndexOf(".");
			var obj:Dynamic = dot < 0 ? game() : getProperty(path.substr(0, dot));
			var fn = getField(obj, dot < 0 ? path : path.substr(dot + 1));
			Reflect.isFunction(fn) ? Reflect.callMethod(obj, fn, a[1] is Array ? a[1] : []) : null;
		});
		add("callMethodFromClass", a -> {
			var cls = classByName(str(a[0]));
			var parts = splitPath(str(a[1]));
			var obj:Dynamic = cls;
			for (i in 0...parts.length - 1) obj = getField(obj, parts[i]);
			var fn = getField(obj, parts[parts.length - 1]);
			Reflect.isFunction(fn) ? Reflect.callMethod(obj, fn, a[2] is Array ? a[2] : []) : null;
		});
		add("createInstance", a -> {
			var cls = Type.resolveClass(str(a[1]));
			if (cls == null) return false;
			variables.set(str(a[0]), Type.createInstance(cls, a[2] is Array ? a[2] : []));
			true;
		});
		add("addInstance", a -> {
			var obj = variables.get(str(a[0]));
			if (obj is FlxBasic && game() != null) {
				if (toBool(a[1])) game().add(obj);
				else addBehindCharacters(obj);
			}
			null;
		});

		// sprites
		add("makeLuaSprite", a -> {
			var tag = str(a[0]);
			removeSprite(tag, true);
			var spr = new FunkinSprite(toFloat(a[2]), toFloat(a[3]));
			var image = str(a[1]);
			if (image != "") spr.loadGraphic(Paths.image(imagePath(image)));
			spr.antialiasing = Options.antialiasing;
			sprites.set(tag, spr);
			spr.active = true;
			null;
		});
		add("makeAnimatedLuaSprite", a -> {
			var tag = str(a[0]);
			removeSprite(tag, true);
			var spr = new FunkinSprite(toFloat(a[2]), toFloat(a[3]));
			var image = str(a[1]);
			if (image != "") spr.frames = Paths.getFrames(imagePath(image));
			spr.antialiasing = Options.antialiasing;
			sprites.set(tag, spr);
			null;
		});
		add("makeGraphic", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) spr.makeGraphic(Std.int(toFloat(a[1], 256)), Std.int(toFloat(a[2], 256)), parseColor(a[3] == null ? "FFFFFF" : a[3]));
			null;
		});
		add("loadGraphic", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) {
				var w = Std.int(toFloat(a[2])), h = Std.int(toFloat(a[3]));
				spr.loadGraphic(Paths.image(imagePath(str(a[1]))), w > 0 || h > 0, w, h);
			}
			null;
		});
		add("loadFrames", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) spr.frames = Paths.getFrames(imagePath(str(a[1])));
			null;
		});
		add("addAnimationByPrefix", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr == null || spr.frames == null) return false;
			spr.animation.addByPrefix(str(a[1]), str(a[2]), toFloat(a[3], 24), toBool(a[4], true));
			if (spr.animation.curAnim == null) spr.animation.play(str(a[1]), true);
			true;
		});
		add("addAnimation", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr == null) return false;
			spr.animation.add(str(a[1]), intList(a[2]), toFloat(a[3], 24), toBool(a[4], true));
			if (spr.animation.curAnim == null) spr.animation.play(str(a[1]), true);
			true;
		});
		add("addAnimationByIndices", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr == null || spr.frames == null) return false;
			spr.animation.addByIndices(str(a[1]), str(a[2]), intList(a[3]), "", toFloat(a[4], 24), toBool(a[5], false));
			if (spr.animation.curAnim == null) spr.animation.play(str(a[1]), true);
			true;
		});
		add("addAnimationByIndicesLoop", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr == null || spr.frames == null) return false;
			spr.animation.addByIndices(str(a[1]), str(a[2]), intList(a[3]), "", toFloat(a[4], 24), true);
			true;
		});
		add("addOffset", a -> {
			var spr:Dynamic = spriteOrObject(str(a[0]));
			if (spr is FunkinSprite) (spr : FunkinSprite).addOffset(str(a[1]), toFloat(a[2]), toFloat(a[3]));
			else if (spr is funkin.game.Character) (spr : funkin.game.Character).addOffset(str(a[1]), toFloat(a[2]), toFloat(a[3]));
			true;
		});
		var playAnim = (a:Array<Dynamic>) -> {
			var obj:Dynamic = spriteOrObject(str(a[0]));
			var anim = str(a[1]);
			var forced = toBool(a[2]);
			var reversed = toBool(a[3]);
			var frame = Std.int(toFloat(a[4]));
			if (obj is funkin.game.Character) (obj : funkin.game.Character).playAnim(anim, forced, LOCK, reversed, frame);
			else if (obj is FunkinSprite) (obj : FunkinSprite).playAnim(anim, forced, NONE, reversed, frame);
			else if (obj is FlxSprite && (obj : FlxSprite).animation.exists(anim)) (obj : FlxSprite).animation.play(anim, forced, reversed, frame);
			true;
		};
		add("playAnim", playAnim);
		add("objectPlayAnimation", a -> playAnim([a[0], a[1], a[2], false, a[3]]));
		add("luaSpritePlayAnimation", a -> playAnim(a));
		add("characterPlayAnim", a -> playAnim(a));
		add("addLuaSprite", a -> {
			var spr = sprites.get(str(a[0]));
			var g = game();
			if (spr == null || g == null) return false;
			if (g.members.indexOf(spr) >= 0) return true;
			if (toBool(a[1])) g.add(spr);
			else addBehindCharacters(spr);
			true;
		});
		add("removeLuaSprite", a -> {
			removeSprite(str(a[0]), toBool(a[1], true));
			null;
		});
		add("luaSpriteExists", a -> sprites.exists(str(a[0])));
		add("setScrollFactor", a -> {
			var obj:FlxObject = spriteOrObject(str(a[0]));
			if (obj != null) obj.scrollFactor.set(toFloat(a[1]), toFloat(a[2]));
			null;
		});
		add("scaleObject", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) {
				spr.scale.set(toFloat(a[1], 1), toFloat(a[2], 1));
				if (toBool(a[3], true)) spr.updateHitbox();
			}
			null;
		});
		add("setGraphicSize", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) {
				spr.setGraphicSize(Std.int(toFloat(a[1])), Std.int(toFloat(a[2])));
				if (toBool(a[3], true)) spr.updateHitbox();
			}
			null;
		});
		add("updateHitbox", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) spr.updateHitbox();
			null;
		});
		add("updateHitboxFromGroup", a -> {
			var spr:FlxSprite = groupMember(str(a[0]), Std.int(toFloat(a[1])));
			if (spr != null) spr.updateHitbox();
			null;
		});
		add("screenCenter", a -> {
			var obj:FlxObject = spriteOrObject(str(a[0]));
			if (obj != null) obj.screenCenter(switch (str(a[1], "xy").toLowerCase()) {
				case "x": X;
				case "y": Y;
				default: XY;
			});
			null;
		});
		add("setObjectCamera", a -> {
			var obj:FlxBasic = spriteOrObject(str(a[0]));
			if (obj != null) obj.cameras = [cameraFromString(a[1])];
			obj != null;
		});
		add("setBlendMode", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			if (spr != null) spr.blend = blendFromString(str(a[1]));
			spr != null;
		});
		add("setObjectOrder", a -> {
			var obj:FlxBasic = spriteOrObject(str(a[0]));
			var g = game();
			if (obj == null || g == null) return false;
			g.remove(obj, true);
			g.insert(Std.int(toFloat(a[1])), obj);
			true;
		});
		add("getObjectOrder", a -> {
			var obj:FlxBasic = spriteOrObject(str(a[0]));
			game() == null || obj == null ? -1 : game().members.indexOf(obj);
		});
		add("objectsOverlap", a -> {
			var o1:FlxObject = spriteOrObject(str(a[0])), o2:FlxObject = spriteOrObject(str(a[1]));
			o1 != null && o2 != null && o1.overlaps(o2);
		});
		add("getMidpointX", a -> {
			var o:FlxObject = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getMidpoint().x;
		});
		add("getMidpointY", a -> {
			var o:FlxObject = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getMidpoint().y;
		});
		add("getGraphicMidpointX", a -> {
			var o:FlxSprite = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getGraphicMidpoint().x;
		});
		add("getGraphicMidpointY", a -> {
			var o:FlxSprite = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getGraphicMidpoint().y;
		});
		add("getScreenPositionX", a -> {
			var o:FlxObject = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getScreenPosition(null, cameraFromString(a[1])).x;
		});
		add("getScreenPositionY", a -> {
			var o:FlxObject = spriteOrObject(str(a[0]));
			o == null ? 0 : o.getScreenPosition(null, cameraFromString(a[1])).y;
		});
		add("getPixelColor", a -> {
			var spr:FlxSprite = spriteOrObject(str(a[0]));
			spr == null ? 0 : (spr.pixels.getPixel32(Std.int(toFloat(a[1])), Std.int(toFloat(a[2]))) : Int);
		});

		// texts
		add("makeLuaText", a -> {
			var tag = str(a[0]);
			removeText(tag, true);
			var t = new FlxText(toFloat(a[3]), toFloat(a[4]), toFloat(a[2]), str(a[1]), 16);
			t.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			t.borderSize = 2;
			t.scrollFactor.set();
			if (game() != null) t.cameras = [game().camHUD];
			texts.set(tag, t);
			null;
		});
		add("addLuaText", a -> {
			var t = texts.get(str(a[0]));
			if (t != null && game() != null && game().members.indexOf(t) < 0) game().add(t);
			t != null;
		});
		add("removeLuaText", a -> {
			removeText(str(a[0]), toBool(a[1], true));
			null;
		});
		add("luaTextExists", a -> texts.exists(str(a[0])));
		inline function text(a:Array<Dynamic>):FlxText {
			var t:Dynamic = spriteOrObject(str(a[0]));
			return t is FlxText ? t : null;
		}
		add("setTextString", a -> { var t = text(a); if (t != null) t.text = str(a[1]); t != null; });
		add("setTextSize", a -> { var t = text(a); if (t != null) t.size = Std.int(toFloat(a[1], 16)); t != null; });
		add("setTextWidth", a -> { var t = text(a); if (t != null) t.fieldWidth = toFloat(a[1]); t != null; });
		add("setTextHeight", a -> { var t = text(a); if (t != null) t.fieldHeight = toFloat(a[1]); t != null; });
		add("setTextAutoSize", a -> { var t = text(a); if (t != null) t.autoSize = toBool(a[1]); t != null; });
		add("setTextColor", a -> { var t = text(a); if (t != null) t.color = parseColor(a[1]); t != null; });
		add("setTextItalic", a -> { var t = text(a); if (t != null) t.italic = toBool(a[1]); t != null; });
		add("setTextFont", a -> {
			var t = text(a);
			if (t != null) t.font = Paths.font(str(a[1]));
			t != null;
		});
		add("setTextBorder", a -> {
			var t = text(a);
			if (t != null) {
				var size = toFloat(a[1], 1);
				t.borderStyle = size > 0 ? OUTLINE : NONE;
				t.borderSize = size;
				if (a[2] != null) t.borderColor = parseColor(a[2]);
			}
			t != null;
		});
		add("setTextAlignment", a -> {
			var t = text(a);
			if (t != null) t.alignment = switch (str(a[1], "left").toLowerCase()) {
				case "right": RIGHT;
				case "center": CENTER;
				default: LEFT;
			};
			t != null;
		});
		add("getTextString", a -> { var t = text(a); t == null ? null : t.text; });
		add("getTextSize", a -> { var t = text(a); t == null ? -1 : t.size; });
		add("getTextFont", a -> { var t = text(a); t == null ? null : t.font; });
		add("getTextWidth", a -> { var t = text(a); t == null ? 0 : t.fieldWidth; });

		// tweens and timers
		inline function tweenVar(tag:String, target:String, values:Dynamic, duration:Dynamic, ease:Dynamic) {
			var obj:Dynamic = spriteOrObject(target);
			if (obj == null) {
				warnMissing(s, 'tween target "$target"');
				return null;
			}
			startTween(tag, obj, values, toFloat(duration, 1), easeFromString(ease), target);
			return null;
		}
		add("doTweenX", a -> tweenVar(str(a[0]), str(a[1]), {x: toFloat(a[2])}, a[3], a[4]));
		add("doTweenY", a -> tweenVar(str(a[0]), str(a[1]), {y: toFloat(a[2])}, a[3], a[4]));
		add("doTweenAngle", a -> tweenVar(str(a[0]), str(a[1]), {angle: toFloat(a[2])}, a[3], a[4]));
		add("doTweenAlpha", a -> tweenVar(str(a[0]), str(a[1]), {alpha: toFloat(a[2])}, a[3], a[4]));
		add("doTweenZoom", a -> {
			var cam = cameraFromString(a[1]);
			startTween(str(a[0]), cam, {zoom: toFloat(a[2], 1)}, toFloat(a[3], 1), easeFromString(a[4]), str(a[1]));
			null;
		});
		add("doTweenColor", a -> {
			var tag = str(a[0]);
			var spr:FlxSprite = spriteOrObject(str(a[1]));
			if (spr == null) return null;
			cancelTween(tag);
			var from = spr.color;
			tweens.set(tag, FlxTween.color(spr, toFloat(a[3], 1), from, parseColor(a[2]), {
				ease: easeFromString(a[4]),
				onComplete: _ -> {
					tweens.remove(tag);
					callOnLuas("onTweenCompleted", [tag, str(a[1])]);
				}
			}));
			null;
		});
		add("startTween", a -> {
			var obj:Dynamic = spriteOrObject(str(a[1]));
			if (obj == null || a[2] == null) return null;
			var options:Dynamic = a[4];
			var ease = options != null ? Reflect.field(options, "ease") : null;
			startTween(str(a[0]), obj, a[2], toFloat(a[3], 1), easeFromString(ease), str(a[1]), options);
			null;
		});
		inline function noteTween(a:Array<Dynamic>, field:String) {
			var st = strum(Std.int(toFloat(a[1])) % 8);
			if (st == null) return null;
			var values:Dynamic = {};
			Reflect.setField(values, field, toFloat(a[2]));
			startTween(str(a[0]), st, values, toFloat(a[3], 1), easeFromString(a[4]), str(a[1]));
			return null;
		}
		add("noteTweenX", a -> noteTween(a, "x"));
		add("noteTweenY", a -> noteTween(a, "y"));
		add("noteTweenAngle", a -> noteTween(a, "angle"));
		add("noteTweenAlpha", a -> noteTween(a, "alpha"));
		add("noteTweenDirection", a -> noteTween(a, "angle"));
		add("cancelTween", a -> {
			cancelTween(str(a[0]));
			null;
		});
		add("runTimer", a -> {
			var tag = str(a[0]);
			cancelTimer(tag);
			var loops = Std.int(toFloat(a[2], 1));
			timers.set(tag, new FlxTimer().start(toFloat(a[1], 1), t -> {
				if (t.finished) timers.remove(tag);
				callOnLuas("onTimerCompleted", [tag, t.loops, t.loopsLeft]);
			}, loops));
			null;
		});
		add("cancelTimer", a -> {
			cancelTimer(str(a[0]));
			null;
		});

		// sound
		add("playMusic", a -> {
			FlxG.sound.playMusic(Paths.music(str(a[0])), toFloat(a[1], 1), toBool(a[2]));
			null;
		});
		add("playSound", a -> {
			var tag = a[2] == null ? null : str(a[2]);
			var path = Paths.sound(str(a[0]));
			if (tag == null || tag == "") {
				FlxG.sound.play(path, toFloat(a[1], 1));
				return null;
			}
			var old = sounds.get(tag);
			if (old != null) old.stop();
			var snd = FlxG.sound.play(path, toFloat(a[1], 1), toBool(a[3]), null, true, () -> {
				sounds.remove(tag);
				callOnLuas("onSoundFinished", [tag]);
			});
			sounds.set(tag, snd);
			null;
		});
		inline function sound(a:Array<Dynamic>):FlxSound {
			var tag = str(a[0]);
			return tag == "" ? FlxG.sound.music : sounds.get(tag);
		}
		add("stopSound", a -> { var snd = sound(a); if (snd != null) { snd.stop(); sounds.remove(str(a[0])); } null; });
		add("pauseSound", a -> { var snd = sound(a); if (snd != null) snd.pause(); null; });
		add("resumeSound", a -> { var snd = sound(a); if (snd != null) snd.play(); null; });
		add("soundFadeIn", a -> { var snd = sound(a); if (snd != null) snd.fadeIn(toFloat(a[1], 1), toFloat(a[2], 0), toFloat(a[3], 1)); null; });
		add("soundFadeOut", a -> { var snd = sound(a); if (snd != null) snd.fadeOut(toFloat(a[1], 1), toFloat(a[2], 0)); null; });
		add("soundFadeCancel", a -> { var snd = sound(a); if (snd != null && snd.fadeTween != null) snd.fadeTween.cancel(); null; });
		add("getSoundVolume", a -> { var snd = sound(a); snd == null ? 0 : snd.volume; });
		add("setSoundVolume", a -> { var snd = sound(a); if (snd != null) snd.volume = toFloat(a[1], 1); null; });
		add("getSoundTime", a -> { var snd = sound(a); snd == null ? 0 : snd.time; });
		add("setSoundTime", a -> { var snd = sound(a); if (snd != null) snd.time = toFloat(a[1]); null; });
		add("luaSoundExists", a -> sounds.exists(str(a[0])));
		add("precacheSound", a -> { FlxG.sound.cache(Paths.sound(str(a[0]))); null; });
		add("precacheMusic", a -> { FlxG.sound.cache(Paths.music(str(a[0]))); null; });
		add("precacheImage", a -> { FlxG.bitmap.add(Paths.image(imagePath(str(a[0])))); null; });

		// cameras
		add("cameraShake", a -> {
			cameraFromString(a[0]).shake(toFloat(a[1], 0.05), toFloat(a[2], 0.5));
			null;
		});
		add("cameraFlash", a -> {
			if (Options.flashingMenu) cameraFromString(a[0]).flash(parseColor(a[1]), toFloat(a[2], 1), null, toBool(a[3]));
			null;
		});
		add("cameraFade", a -> {
			cameraFromString(a[0]).fade(parseColor(a[1]), toFloat(a[2], 1), false, null, toBool(a[3]));
			null;
		});
		add("cameraSetTarget", a -> {
			var g = game();
			if (g == null) return null;
			g.curCameraTarget = switch (str(a[0]).toLowerCase()) {
				case "dad" | "opponent": 0;
				case "gf" | "girlfriend": 2;
				default: 1;
			};
			PsychEvents.cameraForced = false;
			null;
		});
		add("setCameraScroll", a -> {
			if (game() != null) game().camGame.scroll.set(toFloat(a[0]) - FlxG.width / 2, toFloat(a[1]) - FlxG.height / 2);
			null;
		});
		add("setCameraFollowPoint", a -> {
			if (game() != null) game().camFollow.setPosition(toFloat(a[0]), toFloat(a[1]));
			null;
		});
		add("triggerEvent", a -> {
			PsychEvents.trigger(str(a[0]), a[1], a[2]);
			true;
		});

		// characters
		add("characterDance", a -> {
			var c:Dynamic = spriteOrObject(str(a[0]));
			if (c is funkin.game.Character) (c : funkin.game.Character).dance();
			null;
		});
		inline function character(name:Dynamic):funkin.game.Character {
			var c:Dynamic = spriteOrObject(switch (str(name).toLowerCase()) {
				case "dad" | "opponent": "dad";
				case "gf" | "girlfriend": "gf";
				default: "boyfriend";
			});
			return c is funkin.game.Character ? c : null;
		}
		add("getCharacterX", a -> { var c = character(a[0]); c == null ? 0 : c.x; });
		add("getCharacterY", a -> { var c = character(a[0]); c == null ? 0 : c.y; });
		add("setCharacterX", a -> { var c = character(a[0]); if (c != null) c.x = toFloat(a[1]); null; });
		add("setCharacterY", a -> { var c = character(a[0]); if (c != null) c.y = toFloat(a[1]); null; });
		add("addCharacterToList", a -> null);
		add("setHealthBarColors", a -> {
			var g = game();
			if (g != null && g.healthBar != null) {
				g.healthBar.createFilledBar(parseColor(a[0]), parseColor(a[1]));
				g.healthBar.updateBar();
			}
			null;
		});
		add("setTimeBarColors", a -> null);

		// score, health, flow
		add("getHealth", a -> game() == null ? 0 : game().health);
		add("setHealth", a -> { if (game() != null) game().health = toFloat(a[0], 1); null; });
		add("addHealth", a -> { if (game() != null) game().health += toFloat(a[0]); null; });
		add("getScore", a -> game() == null ? 0 : game().songScore);
		add("setScore", a -> { if (game() != null) game().songScore = Std.int(toFloat(a[0])); null; });
		add("addScore", a -> { if (game() != null) game().songScore += Std.int(toFloat(a[0])); null; });
		add("getMisses", a -> game() == null ? 0 : game().misses);
		add("setMisses", a -> { if (game() != null) game().misses = Std.int(toFloat(a[0])); null; });
		add("addMisses", a -> { if (game() != null) game().misses += Std.int(toFloat(a[0])); null; });
		add("setRatingPercent", a -> null);
		add("setRatingName", a -> null);
		add("setRatingFC", a -> null);
		add("getSongPosition", a -> Conductor.songPosition);
		add("startCountdown", a -> { if (game() != null && !game().startedCountdown) game().startCountdown(); true; });
		add("endSong", a -> { if (game() != null) game().endSong(); true; });
		add("restartSong", a -> { FlxG.resetState(); true; });
		add("exitSong", a -> {
			if (game() != null) {
				PlayState.chartingMode = false;
				FlxG.switchState(PlayState.isStoryMode ? new funkin.menus.StoryMenuState() : new funkin.menus.FreeplayState());
			}
			true;
		});
		add("startDialogue", a -> { warnMissing(s, "startDialogue"); false; });
		add("startVideo", a -> { warnMissing(s, "startVideo"); if (game() != null) game().startCountdown(); false; });

		// input
		inline function control(name:Dynamic, state:Int):Bool {
			var c = funkin.options.PlayerSettings.solo.controls;
			return switch (str(name).toLowerCase()) {
				case "left": state == 0 ? c.NOTE_LEFT_P : (state == 1 ? c.NOTE_LEFT : c.NOTE_LEFT_R);
				case "down": state == 0 ? c.NOTE_DOWN_P : (state == 1 ? c.NOTE_DOWN : c.NOTE_DOWN_R);
				case "up": state == 0 ? c.NOTE_UP_P : (state == 1 ? c.NOTE_UP : c.NOTE_UP_R);
				case "right": state == 0 ? c.NOTE_RIGHT_P : (state == 1 ? c.NOTE_RIGHT : c.NOTE_RIGHT_R);
				case "ui_left": state == 0 ? c.LEFT_P : (state == 1 ? c.LEFT : c.LEFT_R);
				case "ui_down": state == 0 ? c.DOWN_P : (state == 1 ? c.DOWN : c.DOWN_R);
				case "ui_up": state == 0 ? c.UP_P : (state == 1 ? c.UP : c.UP_R);
				case "ui_right": state == 0 ? c.RIGHT_P : (state == 1 ? c.RIGHT : c.RIGHT_R);
				case "accept": state == 0 ? c.ACCEPT : (state == 1 ? c.ACCEPT_HOLD : c.ACCEPT_R);
				case "back": state == 0 ? c.BACK : (state == 1 ? c.BACK_HOLD : c.BACK_R);
				case "pause": state == 0 ? c.PAUSE : (state == 1 ? c.PAUSE_HOLD : c.PAUSE_R);
				case "reset": state == 0 ? c.RESET : (state == 1 ? c.RESET_HOLD : c.RESET_R);
				case "space": state == 0 ? FlxG.keys.justPressed.SPACE : (state == 1 ? FlxG.keys.pressed.SPACE : FlxG.keys.justReleased.SPACE);
				default: false;
			}
		}
		add("keyJustPressed", a -> control(a[0], 0));
		add("keyPressed", a -> control(a[0], 1));
		add("keyReleased", a -> control(a[0], 2));
		inline function key(name:Dynamic, status:flixel.input.FlxInput.FlxInputState):Bool {
			var k = FlxKey.fromString(str(name).toUpperCase());
			return k != FlxKey.NONE && FlxG.keys.checkStatus(k, status);
		}
		add("keyboardJustPressed", a -> key(a[0], JUST_PRESSED));
		add("keyboardPressed", a -> key(a[0], PRESSED));
		add("keyboardReleased", a -> key(a[0], JUST_RELEASED));
		inline function gamepadButton(name:Dynamic):flixel.input.gamepad.FlxGamepadInputID
			return flixel.input.gamepad.FlxGamepadInputID.fromString(str(name).toUpperCase());
		add("anyGamepadJustPressed", a -> FlxG.gamepads.anyJustPressed(gamepadButton(a[0])));
		add("anyGamepadPressed", a -> FlxG.gamepads.anyPressed(gamepadButton(a[0])));
		add("anyGamepadReleased", a -> FlxG.gamepads.anyJustReleased(gamepadButton(a[0])));
		add("gamepadJustPressed", a -> { var p = FlxG.gamepads.getByID(Std.int(toFloat(a[0]))); p != null && p.checkStatus(gamepadButton(a[1]), JUST_PRESSED); });
		add("gamepadPressed", a -> { var p = FlxG.gamepads.getByID(Std.int(toFloat(a[0]))); p != null && p.checkStatus(gamepadButton(a[1]), PRESSED); });
		add("gamepadReleased", a -> { var p = FlxG.gamepads.getByID(Std.int(toFloat(a[0]))); p != null && p.checkStatus(gamepadButton(a[1]), JUST_RELEASED); });
		add("mouseClicked", a -> switch (str(a[0], "left").toLowerCase()) {
			case "right": FlxG.mouse.justPressedRight;
			case "middle": FlxG.mouse.justPressedMiddle;
			default: FlxG.mouse.justPressed;
		});
		add("mousePressed", a -> switch (str(a[0], "left").toLowerCase()) {
			case "right": FlxG.mouse.pressedRight;
			case "middle": FlxG.mouse.pressedMiddle;
			default: FlxG.mouse.pressed;
		});
		add("mouseReleased", a -> switch (str(a[0], "left").toLowerCase()) {
			case "right": FlxG.mouse.justReleasedRight;
			case "middle": FlxG.mouse.justReleasedMiddle;
			default: FlxG.mouse.justReleased;
		});
		add("getMouseX", a -> FlxG.mouse.getScreenPosition(cameraFromString(a[0])).x);
		add("getMouseY", a -> FlxG.mouse.getScreenPosition(cameraFromString(a[0])).y);

		// random, colors and strings
		add("getRandomInt", a -> {
			var exclude = a[2] == null ? null : intList(a[2]);
			FlxG.random.int(Std.int(toFloat(a[0])), Std.int(toFloat(a[1], 2147483647)), exclude);
		});
		add("getRandomFloat", a -> FlxG.random.float(toFloat(a[0]), toFloat(a[1], 1)));
		add("getRandomBool", a -> FlxG.random.bool(toFloat(a[0], 50)));
		add("getColorFromHex", a -> (parseColor(a[0]) : Int));
		add("getColorFromString", a -> (parseColor(a[0]) : Int));
		add("getColorFromName", a -> (parseColor(a[0]) : Int));
		add("FlxColor", a -> (parseColor(a[0]) : Int));
		add("stringStartsWith", a -> str(a[0]).startsWith(str(a[1])));
		add("stringEndsWith", a -> str(a[0]).endsWith(str(a[1])));
		add("stringSplit", a -> str(a[0]).split(str(a[1])));
		add("stringTrim", a -> str(a[0]).trim());

		// files and saves
		add("checkFileExists", a -> {
			var path = str(a[0]);
			if (toBool(a[1])) return #if sys sys.FileSystem.exists(path) #else false #end;
			Assets.exists(Paths.getPath(path));
		});
		add("getTextFromFile", a -> {
			var path = str(a[0]);
			var full = Paths.getPath(path);
			Assets.exists(full) ? Assets.getText(full) : null;
		});
		add("directoryFileList", a -> Paths.getFolderContent(str(a[0])));
		add("initSaveData", a -> {
			var name = str(a[0]);
			if (!saves.exists(name)) {
				var save = new FlxSave();
				save.bind("psych-" + name, "CodenameEngine/psych");
				saves.set(name, save);
			}
			null;
		});
		add("flushSaveData", a -> { var save = saves.get(str(a[0])); if (save != null) save.flush(); null; });
		add("eraseSaveData", a -> { var save = saves.get(str(a[0])); if (save != null) save.erase(); null; });
		add("getDataFromSave", a -> {
			var save = saves.get(str(a[0]));
			if (save == null || save.data == null) return a[2];
			var v = Reflect.field(save.data, str(a[1]));
			v == null ? a[2] : v;
		});
		add("setDataFromSave", a -> {
			var save = saves.get(str(a[0]));
			if (save != null) Reflect.setField(save.data, str(a[1]), a[2]);
			null;
		});
		add("getModSetting", a -> null);

		// HScript bridge
		add("runHaxeCode", a -> runHaxeCode(s, str(a[0]), a[1], a[2] == null ? null : str(a[2]), a[3] is Array ? a[3] : []));
		add("runHaxeFunction", a -> {
			var h = hscripts.get(s);
			h == null ? null : h.call(str(a[0]), a[1] is Array ? a[1] : []);
		});
		add("addHaxeLibrary", a -> {
			var h = hscriptFor(s);
			var name = str(a[0]);
			var pack = str(a[1]);
			var cls = Type.resolveClass(pack == "" ? name : '$pack.$name');
			if (cls != null) h.set(name, cls);
			null;
		});

		// shaders are not run for Psych scripts on the console
		for (name in ["initLuaShader", "setSpriteShader", "removeSpriteShader", "setShaderFloat", "setShaderInt", "setShaderBool",
			"setShaderFloatArray", "setShaderIntArray", "setShaderBoolArray", "setShaderSampler2D", "getShaderFloat", "getShaderInt", "getShaderBool"])
			add(name, a -> {
				warnMissing(s, name);
				false;
			});
	}

	static function blendFromString(s:String):BlendMode {
		return switch (s.toLowerCase().trim()) {
			case "add": ADD;
			case "alpha": ALPHA;
			case "darken": DARKEN;
			case "difference": DIFFERENCE;
			case "erase": ERASE;
			case "hardlight": HARDLIGHT;
			case "invert": INVERT;
			case "layer": LAYER;
			case "lighten": LIGHTEN;
			case "multiply": MULTIPLY;
			case "overlay": OVERLAY;
			case "screen": SCREEN;
			case "shader": SHADER;
			case "subtract": SUBTRACT;
			default: NORMAL;
		}
	}

	static function removeSprite(tag:String, destroy:Bool) {
		var spr = sprites.get(tag);
		if (spr == null) return;
		if (game() != null) game().remove(spr, true);
		if (destroy) {
			sprites.remove(tag);
			spr.destroy();
		}
	}

	static function removeText(tag:String, destroy:Bool) {
		var t = texts.get(tag);
		if (t == null) return;
		if (game() != null) game().remove(t, true);
		if (destroy) {
			texts.remove(tag);
			t.destroy();
		}
	}

	static function cancelTween(tag:String) {
		var t = tweens.get(tag);
		if (t != null) {
			t.cancel();
			t.destroy();
			tweens.remove(tag);
		}
	}

	static function cancelTimer(tag:String) {
		var t = timers.get(tag);
		if (t != null) {
			t.cancel();
			t.destroy();
			timers.remove(tag);
		}
	}

	static function startTween(tag:String, obj:Dynamic, values:Dynamic, duration:Float, ease:Float->Float, vars:String, ?options:Dynamic) {
		cancelTween(tag);
		// Psych lets "scale.x" style keys through; flixel's tweens want nested objects
		var target:Dynamic = obj;
		var props:Dynamic = {};
		for (field in Reflect.fields(values)) {
			var v = Reflect.field(values, field);
			if (field.indexOf(".") >= 0) {
				var parts = field.split(".");
				var sub:Dynamic = obj;
				for (i in 0...parts.length - 1) sub = getField(sub, parts[i]);
				if (sub != null) {
					var single:Dynamic = {};
					Reflect.setField(single, parts[parts.length - 1], toFloat(v));
					FlxTween.tween(sub, single, duration, {ease: ease});
				}
			} else Reflect.setField(props, field, toFloat(v));
		}
		var opts:TweenOptions = {
			ease: ease,
			onComplete: _ -> {
				tweens.remove(tag);
				callOnLuas("onTweenCompleted", [tag, vars]);
			}
		};
		if (options != null) {
			var delay = Reflect.field(options, "startDelay");
			if (delay != null) opts.startDelay = toFloat(delay);
			var loopDelay = Reflect.field(options, "loopDelay");
			if (loopDelay != null) opts.loopDelay = toFloat(loopDelay);
			var type = Reflect.field(options, "type");
			if (type != null) opts.type = switch (str(type).toLowerCase()) {
				case "backward": BACKWARD;
				case "looping" | "loop": LOOPING;
				case "persist": PERSIST;
				case "pingpong": PINGPONG;
				default: ONESHOT;
			};
			var onUpdate = Reflect.field(options, "onUpdate");
			if (onUpdate != null) opts.onUpdate = _ -> callOnLuas(str(onUpdate), [tag, vars]);
			var onStart = Reflect.field(options, "onStart");
			if (onStart != null) opts.onStart = _ -> callOnLuas(str(onStart), [tag, vars]);
			var onComplete = Reflect.field(options, "onComplete");
			if (onComplete != null) opts.onComplete = _ -> {
				tweens.remove(tag);
				callOnLuas(str(onComplete), [tag, vars]);
			};
		}
		if (Reflect.fields(props).length > 0) tweens.set(tag, FlxTween.tween(target, props, duration, opts));
	}

	static function hscriptFor(s:PsychLuaScript):HScript {
		var h = hscripts.get(s);
		if (h == null) {
			h = cast Script.fromString("", s.fileName + "-haxe.hx");
			h.load();
			if (game() != null) {
				h.setParent(game());
				h.set("game", game());
			}
			h.set("setVar", (name:String, value:Dynamic) -> variables.set(name, value));
			h.set("getVar", (name:String) -> variables.get(name));
			h.set("removeVar", (name:String) -> variables.remove(name));
			h.set("debugPrint", (text:Dynamic) -> debugPrint(s, Std.string(text)));
			h.set("parentLua", s);
			h.set("this", h);
			hscripts.set(s, h);
		}
		return h;
	}

	static function runHaxeCode(s:PsychLuaScript, code:String, vars:Dynamic, func:String, args:Array<Dynamic>):Dynamic {
		var h = hscriptFor(s);
		if (vars != null) for (field in Reflect.fields(vars)) h.set(field, Reflect.field(vars, field));
		try {
			var expr = h.parser.parseString(code, s.fileName + ":runHaxeCode");
			var result = h.interp.execute(expr);
			if (func != null && func != "") result = h.call(func, args);
			return isPlain(result) ? result : null;
		} catch (e) {
			debugPrint(s, 'runHaxeCode: $e', 0xFFFF5555);
			return null;
		}
	}
}

/** Psych's ClientPrefs, read from Codename's options. */
class ClientPrefs {
	public static function get(name:String):Dynamic {
		return switch (name) {
			case "downScroll": Options.downscroll;
			case "middleScroll": false;
			case "opponentStrums": true;
			case "ghostTapping": Options.ghostTapping;
			case "flashing": Options.flashingMenu;
			case "lowQuality": Options.lowMemoryMode;
			case "globalAntialiasing" | "antialiasing": Options.antialiasing;
			case "shaders": Options.gameplayShaders;
			case "framerate": Options.framerate;
			case "camZooms": Options.camZoomOnBeat;
			case "hideHud": false;
			case "noteOffset": Options.songOffset;
			case "showFPS": Options.fpsCounter;
			case "timeBarType": "Disabled";
			case "scoreZoom": true;
			case "noReset": true;
			case "healthBarAlpha": 1;
			case "hitsoundVolume": 0;
			case "pauseMusic": "Tea Time";
			case "comboOffset": [0, 0, 0, 0];
			case "language": "en-US";
			default: null;
		}
	}
}
