package funkin.ps5;

import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.keyboard.FlxKey;
import funkin.ps5.ui.PS5UI.PadButton;
import lime.ui.Gamepad;
import lime.ui.GamepadButton;

/**
 * Controller input the port's screens need beyond the engine's Controls
 * (L1/R1/L2/R2, △, □, OPTIONS, the touchpad button), with keyboard keys standing in
 * for them on a PC. Also a global plugin for the touchpad shortcuts:
 *
 *  - in a song, pressing the touchpad opens the chart editor on that song;
 *  - the mouse pointer shows up while a mouse or the touchpad moves it, and hides again.
 *
 * Moving the pointer with the touchpad, and USB/Bluetooth mice and keyboards, are
 * handled below the engine, in the PS5 SDL drivers (ps5/sdl), so the editors see them
 * as an ordinary mouse.
 */
class PS5Input extends FlxBasic {
	/** SDL's number for the touchpad click; Lime passes it on unchanged. */
	public static inline var SDL_TOUCHPAD_BUTTON:Int = 20;

	public static var instance:PS5Input;

	static var touchpadDown:Bool = false;
	static var touchpadPressedFrame:Int = -10;
	static var touchpadReleasedFrame:Int = -10;
	static var frame:Int = 0;

	/** While true, the port's screens ignore keys (the on-screen keyboard takes them). */
	public static var typing:Bool = false;

	var idleMouse:Float = 0;
	var lastMouseX:Int = 0;
	var lastMouseY:Int = 0;

	public static function init() {
		if (instance != null) return;
		instance = new PS5Input();
		FlxG.plugins.addPlugin(instance);
		for (g in Gamepad.devices) listen(g);
		Gamepad.onConnect.add(listen);
		#if ps5
		// no system pointer on the console: flixel draws its own while it is in use
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		#end
	}

	static function listen(g:Gamepad) {
		g.onButtonDown.add(b -> {
			if ((b : Int) == SDL_TOUCHPAD_BUTTON) {
				touchpadDown = true;
				touchpadPressedFrame = frame;
			}
		});
		g.onButtonUp.add(b -> {
			if ((b : Int) == SDL_TOUCHPAD_BUTTON) {
				touchpadDown = false;
				touchpadReleasedFrame = frame;
			}
		});
	}

	public function new() {
		super();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		frame++;

		// touchpad shortcut: the chart editor from inside a song
		if (touchpadJustPressed() && Options.ps5TouchpadCharter) {
			var state = FlxG.state;
			if (state is PlayState && PlayState.SONG != null && PlayState.instance != null && !PlayState.instance.inCutscene) {
				var ps = PlayState.instance;
				funkin.editors.charter.Charter.startHere = false;
				FlxG.switchState(new funkin.editors.charter.Charter(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation, false));
			}
		}

		#if ps5
		// show the pointer while it moves, hide it after a few still seconds outside the editors
		var mx = FlxG.mouse.viewX, my = FlxG.mouse.viewY;
		if (mx != lastMouseX || my != lastMouseY || FlxG.mouse.justPressed) {
			idleMouse = 0;
			FlxG.mouse.visible = true;
		} else {
			idleMouse += elapsed;
			if (idleMouse > 4 && !isEditor()) FlxG.mouse.visible = false;
		}
		lastMouseX = mx;
		lastMouseY = my;
		#end
	}

	static function isEditor():Bool {
		return FlxG.state is funkin.editors.ui.UIState;
	}

	public static function touchpadPressed():Bool return touchpadDown || FlxG.keys.pressed.F7;

	/** Pressed this frame. F7 stands in for the touchpad on a PC. */
	public static function touchpadJustPressed():Bool
		return touchpadPressedFrame == frame - 1 || touchpadPressedFrame == frame || FlxG.keys.justPressed.F7;

	/** A button pressed this frame, on any controller or its keyboard stand-in. */
	public static function justPressed(button:PadButton):Bool {
		if (typing) return false;
		var pad = FlxG.gamepads;
		var keys = FlxG.keys;
		return switch (button) {
			case CROSS: pad.anyJustPressed(FlxGamepadInputID.A) || keys.anyJustPressed([ENTER, SPACE]);
			case CIRCLE: pad.anyJustPressed(FlxGamepadInputID.B) || keys.anyJustPressed([ESCAPE, BACKSPACE]);
			case SQUARE: pad.anyJustPressed(FlxGamepadInputID.X) || keys.justPressed.X;
			case TRIANGLE: pad.anyJustPressed(FlxGamepadInputID.Y) || keys.justPressed.F;
			case L1: pad.anyJustPressed(FlxGamepadInputID.LEFT_SHOULDER) || keys.justPressed.Q;
			case R1: pad.anyJustPressed(FlxGamepadInputID.RIGHT_SHOULDER) || keys.justPressed.E;
			case L2: pad.anyJustPressed(FlxGamepadInputID.LEFT_TRIGGER_BUTTON) || keys.justPressed.PAGEUP;
			case R2: pad.anyJustPressed(FlxGamepadInputID.RIGHT_TRIGGER_BUTTON) || keys.justPressed.PAGEDOWN;
			case OPTIONS: pad.anyJustPressed(FlxGamepadInputID.START) || keys.justPressed.TAB;
			case CREATE: pad.anyJustPressed(FlxGamepadInputID.BACK) || keys.justPressed.C;
			case TOUCHPAD: touchpadJustPressed();
			case DPAD: false;
		}
	}

	/** -1, 0 or 1 on each axis this frame (D-pad, left stick, arrow keys), with key repeat. */
	public static function navigation(repeat:RepeatState, elapsed:Float):{x:Int, y:Int} {
		if (typing) return {x: 0, y: 0};
		var pad = FlxG.gamepads;
		var keys = FlxG.keys;
		var left = pad.anyPressed(FlxGamepadInputID.DPAD_LEFT) || pad.anyPressed(FlxGamepadInputID.LEFT_STICK_DIGITAL_LEFT) || keys.pressed.LEFT;
		var right = pad.anyPressed(FlxGamepadInputID.DPAD_RIGHT) || pad.anyPressed(FlxGamepadInputID.LEFT_STICK_DIGITAL_RIGHT) || keys.pressed.RIGHT;
		var up = pad.anyPressed(FlxGamepadInputID.DPAD_UP) || pad.anyPressed(FlxGamepadInputID.LEFT_STICK_DIGITAL_UP) || keys.pressed.UP;
		var down = pad.anyPressed(FlxGamepadInputID.DPAD_DOWN) || pad.anyPressed(FlxGamepadInputID.LEFT_STICK_DIGITAL_DOWN) || keys.pressed.DOWN;
		var x = (right ? 1 : 0) - (left ? 1 : 0);
		var y = (down ? 1 : 0) - (up ? 1 : 0);
		return repeat.step(x, y, elapsed);
	}
}

/** Key repeat for menu navigation: one step on press, then a steady stream while held. */
class RepeatState {
	public var delay:Float = 0.35;
	public var rate:Float = 0.07;
	var lastX:Int = 0;
	var lastY:Int = 0;
	var held:Float = 0;
	var next:Float = 0;

	public function new() {}

	public function step(x:Int, y:Int, elapsed:Float):{x:Int, y:Int} {
		if (x != lastX || y != lastY) {
			lastX = x;
			lastY = y;
			held = 0;
			next = delay;
			return {x: x, y: y};
		}
		if (x == 0 && y == 0) return {x: 0, y: 0};
		held += elapsed;
		if (held >= next) {
			next += rate;
			return {x: x, y: y};
		}
		return {x: 0, y: 0};
	}
}
