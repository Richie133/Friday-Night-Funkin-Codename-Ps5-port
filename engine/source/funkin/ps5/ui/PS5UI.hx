package funkin.ps5.ui;

import flixel.graphics.FlxGraphic;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import funkin.backend.FunkinText;
import openfl.display.BitmapData;

/** The four face buttons, plus the other buttons the port names in its hints. */
enum abstract PadButton(String) from String to String {
	var CROSS = "cross";
	var CIRCLE = "circle";
	var SQUARE = "square";
	var TRIANGLE = "triangle";
	var L1 = "L1";
	var R1 = "R1";
	var L2 = "L2";
	var R2 = "R2";
	var OPTIONS = "OPTIONS";
	var CREATE = "CREATE";
	var TOUCHPAD = "TOUCHPAD";
	var DPAD = "DPAD";
}

/**
 * Drawing helpers shared by the port's screens: rounded panels, PlayStation button
 * glyphs drawn as shapes (the engine's fonts have no ✕○□△), and hint bars.
 */
class PS5UI {
	public static inline var ACCENT:FlxColor = 0xFF9B4DFF;
	public static inline var PANEL:FlxColor = 0xE0161022;
	public static inline var PANEL_LIGHT:FlxColor = 0xF0271C3A;
	public static inline var TEXT_DIM:FlxColor = 0xFFB9B0CC;

	static var glyphCache:Map<String, FlxGraphic> = [];

	/** A rounded rectangle as a sprite. */
	public static function panel(x:Float, y:Float, w:Int, h:Int, color:FlxColor = PANEL, radius:Float = 18, ?border:FlxColor):FlxSprite {
		var spr = new FlxSprite(x, y);
		spr.makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		// a border is stroked on the shape's edge: inset it so none of it is cut off
		var inset = border != null ? 2 : 0;
		FlxSpriteUtil.drawRoundRect(spr, inset, inset, w - inset * 2, h - inset * 2, radius, radius, color,
			border != null ? {thickness: 3, color: border} : null);
		spr.antialiasing = true;
		return spr;
	}

	/** Left edge for a screen title, past the FPS counter when it is showing. */
	public static function headerX():Float {
		var fps = funkin.backend.system.framerate.Framerate.debugMode > 0;
		return fps ? 190 : 44;
	}

	/** The PlayStation symbol for a button, `size` pixels across. */
	public static function glyph(button:PadButton, size:Int = 34):FlxSprite {
		var key = '$button-$size';
		var spr = new FlxSprite();
		var cached = glyphCache.get(key);
		if (cached != null && cached.bitmap != null) {
			spr.loadGraphic(cached);
			spr.antialiasing = true;
			return spr;
		}
		var isText = switch (button) {
			case CROSS | CIRCLE | SQUARE | TRIANGLE | DPAD: false;
			default: true;
		};
		if (isText) {
			var label:String = button;
			var w = Std.int(Math.max(size * 1.3, label.length * size * 0.42 + 14));
			spr.makeGraphic(w, size, FlxColor.TRANSPARENT, true);
			FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, size - 2, size * 0.5, size * 0.5, 0xFF2D2640, {thickness: 2, color: 0xFFDDD6EE});
			var t = new FlxText(0, 0, w, label, Std.int(size * 0.42));
			t.setFormat(Paths.font("vcr.ttf"), Std.int(size * 0.42), FlxColor.WHITE, CENTER);
			t.drawFrame(true);
			spr.stamp(t, 0, Std.int((size - t.height) / 2));
			t.destroy();
		} else {
			spr.makeGraphic(size, size, FlxColor.TRANSPARENT, true);
			var r = size / 2;
			FlxSpriteUtil.drawCircle(spr, r, r, r - 1, 0xFF1E1A28, {thickness: 2, color: 0xFF5A5470});
			var s = size * 0.26;
			var line = {thickness: Math.max(2, size * 0.09), color: 0xFFFFFFFF};
			switch (button) {
				case CROSS:
					line.color = 0xFF7CB2E8;
					FlxSpriteUtil.drawLine(spr, r - s, r - s, r + s, r + s, line);
					FlxSpriteUtil.drawLine(spr, r + s, r - s, r - s, r + s, line);
				case CIRCLE:
					FlxSpriteUtil.drawCircle(spr, r, r, s, FlxColor.TRANSPARENT, {thickness: line.thickness, color: 0xFFFF6666});
				case SQUARE:
					FlxSpriteUtil.drawRect(spr, r - s, r - s, s * 2, s * 2, FlxColor.TRANSPARENT, {thickness: line.thickness, color: 0xFFE89BD5});
				case TRIANGLE:
					var c:FlxColor = 0xFF46D6A6;
					var top = FlxPoint.get(r, r - s * 1.1), left = FlxPoint.get(r - s * 1.1, r + s * 0.8), right = FlxPoint.get(r + s * 1.1, r + s * 0.8);
					FlxSpriteUtil.drawPolygon(spr, [top, right, left, top], FlxColor.TRANSPARENT, {thickness: line.thickness, color: c});
				case DPAD:
					var a = size * 0.14;
					FlxSpriteUtil.drawRect(spr, r - a, r - s * 1.3, a * 2, s * 2.6, 0xFFEDEDED);
					FlxSpriteUtil.drawRect(spr, r - s * 1.3, r - a, s * 2.6, a * 2, 0xFFEDEDED);
				default:
			}
		}
		spr.antialiasing = true;
		var graphic = FlxGraphic.fromBitmapData(spr.pixels.clone(), false, key);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		glyphCache.set(key, graphic);
		return spr;
	}

	/** A row of "glyph + label" hints, laid out left to right. */
	public static function hints(x:Float, y:Float, list:Array<{button:PadButton, label:String}>, size:Int = 30):FlxSpriteGroup {
		var group = new FlxSpriteGroup(x, y);
		var cx = 0.0;
		for (h in list) {
			var g = glyph(h.button, size);
			g.x = cx;
			group.add(g);
			cx += g.width + 8;
			var t = new FunkinText(cx, 0, 0, h.label, Std.int(size * 0.62));
			t.y = (size - t.height) / 2;
			group.add(t);
			cx += t.width + 26;
		}
		return group;
	}

	/** A small colored label, for an engine or a tag. */
	public static function badge(text:String, color:FlxColor, size:Int = 16):FlxSpriteGroup {
		var group = new FlxSpriteGroup();
		var t = new FlxText(0, 0, 0, text, size);
		t.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE);
		var w = Std.int(t.width + 16), h = Std.int(t.height + 6);
		group.add(panel(0, 0, w, h, color, h * 0.6));
		t.x = 8;
		t.y = 3;
		group.add(t);
		return group;
	}

	/** Shortens a string to `max` characters with an ellipsis. */
	public static function ellipsis(s:String, max:Int):String {
		if (s == null) return "";
		return s.length <= max ? s : s.substr(0, max - 1) + "…";
	}

	/** Bitmap from downloaded bytes, or null if the format is not one the engine reads. */
	public static function bitmapFromBytes(bytes:haxe.io.Bytes):Null<BitmapData> {
		try {
			var bmp = BitmapData.fromBytes(openfl.utils.ByteArray.fromBytes(bytes));
			return bmp;
		} catch (e:Dynamic) {
			return null;
		}
	}

	/** Scales a sprite to fit inside w×h, keeping its shape. */
	public static function fit(spr:FlxSprite, w:Float, h:Float) {
		if (spr.frameWidth <= 0 || spr.frameHeight <= 0) return;
		var s = Math.min(w / spr.frameWidth, h / spr.frameHeight);
		spr.scale.set(s, s);
		spr.updateHitbox();
	}
}
