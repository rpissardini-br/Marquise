<p align="center">
  <img src="Icon/AppIcon.png" width="128" alt="Marquise icon">
</p>

# Marquise

**A Dynamic Island for the Mac notch — with a camera-aligned teleprompter, a mirror, a file shelf with AirDrop and an app uninstaller.**

[Português (Brasil)](README.pt-BR.md) · [Download](../../releases/latest) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md)

<p align="center">
  <img src="docs/images/en/open-music.png" width="640" alt="Marquise open, showing the song that is playing with playback controls">
</p>

Marquise lives in the MacBook notch. Closed, it blends into the notch and shows small live
indicators. Hover over it and it opens with a clock, the song that is playing and your
file shelf. It also turns into a teleprompter that sits right below the camera, so you can
read a script while looking almost straight into the lens, or into a mirror to check how
you look before a meeting — and it can hide itself from screen recordings and screen sharing.

- Native Swift and SwiftUI, no dependencies, under 1 MB
- Runs fully on your Mac: no accounts, no analytics, no tracking
- English (US and UK), Portuguese (Brazil and Portugal) and Spanish

## Features

### Teleprompter

<p align="center">
  <img src="docs/images/en/teleprompter-voice.png" width="640" alt="Teleprompter following the voice: spoken words are dimmed, the next ones are bright">
</p>

- **Aligned with the webcam.** The text scrolls in a narrow column right below the
  camera, so your eyes stay close to the lens and the reading doesn't show.
- **Follows your voice** (macOS 26 or later). Marquise listens and moves the text as you
  speak, word by word. It handles skipped words, repeats and going back to reread a
  passage. Spoken words are dimmed so you never lose your place.
  - Speech recognition runs on the Mac. Audio never leaves your computer.
  - Works in English (US, UK), Portuguese (Brazil, Portugal) and Spanish. The language is
    detected from the script, or you can choose it.
  - The first time, macOS downloads the speech model for that language.
- **Fixed speed mode** for when you'd rather not use the microphone.
- **Hidden from screen capture** (on by default): Marquise, the teleprompter included, and
  the script editor are left out of screen recordings and screen sharing. You can turn this
  off in the script editor. See [Limitations](#known-limitations).
- **Adjustable:** speed, column width, text size and a mirrored mode for teleprompter glass.
- **Script editor** with copy and paste, plus a *Paste script* button.

| Shortcut | Action |
| --- | --- |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd> | Open or close the teleprompter |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd> | Pause or resume |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>↑</kbd> / <kbd>↓</kbd> | Faster or slower |
| Trackpad scroll | Move forward or back in the script |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd> | Open or close the [mirror](#mirror) |

Hover over the teleprompter for its controls: voice on or off, play, restart, edit and close.

### Mirror

Check your hair, light and framing before joining a call, even at the last second:
press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd> or click the camera button in the open island.

- Shows the Mac camera, mirrored, right below the notch, the same view people will get.
- Uses the built-in camera, even when an iPhone or external camera is connected.
- **MacBook closed?** If the Mac's camera isn't available (lid closed with an external
  monitor, or a Mac without a camera), Marquise offers to use your iPhone as the camera
  through Continuity Camera. Once you accept, it stops asking until you quit Marquise.
- The camera turns on only while the mirror is open. Nothing is recorded or saved.
- Close it with the ✕ button, the same shortcut or a click anywhere else.
- If the teleprompter is open, it pauses underneath and comes back when the mirror closes.
- Hidden from screen recordings and screen sharing along with the rest of Marquise.

### File shelf

<p align="center">
  <img src="docs/images/en/drop.png" width="420" alt="Dragging a file to the notch: the island becomes a drop zone">
  <img src="docs/images/en/shelf.png" width="420" alt="The shelf holding four items">
</p>

Moving files between folders or disks without copy and paste:

1. Drag files to the notch. It turns into a drop zone and holds them.
2. Open the folder or disk where they should go.
3. Drag them out of the shelf, one at a time or all at once.

Marquise only keeps a reference to each file; nothing is copied when you drop it on the
shelf. When you drag it out, the Finder decides as usual: on the same disk the file is
moved, to another disk it is copied. Hold <kbd>⌘</kbd> while dropping to move between disks.
Items leave the shelf once they have been dropped somewhere.

**AirDrop:** while you drag files to the notch, drop them on the **AirDrop** tile to send them
right away. On the shelf, the **AirDrop** button sends everything, and the small AirDrop
button that appears on hover sends a single item.

### App uninstaller

Drag an app to the notch and drop it on the **Uninstall** tile, or choose
**Uninstall an App…** in the options menu. Marquise lists the app and what it left in your
Library — data, containers, caches, preferences, logs and background items — with the size
of each, and moves only what you keep checked to the Trash. Nothing is deleted for good.

The search is deliberately conservative: it only looks in known Library folders, and an item
must carry the app's exact bundle ID (`com.company.app`) or the app's exact name. It skips
folders of other apps from the same company, vendor folders like *Google* or *Adobe*, Apple
apps, and Marquise itself. If another copy of the app is installed, only the app is selected,
since both copies share the same data. Items in system folders show a lock: Finder can move
them after asking for your password.

To see what would be removed without moving anything:

```bash
/Applications/Marquise.app/Contents/MacOS/Marquise --leftovers /Applications/App.app
```

### Now playing, volume and clock

<p align="center">
  <img src="docs/images/en/closed-music.png" width="640" alt="Closed island with album art and a visualizer">
  <img src="docs/images/en/open-clock.png" width="640" alt="Open island with clock, date and week">
</p>

- Album art and a live visualizer while **Music** or **Spotify** is playing; open the
  island for the title, artist, progress and playback controls.
- Volume changes appear in the notch.
- When nothing is playing: time, date and the current week.

### Options

Right-click the island or use the gear button:

- **Language:** automatic (follows the system) or any of the five languages.
- **Show island on:** the main display (the one with the menu bar, such as an external
  monitor) or the MacBook display with the notch.
- **Open at login.**
- Open the teleprompter or the mirror, or quit.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- Voice following needs macOS 26 or later.
- Designed for Macs with a notch. On other screens, such as an external monitor, Marquise
  draws an island of the same size at the top of the menu bar.

## Install

1. Download `Marquise-<version>.dmg` from [Releases](../../releases/latest).
2. Open it and drag **Marquise** to **Applications**.
3. Open Marquise from Applications. It has no Dock icon: look at the notch.

**The first time, macOS blocks it.** Marquise isn't notarized by Apple yet (that needs a paid
developer account), so macOS says it can't check the app. To allow it, once:

1. Open Marquise. When macOS says it couldn't be opened, click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the message about Marquise.
3. Click **Open Anyway** and confirm with your password or Touch ID.

From then on it opens normally. If you prefer, [build it from source](#build-from-source)
instead; the code is all here.

To check that the download wasn't changed, compare its SHA-256 with `SHA256SUMS.txt` from the same release:

```bash
shasum -a 256 Marquise-1.1.1.dmg
```

### Permissions

macOS asks for each one the first time it is needed. Marquise works without any of them;
only the related feature is disabled.

| Permission | Used for |
| --- | --- |
| Camera | The mirror |
| Microphone | Voice following in the teleprompter |
| Speech Recognition | Turning your voice into text, on the Mac |
| Automation (Music, Spotify) | Showing and controlling what is playing |
| Automation (Finder) | Moving protected files to the Trash in the uninstaller, only when you ask |
| Access data from other apps | Sizing and removing an app's container in the uninstaller |

You can change them later in **System Settings → Privacy & Security**.

## Privacy

- **No data collection.** No analytics, crash reporting, accounts or ads.
- **Network:** the only connection Marquise makes is downloading Spotify album art, over
  HTTPS and only from Spotify's image servers. The speech model is downloaded by macOS.
- **Camera:** used only while the mirror is open, shown on screen and never recorded,
  saved or sent anywhere. The Mac's green camera light shows when it is on.
- **Voice:** recognised on the Mac and used only to find your place in the script. Audio
  and transcripts are not recorded or saved.
- **Stored on your Mac** (in Marquise's preferences): your script, teleprompter settings,
  language choice and the paths of the files on the shelf. They are stored unencrypted, like
  most app preferences. Remove them with `defaults delete com.marquise.app`.
- **Logs** contain states only (for example "listening" or "2 files received"), never what
  you say or file names.

## Known limitations

- **Screen capture hiding** relies on macOS window-sharing settings. Meeting and recording
  apps that capture through macOS respect it, but it can't stop a phone camera, and some
  capture tools may behave differently. Test it with your meeting app before relying on it.
- While the island is open it covers the area right below the notch, so clicks there go to
  Marquise.
- If another app already uses one of the shortcuts, it won't work in Marquise, and there is
  no warning yet.
- The uninstaller finds what an app leaves under its own name or bundle ID. Data an app
  stores under another name (for example a company folder) is not listed, by design.
- The shelf keeps references, not copies: if a file is moved or deleted elsewhere, it
  disappears from the shelf.
- With voice following on, the microphone stays active while the teleprompter is paused.
- The standard macOS volume indicator still appears alongside Marquise's.
- The teleprompter and the mirror follow the island. If you use the MacBook camera with an
  external monitor, choose *MacBook Display* so the text stays right below the camera.

## Build from source

You need the Command Line Tools or Xcode with the **macOS 26 SDK** or later (Swift 6).

```bash
git clone https://github.com/rpissardini-br/marquise.git
```

```bash
cd marquise && ./build.sh && open build/Marquise.app
```

`build.sh` signs the app with a certificate from your keychain so macOS remembers the
permissions between builds. Without one it signs ad hoc, and macOS asks again after every
build. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to create a local signing certificate
and how releases are made.

## Contributing

Bug reports, ideas and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md)
first. To report a security issue, follow [SECURITY.md](SECURITY.md) instead of opening a
public issue.

## License

Copyright © 2026 Rafael Pissardini

Marquise is free software under the [GNU General Public License v3.0](LICENSE). You can use,
study, change and share it. If you distribute a modified version, it must also be released
under the GPL-3.0, with its source code.

Marquise is not affiliated with or endorsed by Apple. Dynamic Island, Mac, macOS and
Apple Music are trademarks of Apple Inc. Spotify is a trademark of Spotify AB.
