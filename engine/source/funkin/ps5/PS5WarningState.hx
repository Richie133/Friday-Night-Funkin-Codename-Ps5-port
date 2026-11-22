package funkin.ps5;

import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.ps5.ui.PS5UI;

/**
 * Shown once every time the game starts, before anything else: this is an unofficial,
 * AI-made port, and the people who made the game and the engine are supported on PC.
 */
class PS5WarningState extends MusicBeatState {
	public static var shownThisSession:Bool = false;

	var next:Class<flixel.FlxState>;
	var wait:Float;
	var timer:Float = 0;
	var prompt:flixel.group.FlxSpriteGroup;
	var leaving:Bool = false;

	public function new(next:Class<flixel.FlxState>) {
		super(false);
		this.next = next;
		// the first time it is read properly; afterwards it can be skipped sooner
		wait = Options.ps5WarningSeen ? 1.0 : 4.0;
	}

	override function create() {
		super.create();
		shownThisSession = true;
		FlxG.camera.bgColor = 0xFF0B0712;

		var glow = new FlxSprite().makeSolid(FlxG.width, FlxG.height, 0xFF0B0712);
		add(glow);
		add(PS5UI.panel(90, 60, FlxG.width - 180, FlxG.height - 160, PS5UI.PANEL_LIGHT, 28, 0xFFFF5D7A));

		var title = new FunkinText(0, 90, FlxG.width, "UNOFFICIAL  AI-MADE  PS5 PORT", 40);
		title.alignment = CENTER;
		title.color = 0xFFFF8FA3;
		add(title);

		var body = new FunkinText(140, 160, FlxG.width - 280, "", 22);
		body.alignment = CENTER;
		body.text = "This is an unofficial port of Codename Engine to jailbroken PS5 consoles, "
			+ "made with the help of AI. It is *not* made, checked or supported by the Codename Engine team, "
			+ "the Funkin' Crew or Sony, and some things may not work.\n\n"
			+ "Please don't send bugs from this port to Codename Engine's developers: report them on the port's GitHub page instead.\n\n"
			+ "If you enjoy it, support the people who made the game and the engine by playing them on PC, "
			+ "where both are free:\n"
			+ "#codename-engine.com#   ·   #ninja-muffin24.itch.io/funkin#";
		body.applyMarkup(body.text, [
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFFF6677), "*"),
			new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFFFE15A), "#")
		]);
		add(body);

		var version = new FunkinText(0, FlxG.height - 140, FlxG.width, 'Port ${PS5.VERSION}  ·  Codename Engine ${lime.app.Application.current.meta.get("version")}', 16);
		version.alignment = CENTER;
		version.color = PS5UI.TEXT_DIM;
		add(version);

		prompt = PS5UI.hints(0, FlxG.height - 78, [
			{button: CROSS, label: "I understand, continue"},
			{button: SQUARE, label: "Open codename-engine.com"}
		], 32);
		prompt.x = (FlxG.width - prompt.width) / 2;
		prompt.alpha = 0;
		add(prompt);
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		timer += elapsed;
		if (timer >= wait && prompt.alpha == 0) FlxTween.tween(prompt, {alpha: 1}, 0.3);
		if (leaving || timer < wait) return;

		if (PS5Input.justPressed(SQUARE)) PS5.openURL(PS5.CODENAME_URL);
		if (PS5Input.justPressed(CROSS) || controls.ACCEPT || FlxG.mouse.justPressed) {
			leaving = true;
			Options.ps5WarningSeen = true;
			Options.save();
			CoolUtil.playMenuSFX(CONFIRM);
			FlxG.camera.fade(FlxColor.BLACK, 0.5, false, () -> {
				MusicBeatState.skipTransIn = MusicBeatState.skipTransOut = true;
				FlxG.switchState(cast Type.createInstance(next, []));
			});
		}
	}
}
