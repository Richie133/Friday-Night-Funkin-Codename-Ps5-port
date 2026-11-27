An unofficial port of Codename Engine (Friday Night Funkin') to jailbroken PS5 consoles, made with AI help. It is not made or supported by the Codename Engine team, the Funkin' Crew or Sony. Support them by playing on PC: [codename-engine.com](https://codename-engine.com).

**Beta.** 0.1.6 fixes the next stop at start-up ("Could not create directory: ./mods", reported through the new `error.txt`): the port moved the working folder to `/data/codename-ps5/` so Codename's relative paths would land there, but the console does not allow that, so `./mods` pointed at a read-only folder. Codename's mods, addons, autoload and scratch (`.temp`) paths are now absolute on the PS5. 0.1.4 and 0.1.5 fixed the ImGui stops; Psych Engine and V-Slice support is still switched off (since 0.1.3). If something goes wrong, Codename's error screen or a notification shows the reason (Codename's errors are also written to `error.txt`); please report it in Issues with a photo, or with `error.txt`, `crash.txt` and `codename.log` (or `codename.prev.log` if you started the game again since) from `/data/codename-ps5/logs/`. `PPSA52210-symbols.txt.gz` turns the `eboot+0x…` addresses into function names.

Install `PPSA52210.zip` with your homebrew app installer.

- Notes on the D-pad, sticks or □ ✕ △ ○; touchpad as a mouse; touchpad click opens the chart editor in a song
- USB keyboard and mouse
- Mod browser (△ on the main menu): GameBanana (Codename mods and all FNF mods), search with an on-screen keyboard, and Game Jolt
- Mod menu (□ on the main menu)
- Picture settings: 1080p / 1440p / 4K, 60 / 120 Hz, V-Sync, frame rate up to 240

Not supported for now: Psych Engine and V-Slice mods, video cutscenes, Discord.
