# Earshot

A small retro recorder for macOS 26 that records the audio apps are playing (a browser
tab, a podcast app, a video call) to `.m4a` files. It never uses the microphone.

- **Source** picks one app (its helper processes included, so browser tabs work) or All Apps.
- **Record** button starts/stops; ⌘R does too, and so does the menu bar icon.
- The name field sets the file name; files go to `~/Music/Earshot` (`Name.m4a`, `Name 2.m4a`, …).
- The magnifier shows the last recording in Finder; the gear shows the folder and permission state.

Capture uses Core Audio process taps. The first launch asks for the
**System Audio Recording Only** permission (System Settings → Privacy & Security →
Screen & System Audio Recording).

## Build

```bash
./build_app.sh                 # builds .build/Earshot.app (signed with your Apple Development identity)
rm -rf /Applications/Earshot.app && cp -R .build/Earshot.app /Applications/
swift tools/make_icon.swift    # only if you change the icon
```

`EARSHOT_AUTORECORD=<seconds>` (e.g. `open --env EARSHOT_AUTORECORD=10 /Applications/Earshot.app`)
records on launch and stops after that many seconds, for scripted testing.
