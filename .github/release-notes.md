An unofficial port of Codename Engine (Friday Night Funkin') to jailbroken PS5 consoles, made with AI help. It is not made or supported by the Codename Engine team, the Funkin' Crew or Sony. Support them by playing on PC: [codename-engine.com](https://codename-engine.com).

**Beta.** 0.1.7 fixes 0.1.6's crash at start-up, which 0.1.6 itself caused: a log line it added asked the system for the working folder (`getcwd`), and the console's `getcwd` crashes in a native app. The port now answers that itself. Crash reports also name the thread and the system library an address belongs to, and follow the call stack when the stack pointer is broken. The keyboard and mouse libraries are looked for in more system folders (0.1.6 did not find them). 0.1.6 made Codename's mods, addons and temp paths absolute; 0.1.4 and 0.1.5 fixed the ImGui stops; Psych Engine and V-Slice support is still switched off (since 0.1.3). If something goes wrong, Codename's error screen or a notification shows the reason; please report it in Issues with a photo, or with `error.txt`, `crash.txt` and `codename.log` (or `codename.prev.log` if you started the game again since) from `/data/codename-ps5/logs/`. `PPSA52210-symbols.txt.gz` turns the `eboot+0x…` addresses into function names.

Install `PPSA52210.zip` with your homebrew app installer.

- Notes on the D-pad, sticks or □ ✕ △ ○; touchpad as a mouse; touchpad click opens the chart editor in a song
- USB keyboard and mouse
- Mod browser (△ on the main menu): GameBanana (Codename mods and all FNF mods), search with an on-screen keyboard, and Game Jolt
- Mod menu (□ on the main menu)
- Picture settings: 1080p / 1440p / 4K, 60 / 120 Hz, V-Sync, frame rate up to 240

Not supported for now: Psych Engine and V-Slice mods, video cutscenes, Discord.
