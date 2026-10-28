# Changelog

All notable changes to Marquise are listed here. Versions follow
[Semantic Versioning](https://semver.org).

## [1.1.1] — 2026-10-28

### Fixed
- The mirror showed no image when the island was hidden from screen recordings (the
  default), as happened on an external monitor. Marquise now draws the camera frames
  itself, so the mirror shows up for you and still stays out of recordings and screen
  sharing.

## [1.1] — 2026-10-28

### Added
- **AirDrop on the shelf:** drag files to the notch and drop them on the AirDrop tile, or send
  shelf items with the AirDrop button (all at once or one at a time on hover).
- **App uninstaller:** drag an app to the notch and drop it on the Uninstall tile, or choose
  *Uninstall an App…* in the options menu. Marquise lists the app and the files it left in
  the Library (data, containers, caches, preferences, logs and background items), with sizes,
  and moves only what you keep checked to the Trash. Nothing is deleted for good.
  - Conservative matching: only known Library folders, only the app's exact bundle ID or exact
    name, never a sibling app's ID (`com.app.canary`) or a vendor folder.
  - Refuses Apple apps, apps inside other apps and Marquise itself; asks you to quit the app
    first; with another copy of the app installed, only the app is selected.
  - Protected items (system folders, apps macOS protects) can be moved with Finder, which asks
    for your password.
  - `Marquise --leftovers /Applications/App.app` prints what would be removed, without moving
    anything.

## [1.0] — 2026-10-27

First public release.

### Island
- Lives in the MacBook notch; on screens without a notch, draws an island of the same size
  in the menu bar.
- Opens on hover with a clock, date and the current week.
- Shows what is playing in Music or Spotify, with album art, a visualizer, progress and
  playback controls.
- Shows volume changes.

### Teleprompter
- Narrow text column right below the camera for a natural gaze.
- Follows your voice word by word (macOS 26 or later), with on-device speech recognition
  in English (US, UK), Portuguese (Brazil, Portugal) and Spanish.
- Fixed-speed mode, adjustable speed, column width, text size and mirrored text.
- Hidden from screen recordings and screen sharing by default.
- Script editor with copy and paste.
- Global shortcuts: ⌃⌥T, ⌃⌥Space and ⌃⌥↑/↓ (and ⌃⌥M for the mirror).

### Mirror
- Shows the built-in camera, mirrored, right below the notch to check how you look before
  a meeting. Opens with ⌃⌥M or the camera button; the camera is on only while it is open.
- With the MacBook closed (or no built-in camera), offers to use the iPhone as the camera
  through Continuity Camera.

### File shelf
- Drag files to the notch to hold them, then drag them out to their destination, one at a
  time or all at once.

### General
- Interface in English (US, UK), Portuguese (Brazil, Portugal) and Spanish, following the
  system language or chosen in the menu.
- Choose the island's display: the main display (with the menu bar) or the MacBook display.
- Open at login.
- Hardened runtime with only the camera, microphone and Apple Events entitlements.
- Universal app for Apple silicon and Intel, macOS 14 or later.
