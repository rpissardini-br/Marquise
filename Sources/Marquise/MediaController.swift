import AppKit
import Observation

enum MediaSource: String, CaseIterable {
    case music, spotify

    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    var appName: String { self == .music ? "Music" : "Spotify" }
    var displayName: String { self == .music ? "Música" : "Spotify" }
    var notificationName: String {
        self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged"
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

struct TrackState: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    /// Posição em `anchor`; a posição atual é extrapolada enquanto toca.
    var position: Double = 0
    var anchor = Date()
    var isPlaying = false
    var updated = Date()

    var key: String { "\(title)\u{1}\(artist)\u{1}\(album)" }

    func position(at date: Date) -> Double {
        let p = isPlaying ? position + date.timeIntervalSince(anchor) : position
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

/// Lê o que está tocando no Música e no Spotify.
/// As notificações distribuídas dos players não exigem permissão; o AppleScript
/// (posição exata, capa e controles) pede permissão de Automação uma vez por app.
@Observable final class MediaController {
    private(set) var states: [MediaSource: TrackState] = [:]
    private(set) var artworks: [MediaSource: NSImage] = [:]
    private(set) var accents: [MediaSource: NSColor] = [:]
    @ObservationIgnored private var artworkKeys: [MediaSource: String] = [:]

    var source: MediaSource? {
        if let playing = states.first(where: { $0.value.isPlaying })?.key { return playing }
        return states.max(by: { $0.value.updated < $1.value.updated })?.key
    }
    var track: TrackState? { source.flatMap { states[$0] } }
    var artwork: NSImage? { source.flatMap { artworks[$0] } }
    var accent: NSColor { source.flatMap { accents[$0] } ?? .white }
    var isPlaying: Bool { track?.isPlaying ?? false }

    func start() {
        for source in MediaSource.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(source.notificationName), object: nil, queue: .main
            ) { [weak self] note in
                self?.handle(note, from: source)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let source = MediaSource.allCases.first(where: { $0.bundleID == app.bundleIdentifier })
            else { return }
            self?.clear(source)
        }
        refreshAll()
    }

    func refreshAll() {
        for source in MediaSource.allCases {
            if source.isRunning {
                refresh(source)
            } else if states[source] != nil {
                clear(source)
            }
        }
    }

    // MARK: - Controles

    func playPause() {
        guard let s = source else { return }
        if var st = states[s] {
            st.position = st.position(at: Date())
            st.anchor = Date()
            st.isPlaying.toggle()
            states[s] = st
        }
        command("playpause", on: s)
    }

    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        guard let s = source else { return }
        if var st = states[s] {
            st.position = seconds
            st.anchor = Date()
            states[s] = st
        }
        command("set player position to \(Int(seconds))", on: s)
    }

    private func command(_ command: String, on source: MediaSource? = nil) {
        guard let s = source ?? self.source, s.isRunning else { return }
        AppleScript.run("tell application \"\(s.appName)\" to \(command)") { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.refresh(s) }
        }
    }

    // MARK: - Estado

    private func handle(_ note: Notification, from s: MediaSource) {
        let info = note.userInfo ?? [:]
        let playerState = info["Player State"] as? String ?? ""
        if playerState == "Stopped" {
            clear(s)
            return
        }

        let old = states[s]
        var st = old ?? TrackState()
        let now = Date()
        st.position = st.position(at: now)
        st.anchor = now
        if let v = info["Name"] as? String { st.title = v }
        if let v = info["Artist"] as? String { st.artist = v }
        if let v = info["Album"] as? String { st.album = v }
        st.isPlaying = playerState == "Playing"
        if st.key != old?.key { st.position = 0 }

        switch s {
        case .music:
            if let t = info["Total Time"] as? NSNumber { st.duration = t.doubleValue / 1000 }
        case .spotify:
            if let d = info["Duration"] as? NSNumber { st.duration = d.doubleValue / 1000 }
            if let p = info["Playback Position"] as? NSNumber { st.position = p.doubleValue }
        }
        st.updated = now
        states[s] = st
        if st.key != old?.key { artworks[s] = nil; accents[s] = nil }

        refresh(s)
    }

    private func refresh(_ s: MediaSource) {
        guard s.isRunning else { return }
        AppleScript.run(s == .spotify ? Scripts.spotifyState : Scripts.musicState) { [weak self] result in
            guard let self, let raw = result?.stringValue else { return }
            self.apply(raw, from: s)
        }
    }

    private func apply(_ raw: String, from s: MediaSource) {
        if raw == "stopped" {
            clear(s)
            return
        }
        let parts = raw.components(separatedBy: "||")
        guard parts.count >= 6 else { return }

        let old = states[s]
        var st = old ?? TrackState()
        st.isPlaying = parts[0] == "playing"
        st.title = parts[1]
        st.artist = parts[2]
        st.album = parts[3]
        let duration = Self.number(parts[4])
        st.duration = s == .spotify ? duration / 1000 : duration
        st.position = Self.number(parts[5])
        st.anchor = Date()
        if old == nil || old?.key != st.key || old?.isPlaying != st.isPlaying { st.updated = Date() }
        states[s] = st

        loadArtwork(for: s, key: st.key, url: parts.count > 6 ? parts[6] : nil)
    }

    private func clear(_ s: MediaSource) {
        states[s] = nil
        artworks[s] = nil
        accents[s] = nil
        artworkKeys[s] = nil
    }

    // MARK: - Capa

    private func loadArtwork(for s: MediaSource, key: String, url: String?) {
        guard artworkKeys[s] != key else { return }
        artworkKeys[s] = key

        switch s {
        case .spotify:
            guard let url, let link = URL(string: url), Self.isSpotifyArtwork(link) else {
                artworkKeys[s] = nil
                return
            }
            URLSession.shared.dataTask(with: link) { [weak self] data, _, _ in
                let image = data.flatMap { $0.count <= Self.maxArtworkBytes ? NSImage(data: $0) : nil }
                DispatchQueue.main.async { self?.setArtwork(image, for: s, key: key) }
            }.resume()
        case .music:
            AppleScript.run(Scripts.musicArtwork) { [weak self] result in
                let data = result?.data ?? Data()
                self?.setArtwork(data.isEmpty ? nil : NSImage(data: data), for: s, key: key)
            }
        }
    }

    static let maxArtworkBytes = 5_000_000

    /// A capa vem de um link informado pelo Spotify; só baixa dos servidores de imagem dele, por HTTPS.
    static func isSpotifyArtwork(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased()
        else { return false }
        return ["scdn.co", "spotifycdn.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func setArtwork(_ image: NSImage?, for s: MediaSource, key: String) {
        guard states[s]?.key == key else { return }
        guard let image else {
            artworkKeys[s] = nil  // tenta de novo no próximo refresh
            return
        }
        artworks[s] = image
        accents[s] = image.islandAccent
    }

    func injectDemo(_ state: TrackState, artwork: NSImage) {
        states[.music] = state
        artworks[.music] = artwork
        accents[.music] = artwork.islandAccent
    }

    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

private enum Scripts {
    static let musicState = """
    tell application "Music"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set t to current track
        return s & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & ((duration of t) as string) & "||" & ((player position) as string)
    end tell
    """

    static let spotifyState = """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set t to current track
        return s & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & ((duration of t) as string) & "||" & ((player position) as string) & "||" & (artwork url of t)
    end tell
    """

    static let musicArtwork = """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        on error
            return ""
        end try
    end tell
    """
}

enum AppleScript {
    private static let queue = DispatchQueue(label: "marquise.applescript", qos: .userInitiated)
    private static var cache: [String: NSAppleScript] = [:]

    /// Executa fora da main thread (uma por vez) e devolve o resultado na main thread.
    static func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            let script: NSAppleScript? = cache[source] ?? {
                let s = NSAppleScript(source: source)
                cache[source] = s
                return s
            }()
            var error: NSDictionary?
            let output = script?.executeAndReturnError(&error)
            let result = error == nil ? output : nil
            DispatchQueue.main.async { completion?(result) }
        }
    }
}

extension NSImage {
    /// Cor de destaque da capa, clareada para ficar legível sobre o preto.
    var islandAccent: NSColor {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        let n = 12
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return .white }

        // Média ponderada pela saturação × brilho: favorece as cores vivas da capa.
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let hi = max(pr, pg, pb), lo = min(pr, pg, pb)
            let saturation = hi == 0 ? 0 : (hi - lo) / hi
            let weight = 0.05 + saturation * hi
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
        }
        let base = NSColor(deviceRed: r / total, green: g / total, blue: b / total, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.25, 1), brightness: max(v, 0.85), alpha: 1)
    }
}
