package funkin.ps5.net;

import haxe.io.Bytes;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Offline answers for the PC test build (`--fixtures <folder>` on the command line,
 * or the CNE_PS5_FIXTURES environment variable). A request is answered from the first
 * file in `index.txt` whose pattern the address contains, so the mod browser can be
 * tried, and screenshotted, without reaching GameBanana or Game Jolt.
 *
 * index.txt: one `pattern<TAB>file` per line, the first match wins.
 */
class Fixtures {
	static var rules:Array<{pattern:String, file:String}> = null;

	public static function answer(url:String, ?postBody:String):Bytes {
		#if sys
		if (rules == null) load();
		for (rule in rules) {
			if (url.indexOf(rule.pattern) < 0) continue;
			var path = Net.fixtures + "/" + rule.file;
			if (!FileSystem.exists(path)) throw 'Fixture missing: ${rule.file}';
			Sys.sleep(0.05); // a little latency, so loading states are visible
			return File.getBytes(path);
		}
		#end
		throw 'HTTP 404 (no fixture) for $url';
	}

	static function load() {
		rules = [];
		#if sys
		var index = Net.fixtures + "/index.txt";
		if (!FileSystem.exists(index)) return;
		for (line in File.getContent(index).split("\n")) {
			line = StringTools.trim(line);
			if (line == "" || line.startsWith("#")) continue;
			var tab = line.indexOf("\t");
			if (tab < 0) continue;
			rules.push({pattern: line.substr(0, tab), file: StringTools.trim(line.substr(tab + 1))});
		}
		#end
	}
}
