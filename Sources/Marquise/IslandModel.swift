import AppKit
import Observation

struct NotchGeometry: Equatable {
    var hasNotch: Bool
    /// Tamanho do notch físico ou, em telas sem notch, de uma "ilha" equivalente na barra de menus.
    var notchSize: CGSize
    var screenFrame: CGRect
    /// Centro horizontal do notch, em coordenadas globais.
    var centerX: CGFloat

    static let fallback = NotchGeometry(
        hasNotch: false, notchSize: CGSize(width: 190, height: 32), screenFrame: .zero, centerX: 0)
}

extension NotchGeometry {
    init(screen: NSScreen) {
        let frame = screen.frame
        screenFrame = frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            hasNotch = true
            notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            centerX = frame.minX + left.width + width / 2
        } else {
            let menuBar = frame.maxY - screen.visibleFrame.maxY
            hasNotch = false
            notchSize = CGSize(width: 190, height: min(max(menuBar, 24), 38))
            centerX = frame.midX
        }
    }
}

enum LiveActivity: Equatable {
    case volume(Float, muted: Bool)
}

enum ClosedMode: Equatable {
    case idle
    case music
    case shelf(Int)
    case activity(LiveActivity)
}

enum OpenTab: Equatable {
    case home, shelf
}

@Observable final class IslandModel {
    var geometry = NotchGeometry.fallback
    var isOpen = false
    var tab: OpenTab = .home
    /// Um arquivo está sendo arrastado perto da ilha: ela vira área de soltar.
    var shelfDropMode = false
    var dropTargeted = false
    private(set) var activity: LiveActivity?

    let media = MediaController()
    let volume = VolumeMonitor()
    let prompter = Teleprompter()
    let mirror = CameraMirror()
    let shelf = Shelf()
    @ObservationIgnored private var activityWork: DispatchWorkItem?
    /// Abre a janela do roteiro (definido pelo AppDelegate).
    @ObservationIgnored var showPrompterEditor: () -> Void = {}
    /// Abre o menu de opções (idioma etc.) onde está o cursor.
    @ObservationIgnored var showOptionsMenu: () -> Void = {}
    /// As teclas de volume do teclado estão ligadas à Marquise (com a permissão de Acessibilidade).
    var volumeKeysOn = false
    /// Liga as teclas de volume (definido pelo AppDelegate).
    @ObservationIgnored var enableVolumeKeys: () -> Void = {}

    init() {
        volume.onChange = { [weak self] value, muted in
            self?.show(.volume(value, muted: muted), for: 1.6)
        }
    }

    func show(_ activity: LiveActivity, for seconds: Double) {
        self.activity = activity
        activityWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.activity = nil }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    var closedMode: ClosedMode {
        if let activity { return .activity(activity) }
        if media.isPlaying { return .music }
        if !shelf.items.isEmpty { return .shelf(shelf.items.count) }
        return .idle
    }

    var wingWidth: CGFloat {
        switch closedMode {
        case .idle: 0
        case .music, .shelf: geometry.notchSize.height + 8
        case .activity: 64
        }
    }

    var closedSize: CGSize {
        CGSize(width: geometry.notchSize.width + wingWidth * 2, height: geometry.notchSize.height)
    }

    var openSize: CGSize {
        CGSize(width: max(geometry.notchSize.width + 300, 520), height: geometry.notchSize.height + 160)
    }

    var prompterSize: CGSize {
        CGSize(width: max(CGFloat(prompter.columnWidth) + 48, geometry.notchSize.width + 240),
               height: geometry.notchSize.height + 176)
    }

    /// Prévia da câmera em 16:9, centralizada logo abaixo do notch.
    var mirrorPreviewSize: CGSize {
        let width = max(geometry.notchSize.width + 196, 396)
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    var mirrorSize: CGSize {
        CGSize(width: mirrorPreviewSize.width + 24, height: geometry.notchSize.height + mirrorPreviewSize.height + 12)
    }

    var dropSize: CGSize {
        CGSize(width: max(geometry.notchSize.width + 240, 460), height: geometry.notchSize.height + 112)
    }

    /// Tamanho atual do corpo da ilha (sem as abas do topo).
    var currentSize: CGSize {
        if mirror.isActive { return mirrorSize }
        if prompter.isActive { return prompterSize }
        if shelfDropMode { return dropSize }
        return isOpen ? openSize : closedSize
    }

    var isExpanded: Bool { isOpen || mirror.isActive || prompter.isActive || shelfDropMode }

    /// Onde um arquivo arrastado faz a ilha virar área de soltar.
    var dropZoneRect: CGRect {
        let width = dropSize.width + 120
        let height = dropSize.height + 40
        return CGRect(x: geometry.centerX - width / 2, y: geometry.screenFrame.maxY - height,
                      width: width, height: height + 20)
    }

    /// Raio das "abas" côncavas no topo, que fundem a ilha com a borda da tela.
    var flare: CGFloat { isExpanded ? 14 : 6 }

    /// Área (coordenadas globais) que abre a ilha no hover ou a mantém aberta.
    var hitRect: CGRect {
        let size = currentSize
        let width = size.width + flare * 2
        let rect = CGRect(
            x: geometry.centerX - width / 2, y: geometry.screenFrame.maxY - size.height,
            width: width, height: size.height)
        if mirror.isActive || prompter.isActive { return rect }
        if shelfDropMode { return rect.insetBy(dx: -24, dy: -24) }
        return rect.insetBy(dx: isOpen ? -14 : -4, dy: isOpen ? -14 : -4)
    }
}

/// Em qual tela a ilha fica quando há mais de uma.
enum IslandScreen: String, CaseIterable {
    /// A tela com a barra de menus: com monitor externo como principal, a ilha vai para ele.
    case main
    /// A tela do MacBook, onde ficam o notch e a câmera.
    case notch

    static var current: IslandScreen {
        get { UserDefaults.standard.string(forKey: "island.screen").flatMap(IslandScreen.init(rawValue:)) ?? .main }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "island.screen") }
    }
}
