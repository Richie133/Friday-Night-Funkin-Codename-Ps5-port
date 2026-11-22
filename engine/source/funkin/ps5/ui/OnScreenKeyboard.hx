package funkin.ps5.ui;

import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.ps5.PS5Input;
import funkin.ps5.ui.PS5UI.PadButton;

/**
 * The port's own on-screen keyboard, for searching mods with a controller.
 *
 *   D-pad / left stick  move        ✕  type the key
 *   ○  delete a letter              △  space
 *   □  shift (capitals, symbols)    L1 / R1  move the cursor
 *   OPTIONS  search                 the touchpad pointer can click keys too
 *
 * A USB or Bluetooth keyboard types into it directly.
 */
class OnScreenKeyboard extends MusicBeatSubstate {
	static var LOWER:Array<Array<String>> = [
		["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
		["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "'"],
		["a", "s", "d", "f", "g", "h", "j", "k", "l", ":", "/"],
		["z", "x", "c", "v", "b", "n", "m", ",", ".", "?", "!"]
	];
	static var UPPER:Array<Array<String>> = [
		["#", "@", "&", "(", ")", "+", "=", "*", "%", "$", "_"],
		["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "\""],
		["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "\\"],
		["Z", "X", "C", "V", "B", "N", "M", "<", ">", "[", "]"]
	];
	/** The bottom row: label, width in keys. */
	static var SPECIAL:Array<{id:String, label:String, w:Int}> = [
		{id: "shift", label: "Shift", w: 2},
		{id: "space", label: "Space", w: 4},
		{id: "back", label: "Delete", w: 2},
		{id: "clear", label: "Clear", w: 1},
		{id: "done", label: "Done", w: 2}
	];

	public var text(default, null):String;
	var caret:Int;
	var title:String;
	var maxLength:Int;
	var onDone:String->Void;
	var onCancel:Void->Void;

	var shift:Bool = false;
	var row:Int = 1;
	var col:Int = 0;
	var repeat = new RepeatState();

	var keyCam:FlxCamera;
	var field:FunkinText;
	var caretSpr:FlxSprite;
	var caretTime:Float = 0;
	var keys:Array<Array<{bg:FlxSprite, label:FlxText, id:String}>> = [];
	var cursor:FlxSprite;
	var keyW:Int = 76;
	var keyH:Int = 62;
	var gap:Int = 8;
	var originX:Float;
	var originY:Float;

	public function new(title:String, initial:String = "", onDone:String->Void, ?onCancel:Void->Void, maxLength:Int = 80) {
		super();
		this.title = title;
		this.text = initial == null ? "" : initial;
		this.caret = this.text.length;
		this.onDone = onDone;
		this.onCancel = onCancel;
		this.maxLength = maxLength;
	}

	override function create() {
		super.create();
		keyCam = new FlxCamera();
		keyCam.bgColor = 0;
		FlxG.cameras.add(keyCam, false);
		cameras = [keyCam];
		PS5Input.typing = true;

		var shade = new FlxSprite().makeSolid(FlxG.width, FlxG.height, 0xB0000000);
		shade.scrollFactor.set();
		add(shade);

		var cols = LOWER[0].length;
		var gridW = cols * keyW + (cols - 1) * gap;
		var panelW = gridW + 60;
		var panelH = 5 * (keyH + gap) + 200;
		var px = (FlxG.width - panelW) / 2;
		var py = FlxG.height - panelH - 20;
		var panel = PS5UI.panel(px, py, panelW, panelH, PS5UI.PANEL_LIGHT, 26, 0xFF5B4A80);
		add(panel);

		var titleText = new FunkinText(px + 30, py + 18, panelW - 60, title, 28);
		add(titleText);

		var fieldBg = PS5UI.panel(px + 30, py + 60, panelW - 60, 60, 0xFF0E0A16, 12, PS5UI.ACCENT);
		add(fieldBg);
		field = new FunkinText(px + 46, py + 72, panelW - 92, "", 32, false);
		add(field);
		caretSpr = new FlxSprite().makeSolid(3, 36, FlxColor.WHITE);
		add(caretSpr);

		originX = px + 30;
		originY = py + 140;
		cursor = PS5UI.panel(0, 0, keyW + 10, keyH + 10, FlxColor.TRANSPARENT, 14, 0xFFFFE15A);
		buildKeys();
		add(cursor);

		var hints = PS5UI.hints(px + 30, py + panelH - 46, [
			{button: CROSS, label: "Type"},
			{button: CIRCLE, label: "Delete"},
			{button: TRIANGLE, label: "Space"},
			{button: SQUARE, label: "Shift"},
			{button: OPTIONS, label: "Done"},
			{button: TOUCHPAD, label: "Cancel"}
		], 26);
		add(hints);

		refreshText();
		moveCursor(0, 0);

		lime.app.Application.current.window.onTextInput.add(onTextInput);
		lime.app.Application.current.window.textInputEnabled = true;

		for (m in members) if (m is FlxSprite) {
			var s:FlxSprite = cast m;
			s.alpha = 0;
			FlxTween.tween(s, {alpha: 1}, 0.15);
		}
	}

	function buildKeys() {
		for (r in keys) for (k in r) {
			remove(k.bg, true);
			remove(k.label, true);
			k.bg.destroy();
			k.label.destroy();
		}
		keys = [];
		var layout = shift ? UPPER : LOWER;
		for (r in 0...layout.length) {
			var rowKeys = [];
			for (c in 0...layout[r].length) rowKeys.push(makeKey(layout[r][c], layout[r][c], originX + c * (keyW + gap), originY + r * (keyH + gap), 1));
			keys.push(rowKeys);
		}
		var special = [];
		var cx = originX;
		var y = originY + layout.length * (keyH + gap);
		for (s in SPECIAL) {
			var label = s.id == "shift" && shift ? "SHIFT" : s.label;
			special.push(makeKey(s.id, label, cx, y, s.w));
			cx += s.w * (keyW + gap);
		}
		keys.push(special);
		if (cursor != null) {
			remove(cursor, true);
			add(cursor);
		}
	}

	function makeKey(id:String, label:String, x:Float, y:Float, widthInKeys:Int) {
		var w = widthInKeys * keyW + (widthInKeys - 1) * gap;
		var special = id.length > 1;
		var bg = PS5UI.panel(x, y, w, keyH, special ? 0xFF3A2F55 : 0xFF2A2140, 12);
		add(bg);
		var t = new FlxText(x, y, w, label, special ? 22 : 30);
		t.setFormat(Paths.font("vcr.ttf"), special ? 22 : 30, FlxColor.WHITE, CENTER);
		t.y = y + (keyH - t.height) / 2;
		add(t);
		return {bg: bg, label: t, id: id};
	}

	function moveCursor(dx:Int, dy:Int) {
		if (dy != 0) {
			var oldRow = row;
			row = FlxMath.wrap(row + dy, 0, keys.length - 1);
			// keep roughly the same column between the letter rows and the wider bottom row
			col = mapColumn(oldRow, row, col);
		}
		if (dx != 0) col = FlxMath.wrap(col + dx, 0, keys[row].length - 1);
		if (col >= keys[row].length) col = keys[row].length - 1;
		var k = keys[row][col];
		cursor.makeGraphic(Std.int(k.bg.width + 10), keyH + 10, FlxColor.TRANSPARENT, true);
		flixel.util.FlxSpriteUtil.drawRoundRect(cursor, 2, 2, k.bg.width + 6, keyH + 6, 16, 16, FlxColor.TRANSPARENT, {thickness: 4, color: 0xFFFFE15A});
		cursor.setPosition(k.bg.x - 5, k.bg.y - 5);
		if (dx != 0 || dy != 0) CoolUtil.playMenuSFX(SCROLL, 0.4);
	}

	function mapColumn(fromRow:Int, toRow:Int, c:Int):Int {
		var last = keys.length - 1;
		if (fromRow != last && toRow == last) {
			var acc = 0;
			for (i => s in SPECIAL) {
				acc += s.w;
				if (c < acc) return i;
			}
			return SPECIAL.length - 1;
		}
		if (fromRow == last && toRow != last) {
			var acc = 0;
			for (i in 0...c) acc += SPECIAL[i].w;
			return Std.int(Math.min(acc + Std.int(SPECIAL[c].w / 2), keys[toRow].length - 1));
		}
		return c;
	}

	function press(id:String) {
		switch (id) {
			case "shift":
				shift = !shift;
				buildKeys();
				moveCursor(0, 0);
			case "space": typeText(" ");
			case "back": backspace();
			case "clear":
				text = "";
				caret = 0;
				refreshText();
			case "done": finish();
			default:
				typeText(id);
		}
	}

	function typeText(s:String) {
		if (text.length + s.length > maxLength) return;
		text = text.substr(0, caret) + s + text.substr(caret);
		caret += s.length;
		refreshText();
		CoolUtil.playMenuSFX(SCROLL, 0.3);
	}

	function backspace() {
		if (caret <= 0) return;
		text = text.substr(0, caret - 1) + text.substr(caret);
		caret--;
		refreshText();
	}

	function refreshText() {
		field.text = text;
		// put the caret after the text before it
		var probe = new FlxText(0, 0, 0, text.substr(0, caret), 32);
		probe.font = field.font;
		var w = text.length == 0 ? 0 : probe.width - 4;
		probe.destroy();
		caretSpr.setPosition(field.x + Math.max(0, w), field.y);
	}

	function onTextInput(s:String) {
		if (s == null || s == "") return;
		for (i in 0...s.length) {
			var c = s.charAt(i);
			if (c.charCodeAt(0) >= 32) typeText(c);
		}
	}

	function finish() {
		CoolUtil.playMenuSFX(CONFIRM);
		var result = StringTools.trim(text);
		closeKeyboard();
		if (onDone != null) onDone(result);
	}

	function cancel() {
		CoolUtil.playMenuSFX(CANCEL);
		closeKeyboard();
		if (onCancel != null) onCancel();
	}

	function closeKeyboard() {
		PS5Input.typing = false;
		lime.app.Application.current.window.onTextInput.remove(onTextInput);
		lime.app.Application.current.window.textInputEnabled = false;
		close();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		caretTime += elapsed;
		caretSpr.visible = (caretTime % 1) < 0.6;

		// the keyboard reads the pad directly: PS5Input.justPressed is muted while typing
		var pad = FlxG.gamepads;
		inline function padPressed(id:flixel.input.gamepad.FlxGamepadInputID) return pad.anyJustPressed(id);

		var left = pad.anyPressed(DPAD_LEFT) || pad.anyPressed(LEFT_STICK_DIGITAL_LEFT) || FlxG.keys.pressed.LEFT;
		var right = pad.anyPressed(DPAD_RIGHT) || pad.anyPressed(LEFT_STICK_DIGITAL_RIGHT) || FlxG.keys.pressed.RIGHT;
		var up = pad.anyPressed(DPAD_UP) || pad.anyPressed(LEFT_STICK_DIGITAL_UP) || FlxG.keys.pressed.UP;
		var down = pad.anyPressed(DPAD_DOWN) || pad.anyPressed(LEFT_STICK_DIGITAL_DOWN) || FlxG.keys.pressed.DOWN;
		var nav = repeat.step((right ? 1 : 0) - (left ? 1 : 0), (down ? 1 : 0) - (up ? 1 : 0), elapsed);
		if (nav.x != 0 || nav.y != 0) moveCursor(nav.x, nav.y);

		if (padPressed(A)) press(keys[row][col].id);
		if (padPressed(B) || FlxG.keys.justPressed.BACKSPACE) backspace();
		if (padPressed(Y)) typeText(" ");
		if (padPressed(X)) press("shift");
		if (padPressed(LEFT_SHOULDER) && caret > 0) {
			caret--;
			refreshText();
		}
		if (padPressed(RIGHT_SHOULDER) && caret < text.length) {
			caret++;
			refreshText();
		}
		if (padPressed(START) || FlxG.keys.justPressed.ENTER) finish();
		else if (PS5Input.touchpadJustPressed() || FlxG.keys.justPressed.ESCAPE) cancel();

		// a pointer (mouse or touchpad) can click keys
		if (FlxG.mouse.justPressed) {
			var mp = FlxG.mouse.getViewPosition(keyCam);
			for (r => rowKeys in keys) for (c => k in rowKeys) {
				if (mp.x >= k.bg.x && mp.x <= k.bg.x + k.bg.width && mp.y >= k.bg.y && mp.y <= k.bg.y + k.bg.height) {
					row = r;
					col = c;
					moveCursor(0, 0);
					press(k.id);
				}
			}
			mp.put();
		}
	}

	override function destroy() {
		PS5Input.typing = false;
		if (FlxG.cameras.list.contains(keyCam)) FlxG.cameras.remove(keyCam);
		super.destroy();
	}
}
