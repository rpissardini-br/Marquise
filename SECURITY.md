# Security policy

## Supported versions

Only the latest release receives security fixes. Please update before reporting.

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Report it privately on GitHub: open the repository's **Security** tab and choose
**Report a vulnerability**. Include:

- what the problem is and what an attacker could do with it;
- the steps to reproduce it;
- your Marquise and macOS versions.

You should get a first reply within 7 days. Once a fix is released, the report is
published with credit to you, unless you prefer to stay anonymous.

## Security design

What Marquise does to keep your Mac safe, so you know what to expect and what counts as
a vulnerability:

- **Signed, not notarized yet.** Releases are code-signed, so macOS refuses to open a copy
  that was changed after release, but they aren't notarized by Apple yet (that needs a paid
  developer account). Check the SHA-256 below, or build from source.
- **Hardened runtime** with only three entitlements: camera (the mirror), microphone
  input (voice following) and Apple Events (controlling Music and Spotify).
- **Minimal network use.** The only connection Marquise makes is downloading Spotify album
  art: HTTPS only, only from Spotify's image hosts (`scdn.co`, `spotifycdn.com`) and with a
  size limit.
- **On-device speech.** Audio is processed by macOS on the Mac and never recorded, saved
  or sent anywhere.
- **Camera only on demand.** The camera is on only while the mirror is open. The image is
  shown on screen and never recorded, saved or sent anywhere.
- **No secrets stored.** Marquise has no accounts, passwords or tokens. Its preferences
  (the script, settings and shelf file paths) are stored unencrypted, like those of most apps.
- **Private logs.** System logs contain states and counts, never speech or file names.
- **The shelf doesn't touch files.** Dropping a file on the shelf only stores its path;
  moving or copying happens in the Finder, when you drag it out.

## Verifying a download

Each release includes `SHA256SUMS.txt`. Compare it with:

```bash
shasum -a 256 Marquise-1.1.dmg
```

You can also check that the app's signature is intact after installing it:

```bash
codesign --verify --deep --strict -v /Applications/Marquise.app
```
