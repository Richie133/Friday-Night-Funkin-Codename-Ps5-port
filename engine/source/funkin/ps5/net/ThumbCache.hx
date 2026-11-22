package funkin.ps5.net;

import flixel.graphics.FlxGraphic;
import funkin.ps5.PS5;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import openfl.display.BitmapData;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Pictures of online mods: kept in memory while the browser is open and on disk
 * (cache/) between visits, so scrolling back does not download them again.
 */
class ThumbCache {
	static var memory:Map<String, FlxGraphic> = [];
	static var waiting:Map<String, Array<FlxGraphic->Void>> = [];
	static var failed:Map<String, Bool> = [];
	static inline var MAX_DISK_FILES:Int = 600;

	public static function get(url:String, onReady:FlxGraphic->Void) {
		if (url == null || url == "" || failed.exists(url)) return;
		var g = memory.get(url);
		if (g != null && g.bitmap != null) {
			onReady(g);
			return;
		}
		var list = waiting.get(url);
		if (list != null) {
			list.push(onReady);
			return;
		}
		waiting.set(url, [onReady]);
		var diskPath = PS5.cachePath + Md5.encode(url) + ".img";
		#if sys
		if (FileSystem.exists(diskPath)) {
			Net.runAsync(() -> {
				var bytes = try File.getBytes(diskPath) catch (e:Dynamic) null;
				Net.onMain(() -> if (bytes != null) decode(url, bytes) else fetch(url, diskPath));
			});
			return;
		}
		#end
		fetch(url, diskPath);
	}

	static function fetch(url:String, diskPath:String) {
		Net.getBytes(url, bytes -> {
			#if sys
			Net.runAsync(() -> try File.saveBytes(diskPath, bytes) catch (e:Dynamic) {});
			#end
			decode(url, bytes);
		}, err -> {
			failed.set(url, true);
			waiting.remove(url);
		});
	}

	static function decode(url:String, bytes:Bytes) {
		var bmp:BitmapData = funkin.ps5.ui.PS5UI.bitmapFromBytes(bytes);
		var callbacks = waiting.get(url);
		waiting.remove(url);
		if (bmp == null) {
			failed.set(url, true);
			return;
		}
		var g = FlxGraphic.fromBitmapData(bmp, false, "ps5thumb:" + url);
		g.persist = true;
		g.destroyOnNoUse = false;
		memory.set(url, g);
		if (callbacks != null) for (cb in callbacks) cb(g);
	}

	/** Frees the pictures when the browser closes. */
	public static function clearMemory() {
		for (url => g in memory) {
			g.persist = false;
			g.destroyOnNoUse = true;
			FlxG.bitmap.remove(g);
		}
		memory = [];
		waiting = [];
		trimDisk();
	}

	static function trimDisk() {
		#if sys
		Net.runAsync(() -> {
			try {
				var files = FileSystem.readDirectory(PS5.cachePath);
				if (files.length <= MAX_DISK_FILES) return;
				var stats = [for (f in files) {name: f, time: FileSystem.stat(PS5.cachePath + f).mtime.getTime()}];
				stats.sort((a, b) -> a.time < b.time ? -1 : 1);
				for (i in 0...stats.length - MAX_DISK_FILES) FileSystem.deleteFile(PS5.cachePath + stats[i].name);
			} catch (e:Dynamic) {}
		});
		#end
	}
}
