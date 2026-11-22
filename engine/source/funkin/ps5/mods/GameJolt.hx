package funkin.ps5.mods;

import funkin.ps5.mods.GameBanana.field;
import funkin.ps5.mods.GameBanana.toFloat;
import funkin.ps5.mods.GameBanana.toInt;
import funkin.ps5.mods.GameBanana.string;
import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.Net;
import haxe.Json;

/**
 * Game Jolt's site API (the one gamejolt.com and its desktop app use), read without an account.
 *
 *  - Games with a tag:  site-api/web/discover/games?section=best&tag=fnf&page=
 *  - Search:            site-api/web/search/games?q=&page=
 *  - One game:          site-api/web/discover/games/overview/{id}
 *  - Its builds:        site-api/web/discover/games/packages/{id}  (payload.builds, payload.packages)
 *  - A download:        POST site-api/web/discover/games/builds/get-download-url/{build}  {forceDownload:true}
 *
 * FNF games on Game Jolt are mostly whole Windows builds of some engine. They can't run
 * on a PS5, but their assets/ and mods/ folders are imported (see ModInstaller).
 */
class GameJolt {
	public static inline var API:String = "https://gamejolt.com/site-api/";
	public static inline var TAG:String = "fnf";

	public static function feed(feed:BrowserFeed, page:Int, ?query:String, onDone:OnlineModPage->Void, onError:String->Void) {
		var url:String;
		if (feed.kind == "search") {
			var q = query == null || query == "" ? "fnf" : query;
			if (q.toLowerCase().indexOf("fnf") < 0 && q.toLowerCase().indexOf("funkin") < 0) q = "fnf " + q;
			url = API + 'web/search/games?q=${Net.urlEncode(q)}' + (page > 1 ? '&page=$page' : "");
		} else {
			var section = feed.kind.startsWith("section:") ? feed.kind.substr("section:".length) : "best";
			url = API + 'web/discover/games?section=$section&tag=$TAG' + (page > 1 ? '&page=$page' : "");
		}
		Net.getText(url, text -> {
			try onDone(parseList(Json.parse(text), page)) catch (e:Dynamic) onError('Game Jolt answered something unexpected ($e)');
		}, onError);
	}

	public static function parseList(data:Dynamic, page:Int):OnlineModPage {
		var payload:Dynamic = field(data, "payload");
		var games:Array<Dynamic> = field(payload, "games");
		if (games == null) games = [];
		var mods:Array<OnlineMod> = [];
		for (g in games) {
			var m = parseGame(g);
			if (m != null) mods.push(m);
		}
		var perPage = toInt(field(payload, "perPage"));
		var count = toInt(field(payload, "gamesCount"));
		if (count == null) count = toInt(field(payload, "count"));
		var hasMore = perPage != null ? mods.length >= perPage : mods.length >= 10;
		if (count != null && perPage != null) hasMore = page * perPage < count;
		return {mods: mods, page: page, hasMore: hasMore, total: count};
	}

	public static function parseGame(g:Dynamic):Null<OnlineMod> {
		var id = toInt(field(g, "id"));
		if (id == null) return null;
		var dev:Dynamic = field(g, "developer");
		var media:Dynamic = field(g, "thumbnail_media_item");
		var thumb:String = field(media, "mediaserver_url");
		if (thumb == null) thumb = field(media, "img_url");
		if (thumb == null) thumb = field(g, "img_thumbnail");
		var header:Dynamic = field(g, "header_media_item");
		var images = [];
		var headerUrl:String = field(header, "mediaserver_url");
		if (headerUrl == null) headerUrl = field(header, "img_url");
		if (headerUrl != null) images.push(headerUrl);
		if (thumb != null) images.push(thumb);
		var slug = string(field(g, "slug"), "game");
		var title = string(field(g, "title"), 'Game $id');
		return {
			source: GAMEJOLT,
			id: Std.string(id),
			name: title,
			author: string(field(dev, "display_name"), string(field(dev, "username"), "unknown")),
			thumbnail: thumb,
			images: images,
			category: "Game Jolt",
			engineHint: ModText.guessEngine(title),
			likes: toInt(field(g, "like_count")),
			views: toInt(field(g, "view_count")),
			updated: toFloat(field(g, "modified_on"), toFloat(field(g, "published_on"), 0)) / 1000,
			profileUrl: 'https://gamejolt.com/games/$slug/$id',
			rated: field(g, "tigrs_age") == 3
		};
	}

	public static function details(mod:OnlineMod, onDone:OnlineModDetails->Void, onError:String->Void) {
		var description = "";
		Net.getText(API + 'web/discover/games/overview/${mod.id}', text -> {
			try {
				var payload:Dynamic = field(Json.parse(text), "payload");
				var game:Dynamic = field(payload, "game");
				var desc:Dynamic = field(game, "description_content");
				if (desc == null) desc = field(payload, "metaDescription");
				description = contentToText(desc);
			} catch (e:Dynamic) {}
			loadBuilds(mod, description, onDone, onError);
		}, _ -> loadBuilds(mod, description, onDone, onError));
	}

	static function loadBuilds(mod:OnlineMod, description:String, onDone:OnlineModDetails->Void, onError:String->Void) {
		Net.getText(API + 'web/discover/games/packages/${mod.id}', text -> {
			try {
				var payload:Dynamic = field(Json.parse(text), "payload");
				var builds:Array<Dynamic> = field(payload, "builds");
				var packages:Array<Dynamic> = field(payload, "packages");
				var packageNames = new Map<Int, String>();
				if (packages != null) for (p in packages) {
					var pid = toInt(field(p, "id"));
					if (pid != null) packageNames.set(pid, string(field(p, "title"), ""));
				}
				var files:Array<OnlineModFile> = [];
				if (builds != null) for (b in builds) {
					var bid = toInt(field(b, "id"));
					if (bid == null) continue;
					var type:String = field(b, "type");
					if (type != null && type != "downloadable" && type != "rom") continue; // html/flash builds can't be installed
					var file:Dynamic = field(b, "primary_file");
					var pkg = packageNames.get(toInt(field(b, "game_package_id")) ?? -1);
					files.push({
						id: Std.string(bid),
						name: string(field(file, "filename"), 'build-$bid.zip'),
						size: toFloat(field(file, "filesize"), -1),
						description: pkg,
						platform: platformOf(b),
						date: toFloat(field(b, "added_on"), 0) / 1000,
						needsResolve: true
					});
				}
				// builds made for the engine's mods folder first, then the smallest
				files.sort((a, b) -> {
					var am = isModFolderName(a.name) ? 0 : 1, bm = isModFolderName(b.name) ? 0 : 1;
					return am != bm ? am - bm : Std.int(a.size - b.size);
				});
				onDone({mod: mod, description: description, files: files});
			} catch (e:Dynamic) onError('Could not read the builds of this game ($e)');
		}, onError);
	}

	/** Turns a build into a download address (valid for a few hours). */
	public static function resolveDownload(file:OnlineModFile, onDone:String->Void, onError:String->Void) {
		Net.postJson(API + 'web/discover/games/builds/get-download-url/${file.id}', '{"forceDownload":true}', text -> {
			try {
				var url:String = field(field(Json.parse(text), "payload"), "url");
				if (url == null) throw "no url";
				onDone(url);
			} catch (e:Dynamic) onError('Game Jolt did not give a download address ($e)');
		}, onError);
	}

	static function platformOf(b:Dynamic):String {
		var list = [];
		if (field(b, "os_windows") == true || field(b, "os_windows_64") == true) list.push("Windows");
		if (field(b, "os_linux") == true || field(b, "os_linux_64") == true) list.push("Linux");
		if (field(b, "os_mac") == true || field(b, "os_mac_64") == true) list.push("Mac");
		if (field(b, "os_other") == true) list.push("Other");
		return list.length == 0 ? "Any" : list.join("/");
	}

	static function isModFolderName(name:String):Bool {
		var n = name.toLowerCase();
		return n.indexOf("mod") >= 0 && (n.indexOf("folder") >= 0 || n.indexOf("psych") >= 0 || n.indexOf("codename") >= 0 || n.indexOf("mods") >= 0);
	}

	/** Game Jolt descriptions are a JSON document of paragraphs and text runs. */
	public static function contentToText(content:Dynamic):String {
		if (content == null) return "";
		if (Std.isOfType(content, String)) {
			var s:String = content;
			if (!s.startsWith("{")) return s;
			try content = Json.parse(s) catch (e:Dynamic) return s;
		}
		var buf = new StringBuf();
		function walk(node:Dynamic) {
			if (node == null) return;
			var type:String = field(node, "type");
			var text:String = field(node, "text");
			if (text != null) buf.add(text);
			var children:Array<Dynamic> = field(node, "content");
			if (children != null) for (c in children) walk(c);
			if (type == "paragraph" || type == "heading" || type == "listItem" || type == "hardBreak") buf.add("\n");
		}
		walk(content);
		return StringTools.trim(buf.toString());
	}
}
