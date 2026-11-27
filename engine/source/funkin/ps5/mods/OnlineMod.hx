package funkin.ps5.mods;

/** Where an online mod comes from. */
enum abstract ModSource(String) from String to String {
	var GAMEBANANA = "gamebanana";
	var GAMEJOLT = "gamejolt";
	var LOCAL = "local";
}

/**
 * Which engine a mod was made for. Only Codename Engine mods are installed for now;
 * Psych Engine and V-Slice ones are recognised so the player can be told why not.
 */
enum abstract ModEngine(String) from String to String {
	var CODENAME = "codename";
	var PSYCH = "psych";
	var VSLICE = "vslice";
	/** A whole game (an .exe build of some engine); its assets are imported where possible. */
	var EXECUTABLE = "executable";
	var UNKNOWN = "unknown";

	public function label():String {
		return switch ((cast this : ModEngine)) {
			case CODENAME: "Codename Engine";
			case PSYCH: "Psych Engine";
			case VSLICE: "V-Slice (base game)";
			case EXECUTABLE: "Full game build";
			default: "Unknown engine";
		}
	}

	/** Whether this version of the port installs and runs mods made for this engine. */
	public function supported():Bool {
		return (cast this : ModEngine) == CODENAME;
	}

	public function color():Int {
		return switch ((cast this : ModEngine)) {
			case CODENAME: 0xFF9B4DFF;
			case PSYCH: 0xFF3FA9F5;
			case VSLICE: 0xFFFF6FA0;
			case EXECUTABLE: 0xFFFFB020;
			default: 0xFF8A8A8A;
		}
	}
}

/** One entry in a list of online mods. */
typedef OnlineMod = {
	var source:ModSource;
	var id:String;
	var name:String;
	var author:String;
	/** Small picture for the grid. */
	var ?thumbnail:String;
	/** Bigger pictures for the details page. */
	var ?images:Array<String>;
	var ?category:String;
	var ?engineHint:ModEngine;
	var ?likes:Int;
	var ?views:Int;
	var ?downloads:Int;
	var ?updated:Float;
	var ?version:String;
	var ?profileUrl:String;
	/** GameBanana flags mods with content ratings; they are hidden unless the player asks. */
	var ?rated:Bool;
}

/** A file that can be downloaded for a mod. */
typedef OnlineModFile = {
	var id:String;
	var name:String;
	var size:Float;
	var ?url:String;
	var ?description:String;
	var ?downloads:Int;
	var ?date:Float;
	var ?md5:String;
	/** Game Jolt: Windows, Linux, HTML and so on. */
	var ?platform:String;
	/** Game Jolt needs one more request to turn a build into a download address. */
	var ?needsResolve:Bool;
}

/** What the details page shows. */
typedef OnlineModDetails = {
	var mod:OnlineMod;
	var description:String;
	var files:Array<OnlineModFile>;
	var ?credits:Array<String>;
}

/** A page of results. */
typedef OnlineModPage = {
	var mods:Array<OnlineMod>;
	var page:Int;
	var hasMore:Bool;
	var ?total:Int;
}

/** A tab of the browser: a feed, a category or a search. */
typedef BrowserFeed = {
	var name:String;
	var source:ModSource;
	/** gamebanana: "subfeed", "category:<id>", "search" ; gamejolt: "section:<name>", "search" */
	var kind:String;
	var ?sort:String;
}

class ModText {
	/** Turns GameBanana's HTML descriptions into plain text for a FlxText. */
	public static function htmlToText(html:String):String {
		if (html == null) return "";
		var s = html;
		s = ~/<br\s*\/?>/gi.replace(s, "\n");
		s = ~/<\/(p|div|li|h[1-6]|tr)>/gi.replace(s, "\n");
		s = ~/<li[^>]*>/gi.replace(s, "• ");
		s = ~/<img[^>]*>/gi.replace(s, "[picture]");
		s = ~/<[^>]+>/g.replace(s, "");
		s = s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
			.replace("&quot;", '"').replace("&#39;", "'").replace("&#039;", "'").replace("&rsquo;", "'")
			.replace("&ldquo;", '"').replace("&rdquo;", '"').replace("&hellip;", "...").replace("&mdash;", "-");
		s = ~/&#(\d+);/g.map(s, r -> {
			var code = Std.parseInt(r.matched(1));
			return code != null && code < 0x110000 ? String.fromCharCode(code) : "";
		});
		s = ~/[ \t]+/g.replace(s, " ");
		s = ~/\n\s*\n\s*\n+/g.replace(s, "\n\n");
		return StringTools.trim(s);
	}

	/** Guesses the engine from a category or title, before anything is downloaded. */
	public static function guessEngine(text:String):ModEngine {
		if (text == null) return UNKNOWN;
		var t = text.toLowerCase();
		if (t.indexOf("codename") >= 0 || t.indexOf("cne") >= 0) return CODENAME;
		if (t.indexOf("psych") >= 0) return PSYCH;
		if (t.indexOf("v-slice") >= 0 || t.indexOf("vslice") >= 0 || t.indexOf("v slice") >= 0 || t.indexOf("polymod") >= 0
			|| t.indexOf("base game") >= 0)
			return VSLICE;
		if (t.indexOf("executable") >= 0) return EXECUTABLE;
		return UNKNOWN;
	}
}
