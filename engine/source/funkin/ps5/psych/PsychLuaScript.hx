package funkin.ps5.psych;

import funkin.backend.chart.ChartData.ChartEvent;
import funkin.backend.scripting.Script;
import funkin.backend.system.Conductor;
import funkin.game.Note;
import funkin.game.PlayState;
import haxe.io.Path;
import openfl.Assets;

/**
 * A Psych Engine `.lua` script, run by Lua 5.1 inside Codename's script system.
 *
 * Codename calls its usual script functions ("create", "update", "onPlayerHit"...) and
 * this class calls the Psych names for them ("onCreate", "onUpdate", "goodNoteHit"...),
 * with Psych's arguments. Returning Function_Stop from the callbacks Psych lets cancel
 * (onStartCountdown, onEndSong, onPause, onGameOver...) cancels the Codename event.
 *
 * The functions Psych gives scripts (makeLuaSprite, doTweenX, setProperty...) are in
 * PsychFunctions.
 */
class PsychLuaScript extends Script {
	public static inline var FUNCTION_STOP = "##PSYCHLUA_FUNCTIONSTOP";
	public static inline var FUNCTION_CONTINUE = "##PSYCHLUA_FUNCTIONCONTINUE";
	public static inline var FUNCTION_STOP_LUA = "##PSYCHLUA_FUNCTIONSTOPLUA";
	public static inline var FUNCTION_STOP_HSCRIPT = "##PSYCHLUA_FUNCTIONSTOPHSCRIPT";
	public static inline var FUNCTION_STOP_ALL = "##PSYCHLUA_FUNCTIONSTOPALL";

	/** Every running Psych script, for callOnLuas and setOnLuas. */
	public static var running:Array<PsychLuaScript> = [];

	public var handle:Int = -1;
	public var closed:Bool = false;
	var code:String = null;
	var functions:Array<Array<Dynamic>->Dynamic> = [];
	var functionNames:Map<String, Int> = [];
	var reportedErrors:Map<String, Bool> = [];

	/** The Psych name of this script, as its `scriptName` global (mods/.../file.lua). */
	public var scriptName:String;

	override function onCreate(path:String) {
		handle = LuaBridge.newState();
		if (handle < 0) {
			closed = true;
			Logs.error('Could not start Lua for $path');
			return;
		}
		LuaBridge.owners.set(handle, dispatch);
		scriptName = path;
		PsychFunctions.register(this);
	}

	override function loadFromString(code:String) {
		this.code = code;
		return this;
	}

	override function onLoad() {
		if (closed) return;
		if (code == null) {
			try code = Assets.getText(path)
			catch (e) {
				error('could not read the script: $e');
				return;
			}
		}
		running.push(this);
		PsychFunctions.setGlobals(this);
		if (!LuaBridge.run(handle, code, fileName)) {
			error(LuaBridge.lastError);
			// Psych keeps a script that failed to load out of the game
			stop();
		}
	}

	/** Gives Lua a Haxe function under `name`. */
	public function addFunction(name:String, fn:Array<Dynamic>->Dynamic) {
		if (closed) return;
		var id = functionNames.get(name);
		if (id == null) {
			id = functions.length;
			functions.push(fn);
			functionNames.set(name, id);
		} else functions[id] = fn;
		LuaBridge.register(handle, name, id);
	}

	function dispatch(id:Int, args:Array<Dynamic>):Dynamic {
		var fn = functions[id];
		if (fn == null) return null;
		var old = Script.curScript;
		Script.curScript = this;
		var result = fn(args == null ? [] : args);
		Script.curScript = old;
		return result;
	}

	/** Calls a Psych callback in this script. Null when it has none. */
	public function callPsych(name:String, ?args:Array<Dynamic>):Dynamic {
		if (closed || !active) return null;
		var result = LuaBridge.call(handle, name, args == null ? [] : args);
		if (LuaBridge.failed) {
			var message = LuaBridge.lastError;
			// one report per message, or a broken onUpdate floods the log
			if (!reportedErrors.exists(message)) {
				reportedErrors.set(message, true);
				error('$name: $message');
				PsychFunctions.debugPrint(this, 'ERROR ($name): $message', 0xFFFF5555);
			}
			return null;
		}
		return result;
	}

	public function setGlobal(name:String, value:Dynamic) {
		if (!closed) LuaBridge.setGlobal(handle, name, value);
	}

	public function getGlobal(name:String):Dynamic {
		return closed ? null : LuaBridge.getGlobal(handle, name);
	}

	override function set(variable:String, value:Dynamic) {
		// only plain values make sense in Lua: Codename's class shortcuts are left out
		if (closed || value == null) return;
		if (value is String || value is Bool || value is Int || value is Float) setGlobal(variable, value);
	}

	override function get(variable:String):Dynamic
		return getGlobal(variable);

	/** Stops the script for good (Psych's `close()`). */
	public function stop() {
		if (closed) return;
		active = false;
		closed = true;
		running.remove(this);
		LuaBridge.close(handle);
	}

	static function isStop(v:Dynamic):Bool
		return v == FUNCTION_STOP || v == FUNCTION_STOP_LUA || v == FUNCTION_STOP_ALL;

	inline function game():PlayState
		return PlayState.instance;

	override function onCall(func:String, parameters:Array<Dynamic>):Dynamic {
		if (closed) return null;
		var arg:Dynamic = parameters != null && parameters.length > 0 ? parameters[0] : null;
		switch (func) {
			case "create":
				callPsych("onCreate");
			case "postCreate":
				PsychFunctions.updateGlobals(this);
				callPsych("onCreatePost");
			case "update":
				PsychFunctions.updateGlobals(this);
				callPsych("onUpdate", [arg]);
			case "postUpdate":
				callPsych("onUpdatePost", [arg]);
			case "beatHit":
				setGlobal("curBeat", arg);
				callPsych("onBeatHit");
			case "stepHit":
				setGlobal("curStep", arg);
				callPsych("onStepHit");
			case "measureHit":
				setGlobal("curSection", arg);
				PsychFunctions.updateSectionGlobals(this);
				callPsych("onSectionHit");
			case "onStartCountdown":
				if (isStop(callPsych("onStartCountdown"))) cancelEvent(arg);
			case "onCountdown":
				var counter:Int = Reflect.field(arg, "swagCounter");
				callPsych("onCountdownTick", [counter]);
			case "onSongStart":
				setGlobal("startedCountdown", true);
				callPsych("onSongStart");
			case "onSongEnd":
				if (isStop(callPsych("onEndSong"))) cancelEvent(arg);
			case "onPlayerHit" | "onDadHit":
				var note:Note = Reflect.field(arg, "note");
				if (note != null) {
					var args:Array<Dynamic> = [PsychFunctions.noteIndex(note), note.strumID, note.noteType == null ? "" : note.noteType, note.isSustainNote];
					if (isStop(callPsych(func == "onPlayerHit" ? "goodNoteHitPre" : "opponentNoteHitPre", args))) cancelEvent(arg);
					callPsych(func == "onPlayerHit" ? "goodNoteHit" : "opponentNoteHit", args);
				}
			case "onPlayerMiss":
				var note:Note = Reflect.field(arg, "note");
				if (note != null)
					callPsych("noteMiss", [PsychFunctions.noteIndex(note), note.strumID, note.noteType == null ? "" : note.noteType, note.isSustainNote]);
				else
					callPsych("noteMissPress", [Reflect.field(arg, "direction")]);
			case "onEvent":
				var event:ChartEvent = Reflect.field(arg, "event");
				if (event != null) {
					var p = event.params == null ? [] : event.params;
					callPsych("onEvent", [event.name, PsychEvents.paramString(p[0]), PsychEvents.paramString(p[1]), event.time]);
				}
			case "onGamePause":
				if (isStop(callPsych("onPause"))) cancelEvent(arg);
			case "onSubstateClose":
				if (game() != null && game().paused == false) callPsych("onResume");
			case "onGameOver":
				setGlobal("inGameOver", true);
				if (isStop(callPsych("onGameOver"))) cancelEvent(arg);
			case "onCameraMove":
				var g = game();
				if (g != null) callPsych("onMoveCamera", [switch (g.curCameraTarget) {
					case 0: "dad";
					case 1: "boyfriend";
					default: "gf";
				}]);
			case "onFocus":
				callPsych("onFocus");
			case "onFocusLost":
				callPsych("onFocusLost");
			case "destroy":
				callPsych("onDestroy");
			default:
				// direct calls (Codename's "HScript Call" event, callOnLuas from HScript)
				if (parameters == null || parameters.length == 0 || [for (p in parameters) PsychFunctions.isPlain(p)].indexOf(false) < 0)
					if (LuaBridge.hasFunction(handle, func)) return callPsych(func, parameters);
		}
		return null;
	}

	static function cancelEvent(event:Dynamic) {
		if (event is funkin.backend.scripting.events.CancellableEvent)
			(event : funkin.backend.scripting.events.CancellableEvent).cancel();
	}

	override function error(text:String, ?additionalInfo:Dynamic) {
		Logs.traceColored([Logs.logText('[Psych Lua] $fileName: ', RED), Logs.logText(text)], ERROR);
	}

	override function destroy() {
		if (!closed) {
			stop();
			PsychFunctions.scriptStopped(this);
		}
		super.destroy();
	}
}
