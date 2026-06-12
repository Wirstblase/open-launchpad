# OpenLaunchpad

A free, open-source clone of the classic macOS Launchpad (Sequoia 15.7.4 style). Built because macOS 26 Tahoe replaced the full-screen app grid with a Spotlight drawer, and that sucks.

Full-screen blurred overlay. Paged 7x5 grid of your apps. Drag to reorder or create folders. Trackpad pinch to open, search to filter. Zoom-in on open, zoom-out on dismiss. Exactly how Launchpad used to work.

## Build and run

```
swift build
swift run
```

Requires macOS 14+ and Swift 6.

A menu bar icon appears. Click it to open the launcher. ESC or click the background to dismiss.

## Build .app bundle

```
./build.sh
```

This produces `OpenLaunchpad.app` in the project root. Drag it to `/Applications` to install.

## Features

- Full-screen blurred overlay (hides Dock and menu bar)
- Zoom-in open animation, zoom-out dismiss animation
- Paged app grid (7 columns x 5 rows, swipe between pages)
- Clickable page indicator dots
- Search bar always visible at top (click to type, real-time filtering)
- Drag and drop to reorder apps
- Drag one app onto another to create folders
- Click folder to expand, click title to rename, drag apps out to remove
- Long-press to enter jiggle mode
- Keyboard navigation (arrows, Page Up/Down, Enter)
- Global hotkey: Option+Space toggles launchpad from anywhere
- Trackpad pinch gesture: thumb + 3 fingers in to open, spread to close
- Auto-detects newly installed apps while running
- Layout persists across launches

## Where stuff lives

The app itself can live anywhere. Drag it to `/Applications` if you want.

Config and layout data is stored at:

```
~/Library/Application Support/OpenLaunchpad/layout.json
```

That file holds your icon order, folders, folder names, and hidden apps. Delete it to reset everything to defaults. If it gets corrupted, a backup is made automatically and the app starts fresh.

Launch frequency stats are kept in `UserDefaults` under the key `OpenLaunchpadLaunchCounts`.

## License

MIT

## Related Projects

- [Relaunched](https://github.com/rhysx19/Relaunched) — Full-screen launcher with pinch gestures, folders, and math parser
- [Launchpad_Back](https://github.com/EricYang801/Launchpad_Back) — Clean architecture, Xcode project, good test coverage
- [Launchy](https://github.com/Punshnut/macos-launchy) — Feature-rich with Floaty/HUD mode, 40 languages, hot corners
- [LaunchBack](https://github.com/trey-a-12/LaunchBack) — First open-source pre-Tahoe reimplementation
- [QuickLaunch](https://github.com/vorojar/QuickLaunch) — Signed and notarized, pinyin search, tiny footprint
- [launch-box](https://github.com/flyu518/launch-box) — Categories, favorites, import/export, SPM-based
