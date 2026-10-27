import Observation
import SwiftUI

struct IslandRootView: View {
    let model: IslandModel

    var body: some View {
        IslandView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.locale, Localization.shared.locale)
    }
}

/// Formato do notch: topo reto com abas côncavas e cantos inferiores arredondados.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set { flare = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let f = flare
        let b = min(bottomRadius, r.height - f, (r.width - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + f, y: r.minY + f), control: CGPoint(x: r.minX + f, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + f, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + f + b, y: r.maxY), control: CGPoint(x: r.minX + f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f, y: r.maxY - b), control: CGPoint(x: r.maxX - f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - f, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct IslandView: View {
    let model: IslandModel

    var body: some View {
        let size = model.currentSize
        let shape = NotchShape(flare: model.flare, bottomRadius: model.isExpanded ? 30 : 11)

        ZStack(alignment: .top) {
            if model.mirror.isActive {
                MirrorContent(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.28).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else if model.prompter.isActive {
                PrompterContent(model: model, onEdit: model.showPrompterEditor)
                    .frame(width: model.prompterSize.width, height: model.prompterSize.height, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.28).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else if model.shelfDropMode {
                DropZoneView(model: model)
                    .frame(width: model.dropSize.width, height: model.dropSize.height, alignment: .top)
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            } else if model.isOpen {
                OpenContent(model: model)
                    .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                            .animation(.easeOut(duration: 0.28).delay(0.06)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else {
                ClosedContent(model: model)
                    .frame(width: model.closedSize.width, height: model.closedSize.height)
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, model.flare)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(model.isExpanded ? 0.5 : 0), radius: 20, y: 10)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.isOpen)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.prompter.isActive)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: model.mirror.isActive)
        .animation(.spring(response: 0.38, dampingFraction: 0.75), value: model.shelfDropMode)
        .animation(.easeInOut(duration: 0.2), value: model.tab)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.closedMode)
    }
}

// MARK: - Fechada

struct ClosedContent: View {
    let model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: model.wingWidth)
            Color.clear.frame(width: model.geometry.notchSize.width)
            trailing.frame(width: model.wingWidth)
        }
        .frame(height: model.geometry.notchSize.height)
    }

    @ViewBuilder private var leading: some View {
        switch model.closedMode {
        case .idle:
            EmptyView()
        case .music:
            ArtworkView(image: model.media.artwork, size: model.geometry.notchSize.height - 12, radius: 6)
        case .shelf:
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .activity(.volume(let value, let muted)):
            Image(systemName: Self.speakerSymbol(value, muted: muted))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.closedMode {
        case .idle:
            EmptyView()
        case .music:
            VisualizerBars(color: Color(nsColor: model.media.accent), playing: model.media.isPlaying, maxHeight: 14)
        case .shelf(let count):
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        case .activity(.volume(let value, let muted)):
            Capsule()
                .fill(.white.opacity(0.2))
                .frame(width: 34, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: 34 * CGFloat(muted ? 0 : value))
                }
        }
    }

    static func speakerSymbol(_ value: Float, muted: Bool) -> String {
        if muted || value == 0 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.wave.1.fill" }
        if value < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - Aberta

struct OpenContent: View {
    let model: IslandModel

    var body: some View {
        let media = model.media
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    TabPill(id: "tab-home", symbol: media.track != nil ? "music.note" : "clock",
                            label: nil, selected: model.tab == .home) { model.tab = .home }
                    TabPill(id: "tab-shelf", symbol: "tray.full",
                            label: model.shelf.items.isEmpty ? nil : "\(model.shelf.items.count)",
                            selected: model.tab == .shelf) { model.tab = .shelf }
                }
                Spacer(minLength: model.geometry.notchSize.width + 20)
                HStack(spacing: 10) {
                    Button(action: model.mirror.start) {
                        Image(systemName: "web.camera")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(HoverState.shared.id == "mirror" ? 0.18 : 0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .onHover { HoverState.shared.set("mirror", $0) }
                    .help(L(.cameraMirror))
                    Button(action: model.showPrompterEditor) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(HoverState.shared.id == "prompter" ? 0.18 : 0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .onHover { HoverState.shared.set("prompter", $0) }
                    .help(L(.teleprompter))
                    Button(action: model.showOptionsMenu) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(HoverState.shared.id == "options" ? 0.18 : 0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .onHover { HoverState.shared.set("options", $0) }
                    .help(L(.options))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(height: model.geometry.notchSize.height)
            .padding(.horizontal, 18)

            Group {
                if model.tab == .shelf {
                    ShelfView(shelf: model.shelf)
                } else if let track = media.track {
                    NowPlayingView(media: media, track: track)
                } else {
                    IdleView()
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)

            Spacer(minLength: 0)

            VolumeRow(model: model)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Volume

struct VolumeRow: View {
    let model: IslandModel

    var body: some View {
        let volume = model.volume
        let enabled = volume.backend != .none
        HStack(spacing: 10) {
            Button { volume.toggleMute() } label: {
                Image(systemName: ClosedContent.speakerSymbol(volume.level, muted: volume.muted))
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(volume.muted ? L(.unmute) : L(.mute))
            .disabled(!enabled)

            VolumeSlider(value: volume.muted ? 0 : volume.level) { volume.set($0) }
                .disabled(!enabled)

            // O macOS não muda o volume desta saída: oferece ligar as teclas do teclado à Marquise.
            if volume.controlsOutsideMacOS && !model.volumeKeysOn {
                Button(action: model.enableVolumeKeys) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(HoverState.shared.id == "volume-keys" ? 0.18 : 0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .onHover { HoverState.shared.set("volume-keys", $0) }
                .help(L(.useVolumeKeys))
            }

            if volume.permissionDenied && !enabled {
                // Volume pelo Mac sem permissão: leva direto ao ajuste.
                Button(L(.allowSystemAudio), action: Self.openSystemAudioSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text(enabled || volume.deviceName.isEmpty ? volume.deviceName : L(.noVolumeControl, volume.deviceName))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.35))
        .frame(height: 22)
    }

    static func openSystemAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct VolumeSlider: View {
    let value: Float
    let onChange: (Float) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let hovering = HoverState.shared.id == "volume" && isEnabled
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(.white.opacity(isEnabled ? 1 : 0.4))
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
            .frame(height: hovering ? 8 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(Float(drag.location.x / max(geo.size.width, 1)))
            })
        }
        .frame(height: 22)
        .onHover { HoverState.shared.set("volume", $0) }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct NowPlayingView: View {
    let media: MediaController
    let track: TrackState

    var body: some View {
        let accent = Color(nsColor: media.accent)
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(image: media.artwork, size: 88, radius: 16)
                .shadow(color: accent.opacity(0.35), radius: 14)
                .scaleEffect(track.isPlaying ? 1 : 0.92)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: track.isPlaying)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.isEmpty ? L(.untitled) : track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                ProgressRow(media: media, track: track, accent: accent)
                    .padding(.top, 8)
                HStack(spacing: 18) {
                    Spacer()
                    ControlButton(id: "prev", symbol: "backward.fill", size: 15) { media.previous() }
                    ControlButton(id: "play", symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 21) { media.playPause() }
                    ControlButton(id: "next", symbol: "forward.fill", size: 15) { media.next() }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }
}

struct ProgressRow: View {
    let media: MediaController
    let track: TrackState
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = track.position(at: context.date)
            let fraction = track.duration > 0 ? position / track.duration : 0
            HStack(spacing: 8) {
                Text(Self.format(position))
                    .frame(width: 36, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(accent).frame(width: geo.size.width * fraction)
                    }
                    .frame(height: 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard track.duration > 0 else { return }
                        let x = min(max(value.location.x / geo.size.width, 0), 1)
                        media.seek(to: track.duration * x)
                    })
                }
                .frame(height: 12)
                Text("-" + Self.format(max(track.duration - position, 0)))
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct IdleView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                    Label(L(.nothingPlaying), systemImage: "music.note")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 4)
                }
                Spacer()
                WeekStrip(date: context.date)
            }
        }
    }
}

struct WeekStrip: View {
    let date: Date

    /// A semana começa no dia certo para o idioma (domingo no Brasil e EUA, segunda na Europa).
    static func calendar(for locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        calendar.firstWeekday = (weekdays.firstIndex(of: locale.firstDayOfWeek) ?? 0) + 1
        return calendar
    }

    var body: some View {
        let calendar = Self.calendar(for: Localization.shared.locale)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? date
                let isToday = calendar.isDate(day, inSameDayAs: date)
                VStack(spacing: 4) {
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(isToday ? 0.9 : 0.4))
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? Color.black : Color.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(isToday ? Color.white : Color.white.opacity(0.08)))
                }
            }
        }
    }
}

// MARK: - Componentes

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.1)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct VisualizerBars: View {
    let color: Color
    let playing: Bool
    let maxHeight: CGFloat

    private static let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private static let phases: [Double] = [0, 1.3, 2.1, 0.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = abs(sin(t * Self.speeds[i] + Self.phases[i]) * cos(t * Self.speeds[(i + 1) % 4] * 0.5))
                    let level = playing ? 0.25 + 0.75 * wave : 0.2
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(3, maxHeight * level))
                }
            }
            .frame(height: maxHeight)
        }
    }
}

/// Item sob o cursor (o SDK sem Xcode não tem o plugin do macro @State).
@Observable final class HoverState {
    static let shared = HoverState()
    var id: String?

    func set(_ id: String, _ inside: Bool) {
        if inside { self.id = id } else if self.id == id { self.id = nil }
    }
}

struct ControlButton: View {
    let id: String
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let hovering = HoverState.shared.id == id
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { HoverState.shared.set(id, $0) }
    }
}

struct TabPill: View {
    let id: String
    let symbol: String
    let label: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let hovering = HoverState.shared.id == id
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                if let label { Text(label).font(.system(size: 11, weight: .semibold)).monospacedDigit() }
            }
            .foregroundStyle(.white.opacity(selected ? 0.95 : 0.55))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(selected ? 0.16 : (hovering ? 0.08 : 0))))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { HoverState.shared.set(id, $0) }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
