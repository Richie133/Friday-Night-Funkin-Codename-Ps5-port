An unofficial port of Codename Engine (Friday Night Funkin') to jailbroken PS5 consoles, made with AI help. It is not made or supported by the Codename Engine team, the Funkin' Crew or Sony. Support them by playing on PC: [codename-engine.com](https://codename-engine.com).

**Beta.** 0.1.5 is 0.1.4 built again so that its ImGui change is complete (0.1.4's build reused old ImGui objects). 0.1.4 fixed the next stop at start-up, found with the crash report added in 0.1.2: Codename switched ImGui's multi-viewport mode (debug windows in separate OS windows) back on after ImGui had switched it off for the console's single window, and ImGui ended the game on its second frame. It stays off on the PS5, and ImGui's checks are written to the log instead of ending the game, since ImGui only draws the debug console. Psych Engine and V-Slice support is still switched off (since 0.1.3). If something goes wrong, Codename's error screen or a notification shows the reason (Codename's errors are also written to `error.txt`); please report it in Issues with a photo, or with `error.txt`, `crash.txt` and `codename.log` (or `codename.prev.log` if you started the game again since) from `/data/codename-ps5/logs/`. `PPSA52210-symbols.txt.gz` turns the `eboot+0x…` addresses into function names.

Install `PPSA52210.zip` with your homebrew app installer.

- Notes on the D-pad, sticks or □ ✕ △ ○; touchpad as a mouse; touchpad click opens the chart editor in a song
- USB keyboard and mouse
- Mod browser (△ on the main menu): GameBanana (Codename mods and all FNF mods), search with an on-screen keyboard, and Game Jolt
- Mod menu (□ on the main menu)
- Picture settings: 1080p / 1440p / 4K, 60 / 120 Hz, V-Sync, frame rate up to 240

Not supported for now: Psych Engine and V-Slice mods, video cutscenes, Discord.
