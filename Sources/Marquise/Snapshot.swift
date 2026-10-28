import AppKit
import SwiftUI

/// `Marquise --snapshot <pasta> [idioma]` renderiza cada estado em PNG, sem precisar de permissão de Gravação de Tela.
/// O idioma (ex.: `en-US`) vale para as telas principais; o padrão é português do Brasil.
@MainActor enum Snapshot {
    static func run(into directory: String, language mainLanguage: AppLanguage = .ptBR) {
        Shelf.persistent = false
        Teleprompter.voiceEnabled = false
        CameraMirror.cameraEnabled = false
        let notch = NotchGeometry(
            hasNotch: true, notchSize: CGSize(width: 185, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956), centerX: 735)
        let states: [(String, (IslandModel) -> Void)] = [
            ("1-fechada", { _ in }),
            ("2-fechada-musica", { $0.media.loadDemo() }),
            ("3-fechada-volume", { $0.show(.volume(0.6, muted: false), for: 60) }),
            ("5-aberta-relogio", { $0.isOpen = true }),
            ("6-aberta-musica", { $0.media.loadDemo(); $0.isOpen = true }),
            ("7-teleprompter", { $0.prompter.begin() }),
            ("7b-teleprompter-voz", { m in
                m.prompter.begin()
                m.prompter.showDemo(spokenThrough: 17, status: .listening)
            }),
            ("7c-espelho", { $0.mirror.start() }),
            ("7d-espelho-iphone", { $0.mirror.showDemo(.offerIPhone, camera: "iPhone", lidClosed: true) }),
            ("8-soltar-arquivo", { $0.shelfDropMode = true; $0.dropTarget = .shelf }),
            ("8b-soltar-app", { m in
                m.shelfDropMode = true
                m.dropApp = URL(fileURLWithPath: "/System/Applications/Calculator.app")
                m.dropTarget = .uninstall
            }),
            ("9-prateleira", { m in
                let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                m.shelf.removeAll()
                m.shelf.add(["Package.swift", "Info.plist", "build.sh", "previews"].map { base.appendingPathComponent($0) })
                m.tab = .shelf
                m.isOpen = true
            }),
            ("10-fechada-prateleira", { m in
                let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                m.shelf.removeAll()
                m.shelf.add(["Package.swift", "Info.plist"].map { base.appendingPathComponent($0) })
            }),
        ]
        // Algumas telas em cada idioma (sem alterar a escolha salva do usuário).
        let saved = Localization.shared.choice
        var all = states
        for language in AppLanguage.allCases {
            let set: (IslandModel) -> Void = { _ in Localization.shared.choice = language }
            all.append(("idioma-\(language.rawValue)-relogio", { set($0); $0.isOpen = true }))
            all.append(("idioma-\(language.rawValue)-prateleira", { set($0); $0.tab = .shelf; $0.isOpen = true }))
            all.append(("idioma-\(language.rawValue)-soltar", { set($0); $0.shelfDropMode = true; $0.shelf.add([URL(fileURLWithPath: "/tmp")]) }))
        }
        defer { Localization.shared.choice = saved }

        for (name, setup) in all {
            Localization.shared.choice = name.hasPrefix("idioma-") ? Localization.shared.choice : mainLanguage
            let model = IslandModel()
            model.geometry = notch
            setup(model)
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.6), Color(red: 0.6, green: 0.4, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.white.opacity(0.25)).frame(height: 32)
                IslandRootView(model: model)
            }
            .frame(width: 640, height: max(220, model.currentSize.height + 40))
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }

        // Janela do desinstalador, com dados de exemplo.
        Localization.shared.choice = mainLanguage
        for (name, done) in [("11-desinstalador", false), ("12-desinstalador-pronto", true)] {
            let uninstaller = Uninstaller()
            uninstaller.showDemo(done: done)
            let view = UninstallerView(model: uninstaller, onClose: {}, scrolls: false)
                .frame(width: 600, height: 560)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}

extension MediaController {
    func loadDemo() {
        let size = NSSize(width: 300, height: 300)
        let art = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [.systemOrange, .systemPink, .systemPurple])?.draw(in: rect, angle: -45)
            return true
        }
        injectDemo(TrackState(title: "Aurora", artist: "Lumen", album: "Demo",
                              duration: 214, position: 71, anchor: Date(), isPlaying: true),
                   artwork: art)
    }
}
