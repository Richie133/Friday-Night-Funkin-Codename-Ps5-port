package funkin.ps5.psych;

import flixel.util.FlxTimer;
import funkin.backend.chart.ChartData.ChartEvent;
import funkin.backend.scripting.Script;
import funkin.game.Character;
import funkin.game.PlayState;

using StringTools;

/**
 * Psych Engine's built-in chart events, played on Codename's PlayState.
 *
 * Psych charts keep their events under Psych's names when a mod is converted
 * (except the three that Codename has its own version of, which the converter
 * rewrites). This script is added to a song when its chart has any of them.
 */
class PsychEvents extends Script {
	public static var NAMES = ["Hey!", "Set GF Speed", "Camera Follow Pos", "Alt Idle Animation", "Screen Shake", "Change Scroll Speed",
		"Set Property", "Play Sound", "Psych Add Camera Zoom", "Psych Play Animation", "Psych Change Character"];

	/** Whether "Camera Follow Pos" (or a script) has pinned the camera. */
	public static var cameraForced:Bool = false;
	static var targetBeforeForce:Int = 1;

	/** Adds the events script to the song when its chart uses Psych's events. */
	public static function attach(game:PlayState) {
		cameraForced = false;
		if (PlayState.SONG == null || PlayState.SONG.events == null) return;
		for (e in PlayState.SONG.events) if (NAMES.contains(e.name)) {
			var script = new PsychEvents("psych-events");
			game.scripts.add(script);
			script.load();
			return;
		}
	}

	public static function paramString(v:Dynamic):String
		return v == null ? "" : Std.string(v);

	public static function forceCamera(force:Bool) {
		var g = PlayState.instance;
		if (g == null || force == cameraForced) return;
		cameraForced = force;
		if (force) {
			targetBeforeForce = g.curCameraTarget;
			g.curCameraTarget = -1;
		} else g.curCameraTarget = targetBeforeForce;
	}

	/** Psych's triggerEvent: runs a built-in event and tells every Lua script. */
	public static function trigger(name:String, v1:Dynamic, v2:Dynamic) {
		run(name, paramString(v1), paramString(v2));
		PsychFunctions.callOnLuas("onEvent", [name, paramString(v1), paramString(v2), funkin.backend.system.Conductor.songPosition]);
	}

	override function onCall(func:String, parameters:Array<Dynamic>):Dynamic {
		if (func == "onEvent" && parameters != null && parameters.length > 0) {
			var event:ChartEvent = Reflect.field(parameters[0], "event");
			if (event != null && NAMES.contains(event.name)) {
				var p = event.params == null ? [] : event.params;
				run(event.name, paramString(p[0]), paramString(p[1]));
			}
		}
		return null;
	}

	static function character(name:String):Character {
		var g = PlayState.instance;
		return switch (name.trim().toLowerCase()) {
			case "dad" | "opponent" | "0": g.dad;
			case "gf" | "girlfriend" | "2": g.gf;
			case "bf" | "boyfriend" | "1": g.boyfriend;
			default: null;
		}
	}

	static function float(s:String, def:Float):Float {
		var f = Std.parseFloat(s);
		return Math.isNaN(f) ? def : f;
	}

	public static function run(name:String, v1:String, v2:String) {
		var g = PlayState.instance;
		if (g == null) return;
		switch (name) {
			case "Hey!":
				var who = switch (v1.trim().toLowerCase()) {
					case "bf" | "boyfriend" | "0": 0;
					case "gf" | "girlfriend" | "1": 1;
					default: 2;
				};
				var time = float(v2, 0.6);
				if (who != 1 && g.boyfriend != null && g.boyfriend.hasAnimation("hey")) {
					g.boyfriend.playAnim("hey", true, LOCK);
					new FlxTimer().start(time, _ -> if (g.boyfriend != null && g.boyfriend.getAnimName() == "hey") g.boyfriend.dance());
				}
				var cheer = g.gf != null && g.gf.hasAnimation("cheer") ? g.gf : (g.dad != null && g.dad.curCharacter.startsWith("gf") ? g.dad : null);
				if (who != 0 && cheer != null && cheer.hasAnimation("cheer")) {
					cheer.playAnim("cheer", true, LOCK);
					new FlxTimer().start(time, _ -> if (cheer.getAnimName() == "cheer") cheer.dance());
				}
			case "Set GF Speed":
				var speed = Std.parseInt(v1);
				if (g.gf != null) g.gf.beatInterval = speed == null || speed < 1 ? 1 : speed;
			case "Camera Follow Pos":
				if (v1.trim() == "" && v2.trim() == "") forceCamera(false);
				else {
					forceCamera(true);
					g.camFollow.setPosition(float(v1, 0), float(v2, 0));
				}
			case "Alt Idle Animation":
				var c = character(v1);
				if (c != null) c.idleSuffix = v2;
			case "Screen Shake":
				for (i => value in [v1, v2]) {
					var parts = value.split(",");
					var duration = float(parts[0], 0), intensity = parts.length > 1 ? float(parts[1], 0) : 0;
					if (duration > 0 && intensity != 0) (i == 0 ? g.camGame : g.camHUD).shake(intensity, duration);
				}
			case "Change Scroll Speed":
				var mult = float(v1, 1), duration = float(v2, 0);
				var target = PlayState.SONG.scrollSpeed * mult;
				if (duration <= 0) setScrollSpeed(target);
				else flixel.tweens.FlxTween.num(g.scrollSpeed, target, duration, {ease: flixel.tweens.FlxEase.linear}, setScrollSpeed);
			case "Set Property":
				var value:Dynamic = v2;
				if (v2 == "true") value = true;
				else if (v2 == "false") value = false;
				else if (!Math.isNaN(Std.parseFloat(v2))) value = Std.parseFloat(v2);
				PsychFunctions.setProperty(v1.trim(), value);
			case "Play Sound":
				if (v1.trim() != "") flixel.FlxG.sound.play(Paths.sound(v1.trim()), float(v2, 1));
			case "Psych Add Camera Zoom":
				if (Options.camZoomOnBeat && g.camGame.zoom < 1.35) {
					g.camGame.zoom += float(v1, 0.015);
					g.camHUD.zoom += float(v2, 0.03);
				}
			case "Psych Play Animation":
				var c = character(v2.trim() == "" ? "dad" : v2);
				if (c != null) c.playAnim(v1, true, LOCK);
			case "Psych Change Character":
				// the converter turns this into Codename's "Character Change"; scripts may still trigger it
				Logs.warn('[Psych] "Change Character" from a script is not supported on the PS5 port');
		}
	}

	static function setScrollSpeed(speed:Float) {
		var g = PlayState.instance;
		if (g == null) return;
		g.scrollSpeed = speed;
	}
}
