package funkin.ps5;

/**
 * The few console functions the Haxe side calls directly. They live in the PS5 platform
 * layer (ps5/native/codename_ps5.c), linked into the same eboot.bin. On a PC build
 * every call does nothing.
 */
#if ps5
@:cppFileCode('
extern "C" {
	int cne_ps5_open_browser(const char *url);
	void cne_ps5_set_touchpad_mouse(int enabled, double speed);
	int cne_ps5_display_width(void);
	int cne_ps5_display_height(void);
	int cne_ps5_display_refresh(void);
	void cne_ps5_notify(const char *text);
	double cne_ps5_free_space(const char *path);
}
')
#end
class PS5Native {
	public static function openBrowser(url:String):Bool {
		#if ps5
		return untyped __cpp__("cne_ps5_open_browser({0}.utf8_str()) == 0", url);
		#else
		return false;
		#end
	}

	/** The touchpad drives the pointer like a laptop trackpad; `speed` scales its movement. */
	public static function setTouchpadMouse(enabled:Bool, speed:Float) {
		#if ps5
		untyped __cpp__("cne_ps5_set_touchpad_mouse({0} ? 1 : 0, {1})", enabled, speed);
		#end
	}

	/** The video mode the game started in (it changes on the next start). */
	public static function displayMode():{width:Int, height:Int, refresh:Int} {
		#if ps5
		return {
			width: untyped __cpp__("cne_ps5_display_width()"),
			height: untyped __cpp__("cne_ps5_display_height()"),
			refresh: untyped __cpp__("cne_ps5_display_refresh()")
		};
		#else
		var w = lime.app.Application.current.window;
		return {width: w.width, height: w.height, refresh: w.displayMode != null ? w.displayMode.refreshRate : 60};
		#end
	}

	/** A system notification (the pop-up in the top right of the TV). */
	public static function notify(text:String) {
		#if ps5
		untyped __cpp__("cne_ps5_notify({0}.utf8_str())", text);
		#else
		Logs.trace('[notify] $text');
		#end
	}

	/** Free space on the drive holding `path`, in bytes, or -1 when unknown. */
	public static function freeSpace(path:String):Float {
		#if ps5
		return untyped __cpp__("cne_ps5_free_space({0}.utf8_str())", path);
		#else
		return -1;
		#end
	}
}
