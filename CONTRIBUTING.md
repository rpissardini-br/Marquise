# Contributing to Marquise

Thanks for helping! Bug reports, ideas, translations and code are all welcome.

- **Bugs and ideas:** open an issue using one of the templates. Search existing issues first.
- **Security problems:** follow [SECURITY.md](SECURITY.md), not a public issue.
- **Code:** for anything larger than a small fix, open an issue first so we can agree on
  the approach before you spend time on it.

## Building

You need the Command Line Tools or Xcode with the **macOS 26 SDK** or later (Swift 6).
Marquise is a Swift package with no dependencies.

```bash
./build.sh && open build/Marquise.app
```

`build.sh` compiles a release build, assembles `build/Marquise.app` and signs it with
hardened runtime.

### Local signing certificate (recommended)

macOS ties permissions (camera, microphone, speech, automation, system audio, accessibility) to the app's signature. With ad hoc
signing every build looks like a new app and macOS asks again. A self-signed certificate
keeps the same identity across builds:

1. Open **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name it, for example `Marquise Local`. Identity Type: **Self-Signed Root**.
   Certificate Type: **Code Signing**.
3. Build with it:

   ```bash
   LOCAL_CERT="Marquise Local" ./build.sh
   ```

The certificate doesn't need to be trusted in Keychain Access; leave its trust settings as
they are. It's only for your own builds and can't be used for releases.

## Screenshots without screen recording

The app can render its states to PNG files, with demo data and without touching your
preferences:

```bash
swift build -c release && .build/release/Marquise --snapshot previews en-US
```

The last argument is the language of the main screens (`pt-BR` if omitted). Images for
each language are also generated. The README images in `docs/images` come from this mode.

## Project layout

| Path | What it is |
| --- | --- |
| `Sources/Marquise/AppDelegate.swift` | Window, hover and mouse handling, menus, shortcuts, file drops |
| `Sources/Marquise/IslandModel.swift` | Notch geometry and the island's state and sizes |
| `Sources/Marquise/IslandView.swift` | The island's SwiftUI views (closed, open, clock, music) |
| `Sources/Marquise/Teleprompter.swift` | Teleprompter state, text layout, views and script editor |
| `Sources/Marquise/VoiceListener.swift` | On-device speech recognition (SpeechAnalyzer) |
| `Sources/Marquise/VoiceMatcher.swift` | Finds where the speaker is in the script |
| `Sources/Marquise/Mirror.swift` | Camera mirror |
| `Sources/Marquise/Shelf.swift` | File shelf and dragging files out |
| `Sources/Marquise/MediaController.swift` | Music and Spotify state and controls |
| `Sources/Marquise/VolumeMonitor.swift` | Volume of the current output: macOS or the monitor |
| `Sources/Marquise/SoftwareVolume.swift` | Volume on the Mac for monitors and TVs (Core Audio process tap) |
| `Sources/Marquise/DDC.swift` | Talking to external monitors over the cable (DDC/CI) |
| `Sources/Marquise/VolumeKeys.swift` | Optional volume keys for the monitor |
| `Sources/Marquise/HotKeys.swift` | Global shortcuts |
| `Sources/Marquise/Localization.swift` | Languages and all interface text |
| `Sources/Marquise/Snapshot.swift` | `--snapshot` mode |
| `Resources/*.lproj/InfoPlist.strings` | Translated permission prompts |
| `Icon/make-icon.swift` | Draws the app icon and generates `Resources/AppIcon.icns` (`swift Icon/make-icon.swift`) |
| `Extras/` | Code not in the app yet (battery indicator) |
| `build.sh`, `release.sh` | Development build and release installers |

## Code style

- Match the surrounding code: naming, structure and comment density. Code comments are
  currently in Portuguese; English comments are welcome too.
- Keep Marquise dependency-free and its permissions minimal. A change that needs a new
  entitlement, permission or network connection should explain why in the pull request.
- Never log what the user says, script text or file names.
- Check your change in light of the [known limitations](README.md#known-limitations), and
  update the README if it changes what users see.

## Translations

All interface text lives in `Localization.swift`, one table per language:
`pt-BR`, `pt-PT`, `en-US`, `en-GB` and `es`. Missing keys fall back to the closest language
(pt-PT → pt-BR, en-GB → en-US). When you add text, add it to every table. Permission
prompts are translated in `Resources/<language>.lproj/InfoPlist.strings`.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make the change and run `./build.sh` with no errors or new warnings.
3. Try it in the app, in at least one other language if you changed text.
4. Add a line to `CHANGELOG.md` under the unreleased version.
5. Open the pull request and fill in the template.

## Releases (maintainers)

`release.sh` builds a universal app (Apple silicon and Intel), signs it with hardened
runtime and creates `dist/Marquise-<version>.dmg`, `dist/Marquise-<version>.pkg` and
`dist/SHA256SUMS.txt`. The version comes from `CFBundleShortVersionString` in `Info.plist`.

Without arguments it makes a local test build, which Gatekeeper rejects on other Macs. A
public release needs an Apple Developer Program membership:

1. Create **Developer ID Application** and **Developer ID Installer** certificates and
   install them in the keychain.
2. Store the notarization credentials once, with an app-specific password from
   appleid.apple.com:

   ```bash
   xcrun notarytool store-credentials "marquise-notary" --apple-id "you@example.com" --team-id "TEAMID"
   ```

3. Build, sign, notarize and staple:

   ```bash
   DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)" DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)" NOTARY_PROFILE="marquise-notary" ./release.sh
   ```

4. Create a GitHub release with a `v<version>` tag, attach the three files from `dist/` and
   copy the version's notes from `CHANGELOG.md`.

Never change the bundle identifier (`com.marquise.app`): macOS would treat the update as a
different app and ask users for every permission again.
