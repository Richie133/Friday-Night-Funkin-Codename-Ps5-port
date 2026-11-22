package funkin.ps5.mods;

import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.ps5.PS5;
import funkin.ps5.PS5Input;
import funkin.ps5.mods.ModDownloads;
import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.ThumbCache;
import funkin.ps5.ui.PS5UI;

/**
 * One online mod: its pictures, description and files. ✕ downloads the selected file,
 * which is unpacked and installed into mods/ (converted first if it is a Psych or V-Slice mod).
 */
class ModDetailsSubstate extends MusicBeatSubstate {
	var mod:OnlineMod;
	var details:OnlineModDetails;
	var cam:FlxCamera;

	var picture:FlxSprite;
	var pictureIndex:Int = 0;
	var title:FunkinText;
	var info:FunkinText;
	var description:FunkinText;
	var descScroll:Float = 0;
	var descCam:FlxCamera;
	var filesGroup:FlxSpriteGroup;
	var status:FunkinText;
	var selectedFile:Int = 0;
	var repeat = new RepeatState();
	var job:ModJob;

	static inline var PANEL_X:Int = 40;
	static inline var PANEL_Y:Int = 30;

	public function new(mod:OnlineMod) {
		super();
		this.mod = mod;
	}

	override function create() {
		super.create();
		cam = new FlxCamera();
		cam.bgColor = 0;
		FlxG.cameras.add(cam, false);
		cameras = [cam];

		add(new FlxSprite().makeSolid(FlxG.width, FlxG.height, 0xD0000000));
		// covers the browser's own hint bar, so only this screen's hints show
		add(new FlxSprite(0, FlxG.height - 56).makeSolid(FlxG.width, 56, 0xFF0B0712));
		add(PS5UI.panel(PANEL_X, PANEL_Y, FlxG.width - PANEL_X * 2, FlxG.height - PANEL_Y * 2 - 50, PS5UI.PANEL_LIGHT, 24, 0xFF5B4A80));

		picture = new FlxSprite(PANEL_X + 24, PANEL_Y + 24).makeSolid(530, 298, 0xFF1C1529);
		add(picture);
		if (mod.thumbnail != null) showPicture(mod.thumbnail);

		title = new FunkinText(PANEL_X + 574, PANEL_Y + 24, 620, mod.name, 30);
		add(title);
		info = new FunkinText(PANEL_X + 574, title.y + title.height + 8, 620, infoLine(), 18);
		info.color = PS5UI.TEXT_DIM;
		add(info);

		var engine = mod.engineHint != null ? mod.engineHint : UNKNOWN;
		var badge = PS5UI.badge(engine == UNKNOWN ? "Engine detected on install" : engine.label(), engine.color(), 16);
		badge.setPosition(PANEL_X + 574, info.y + info.height + 10);
		add(badge);

		filesGroup = new FlxSpriteGroup();
		add(filesGroup);

		// the description scrolls in its own camera, below the picture
		descCam = new FlxCamera(PANEL_X + 24, PANEL_Y + 340, 530, FlxG.height - PANEL_Y * 2 - 50 - 364);
		descCam.bgColor = 0;
		FlxG.cameras.add(descCam, false);
		description = new FunkinText(0, 0, 520, "Loading...", 16);
		description.cameras = [descCam];
		add(description);

		status = new FunkinText(PANEL_X + 574, FlxG.height - PANEL_Y - 50 - 70, 620, "", 18);
		add(status);

		add(PS5UI.hints(PANEL_X, FlxG.height - 44, [
			{button: CROSS, label: "Download"},
			{button: SQUARE, label: "Open page"},
			{button: L2, label: "Picture"},
			{button: DPAD, label: "File"},
			{button: CIRCLE, label: "Back"}
		], 28));

		var load = mod.source == GAMEJOLT ? GameJolt.details : GameBanana.details;
		load(mod, d -> {
			if (!exists) return;
			details = d;
			mod = d.mod;
			title.text = mod.name;
			info.text = infoLine();
			var text = d.description == "" ? "(no description)" : d.description;
			if (d.credits != null && d.credits.length > 0) text += "\n\nCredits:\n" + d.credits.join("\n");
			description.text = text;
			buildFiles();
			if (mod.images != null && mod.images.length > 0) showPicture(mod.images[0]);
		}, err -> {
			if (!exists) return;
			description.text = 'Could not load this mod.\n$err';
		});
	}

	function infoLine():String {
		var parts = ['by ${mod.author}'];
		if (mod.category != null) parts.push(mod.category);
		if (mod.likes != null) parts.push('${mod.likes} likes');
		if (mod.views != null) parts.push('${mod.views} views');
		if (mod.version != null && mod.version != "") parts.push('v${mod.version}');
		if (mod.updated != null && mod.updated > 0) parts.push("updated " + DateTools.format(Date.fromTime(mod.updated * 1000), "%Y-%m-%d"));
		var installed = InstalledMods.findBySource(mod.source, mod.id);
		if (installed != null) parts.push('installed as "${installed.folder}"');
		return parts.join("  ·  ");
	}

	function showPicture(url:String) {
		ThumbCache.get(url, g -> {
			if (picture == null || !exists) return;
			picture.loadGraphic(g);
			picture.antialiasing = true;
			var s = Math.min(530 / picture.frameWidth, 298 / picture.frameHeight);
			picture.scale.set(s, s);
			picture.updateHitbox();
			picture.setPosition(PANEL_X + 24 + (530 - picture.width) / 2, PANEL_Y + 24 + (298 - picture.height) / 2);
		});
	}

	function buildFiles() {
		filesGroup.clear();
		var y = badgeBottom() + 24;
		var header = new FunkinText(PANEL_X + 574, y, 620, details.files.length == 0 ? "This mod has no files to download." : "Files", 22);
		filesGroup.add(header);
		y += 36;
		for (i => f in details.files) {
			if (i >= 6) {
				filesGroup.add(new FunkinText(PANEL_X + 574, y, 620, '... and ${details.files.length - 6} more', 16));
				break;
			}
			var sel = i == selectedFile;
			filesGroup.add(PS5UI.panel(PANEL_X + 570, y, 640, 58, sel ? 0xFF3A2F55 : 0xFF221A33, 12, sel ? 0xFFFFE15A : null));
			var name = new FunkinText(PANEL_X + 586, y + 6, 420, PS5UI.ellipsis(f.name, 38), 18);
			filesGroup.add(name);
			var extra = [];
			if (f.size > 0) extra.push(PS5.formatBytes(f.size));
			if (f.platform != null) extra.push(f.platform);
			if (f.downloads != null) extra.push('${f.downloads} downloads');
			if (f.description != null && f.description != "") extra.push(PS5UI.ellipsis(f.description, 40));
			var sub = new FunkinText(PANEL_X + 586, y + 32, 600, extra.join("  ·  "), 14);
			sub.color = PS5UI.TEXT_DIM;
			filesGroup.add(sub);
			if (!Archive.isArchive(f.name)) {
				var warn = new FunkinText(PANEL_X + 1010, y + 8, 190, "not an archive", 14);
				warn.color = 0xFFFFAA55;
				filesGroup.add(warn);
			}
			y += 66;
		}
	}

	function badgeBottom():Float return info.y + info.height + 44;

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (job != null) {
			status.text = job.message;
			status.color = job.state == FAILED ? 0xFFFF7777 : (job.state == DONE ? 0xFF77FF99 : FlxColor.WHITE);
		}

		if (PS5Input.justPressed(CIRCLE)) {
			CoolUtil.playMenuSFX(CANCEL);
			close();
			return;
		}
		if (details == null) return;

		var nav = PS5Input.navigation(repeat, elapsed);
		if (nav.y != 0 && details.files.length > 0) {
			selectedFile = FlxMath.wrap(selectedFile + nav.y, 0, Std.int(Math.min(details.files.length, 6)) - 1);
			CoolUtil.playMenuSFX(SCROLL, 0.5);
			buildFiles();
		}
		// right stick, R2 or the mouse wheel scroll the description
		var scroll = 0.0;
		var pad = FlxG.gamepads.lastActive;
		if (pad != null) scroll += pad.analog.value.RIGHT_STICK_Y * 600 * elapsed;
		if (FlxG.gamepads.anyPressed(RIGHT_TRIGGER_BUTTON) || FlxG.keys.pressed.PAGEDOWN) scroll += 500 * elapsed;
		scroll -= FlxG.mouse.wheel * 60;
		if (scroll != 0) {
			descScroll = FlxMath.bound(descScroll + scroll, 0, Math.max(0, description.height - descCam.height + 20));
			descCam.scroll.y = descScroll;
		}
		if (PS5Input.justPressed(L2) && mod.images != null && mod.images.length > 1) {
			pictureIndex = (pictureIndex + 1) % mod.images.length;
			showPicture(mod.images[pictureIndex]);
		}
		if (PS5Input.justPressed(SQUARE) && mod.profileUrl != null) PS5.openURL(mod.profileUrl);
		if (PS5Input.justPressed(CROSS) && details.files.length > 0) startDownload();
	}

	function startDownload() {
		var file = details.files[selectedFile];
		if (job != null && !job.finished && job.file == file) return;
		if (!Archive.isArchive(file.name) && mod.source == GAMEBANANA) {
			status.text = '"${file.name}" is not a .zip, .7z or .rar, so it can\'t be installed.';
			status.color = 0xFFFFAA55;
			CoolUtil.playMenuSFX(WARNING);
			return;
		}
		CoolUtil.playMenuSFX(CONFIRM);
		job = ModDownloads.enqueue(mod, file);
		status.text = "Added to the downloads (OPTIONS in the browser shows them).";
	}

	override function destroy() {
		for (c in [cam, descCam]) if (c != null && FlxG.cameras.list.contains(c)) FlxG.cameras.remove(c);
		super.destroy();
	}
}
