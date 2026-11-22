package funkin.ps5.mods;

import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;
import funkin.ps5.PS5;
import funkin.ps5.PS5Input;
import funkin.ps5.mods.ModDownloads;
import funkin.ps5.mods.OnlineMod;
import funkin.ps5.net.ThumbCache;
import funkin.ps5.ui.OnScreenKeyboard;
import funkin.ps5.ui.PS5UI;

/** A card in the grid. */
private class ModCard extends FlxSpriteGroup {
	public static inline var W:Int = 284;
	public static inline var H:Int = 236;
	public static inline var THUMB_H:Int = 160;

	public var mod:OnlineMod;
	var bg:FlxSprite;
	var thumb:FlxSprite;
	var border:FlxSprite;
	var title:FlxText;
	var author:FlxText;
	var badge:FlxSpriteGroup;
	var installedBadge:FlxSpriteGroup;
	public var selected(default, set):Bool = false;

	public function new(mod:OnlineMod) {
		super();
		this.mod = mod;
		bg = PS5UI.panel(0, 0, W, H, 0xFF1C1529, 14);
		add(bg);
		thumb = new FlxSprite(6, 6).makeSolid(W - 12, THUMB_H, 0xFF2A2140);
		add(thumb);
		title = new FlxText(10, THUMB_H + 12, W - 20, PS5UI.ellipsis(mod.name, 46), 18);
		title.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE);
		title.fieldHeight = 42;
		add(title);
		author = new FlxText(10, H - 26, W - 20, "by " + PS5UI.ellipsis(mod.author, 28), 14);
		author.setFormat(Paths.font("vcr.ttf"), 14, PS5UI.TEXT_DIM);
		add(author);
		if (mod.engineHint != null && mod.engineHint != UNKNOWN) {
			badge = PS5UI.badge(mod.engineHint.label().split(" ")[0], mod.engineHint.color(), 13);
			badge.setPosition(12, 12);
			add(badge);
		}
		if (InstalledMods.findBySource(mod.source, mod.id) != null) {
			installedBadge = PS5UI.badge("Installed", 0xFF2FA866, 13);
			installedBadge.setPosition(W - installedBadge.width - 12, 12);
			add(installedBadge);
		}
		border = PS5UI.panel(-4, -4, W + 8, H + 8, FlxColor.TRANSPARENT, 18, 0xFFFFE15A);
		border.visible = false;
		add(border);

		if (mod.thumbnail != null) ThumbCache.get(mod.thumbnail, g -> {
			if (thumb == null || !exists) return;
			thumb.loadGraphic(g);
			thumb.antialiasing = true;
			var s = Math.min((W - 12) / thumb.frameWidth, THUMB_H / thumb.frameHeight);
			thumb.scale.set(s, s);
			thumb.updateHitbox();
			thumb.x = x + 6 + (W - 12 - thumb.width) / 2;
			thumb.y = y + 6 + (THUMB_H - thumb.height) / 2;
		});
	}

	function set_selected(v:Bool) {
		border.visible = v;
		bg.color = v ? 0xFFFFFFFF : 0xFFCCCCCC;
		return selected = v;
	}
}

/**
 * Browse, search and download mods from GameBanana and Game Jolt.
 *
 * Tabs (L1 / R1): Codename (GameBanana's Codename mod folder category), all FNF mods,
 * Psych, V-Slice, a GameBanana search, Game Jolt's FNF games, and the downloads.
 */
class ModBrowserState extends MusicBeatState {
	public static var tabs:Array<BrowserFeed> = [
		{name: "Codename", source: GAMEBANANA, kind: 'category:${GameBanana.CODENAME_CATEGORY}'},
		{name: "All FNF", source: GAMEBANANA, kind: "subfeed", sort: "default"},
		{name: "Psych", source: GAMEBANANA, kind: "search-preset:psych engine"},
		{name: "V-Slice", source: GAMEBANANA, kind: "search-preset:v-slice"},
		{name: "Search", source: GAMEBANANA, kind: "search"},
		{name: "Game Jolt", source: GAMEJOLT, kind: "section:best"},
		{name: "Downloads", source: LOCAL, kind: "downloads"}
	];
	static var SORTS:Map<String, Array<{label:String, value:String}>> = [
		"subfeed" => [{label: "Popular", value: "default"}, {label: "Newest", value: "new"}, {label: "Updated", value: "updated"}],
		"category" => [{label: "Default", value: null}, {label: "Newest", value: "Generic_Newest"}, {label: "Most liked", value: "Generic_MostLiked"},
			{label: "Most downloaded", value: "Generic_MostDownloaded"}, {label: "Updated", value: "Generic_LatestUpdated"}],
		"gamejolt" => [{label: "Best", value: "section:best"}, {label: "Hot", value: "section:hot"}, {label: "New", value: "section:new"}]
	];

	var tab:Int;
	var query:String = "";
	var gjQuery:String = "";
	var sortIndex:Map<Int, Int> = [];

	var bg:FlxSprite;
	var tabTexts:Array<FlxText> = [];
	var tabUnderline:FlxSprite;
	var status:FunkinText;
	var subtitle:FunkinText;
	var grid:FlxTypedSpriteGroup<ModCard>;
	var gridCam:FlxCamera;
	var hints:FlxSpriteGroup;
	var downloadsGroup:FlxSpriteGroup;

	var mods:Array<OnlineMod> = [];
	var page:Int = 0;
	var hasMore:Bool = true;
	var loading:Bool = false;
	var requestId:Int = 0;
	var selected:Int = 0;
	var scrollY:Float = 0;
	var repeat = new RepeatState();
	var downloadSel:Int = 0;

	static inline var COLS:Int = 4;
	static inline var GRID_X:Int = 40;
	static inline var GRID_Y:Int = 150;
	static inline var GAP_X:Int = 16;
	static inline var GAP_Y:Int = 20;

	/** Where ○ goes: the main menu when the browser was opened from there, else the installed mods. */
	var backToMainMenu:Bool;

	public function new(?startTab:Int, backToMainMenu:Bool = false) {
		super(false);
		this.backToMainMenu = backToMainMenu;
		tab = startTab != null ? startTab : Options.ps5LastBrowserTab;
		if (tab < 0 || tab >= tabs.length) tab = 0;
	}

	override function create() {
		super.create();
		funkin.ps5.net.Net.init();
		CoolUtil.playMenuSong();

		bg = new FlxSprite().loadAnimatedGraphic(Paths.image('menus/menuDesat'));
		bg.color = 0xFF3A2266;
		bg.setGraphicSize(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.scrollFactor.set();
		bg.antialiasing = true;
		add(bg);
		var shade = new FlxSprite().makeSolid(FlxG.width, FlxG.height, 0x88000000);
		shade.scrollFactor.set();
		add(shade);

		gridCam = new FlxCamera(0, GRID_Y - 10, FlxG.width, FlxG.height - GRID_Y - 60);
		gridCam.bgColor = 0;
		FlxG.cameras.add(gridCam, false);
		grid = new FlxTypedSpriteGroup<ModCard>();
		grid.cameras = [gridCam];
		add(grid);

		downloadsGroup = new FlxSpriteGroup();
		add(downloadsGroup);

		var header = PS5UI.panel(20, 14, FlxG.width - 40, 116, PS5UI.PANEL, 22);
		add(header);
		// keep clear of the FPS counter in the top-left corner when it is on
		var titleText = new FunkinText(PS5UI.headerX(), 24, 0, "MOD BROWSER", 34);
		add(titleText);
		subtitle = new FunkinText(titleText.x + titleText.width + 20, 34, 0, "", 18);
		subtitle.color = PS5UI.TEXT_DIM;
		add(subtitle);

		var l1 = PS5UI.glyph(L1, 30);
		l1.setPosition(40, 80);
		add(l1);
		var tx = l1.x + l1.width + 14;
		for (i => t in tabs) {
			var text = new FlxText(tx, 82, 0, t.name, 22);
			text.setFormat(Paths.font("vcr.ttf"), 22, FlxColor.WHITE);
			add(text);
			tabTexts.push(text);
			tx += text.width + 26;
		}
		var r1 = PS5UI.glyph(R1, 30);
		r1.setPosition(tx, 80);
		add(r1);
		tabUnderline = new FlxSprite().makeSolid(10, 4, PS5UI.ACCENT);
		add(tabUnderline);

		status = new FunkinText(0, FlxG.height / 2, FlxG.width, "", 24);
		status.alignment = CENTER;
		add(status);

		hints = new FlxSpriteGroup();
		add(hints);

		ModDownloads.onAnyChange = job -> if (tabs[tab].kind == "downloads") refreshDownloads();

		// the Psych and V-Slice tabs use GameBanana's own categories when the list loads
		if (GameBanana.categories.length == 0) GameBanana.loadCategories(() -> {
			resolvePresetTabs();
			if (tabs[tab].kind.startsWith("category")) reload();
		}, _ -> {});
		else resolvePresetTabs();

		switchTab(0, true);
	}

	function resolvePresetTabs() {
		for (t in tabs) {
			if (!t.kind.startsWith("search-preset:")) continue;
			var want = t.name == "Psych" ? ["psych"] : ["v-slice", "vslice", "v slice", "base game"];
			for (c in GameBanana.categories) {
				var n = c.name.toLowerCase();
				var match = false;
				for (w in want) if (n.indexOf(w) >= 0) match = true;
				if (match && (n.indexOf("folder") >= 0 || n.indexOf("mod") >= 0 || c.count > 20)) {
					t.kind = 'category:${c.id}';
					break;
				}
			}
		}
	}

	function switchTab(change:Int, force:Bool = false) {
		if (change == 0 && !force) return;
		tab = FlxMath.wrap(tab + change, 0, tabs.length - 1);
		Options.ps5LastBrowserTab = tab;
		for (i => t in tabTexts) {
			t.color = i == tab ? FlxColor.WHITE : 0xFF8F86A6;
			t.alpha = i == tab ? 1 : 0.8;
		}
		var cur = tabTexts[tab];
		tabUnderline.makeSolid(Std.int(cur.width), 4, PS5UI.ACCENT);
		tabUnderline.setPosition(cur.x, cur.y + cur.height + 4);
		if (change != 0) CoolUtil.playMenuSFX(SCROLL, 0.6);
		updateHints();
		var feed = tabs[tab];
		if (feed.kind == "downloads") {
			clearGrid();
			status.text = "";
			subtitle.text = 'Downloads: ${ModDownloads.active} running';
			refreshDownloads();
			return;
		}
		downloadsGroup.clear();
		if (feed.kind == "search" && query == "") {
			clearGrid();
			subtitle.text = "Search GameBanana";
			status.text = "Press TRIANGLE (or F) to type what to look for.";
			return;
		}
		reload();
	}

	function updateHints() {
		hints.clear();
		var feed = tabs[tab];
		var list:Array<{button:PadButton, label:String}> = feed.kind == "downloads" ? [
			{button: CROSS, label: "Play / open"},
			{button: SQUARE, label: "Cancel"},
			{button: TRIANGLE, label: "Clear finished"},
			{button: CIRCLE, label: "Back"}
		] : [
			{button: CROSS, label: "Details"},
			{button: TRIANGLE, label: "Search"},
			{button: SQUARE, label: "Sort"},
			{button: OPTIONS, label: "Downloads"},
			{button: CIRCLE, label: backToMainMenu ? "Back" : "Installed mods"}
		];
		var h = PS5UI.hints(40, FlxG.height - 44, list, 28);
		hints.add(h);
	}

	function feedForRequest():BrowserFeed {
		var feed = tabs[tab];
		if (feed.kind.startsWith("search-preset:")) return {name: feed.name, source: GAMEBANANA, kind: "search"};
		var sorts = sortsFor(feed);
		if (sorts != null) {
			var s = sorts[sortIndex.exists(tab) ? sortIndex.get(tab) : 0];
			if (feed.source == GAMEJOLT) return {name: feed.name, source: GAMEJOLT, kind: gjQuery != "" ? "search" : s.value};
			return {name: feed.name, source: feed.source, kind: feed.kind, sort: s.value};
		}
		return feed;
	}

	function sortsFor(feed:BrowserFeed) {
		if (feed.source == GAMEJOLT) return SORTS.get("gamejolt");
		if (feed.kind == "subfeed") return SORTS.get("subfeed");
		if (feed.kind.startsWith("category:")) return SORTS.get("category");
		return null;
	}

	function queryForRequest():String {
		var feed = tabs[tab];
		if (feed.kind.startsWith("search-preset:")) return feed.kind.substr("search-preset:".length);
		if (feed.source == GAMEJOLT) return gjQuery;
		return query;
	}

	function reload() {
		clearGrid();
		mods = [];
		page = 0;
		hasMore = true;
		selected = 0;
		scrollY = 0;
		gridCam.scroll.y = 0;
		loadMore();
	}

	function clearGrid() {
		for (c in grid.members) if (c != null) c.destroy();
		grid.clear();
	}

	function loadMore() {
		if (loading || !hasMore) return;
		loading = true;
		var id = ++requestId;
		var feed = feedForRequest();
		var q = queryForRequest();
		status.text = mods.length == 0 ? "Loading..." : "";
		var sorts = sortsFor(tabs[tab]);
		var sortLabel = sorts != null ? sorts[sortIndex.exists(tab) ? sortIndex.get(tab) : 0].label : "";
		subtitle.text = (feed.source == GAMEJOLT ? "Game Jolt" : "GameBanana") + (q != "" ? '  ·  "$q"' : "") + (sortLabel != "" ? '  ·  $sortLabel' : "");
		var onDone = (result:OnlineModPage) -> {
			if (id != requestId) return;
			loading = false;
			page = result.page;
			hasMore = result.hasMore;
			var added = 0;
			for (m in result.mods) {
				if (m.rated == true && !Options.ps5ShowRatedMods) continue;
				var dup = false;
				for (o in mods) if (o.id == m.id && o.source == m.source) dup = true;
				if (dup) continue;
				mods.push(m);
				addCard(m);
				added++;
			}
			if (mods.length == 0) status.text = "Nothing here." + (hasMore ? "" : " Try another tab or search.");
			else status.text = "";
			if (added == 0 && hasMore) loadMore();
			updateSelection();
		};
		var onError = (err:String) -> {
			if (id != requestId) return;
			loading = false;
			// a sort the API refuses: try once more without it
			if (feed.sort != null && sortIndex.get(tab) != 0 && page == 0) {
				sortIndex.set(tab, 0);
				loadMore();
				return;
			}
			hasMore = false;
			status.text = 'Could not load the list.\n$err\n\nPress SQUARE to try again.';
		};
		if (feed.source == GAMEJOLT) GameJolt.feed(feed, page + 1, q, onDone, onError);
		else GameBanana.feed(feed, page + 1, q, onDone, onError);
	}

	function addCard(m:OnlineMod) {
		var i = grid.length;
		var card = new ModCard(m);
		card.setPosition(GRID_X + (i % COLS) * (ModCard.W + GAP_X), 10 + Std.int(i / COLS) * (ModCard.H + GAP_Y));
		grid.add(card);
	}

	function updateSelection() {
		for (i => c in grid.members) if (c != null) c.selected = i == selected;
		if (grid.length == 0) return;
		var rowY = Std.int(selected / COLS) * (ModCard.H + GAP_Y);
		var view = gridCam.height;
		if (rowY - scrollY > view - ModCard.H - 20) scrollY = rowY - view + ModCard.H + 30;
		if (rowY < scrollY) scrollY = rowY;
		// near the end: fetch the next page
		if (selected >= grid.length - COLS * 2) loadMore();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		gridCam.scroll.y = CoolUtil.fpsLerp(gridCam.scroll.y, scrollY, 0.25);

		if (PS5Input.justPressed(L1)) switchTab(-1);
		else if (PS5Input.justPressed(R1)) switchTab(1);
		if (PS5Input.justPressed(CIRCLE)) {
			CoolUtil.playMenuSFX(CANCEL);
			FlxG.switchState(backToMainMenu ? new funkin.menus.MainMenuState() : new ModMenuState());
			return;
		}

		var feed = tabs[tab];
		if (feed.kind == "downloads") {
			updateDownloads(elapsed);
			return;
		}
		if (PS5Input.justPressed(OPTIONS)) {
			switchTab(tabs.length - 1 - tab);
			return;
		}

		var nav = PS5Input.navigation(repeat, elapsed);
		if ((nav.x != 0 || nav.y != 0) && grid.length > 0) {
			var next = selected + nav.x + nav.y * COLS;
			if (next < 0) next = 0;
			if (next >= grid.length) next = grid.length - 1;
			if (next != selected) {
				selected = next;
				CoolUtil.playMenuSFX(SCROLL, 0.5);
				updateSelection();
			}
		}
		if (FlxG.mouse.wheel != 0) {
			scrollY = Math.max(0, scrollY - FlxG.mouse.wheel * 120);
			if (scrollY > (Std.int(grid.length / COLS) - 1) * (ModCard.H + GAP_Y)) loadMore();
		}
		if (FlxG.mouse.justPressed) {
			var mp = FlxG.mouse.getViewPosition(gridCam);
			mp.y += gridCam.scroll.y;
			for (i => c in grid.members) if (c != null && mp.x >= c.x && mp.x <= c.x + ModCard.W && mp.y >= c.y && mp.y <= c.y + ModCard.H) {
				if (selected == i) openDetails();
				else {
					selected = i;
					updateSelection();
				}
			}
			mp.put();
		}

		if (PS5Input.justPressed(CROSS) && grid.length > 0) openDetails();
		if (PS5Input.justPressed(TRIANGLE)) openSearch();
		if (PS5Input.justPressed(SQUARE)) {
			if (!hasMore && mods.length == 0) reload();
			else cycleSort();
		}
	}

	function cycleSort() {
		var sorts = sortsFor(tabs[tab]);
		if (sorts == null) return;
		var cur = sortIndex.exists(tab) ? sortIndex.get(tab) : 0;
		sortIndex.set(tab, (cur + 1) % sorts.length);
		CoolUtil.playMenuSFX(SCROLL);
		reload();
	}

	function openSearch() {
		var feed = tabs[tab];
		var isGJ = feed.source == GAMEJOLT;
		persistentUpdate = false;
		openSubState(new OnScreenKeyboard(isGJ ? "Search Game Jolt (FNF games)" : "Search GameBanana (FNF mods)", isGJ ? gjQuery : query, text -> {
			if (isGJ) gjQuery = text;
			else {
				query = text;
				if (feed.kind != "search") {
					for (i => t in tabs) if (t.kind == "search") tab = i;
				}
			}
			switchTab(0, true);
		}));
	}

	function openDetails() {
		var m = grid.members[selected];
		if (m == null) return;
		CoolUtil.playMenuSFX(CONFIRM, 0.7);
		persistentUpdate = false;
		openSubState(new ModDetailsSubstate(m.mod));
	}

	// downloads tab

	function refreshDownloads() {
		downloadsGroup.clear();
		subtitle.text = 'Downloads: ${ModDownloads.active} running';
		if (ModDownloads.jobs.length == 0) {
			status.text = "No downloads yet.\nOpen a mod and press CROSS on one of its files.";
			return;
		}
		status.text = "";
		if (downloadSel >= ModDownloads.jobs.length) downloadSel = ModDownloads.jobs.length - 1;
		for (i => job in ModDownloads.jobs) {
			var y = 150 + i * 104;
			if (y > FlxG.height - 150) break;
			var panel = PS5UI.panel(40, y, FlxG.width - 80, 92, i == downloadSel ? PS5UI.PANEL_LIGHT : PS5UI.PANEL, 16, i == downloadSel ? 0xFFFFE15A : null);
			downloadsGroup.add(panel);
			var name = new FunkinText(60, y + 10, FlxG.width - 400, PS5UI.ellipsis(job.mod.name, 50) + "  ·  " + PS5UI.ellipsis(job.file.name, 40), 20);
			downloadsGroup.add(name);
			var msg = new FunkinText(60, y + 40, FlxG.width - 400, PS5UI.ellipsis(job.message, 90), 16);
			msg.color = job.state == FAILED ? 0xFFFF7777 : (job.state == DONE ? 0xFF77FF99 : PS5UI.TEXT_DIM);
			downloadsGroup.add(msg);
			var barBg = new FlxSprite(FlxG.width - 320, y + 38).makeSolid(240, 14, 0xFF2A2140);
			downloadsGroup.add(barBg);
			var p = job.state == DONE ? 1 : job.progress;
			if (p > 0) downloadsGroup.add(new FlxSprite(barBg.x, barBg.y).makeSolid(Std.int(Math.max(2, 240 * p)), 14, job.state == FAILED ? 0xFFAA3344 : PS5UI.ACCENT));
		}
	}

	function updateDownloads(elapsed:Float) {
		var nav = PS5Input.navigation(repeat, elapsed);
		if (nav.y != 0 && ModDownloads.jobs.length > 0) {
			downloadSel = FlxMath.wrap(downloadSel + nav.y, 0, ModDownloads.jobs.length - 1);
			refreshDownloads();
		}
		var job = ModDownloads.jobs[downloadSel];
		if (PS5Input.justPressed(SQUARE) && job != null) {
			job.cancel();
			refreshDownloads();
		}
		if (PS5Input.justPressed(TRIANGLE)) {
			ModDownloads.clearFinished();
			downloadSel = 0;
			refreshDownloads();
		}
		if (PS5Input.justPressed(CROSS) && job != null && job.state == DONE && job.installed.length > 0) {
			CoolUtil.playMenuSFX(CONFIRM);
			funkin.backend.assets.ModsFolder.switchMod(job.installed[0]);
		}
	}

	override function destroy() {
		ModDownloads.onAnyChange = null;
		if (FlxG.cameras.list.contains(gridCam)) FlxG.cameras.remove(gridCam);
		super.destroy();
	}
}
