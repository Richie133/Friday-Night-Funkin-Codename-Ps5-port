package funkin.ps5.mods;

import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.backend.assets.ModsFolder;
import funkin.ps5.PS5;
import funkin.ps5.PS5Input;
import funkin.ps5.mods.InstalledMods;
import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.ThumbCache;
import funkin.ps5.ui.PS5UI;
import haxe.io.Path;

/**
 * The installed mods: pick one to play, see what it is and where it came from,
 * delete it, or go and get more. The base game is the first entry.
 */
class ModMenuState extends MusicBeatState {
	var mods:Array<Null<InstalledMod>> = [];
	var selected:Int = 0;
	var repeat = new RepeatState();
	var listCam:FlxCamera;
	var rows:FlxSpriteGroup;
	var detail:FlxSpriteGroup;
	var scroll:Float = 0;
	var confirmDelete:Bool = false;
	var toast:FunkinText;
	var toastTime:Float = 0;

	static inline var ROW_H:Int = 74;

	public function new() {
		super(false);
	}

	override function create() {
		super.create();
		CoolUtil.playMenuSong();

		var bg = new FlxSprite().loadAnimatedGraphic(Paths.image('menus/menuDesat'));
		bg.color = 0xFF2A3A66;
		bg.setGraphicSize(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.antialiasing = true;
		add(bg);
		add(new FlxSprite().makeSolid(FlxG.width, FlxG.height, 0x77000000));

		add(PS5UI.panel(20, 14, FlxG.width - 40, 70, PS5UI.PANEL, 22));
		var title = new FunkinText(PS5UI.headerX(), 30, 0, "MODS", 34);
		add(title);
		var count = new FunkinText(title.x + title.width + 20, 40, 0, "", 18);
		count.color = PS5UI.TEXT_DIM;
		add(count);

		add(PS5UI.panel(20, 96, 520, FlxG.height - 160, PS5UI.PANEL, 20));
		listCam = new FlxCamera(30, 106, 500, FlxG.height - 180);
		listCam.bgColor = 0;
		FlxG.cameras.add(listCam, false);
		rows = new FlxSpriteGroup();
		rows.cameras = [listCam];
		add(rows);

		add(PS5UI.panel(556, 96, FlxG.width - 576, FlxG.height - 160, PS5UI.PANEL, 20));
		detail = new FlxSpriteGroup();
		add(detail);

		add(PS5UI.hints(40, FlxG.height - 44, [
			{button: CROSS, label: "Play"},
			{button: TRIANGLE, label: "Get mods online"},
			{button: SQUARE, label: "Delete"},
			{button: L1, label: "Addons"},
			{button: CIRCLE, label: "Back"}
		], 28));

		toast = new FunkinText(0, FlxG.height - 110, FlxG.width, "", 22);
		toast.alignment = CENTER;
		add(toast);

		reloadList();
		count.text = '${mods.length - 1} installed  ·  ${ModsFolder.modsPath}';
	}

	function reloadList() {
		mods = [null];
		for (m in InstalledMods.list()) mods.push(m);
		var current = ModsFolder.currentModFolder;
		for (i => m in mods) if ((m == null && current == null) || (m != null && m.folder == current)) selected = i;
		buildRows();
		showDetail();
	}

	function buildRows() {
		for (r in rows.members) if (r != null) r.destroy();
		rows.clear();
		for (i => m in mods) {
			var y = i * ROW_H;
			var sel = i == selected;
			rows.add(PS5UI.panel(0, y, 500, ROW_H - 8, sel ? 0xFF3A2F55 : 0xFF1E1730, 14, sel ? 0xFFFFE15A : null));
			var name = new FunkinText(70, y + 8, 410, m == null ? "Base game (no mod)" : PS5UI.ellipsis(m.name, 30), 20);
			rows.add(name);
			var sub = m == null ? "Friday Night Funkin' with Codename Engine" : m.engine.label() + (m.songs != null ? '  ·  ${m.songs} songs' : "");
			var subText = new FunkinText(70, y + 36, 410, sub, 14);
			subText.color = m == null ? PS5UI.TEXT_DIM : m.engine.color();
			rows.add(subText);
			var iconSpr = new FlxSprite(10, y + 7).makeSolid(52, 52, m == null ? 0xFF9B4DFF : m.engine.color());
			iconSpr.alpha = 0.6;
			rows.add(iconSpr);
			if (m != null && m.icon != null) loadIcon(iconSpr, m.icon, 52);
			if ((m == null && ModsFolder.currentModFolder == null) || (m != null && m.folder == ModsFolder.currentModFolder)) {
				var on = PS5UI.badge("Playing", 0xFF2FA866, 12);
				on.setPosition(500 - on.width - 12, y + 10);
				rows.add(on);
			}
		}
	}

	function loadIcon(spr:FlxSprite, path:String, size:Int) {
		#if sys
		try {
			var bmp = openfl.display.BitmapData.fromFile(path);
			if (bmp == null) return;
			spr.loadGraphic(bmp);
			spr.alpha = 1;
			var s = Math.min(size / spr.frameWidth, size / spr.frameHeight);
			spr.scale.set(s, s);
			spr.updateHitbox();
			spr.antialiasing = true;
		} catch (e:Dynamic) {}
		#end
	}

	function showDetail() {
		for (d in detail.members) if (d != null) d.destroy();
		detail.clear();
		var m = mods[selected];
		var x = 580.0, y = 116.0, w = FlxG.width - 620;
		var big = new FlxSprite(x, y).makeSolid(150, 150, m == null ? 0xFF9B4DFF : m.engine.color());
		big.alpha = 0.5;
		detail.add(big);
		if (m != null && m.icon != null) loadIcon(big, m.icon, 150);
		else if (m != null && m.thumbnailUrl != null) ThumbCache.get(m.thumbnailUrl, g -> {
			if (!big.exists) return;
			big.loadGraphic(g);
			big.alpha = 1;
			var s = Math.min(260 / big.frameWidth, 150 / big.frameHeight);
			big.scale.set(s, s);
			big.updateHitbox();
		});
		var name = new FunkinText(x + 290, y, w - 290, m == null ? "Base game" : m.name, 28);
		detail.add(name);
		var lines = [];
		if (m == null) {
			lines.push("Codename Engine's own songs and weeks, with no mod loaded.");
		} else {
			lines.push(m.engine.label() + (m.engine == PSYCH ? " (converted; Lua scripts run through the Psych layer)" : (m.engine == VSLICE ? " (converted; Polymod scripts don't run)" : "")));
			if (m.author != null) lines.push('by ${m.author}');
			if (m.source != null && m.source != LOCAL) lines.push('From ${m.source == GAMEBANANA ? "GameBanana" : "Game Jolt"}' + (m.version != null && m.version != "" ? ', version ${m.version}' : ""));
			else lines.push("Copied in by hand");
			if (m.installed != null) lines.push("Installed " + DateTools.format(Date.fromTime(m.installed), "%Y-%m-%d"));
			if (m.songs != null) lines.push('${m.songs} songs');
			lines.push('Folder: mods/${m.folder}${m.isZip ? " (compressed)" : ""}');
		}
		var info = new FunkinText(x + 290, name.y + name.height + 10, w - 290, lines.join("\n"), 16);
		info.color = PS5UI.TEXT_DIM;
		detail.add(info);
		var desc = new FunkinText(x, y + 180, w, m == null ? "" : (m.description == "" ? "(no description)" : m.description), 18);
		detail.add(desc);
		if (confirmDelete && m != null) {
			var warn = PS5UI.panel(x - 10, FlxG.height - 230, w + 20, 100, 0xF0401424, 16, 0xFFFF5566);
			detail.add(warn);
			var t = new FunkinText(x + 10, FlxG.height - 215, w - 20, 'Delete "${m.name}"? This removes mods/${m.folder} for good.\nPress SQUARE again to delete, or CIRCLE to keep it.', 18);
			detail.add(t);
		}
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		listCam.scroll.y = CoolUtil.fpsLerp(listCam.scroll.y, scroll, 0.3);
		if (toastTime > 0) {
			toastTime -= elapsed;
			toast.alpha = Math.min(1, toastTime * 2);
		}

		var nav = PS5Input.navigation(repeat, elapsed);
		var move = nav.y - FlxG.mouse.wheel;
		if (move != 0) {
			selected = FlxMath.wrap(selected + move, 0, mods.length - 1);
			confirmDelete = false;
			CoolUtil.playMenuSFX(SCROLL, 0.6);
			var top = selected * ROW_H;
			if (top < scroll) scroll = top;
			if (top + ROW_H > scroll + listCam.height) scroll = top + ROW_H - listCam.height;
			buildRows();
			showDetail();
		}
		if (FlxG.mouse.justPressed) {
			var mp = FlxG.mouse.getViewPosition(listCam);
			if (mp.x >= 0 && mp.x <= 500 && mp.y >= 0 && mp.y <= listCam.height) {
				var i = Std.int((mp.y + listCam.scroll.y) / ROW_H);
				if (i >= 0 && i < mods.length) {
					if (i == selected) play();
					else {
						selected = i;
						buildRows();
						showDetail();
					}
				}
			}
			mp.put();
		}

		if (PS5Input.justPressed(CIRCLE)) {
			if (confirmDelete) {
				confirmDelete = false;
				showDetail();
			} else {
				CoolUtil.playMenuSFX(CANCEL);
				FlxG.switchState(new funkin.menus.MainMenuState());
			}
			return;
		}
		if (PS5Input.justPressed(CROSS)) play();
		if (PS5Input.justPressed(TRIANGLE)) {
			CoolUtil.playMenuSFX(CONFIRM);
			FlxG.switchState(new ModBrowserState());
		}
		if (PS5Input.justPressed(L1)) {
			persistentUpdate = false;
			persistentDraw = true;
			openSubState(new funkin.menus.ModSwitchMenu());
		}
		if (PS5Input.justPressed(SQUARE) && mods[selected] != null) {
			if (!confirmDelete) {
				confirmDelete = true;
				CoolUtil.playMenuSFX(WARNING);
				showDetail();
			} else {
				var m = mods[selected];
				InstalledMods.delete(m);
				confirmDelete = false;
				showToast('Deleted "${m.name}"');
				var wasCurrent = ModsFolder.currentModFolder == m.folder;
				if (wasCurrent) {
					ModsFolder.switchMod(null);
					return;
				}
				selected = Std.int(Math.min(selected, mods.length - 2));
				reloadList();
			}
		}
	}

	function play() {
		var m = mods[selected];
		CoolUtil.playMenuSFX(CONFIRM);
		ModsFolder.switchMod(m == null ? null : m.folder);
	}

	function showToast(text:String) {
		toast.text = text;
		toastTime = 2.5;
	}

	override function destroy() {
		if (FlxG.cameras.list.contains(listCam)) FlxG.cameras.remove(listCam);
		super.destroy();
	}
}
