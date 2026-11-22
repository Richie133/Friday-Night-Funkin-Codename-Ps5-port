package funkin.ps5.options;

import funkin.options.TreeMenuScreen;
import funkin.options.type.*;
import funkin.ps5.PS5;
import funkin.ps5.PS5Native;
#if sys
import sys.io.File;
#end

/**
 * Options → PS5: the console's picture, the controller and touchpad, mods, and the
 * port itself. Picture settings are written to display.cfg, which the platform layer
 * reads before it opens the screen, so they apply the next time the game starts.
 */
class PS5Options extends TreeMenuScreen {
	public function new() {
		super('optionsTree.ps5-name', 'optionsTree.ps5-desc', 'PS5Options.');

		add(new TextOption(getNameID('graphics'), getDescID('graphics'), ' >', () -> parent.addMenu(new PS5GraphicsOptions())));
		add(new TextOption(getNameID('controller'), getDescID('controller'), ' >', () -> parent.addMenu(new PS5ControllerOptions())));
		add(new TextOption(getNameID('mods'), getDescID('mods'), ' >', () -> parent.addMenu(new PS5ModOptions())));
		add(new Separator());
		add(new TextOption(getNameID('warning'), getDescID('warning'), ' >', () -> FlxG.switchState(new PS5WarningState(funkin.options.OptionsMenu))));
		add(new TextOption(getNameID('support'), getDescID('support'), ' >', () -> PS5.openURL(PS5.CODENAME_URL)));
		add(new TextOption(getNameID('source'), getDescID('source'), ' >', () -> PS5.openURL(PS5.REPO_URL)));
	}

	/** Writes the picture settings for the platform layer. */
	public static function saveDisplayConfig() {
		#if sys
		var sizes = [[1920, 1080], [2560, 1440], [3840, 2160]];
		var size = sizes[Std.int(Math.max(0, Math.min(2, Options.ps5Resolution)))];
		var refresh = Options.ps5RefreshRate >= 120 ? 120 : 60;
		try File.saveContent(PS5.dataRoot + "display.cfg",
			'# written by Options > PS5 > Picture; read when the game starts\n'
			+ 'width=${size[0]}\nheight=${size[1]}\nrefresh=$refresh\nvsync=${Options.ps5VSync ? 1 : 0}\n') catch (e:Dynamic) {}
		#end
	}

	/** Applies what can change while the game runs. */
	public static function applyLive() {
		PS5Native.setTouchpadMouse(Options.ps5TouchpadMouse, Options.ps5TouchpadSpeed);
		#if !web
		try lime.app.Application.current.window.setVSyncMode(Options.ps5VSync ? ON : OFF) catch (e:Dynamic) {}
		#end
	}
}

class PS5GraphicsOptions extends TreeMenuScreen {
	var framerateOption:NumOption;

	public function new() {
		super('PS5Options.graphics-name', 'PS5Options.graphics-desc', 'PS5Options.Graphics.');
		var mode = PS5Native.displayMode();

		add(new ArrayOption(getNameID('resolution'), getDescID('resolution'), [0, 1, 2], ["1080p", "1440p", "4K"],
			'ps5Resolution', _ -> PS5Options.saveDisplayConfig()));
		add(new ArrayOption(getNameID('refresh'), getDescID('refresh'), [60, 120], ["60 Hz", "120 Hz"],
			'ps5RefreshRate', _ -> PS5Options.saveDisplayConfig()));
		add(new Checkbox(getNameID('vsync'), getDescID('vsync'), 'ps5VSync', () -> {
			PS5Options.saveDisplayConfig();
			PS5Options.applyLive();
		}));
		add(framerateOption = new NumOption(getNameID('framerate'), getDescID('framerate'), 30, 240, 10, 'framerate', value -> {
			var fps = Math.floor(value);
			if (FlxG.updateFramerate < fps) FlxG.drawFramerate = FlxG.updateFramerate = fps;
			else FlxG.updateFramerate = FlxG.drawFramerate = fps;
		}));
		add(new Separator());
		add(new ArrayOption('AppearanceOptions.Advanced.quality-name', 'AppearanceOptions.Advanced.quality-desc',
			[0, 1, 2], ['AppearanceOptions.Advanced.quality-low', 'AppearanceOptions.Advanced.quality-high', 'AppearanceOptions.Advanced.quality-custom'],
			'quality', _ -> Options.applyQuality()));
		add(new Checkbox('AppearanceOptions.Advanced.antialiasing-name', 'AppearanceOptions.Advanced.antialiasing-desc', 'antialiasing', () -> {
			FlxG.game.stage.quality = (FlxG.enableAntialiasing = Options.antialiasing) ? BEST : LOW;
		}));
		add(new Checkbox('AppearanceOptions.Advanced.gameplayShaders-name', 'AppearanceOptions.Advanced.gameplayShaders-desc', 'gameplayShaders'));
		add(new Checkbox('AppearanceOptions.Advanced.lowMemoryMode-name', 'AppearanceOptions.Advanced.lowMemoryMode-desc', 'lowMemoryMode'));
		add(new Checkbox('AppearanceOptions.Advanced.gpuOnlyBitmaps-name', 'AppearanceOptions.Advanced.gpuOnlyBitmaps-desc', 'gpuOnlyBitmaps'));
		add(new Checkbox('AppearanceOptions.flashingMenu-name', 'AppearanceOptions.flashingMenu-desc', 'flashingMenu'));
		add(new Checkbox('AppearanceOptions.fpsCounter-name', 'AppearanceOptions.fpsCounter-desc', 'fpsCounter', () -> {
			funkin.backend.system.framerate.Framerate.debugMode = Options.fpsCounter ? 1 : 0;
		}));
		add(new Separator());
		add(new TextOption(getNameID('current'), TU.translate(getDescID('current'), ['${mode.width}x${mode.height}', mode.refresh]), "", null));
	}
}

class PS5ControllerOptions extends TreeMenuScreen {
	public function new() {
		super('PS5Options.controller-name', 'PS5Options.controller-desc', 'PS5Options.Controller.');
		add(new Checkbox(getNameID('touchpadMouse'), getDescID('touchpadMouse'), 'ps5TouchpadMouse', () -> PS5Options.applyLive()));
		add(new NumOption(getNameID('touchpadSpeed'), getDescID('touchpadSpeed'), 0.25, 3, 0.25, 'ps5TouchpadSpeed', _ -> PS5Options.applyLive()));
		add(new Checkbox(getNameID('touchpadCharter'), getDescID('touchpadCharter'), 'ps5TouchpadCharter'));
		add(new Checkbox(getNameID('menuHints'), getDescID('menuHints'), 'ps5MenuHints'));
		add(new Separator());
		add(new TextOption(getNameID('layout'), getDescID('layout'), "", null));
		add(new TextOption('optionsTree.controls-name', 'optionsTree.controls-desc', ' >', () -> {
			parent.persistentUpdate = false;
			parent.openSubState(new funkin.options.keybinds.KeybindsOptions());
		}));
	}
}

class PS5ModOptions extends TreeMenuScreen {
	public function new() {
		super('PS5Options.mods-name', 'PS5Options.mods-desc', 'PS5Options.Mods.');
		add(new TextOption(getNameID('browser'), getDescID('browser'), ' >', () -> FlxG.switchState(new funkin.ps5.mods.ModBrowserState())));
		add(new TextOption(getNameID('installed'), getDescID('installed'), ' >', () -> FlxG.switchState(new funkin.ps5.mods.ModMenuState())));
		add(new Checkbox(getNameID('showRated'), getDescID('showRated'), 'ps5ShowRatedMods'));
		add(new TextOption(getNameID('clearCache'), getDescID('clearCache'), "", () -> {
			PS5.deleteDir(PS5.cachePath);
			PS5.deleteDir(PS5.downloadsPath);
			PS5.ensureDir(PS5.cachePath);
			PS5.ensureDir(PS5.downloadsPath);
			CoolUtil.playMenuSFX(CONFIRM);
		}));
		add(new TextOption(getNameID('folder'), TU.translate(getDescID('folder'), [funkin.backend.assets.ModsFolder.modsPath]), "", null));
	}
}
