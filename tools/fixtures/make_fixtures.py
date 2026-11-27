#!/usr/bin/env python3
"""Builds the offline fixtures the PC test build answers from (CNE_PS5_FIXTURES=<out>).

    make_fixtures.py <codename assets folder> <out folder>

Writes made-up GameBanana and Game Jolt answers in the shapes those APIs use, pictures,
and three small test mods built from the base game's own files: a Psych Engine mod, a
V-Slice mod and a Codename Engine mod, each zipped the way GameBanana serves them.
(Psych and V-Slice support is switched off for now: their mods check that the
installer turns them down with a clear message.)
Nothing here is downloaded; every mod, name and number is invented.
"""
import io
import json
import os
import shutil
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

ASSETS, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
rules = []


def rule(pattern, name, data):
    path = os.path.join(OUT, name)
    mode = "wb" if isinstance(data, bytes) else "w"
    with open(path, mode) as f:
        f.write(data if isinstance(data, (bytes, str)) else json.dumps(data, indent=1))
    rules.append(f"{pattern}\t{name}")


def picture(text, color, size=(530, 298)):
    img = Image.new("RGB", size, color)
    d = ImageDraw.Draw(img)
    for i in range(0, size[0], 24):
        d.line([(i, 0), (i - size[1], size[1])], fill=tuple(min(255, c + 30) for c in color), width=8)
    try:
        font = ImageFont.truetype(os.path.join(ASSETS, "fonts", "vcr.ttf"), 34)
    except OSError:
        font = ImageFont.load_default()
    d.text((24, size[1] - 70), text, fill=(255, 255, 255), font=font)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return buf.getvalue()


def zip_folder(folder, inner=None):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(folder):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, folder)
                z.write(full, os.path.join(inner, rel) if inner else rel)
    return buf.getvalue()


tmp = os.path.join(OUT, "_build")
shutil.rmtree(tmp, ignore_errors=True)
song_audio = os.path.join(ASSETS, "songs", "bopeebo", "song")
dad_sheet = os.path.join(ASSETS, "images", "characters", "dad")


def chart_notes(step=500, count=48):
    sections = []
    for s in range(count // 8):
        notes = []
        for i in range(8):
            t = (s * 8 + i) * step
            notes.append([t, (i % 4) + (4 if (s % 2) else 0), 0])
        sections.append({"sectionNotes": notes, "lengthInSteps": 16, "sectionBeats": 4, "mustHitSection": s % 2 == 0,
                         "gfSection": False, "altAnim": False, "changeBPM": False, "bpm": 120})
    return sections


# ---- a Psych Engine mod (0.7 layout) ----------------------------------------------------
psych = os.path.join(tmp, "Psych Test Mod")
os.makedirs(os.path.join(psych, "data", "test-song"))
os.makedirs(os.path.join(psych, "songs", "test-song"))
os.makedirs(os.path.join(psych, "characters"))
os.makedirs(os.path.join(psych, "stages"))
os.makedirs(os.path.join(psych, "weeks"))
os.makedirs(os.path.join(psych, "images", "characters"))
os.makedirs(os.path.join(psych, "images", "icons"))
os.makedirs(os.path.join(psych, "scripts"))
json.dump({"name": "Psych Test Mod", "description": "A Psych Engine mod made for the port's tests.", "restart": False},
          open(os.path.join(psych, "pack.json"), "w"))
for diff, suffix in [("normal", ""), ("hard", "-hard")]:
    chart = {"song": {"song": "Test Song", "notes": chart_notes(), "events": [[2000, [["Hey!", "BF", "0.6"]]],
                                                                         [4000, [["Lua Test Event", "a", "b"], ["Add Camera Zoom", "0.03", "0.05"]]]],
                      "bpm": 120, "needsVoices": True, "speed": 2.2 if diff == "hard" else 1.8,
                      "player1": "bf", "player2": "psych-dad", "gfVersion": "gf", "stage": "psych-stage"}}
    json.dump(chart, open(os.path.join(psych, "data", "test-song", f"test-song{suffix}.json"), "w"))
for f in ("Inst.ogg", "Voices.ogg"):
    shutil.copy(os.path.join(song_audio, f), os.path.join(psych, "songs", "test-song", f))
for ext in ("png", "xml"):
    shutil.copy(f"{dad_sheet}.{ext}", os.path.join(psych, "images", "characters", f"PSYCH_DAD.{ext}"))
json.dump({
    "animations": [
        {"anim": "idle", "name": "Dad idle dance", "fps": 24, "loop": False, "indices": [], "offsets": [0, 0]},
        {"anim": "singLEFT", "name": "dad sing note right", "fps": 24, "loop": False, "indices": [], "offsets": [-10, 10]},
        {"anim": "singDOWN", "name": "Dad Sing Note DOWN", "fps": 24, "loop": False, "indices": [], "offsets": [2, -31]},
        {"anim": "singUP", "name": "Dad Sing note UP", "fps": 24, "loop": False, "indices": [], "offsets": [-10, 50]},
        {"anim": "singRIGHT", "name": "Dad Sing Note LEFT", "fps": 24, "loop": False, "indices": [], "offsets": [-4, 26]}],
    "image": "characters/PSYCH_DAD", "scale": 1, "sing_duration": 6.1, "healthicon": "dad",
    "position": [0, 0], "camera_position": [0, 0], "flip_x": False, "no_antialiasing": False,
    "healthbar_colors": [175, 102, 206]}, open(os.path.join(psych, "characters", "psych-dad.json"), "w"))
json.dump({"directory": "", "defaultZoom": 0.85, "isPixelStage": False, "boyfriend": [770, 100], "girlfriend": [400, 130],
           "opponent": [100, 100], "hide_girlfriend": False, "camera_boyfriend": [0, 0], "camera_opponent": [0, 0],
           "camera_girlfriend": [0, 0], "camera_speed": 1}, open(os.path.join(psych, "stages", "psych-stage.json"), "w"))
open(os.path.join(psych, "stages", "psych-stage.lua"), "w").write(
    "function onCreate()\n\tmakeLuaSprite('bg', 'stageback', -600, -200)\n\tsetScrollFactor('bg', 0.9, 0.9)\n"
    "\taddLuaSprite('bg', false)\n\tmakeLuaSprite('front', 'stagefront', -650, 600)\n\tscaleObject('front', 1.1, 1.1)\n"
    "\taddLuaSprite('front', false)\nend\n")
open(os.path.join(psych, "scripts", "hello.lua"), "w").write("""local hits = 0
function onCreate()
	makeLuaText('info', 'Psych Lua: ready', 600, 20, 60)
	setTextSize('info', 24)
	setTextColor('info', '00FF99')
	addLuaText('info')
end
function onCreatePost()
	debugPrint('Psych Lua layer is running (', version, ')')
	setProperty('info.alpha', 0.9)
	runTimer('tick', 1, 0)
end
function onTimerCompleted(tag, loops, left)
	if tag == 'tick' then
		setTextString('info', 'beat ' .. curBeat .. ' | hits ' .. hits .. ' | band ' .. bit.band(12, 10) .. ' | hp ' .. string.format('%.2f', getHealth()))
	end
end
function onBeatHit()
	if curBeat % 4 == 0 then doTweenAngle('spin', 'iconP2', getProperty('iconP2.angle') + 360, 0.4, 'quadOut') end
end
function goodNoteHit(id, direction, noteType, isSustainNote)
	hits = hits + 1
	if hits % 10 == 0 then cameraFlash('game', 'FFFFFF', 0.2) end
end
function onEvent(name, v1, v2)
	if name == 'Lua Test Event' then debugPrint('custom event: ', v1, ' ', v2) end
end
""")
os.makedirs(os.path.join(psych, "custom_events"))
open(os.path.join(psych, "custom_events", "Lua Test Event.txt"), "w").write("An event made for the port's tests.\n")
open(os.path.join(psych, "custom_events", "Lua Test Event.lua"), "w").write(
    "function onEvent(name, v1, v2)\n\tif name == 'Lua Test Event' then setProperty('defaultCamZoom', 0.95) end\nend\n")
open(os.path.join(psych, "data", "test-song", "script.lua"), "w").write(
    "function onSongStart()\n\tdebugPrint('song script: the song started')\nend\n")
json.dump({"songs": [["Test Song", "psych-dad", [146, 113, 253]]], "weekCharacters": ["dad", "bf", "gf"],
           "weekBackground": "stage", "storyName": "PSYCH TEST WEEK", "weekName": "Psych Week", "freeplayColor": [146, 113, 253],
           "startUnlocked": True, "hiddenUntilUnlocked": False, "hideStoryMode": False, "hideFreeplay": False,
           "difficulties": "Normal, Hard"}, open(os.path.join(psych, "weeks", "psychweek.json"), "w"))
shutil.copy(os.path.join(ASSETS, "images", "icons", "dad", "icon.png"), os.path.join(psych, "images", "icons", "icon-psych-dad.png"))
rule("files/psych-test-mod.zip", "psych-test-mod.zip", zip_folder(psych, "Psych Test Mod"))

# ---- a V-Slice mod ------------------------------------------------------------------------
vs = os.path.join(tmp, "vslice")
os.makedirs(os.path.join(vs, "data", "songs", "vslice-song"))
os.makedirs(os.path.join(vs, "songs", "vslice-song"))
json.dump({"title": "V-Slice Test Mod", "description": "A V-Slice mod made for the port's tests.", "api_version": "0.6.3",
           "mod_version": "1.0.0", "contributors": [{"name": "nobody"}]}, open(os.path.join(vs, "_polymod_meta.json"), "w"))
json.dump({"version": "2.2.4", "songName": "VSlice Song", "artist": "Kawai Sprite", "timeFormat": "ms",
           "timeChanges": [{"t": 0, "bpm": 120, "n": 4, "d": 4}],
           "playData": {"album": "volume1", "previewStart": 0, "previewEnd": 15000, "songVariations": [],
                        "difficulties": ["easy", "normal", "hard"], "characters": {"player": "bf", "girlfriend": "gf", "opponent": "dad"},
                        "stage": "mainStage", "noteStyle": "funkin", "ratings": {"easy": 1, "normal": 2, "hard": 3}},
           "generatedBy": "tests"}, open(os.path.join(vs, "data", "songs", "vslice-song", "vslice-song-metadata.json"), "w"))
notes = [{"t": i * 500, "d": (i % 8), "l": 0} for i in range(48)]
json.dump({"version": "2.0.0", "scrollSpeed": {"easy": 1.4, "normal": 1.8, "hard": 2.2},
           "events": [{"t": 0, "e": "FocusCamera", "v": {"char": 1}}],
           "notes": {"easy": notes[::2], "normal": notes, "hard": notes}, "generatedBy": "tests"},
          open(os.path.join(vs, "data", "songs", "vslice-song", "vslice-song-chart.json"), "w"))
shutil.copy(os.path.join(song_audio, "Inst.ogg"), os.path.join(vs, "songs", "vslice-song", "Inst.ogg"))
shutil.copy(os.path.join(song_audio, "Voices.ogg"), os.path.join(vs, "songs", "vslice-song", "Voices-bf.ogg"))
shutil.copy(os.path.join(song_audio, "Voices.ogg"), os.path.join(vs, "songs", "vslice-song", "Voices-dad.ogg"))
rule("files/vslice-test-mod.zip", "vslice-test-mod.zip", zip_folder(vs))

# ---- a Codename Engine mod ------------------------------------------------------------------
cne = os.path.join(tmp, "cne")
os.makedirs(os.path.join(cne, "data", "config"))
os.makedirs(os.path.join(cne, "songs", "cne-song", "charts"))
os.makedirs(os.path.join(cne, "songs", "cne-song", "song"))
open(os.path.join(cne, "data", "config", "modpack.ini"), "w").write(
    "[Common]\nNAME=Codename Test Mod\nDESCRIPTION=A Codename Engine mod made for the port's tests.\n")
shutil.copy(os.path.join(ASSETS, "songs", "bopeebo", "charts", "normal.json"), os.path.join(cne, "songs", "cne-song", "charts", "normal.json"))
json.dump({"displayName": "CNE Song", "bpm": 100, "icon": "dad", "color": "#9271FD", "difficulties": ["normal"]},
          open(os.path.join(cne, "songs", "cne-song", "meta.json"), "w"))
for f in ("Inst.ogg", "Voices.ogg"):
    shutil.copy(os.path.join(song_audio, f), os.path.join(cne, "songs", "cne-song", "song", f))
rule("files/codename-test-mod.zip", "codename-test-mod.zip", zip_folder(cne, "Codename Test Mod"))

# ---- GameBanana answers ------------------------------------------------------------------------
MODS = [
    (900001, "Codename Test Mod", "tester", "Codename Mod Folder Mods", (110, 60, 200), "codename-test-mod.zip"),
    (900002, "Psych Test Mod", "psychfan", "Psych Mod Folders", (40, 120, 200), "psych-test-mod.zip"),
    (900003, "V-Slice Test Mod", "slicer", "V-Slice Mod Folders", (200, 70, 120), "vslice-test-mod.zip"),
]
for n in range(4, 13):
    MODS.append((900000 + n, f"Made-up Mod {n}", f"author{n}", "Codename Mod Folder Mods", (60 + n * 12, 90, 160 - n * 6), None))


def record(mid, name, author, cat, color):
    return {"_idRow": mid, "_sModelName": "Mod", "_sSingularTitle": "Mod", "_sName": name,
            "_sProfileUrl": f"https://gamebanana.com/mods/{mid}", "_tsDateAdded": 1790000000, "_tsDateModified": 1795000000,
            "_bHasFiles": True, "_aTags": [],
            "_aPreviewMedia": {"_aImages": [{"_sType": "screenshot", "_sBaseUrl": "https://images.gamebanana.com/img/ss/mods",
                                             "_sFile": f"{mid}.jpg", "_sFile220": f"220-90_{mid}.jpg", "_sFile530": f"530-90_{mid}.jpg"}]},
            "_aSubmitter": {"_idRow": 1, "_sName": author}, "_aGame": {"_idRow": 8694, "_sName": "Friday Night Funkin'"},
            "_aRootCategory": {"_sName": "Mod Folders"}, "_aSubCategory": {"_sName": cat},
            "_sVersion": "1.0", "_tsDateUpdated": 1795000000, "_bIsObsolete": False, "_bHasContentRatings": False,
            "_nLikeCount": mid % 97, "_nViewCount": mid % 1000 * 3}


for mid, name, author, cat, color, _ in MODS:
    rule(f"/{mid}.jpg", f"img-{mid}.jpg", picture(name, color))
    rule(f"_{mid}.jpg", f"img-{mid}.jpg", picture(name, color))
page = {"_aMetadata": {"_nRecordCount": len(MODS), "_bIsComplete": True, "_nPerpage": 15},
        "_aRecords": [record(*m[:5]) for m in MODS]}
rule("apiv11/Mod/Categories", "gb-categories.json", [
    {"_idRow": 34764, "_sName": "Codename Mod Folder Mods", "_nItemCount": 120, "_idParentCategoryRow": 0},
    {"_idRow": 40001, "_sName": "Psych Mod Folders", "_nItemCount": 4000, "_idParentCategoryRow": 0},
    {"_idRow": 40002, "_sName": "V-Slice Mod Folders", "_nItemCount": 300, "_idParentCategoryRow": 0}])
for mid, name, author, cat, color, file in MODS:
    files = []
    if file:
        files.append({"_idRow": mid * 10, "_sFile": file, "_nFilesize": os.path.getsize(os.path.join(OUT, file)),
                      "_sDescription": "", "_tsDateAdded": 1795000000, "_nDownloadCount": 42,
                      "_sDownloadUrl": f"https://gamebanana.com/dl/{mid * 10}", "_sMd5Checksum": ""})
        rules.append(f"/dl/{mid * 10}\t{file}")
    prof = record(mid, name, author, cat, color)
    prof.update({"_sText": f"<b>{name}</b><br>This mod was made up for the port's offline tests.<br><ul><li>One song</li><li>Converted on install</li></ul>",
                 "_aFiles": files, "_aCategory": {"_sName": cat}, "_aSuperCategory": {"_sName": "Mod Folders"},
                 "_aCredits": [{"_sGroupName": "Key Authors", "_aAuthors": [{"_sName": author, "_sRole": "everything"}]}]})
    rule(f"apiv11/Mod/{mid}/ProfilePage", f"gb-profile-{mid}.json", prof)
rule("apiv11/Mod/Index", "gb-index.json", page)
rule("apiv11/Game/8694/Subfeed", "gb-subfeed.json", page)
rule("apiv11/Util/Search/Results", "gb-search.json", {"_aMetadata": {"_nRecordCount": 2, "_bIsComplete": True},
                                                      "_aRecords": [record(*MODS[1][:5]), record(*MODS[2][:5])]})

# ---- Game Jolt answers -------------------------------------------------------------------------
games = [{"id": 700000 + i, "title": f"FNF Vs Made-up {i}", "slug": f"fnf-vs-madeup-{i}",
          "developer": {"display_name": f"dev{i}", "username": f"dev{i}"},
          "thumbnail_media_item": {"mediaserver_url": f"https://m.gjcdn.net/game-thumbnail/500/{700000 + i}.jpg"}} for i in range(1, 9)]
for g in games:
    rule(f"/{g['id']}.jpg", f"gj-{g['id']}.jpg", picture(g["title"], (30, 140, 90)))
rule("site-api/web/discover/games?", "gj-list.json", {"payload": {"games": games, "gamesCount": len(games), "perPage": 24}})
rules.append("site-api/web/search/games\tgj-list.json")
for g in games:
    rule(f"games/overview/{g['id']}", f"gj-overview-{g['id']}.json",
         {"payload": {"game": {"description_content": json.dumps({"type": "doc", "content": [{"type": "paragraph", "content": [
             {"type": "text", "text": "A made-up Game Jolt game. Its Windows build carries a Psych Engine mods folder."}]}]})}}})
    rule(f"games/packages/{g['id']}", f"gj-packages-{g['id']}.json",
         {"payload": {"packages": [{"id": 1, "title": "Mod folder"}], "builds": [
             {"id": g["id"] * 10, "type": "downloadable", "os_windows": True, "game_package_id": 1,
              "primary_file": {"filename": "psych-mod-folder.zip", "filesize": os.path.getsize(os.path.join(OUT, "psych-test-mod.zip"))}}]}})
    rule(f"get-download-url/{g['id'] * 10}", f"gj-url-{g['id']}.json", {"payload": {"url": f"https://files.gamejolt.net/files/psych-test-mod.zip"}})

shutil.rmtree(tmp, ignore_errors=True)
with open(os.path.join(OUT, "index.txt"), "w") as f:
    f.write("# pattern<TAB>file: the first pattern the address contains answers it\n")
    f.write("\n".join(rules) + "\n")
print(f"{len(rules)} fixtures in {OUT}")
