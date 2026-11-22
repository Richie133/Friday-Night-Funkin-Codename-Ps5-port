package funkin.ps5.mods;

import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.Net;
import haxe.Json;

/**
 * GameBanana's public API v11 (the one gamebanana.com itself uses), read without an account.
 *
 *  - Feed of a game:      apiv11/Game/{game}/Subfeed?_nPage=&_nPerpage=&_csvModelInclusions=Mod&_sSort=
 *  - Mods of a category:  apiv11/Mod/Index?_nPage=&_nPerpage=&_aFilters[Generic_Category]={id}&_sSort=
 *  - Search:              apiv11/Util/Search/Results?_sModelName=Mod&_idGameRow={game}&_sSearchString=&_nPage=
 *  - One mod:             apiv11/Mod/{id}/ProfilePage  (files in _aFiles, each with _sDownloadUrl)
 *  - Categories:          apiv11/Mod/Categories?_idGameRow={game}&_sSort=a_to_z&_bShowEmpty=true
 *
 * Every field is read defensively: a missing one gives an empty value, never a crash.
 */
class GameBanana {
	public static inline var API:String = "https://gamebanana.com/apiv11/";
	/** Friday Night Funkin' on GameBanana. */
	public static inline var FNF_GAME_ID:Int = 8694;
	/** "Codename Mod Folder Mods". */
	public static inline var CODENAME_CATEGORY:Int = 34764;
	public static inline var PER_PAGE:Int = 15;

	/** Known categories, found by name the first time the category list loads. */
	public static var categories:Array<{id:Int, name:String, count:Int, parent:Int}> = [];

	public static function feed(feed:BrowserFeed, page:Int, ?query:String, onDone:OnlineModPage->Void, onError:String->Void) {
		var url:String;
		var kind = feed.kind;
		if (kind == "search") {
			url = API + 'Util/Search/Results?_sModelName=Mod&_sOrder=best_match&_idGameRow=$FNF_GAME_ID'
				+ '&_sSearchString=${Net.urlEncode(query == null ? "" : query)}&_csvFields=name,description,article,attribs,owner&_nPage=$page';
		} else if (kind.startsWith("category:")) {
			var id = kind.substr("category:".length);
			url = API + 'Mod/Index?_nPage=$page&_nPerpage=$PER_PAGE&_aFilters%5BGeneric_Category%5D=$id'
				+ (feed.sort != null ? '&_sSort=${feed.sort}' : "");
		} else {
			url = API + 'Game/$FNF_GAME_ID/Subfeed?_nPage=$page&_nPerpage=$PER_PAGE&_csvModelInclusions=Mod'
				+ '&_sSort=${feed.sort == null ? "default" : feed.sort}';
		}
		Net.getText(url, text -> {
			try {
				var categoryId = kind.startsWith("category:") ? kind.substr("category:".length) : null;
				onDone(parsePage(Json.parse(text), page, categoryId));
			} catch (e:Dynamic) {
				onError('GameBanana answered something unexpected ($e)');
			}
		}, onError);
	}

	public static function parsePage(data:Dynamic, page:Int, ?categoryId:String):OnlineModPage {
		var meta:Dynamic = field(data, "_aMetadata");
		var records:Array<Dynamic> = field(data, "_aRecords");
		if (records == null) records = [];
		var mods:Array<OnlineMod> = [];
		var foreign = 0;
		for (r in records) {
			var model:String = field(r, "_sModelName");
			if (model != null && model != "Mod") continue;
			var mod = parseRecord(r);
			if (mod == null) continue;
			// The category filter is checked on our side too: an API that ignored it
			// would otherwise fill the Codename tab with every game's mods.
			var game:Dynamic = field(r, "_aGame");
			var gameId:Null<Int> = toInt(field(game, "_idRow"));
			if (gameId != null && gameId != FNF_GAME_ID) {
				foreign++;
				continue;
			}
			mods.push(mod);
		}
		var complete:Null<Bool> = field(meta, "_bIsComplete");
		var total:Null<Int> = toInt(field(meta, "_nRecordCount"));
		var perPage:Null<Int> = toInt(field(meta, "_nPerpage"));
		var hasMore = complete != null ? !complete : records.length >= (perPage == null ? PER_PAGE : perPage);
		if (foreign > 0 && mods.length == 0) hasMore = false;
		return {mods: mods, page: page, hasMore: hasMore, total: total};
	}

	public static function parseRecord(r:Dynamic):Null<OnlineMod> {
		var id = toInt(field(r, "_idRow"));
		if (id == null) return null;
		var submitter:Dynamic = field(r, "_aSubmitter");
		var root:Dynamic = field(r, "_aRootCategory");
		var sub:Dynamic = field(r, "_aSubCategory");
		var catName:String = field(sub, "_sName");
		var rootName:String = field(root, "_sName");
		var category = rootName != null && catName != null && rootName != catName ? '$rootName > $catName' : (catName != null ? catName : rootName);
		var images = parseImages(field(r, "_aPreviewMedia"));
		var name:String = field(r, "_sName");
		return {
			source: GAMEBANANA,
			id: Std.string(id),
			name: name == null ? 'Mod $id' : ModText.htmlToText(name),
			author: string(field(submitter, "_sName"), "unknown"),
			thumbnail: images.small,
			images: images.large,
			category: category,
			engineHint: ModText.guessEngine(category + " " + name),
			likes: toInt(field(r, "_nLikeCount")),
			views: toInt(field(r, "_nViewCount")),
			downloads: toInt(field(r, "_nDownloadCount")),
			updated: toFloat(field(r, "_tsDateUpdated"), toFloat(field(r, "_tsDateModified"), 0)),
			version: field(r, "_sVersion"),
			profileUrl: string(field(r, "_sProfileUrl"), 'https://gamebanana.com/mods/$id'),
			rated: field(r, "_bHasContentRatings") == true
		};
	}

	static function parseImages(media:Dynamic):{small:String, large:Array<String>} {
		var small:String = null;
		var large:Array<String> = [];
		var list:Array<Dynamic> = field(media, "_aImages");
		if (list != null) for (img in list) {
			var base:String = field(img, "_sBaseUrl");
			var file:String = field(img, "_sFile");
			if (base == null || file == null) continue;
			if (small == null) {
				var f220:String = field(img, "_sFile220");
				var f100:String = field(img, "_sFile100");
				small = '$base/' + (f220 != null ? f220 : (f100 != null ? f100 : file));
			}
			var f530:String = field(img, "_sFile530");
			large.push('$base/' + (f530 != null ? f530 : file));
		}
		return {small: small, large: large};
	}

	public static function details(mod:OnlineMod, onDone:OnlineModDetails->Void, onError:String->Void) {
		Net.getText(API + 'Mod/${mod.id}/ProfilePage', text -> {
			try {
				var data:Dynamic = Json.parse(text);
				var full = parseRecord(data);
				if (full != null) {
					// ProfilePage has the category of the mod itself under _aCategory
					var cat:Dynamic = field(data, "_aCategory");
					var superCat:Dynamic = field(data, "_aSuperCategory");
					var catName:String = field(cat, "_sName");
					var superName:String = field(superCat, "_sName");
					if (catName != null) full.category = superName != null && superName != catName ? '$superName > $catName' : catName;
					full.engineHint = ModText.guessEngine(full.category + " " + full.name);
					if (full.thumbnail == null) full.thumbnail = mod.thumbnail;
				} else full = mod;

				var files:Array<OnlineModFile> = [];
				var list:Array<Dynamic> = field(data, "_aFiles");
				if (list != null) for (f in list) {
					var fileId = toInt(field(f, "_idRow"));
					var url:String = field(f, "_sDownloadUrl");
					if (fileId == null && url == null) continue;
					if (url == null) url = 'https://gamebanana.com/dl/$fileId';
					files.push({
						id: Std.string(fileId),
						name: string(field(f, "_sFile"), "file"),
						size: toFloat(field(f, "_nFilesize"), -1),
						url: url,
						description: field(f, "_sDescription"),
						downloads: toInt(field(f, "_nDownloadCount")),
						date: toFloat(field(f, "_tsDateAdded"), 0),
						md5: field(f, "_sMd5Checksum")
					});
				}
				var credits:Array<String> = [];
				var groups:Array<Dynamic> = field(data, "_aCredits");
				if (groups != null) for (g in groups) {
					var authors:Array<Dynamic> = field(g, "_aAuthors");
					var groupName:String = field(g, "_sGroupName");
					if (authors != null) for (a in authors) {
						var n:String = field(a, "_sName");
						var role:String = field(a, "_sRole");
						if (n == null) continue;
						credits.push(n + (role != null && role != "" ? ' ($role)' : (groupName != null ? ' ($groupName)' : "")));
					}
				}
				var text:String = field(data, "_sText");
				var desc:String = field(data, "_sDescription");
				onDone({
					mod: full,
					description: ModText.htmlToText(text != null ? text : (desc != null ? desc : "")),
					files: files,
					credits: credits
				});
			} catch (e:Dynamic) {
				onError('Could not read this mod ($e)');
			}
		}, onError);
	}

	/** Loads the category list of Friday Night Funkin', for the "Categories" tab. */
	public static function loadCategories(onDone:Void->Void, onError:String->Void) {
		Net.getText(API + 'Mod/Categories?_idGameRow=$FNF_GAME_ID&_sSort=a_to_z&_bShowEmpty=true', text -> {
			try {
				var list:Array<Dynamic> = Json.parse(text);
				categories = [];
				for (c in list) {
					var id = toInt(field(c, "_idRow"));
					var name:String = field(c, "_sName");
					if (id == null || name == null) continue;
					categories.push({
						id: id,
						name: name,
						count: toInt(field(c, "_nItemCount")) ?? 0,
						parent: toInt(field(c, "_idParentCategoryRow")) ?? 0
					});
				}
				onDone();
			} catch (e:Dynamic) onError('No category list ($e)');
		}, onError);
	}

	// helpers that never throw

	public static function field(o:Dynamic, name:String):Dynamic {
		if (o == null || Std.isOfType(o, String) || Std.isOfType(o, Float) || Std.isOfType(o, Bool)) return null;
		return Reflect.field(o, name);
	}

	public static function toInt(v:Dynamic):Null<Int> {
		if (v == null) return null;
		if (Std.isOfType(v, Int)) return v;
		if (Std.isOfType(v, Float)) return Std.int(v);
		if (Std.isOfType(v, String)) return Std.parseInt(v);
		return null;
	}

	public static function toFloat(v:Dynamic, def:Float):Float {
		if (v == null) return def;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
		if (Std.isOfType(v, String)) {
			var f = Std.parseFloat(v);
			return Math.isNaN(f) ? def : f;
		}
		return def;
	}

	public static function string(v:Dynamic, def:String):String {
		return v == null ? def : Std.string(v);
	}
}
