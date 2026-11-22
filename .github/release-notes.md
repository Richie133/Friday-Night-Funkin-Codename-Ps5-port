An unofficial port of Codename Engine (Friday Night Funkin') to jailbroken PS5 consoles, made with AI help. It is not made or supported by the Codename Engine team, the Funkin' Crew or Sony. Support them by playing on PC: [codename-engine.com](https://codename-engine.com).

**Beta.** 0.1.2 fixes the stop at start-up that 0.1.1 had on the console ("abort is called"): Dear ImGui, which Codename uses for its debug console, looked for a `libGL` the PS5 does not have, and the first frame stopped on its check. It now gets OpenGL from the console's driver. If the game still stops, it now shows a notification with the reason and writes the details (the failed check or crash and the call stack) to `/data/codename-ps5/logs/crash.txt`. Please report problems in Issues with that file and `codename.log` from the same folder, or a photo of the notification. `PPSA52210-symbols.txt.gz` turns the `eboot+0x…` addresses into function names.

Install `PPSA52210.zip` with your homebrew app installer.

- Notes on the D-pad, sticks or □ ✕ △ ○; touchpad as a mouse; touchpad click opens the chart editor in a song
- USB keyboard and mouse
- Mod browser (△ on the main menu): GameBanana (Codename mods, all FNF mods, Psych and V-Slice), search with an on-screen keyboard, and Game Jolt
- Psych Engine mods (with their Lua scripts) and V-Slice mods are converted when installed
- Mod menu (□ on the main menu)
- Picture settings: 1080p / 1440p / 4K, 60 / 120 Hz, V-Sync, frame rate up to 240

Not supported: video cutscenes, Discord, Psych `.hx` scripts and shaders in Psych Lua scripts.
