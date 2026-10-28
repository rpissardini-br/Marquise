#if PROMO
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Vídeo de divulgação, desenhado quadro a quadro com a interface real da ilha.
/// Só existe na compilação com `-DPROMO` (veja `Promo/make-promo.sh`); não vai no app.
///
/// `Marquise --promo <saida.mp4> [idioma] [--vertical]` grava o vídeo (1920×1080, ou 1080×1920 com
/// `--vertical`, para Reels, TikTok e Shorts; 30 qps, sem áudio).
/// `Marquise --promo-stills <pasta> [idioma] [--vertical]` grava só alguns quadros em PNG, para conferir.
@MainActor enum Promo {
    static let fps = 30
    static let duration = 33.0
    /// A cena é desenhada em pontos e ampliada 1,6× para 1920×1080.
    static var vertical = false
    static var canvas: CGSize { vertical ? CGSize(width: 675, height: 1200) : CGSize(width: 1200, height: 675) }
    static let scale: CGFloat = 1.6
    /// No vertical a ilha aparece maior (a tela é estreita e sobra altura).
    static var islandZoom: CGFloat { vertical ? 1.18 : 1 }

    static func run(arguments args: [String]) -> Int32 {
        Shelf.persistent = false
        Teleprompter.voiceEnabled = false
        CameraMirror.cameraEnabled = false
        CameraMirror.demoImage = portrait()

        let stills = args.firstIndex(of: "--promo-stills")
        guard let flag = stills ?? args.firstIndex(of: "--promo"), flag + 1 < args.count else { return 2 }
        let output = URL(fileURLWithPath: args[flag + 1])
        let language = args.dropFirst(flag + 2).lazy.compactMap(AppLanguage.init(rawValue:)).first ?? .ptBR
        vertical = args.contains("--vertical")
        Localization.shared.choice = language
        let scenes = Scenes(language: language)

        if stills != nil {
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for t in [1.0, 2.6, 5.5, 9.5, 12.5, 15.0, 18.0, 20.0, 22.2, 24.0, 25.6, 27.0, 28.5, 31.0] {
                guard let image = render(scenes.frame(at: t)) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: output.appendingPathComponent(String(format: "t%05.1f.png", t)))
            }
            print("Quadros em \(output.path)")
            return 0
        }
        return write(scenes, to: output) ? 0 : 1
    }

    private static func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Localization.shared.locale))
        renderer.scale = scale
        return renderer.cgImage
    }

    private static func write(_ scenes: Scenes, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let width = Int(canvas.width * scale), height = Int(canvas.height * scale)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let total = Int(duration * Double(fps))
        for index in 0..<total {
            autoreleasepool {
                let t = Double(index) / Double(fps)
                guard let image = render(scenes.frame(at: t)), let pool = adaptor.pixelBufferPool else { return }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { return }
                CVPixelBufferLockBaseAddress(buffer, [])
                let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
            }
            if index % (fps * 3) == 0 { print("quadro \(index)/\(total)") }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        print(writer.status == .completed ? "Vídeo: \(url.path)" : "Falhou: \(writer.error?.localizedDescription ?? "?")")
        return writer.status == .completed
    }

    /// Ilustração no lugar da câmera no espelho: uma silhueta numa sala com luz quente.
    private static func portrait() -> NSImage? {
        let view = ZStack {
            LinearGradient(colors: [Color(hex: 0xF2D4BC), Color(hex: 0xC8A3CF)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0xFFF1D6).opacity(0.7)).frame(width: 160).blur(radius: 40).offset(x: -170, y: -90)
            Circle().fill(Color(hex: 0x9F7BD0).opacity(0.5)).frame(width: 200).blur(radius: 50).offset(x: 190, y: 60)
            Image(systemName: "person.fill")
                .font(.system(size: 250))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0x4A3A55), Color(hex: 0x2A2233)], startPoint: .top, endPoint: .bottom))
                .offset(y: 70)
        }
        .frame(width: 640, height: 360)
        .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Curvas

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
/// Progresso de `t` entre `a` e `b` (0 antes, 1 depois).
private func span(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
/// Mola amortecida, como as animações da ilha (passa um pouco do ponto e volta).
private func spring(_ x: Double) -> Double { x >= 1 ? 1 : 1 - exp(-7 * x) * cos(9 * x) }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }

// MARK: - Textos

private struct Caption {
    let title: String
    let subtitle: String
}

private struct PromoText {
    let captions: [Caption]
    let youSee: String
    let theySee: String
    let tagline: String
    let requirement: String
    let files: [String]

    static func `for`(_ language: AppLanguage) -> PromoText {
        switch language {
        case .ptBR, .ptPT:
            return PromoText(captions: [
                Caption(title: "Seu notch pode fazer mais.", subtitle: "Conheça a Marquise."),
                Caption(title: "Música e controles, direto no notch.", subtitle: "Passe o mouse e a ilha abre."),
                Caption(title: "Um teleprompter que segue a sua voz.", subtitle: "O texto fica logo abaixo da câmera."),
                Caption(title: "Invisível para quem assiste.", subtitle: "Fora das gravações e do compartilhamento de tela."),
                Caption(title: "Um espelho antes da reunião.", subtitle: language == .ptPT ? "Com o MacBook fechado, usa o iPhone." : "Com o MacBook fechado, usa o iPhone."),
                Caption(title: "Prateleira de arquivos e AirDrop.", subtitle: "Arraste até o notch e solte onde quiser."),
                Caption(title: "Desinstale apps sem deixar rastro.", subtitle: "Tudo vai para o Lixo. Nada é apagado de vez."),
            ], youSee: "Você vê", theySee: "Quem assiste vê",
            tagline: "Grátis e open source para Mac.", requirement: "macOS 14 ou posterior",
            files: ["Apresentação.key", "Contrato.pdf", "Viagem.jpg", "Roteiro.txt"])
        case .es:
            return PromoText(captions: [
                Caption(title: "Tu notch puede hacer más.", subtitle: "Conoce Marquise."),
                Caption(title: "Música y controles, en el notch.", subtitle: "Pasa el ratón y la isla se abre."),
                Caption(title: "Un teleprompter que sigue tu voz.", subtitle: "El texto queda justo debajo de la cámara."),
                Caption(title: "Invisible para quien te ve.", subtitle: "Fuera de las grabaciones y de la pantalla compartida."),
                Caption(title: "Un espejo antes de la reunión.", subtitle: "Con el MacBook cerrado, usa tu iPhone."),
                Caption(title: "Bandeja de archivos y AirDrop.", subtitle: "Arrastra al notch y suelta donde quieras."),
                Caption(title: "Desinstala apps sin dejar rastro.", subtitle: "Todo va a la Papelera. No se borra nada definitivamente."),
            ], youSee: "Tú ves", theySee: "Lo que ven los demás",
            tagline: "Gratis y de código abierto para Mac.", requirement: "macOS 14 o posterior",
            files: ["Presentación.key", "Contrato.pdf", "Viaje.jpg", "Guion.txt"])
        case .enUS, .enGB:
            let bin = language == .enGB ? "Bin" : "Trash"
            return PromoText(captions: [
                Caption(title: "Your notch can do more.", subtitle: "Meet Marquise."),
                Caption(title: "Music and controls, right in the notch.", subtitle: "Hover and the island opens."),
                Caption(title: "A teleprompter that follows your voice.", subtitle: "The text sits right below the camera."),
                Caption(title: "Invisible to your audience.", subtitle: "Hidden from recordings and screen sharing."),
                Caption(title: "A mirror before the meeting.", subtitle: "Lid closed? It uses your iPhone."),
                Caption(title: "A file shelf, with AirDrop.", subtitle: "Drag to the notch, drop anywhere."),
                Caption(title: "Uninstall apps, leave nothing behind.", subtitle: "Everything goes to the \(bin). Nothing is deleted for good."),
            ], youSee: "You see", theySee: "They see",
            tagline: "Free and open source for Mac.", requirement: "macOS 14 or later",
            files: ["Presentation.key", "Contract.pdf", "Trip.jpg", "Script.txt"])
        }
    }
}

// MARK: - Cenas

/// Linha do tempo (segundos):
/// 0–3,5 abertura · 3,5–8 música · 8–13,5 teleprompter · 13,5–16,5 invisível nas gravações ·
/// 16,5–21 espelho · 21–25 prateleira e AirDrop · 25–29 desinstalador · 29–33 encerramento.
@MainActor private final class Scenes {
    let text: PromoText
    static var geometry: NotchGeometry {
        NotchGeometry(hasNotch: true, notchSize: CGSize(width: 185, height: 32),
                      screenFrame: CGRect(origin: .zero, size: Promo.canvas), centerX: Promo.canvas.width / 2)
    }

    let idle: IslandModel
    let closedMusic: IslandModel
    let openMusic: IslandModel
    let prompter: IslandModel
    let mirror: IslandModel
    let mirrorIPhone: IslandModel
    let dropShelf: IslandModel
    let dropAirDrop: IslandModel
    let shelfOpen: IslandModel
    let dropApp: IslandModel
    let uninstaller = Uninstaller()
    let uninstallerDone = Uninstaller()
    let document: NSImage
    let appIcon: NSImage
    let marquiseIcon: NSImage?

    init(language: AppLanguage) {
        text = PromoText.for(language)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("marquise-promo")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Arquivos de exemplo (vazios) para a prateleira mostrar os ícones de cada tipo.
        let files = text.files.map { folder.appendingPathComponent($0) }
        files.forEach { FileManager.default.createFile(atPath: $0.path, contents: Data()) }
        document = NSWorkspace.shared.icon(for: .pdf)

        // App de exemplo "Lumen", com ícone próprio, para a cena do desinstalador.
        let lumen = folder.appendingPathComponent("Lumen.app")
        try? FileManager.default.createDirectory(at: lumen.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let icon = Scenes.lumenIcon()
        NSWorkspace.shared.setIcon(icon, forFile: lumen.path)
        appIcon = icon
        marquiseIcon = NSImage(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Icon/AppIcon-dark.png"))

        func model(_ setup: (IslandModel) -> Void) -> IslandModel {
            let m = IslandModel()
            m.geometry = Scenes.geometry
            setup(m)
            return m
        }
        idle = model { _ in }
        closedMusic = model { $0.media.loadDemo() }
        openMusic = model { $0.media.loadDemo(); $0.isOpen = true }
        prompter = model { m in
            m.prompter.begin()
            m.prompter.toggleRunning()
        }
        mirror = model { $0.mirror.showDemo(.live, camera: nil, lidClosed: false) }
        mirrorIPhone = model { $0.mirror.showDemo(.offerIPhone, camera: "iPhone", lidClosed: true) }
        dropShelf = model { $0.shelfDropMode = true; $0.dropTarget = .shelf }
        dropAirDrop = model { $0.shelfDropMode = true; $0.dropTarget = .airDrop }
        shelfOpen = model { m in
            m.shelf.add(files)
            m.tab = .shelf
            m.isOpen = true
        }
        dropApp = model { m in
            m.shelfDropMode = true
            m.dropApp = lumen
            m.dropTarget = .uninstall
        }
        Uninstaller.demoAppIcon = icon
        uninstaller.showDemo(done: false)
        uninstallerDone.showDemo(done: true, allRemoved: true)
    }

    /// Ícone do app de exemplo: um quadrado arredondado laranja com um "play".
    private static func lumenIcon() -> NSImage {
        let view = ZStack {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFB34D), Color(hex: 0xF0596B)], startPoint: .top, endPoint: .bottom))
                .frame(width: 206, height: 206)
            Image(systemName: "play.fill").font(.system(size: 92, weight: .bold)).foregroundStyle(.white).offset(x: 8)
        }
        .frame(width: 256, height: 256)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage ?? NSImage()
    }

    // MARK: Quadro

    func frame(at t: Double) -> some View {
        update(at: t)
        let endFade = span(t, 28.8, 29.6)
        return ZStack {
            Desktop {
                self.island(at: t)
            }
            overlays(at: t)
            captionView(at: t)
            EndCard(text: text, icon: marquiseIcon, progress: span(t, 29.2, 30.4))
                .opacity(endFade)
        }
        .frame(width: Promo.canvas.width, height: Promo.canvas.height)
        .clipped()
    }

    /// Ponto na tela, em frações da largura e da altura.
    private func from(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Promo.canvas.width * x, y: Promo.canvas.height * y)
    }

    /// Ponto na ilha: `dx` a partir do centro e `y` a partir do topo (antes da ampliação).
    private func onIsland(_ dx: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Promo.canvas.width / 2 + dx * Promo.islandZoom, y: y * Promo.islandZoom)
    }

    /// Valores que mudam a cada quadro: posição da música e do texto do teleprompter.
    private func update(at t: Double) {
        for m in [closedMusic, openMusic] {
            m.media.loadDemo(position: 71 + t)
        }
        // O texto acompanha a "voz": cerca de 3,4 palavras por segundo a partir do início da cena.
        let words = max(0, (t - 8.6) * 3.4)
        let p = prompter.prompter
        let layout = p.layout
        let index = Int(words)
        p.showDemo(spokenThrough: index, status: .listening)
        let a = layout.offset(forWord: index), b = layout.offset(forWord: index + 1)
        p.promoOffset = lerp(a, b, words - Double(index))
    }

    @ViewBuilder private func island(at t: Double) -> some View {
        switch t {
        case ..<1.8: IslandFrame(from: idle, to: idle, progress: 1)
        case ..<3.5: IslandFrame(from: idle, to: closedMusic, progress: span(t, 1.8, 2.5))
        case ..<8.0: IslandFrame(from: closedMusic, to: openMusic, progress: span(t, 3.5, 4.2))
        case ..<13.5: IslandFrame(from: openMusic, to: prompter, progress: span(t, 8.0, 8.7))
        case ..<16.5: IslandFrame(from: prompter, to: prompter, progress: 1)
        case ..<19.0: IslandFrame(from: prompter, to: mirror, progress: span(t, 16.5, 17.2))
        case ..<21.0: IslandFrame(from: mirror, to: mirrorIPhone, progress: span(t, 19.0, 19.5))
        case ..<22.3: IslandFrame(from: mirrorIPhone, to: dropShelf, progress: span(t, 21.2, 21.8))
        case ..<23.2: IslandFrame(from: dropShelf, to: dropAirDrop, progress: span(t, 22.3, 22.5))
        case ..<25.0: IslandFrame(from: dropAirDrop, to: shelfOpen, progress: span(t, 23.2, 23.9))
        case ..<26.2: IslandFrame(from: shelfOpen, to: dropApp, progress: span(t, 25.1, 25.7))
        default: IslandFrame(from: dropApp, to: idle, progress: span(t, 26.2, 26.8))
        }
    }

    @ViewBuilder private func overlays(at t: Double) -> some View {
        // Cursor indo até a ilha para abri-la.
        if t >= 2.6 && t < 4.0 {
            let p = easeInOut(span(t, 2.6, 3.4))
            Cursor()
                .position(from(0.7, 0.49), to: onIsland(40, 24), p)
                .opacity(1 - span(t, 3.7, 4.0))
        }
        // "Invisível": a tela de quem apresenta e a que os outros veem.
        if t >= 13.5 && t < 16.8 {
            HiddenComparison(text: text, island: IslandFrame(from: prompter, to: prompter, progress: 1))
                .opacity(span(t, 13.5, 13.9) * (1 - span(t, 16.3, 16.7)))
        }
        // Arrastando um PDF até o AirDrop.
        if t >= 20.6 && t < 23.4 {
            let p = easeInOut(span(t, 20.6, 22.9))
            DraggedFile(icon: document)
                .position(from(0.22, 0.83), to: onIsland(105, 92), p)
                .opacity(span(t, 20.6, 20.8) * (1 - span(t, 23.0, 23.3)))
        }
        // Arrastando o app até "Desinstalar".
        if t >= 24.6 && t < 26.4 {
            let p = easeInOut(span(t, 24.6, 25.9))
            DraggedFile(icon: appIcon)
                .position(from(0.82, 0.83), to: onIsland(148, 92), p)
                .opacity(span(t, 24.6, 24.8) * (1 - span(t, 26.0, 26.3)))
        }
        // A janela do desinstalador, primeiro com a lista e depois concluída.
        if t >= 26.2 && t < 29.6 {
            let appear = spring(span(t, 26.3, 27.0))
            ZStack {
                UninstallWindow(model: uninstaller).opacity(1 - span(t, 27.9, 28.1))
                UninstallWindow(model: uninstallerDone).opacity(span(t, 27.9, 28.1))
            }
            .scaleEffect((Promo.vertical ? 0.82 : 0.8) * (0.9 + 0.1 * appear))
            .opacity(span(t, 26.3, 26.6))
            .position(x: Promo.canvas.width / 2, y: Promo.vertical ? 830 : 304)
        }
    }

    @ViewBuilder private func captionView(at t: Double) -> some View {
        let windows: [(Double, Double)] = [(0.5, 3.4), (3.9, 8.0), (8.6, 13.4), (13.7, 16.4),
                                          (16.9, 20.9), (21.2, 24.9), (25.2, 28.8)]
        ForEach(Array(windows.enumerated()), id: \.offset) { index, window in
            if t >= window.0 && t < window.1 {
                let p = easeOut(span(t, window.0, window.0 + 0.5)) * (1 - span(t, window.1 - 0.35, window.1))
                // Na cena do desinstalador a janela ocupa o meio: o texto fica embaixo, menor.
                if Promo.vertical {
                    // No vertical o texto fica logo abaixo da ilha, e as demonstrações vão embaixo dele.
                    CaptionView(caption: self.text.captions[index], compact: false)
                        .padding(.horizontal, 40)
                        .opacity(p)
                        .offset(y: 14 * (1 - p))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 370)
                } else {
                    CaptionView(caption: self.text.captions[index], compact: index == 6)
                        .opacity(p)
                        .offset(y: 14 * (1 - p))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, index == 6 ? 18 : 64)
                }
            }
        }
    }
}

// MARK: - Peças

/// A ilha passando de um estado para outro: o formato cresce com mola e o conteúdo troca.
private struct IslandFrame: View {
    let from: IslandModel
    let to: IslandModel
    let progress: Double

    var body: some View {
        let p = spring(progress)
        let size = CGSize(width: lerp(from.currentSize.width, to.currentSize.width, p),
                          height: lerp(from.currentSize.height, to.currentSize.height, p))
        let flare = lerp(from.flare, to.flare, p)
        let radius = lerp(from.isExpanded ? 30 : 11, to.isExpanded ? 30 : 11, p)
        let shape = NotchShape(flare: flare, bottomRadius: radius)
        ZStack(alignment: .top) {
            IslandContent(model: from).opacity(1 - span(progress, 0, 0.35))
            IslandContent(model: to).opacity(span(progress, 0.25, 0.8))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, flare)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(to.isExpanded || from.isExpanded ? 0.5 * p : 0), radius: 20, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// O mesmo conteúdo que a `IslandView` mostra em cada estado.
private struct IslandContent: View {
    let model: IslandModel

    var body: some View {
        if model.mirror.isActive {
            MirrorContent(model: model)
        } else if model.prompter.isActive {
            PrompterContent(model: model, onEdit: {})
                .frame(width: model.prompterSize.width, height: model.prompterSize.height, alignment: .top)
        } else if model.shelfDropMode {
            DropZoneView(model: model)
                .frame(width: model.dropSize.width, height: model.dropSize.height, alignment: .top)
        } else if model.isOpen {
            OpenContent(model: model)
                .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
        } else {
            ClosedContent(model: model)
                .frame(width: model.closedSize.width, height: model.closedSize.height)
        }
    }
}

/// Tela do Mac: papel de parede, barra de menus e a ilha no notch.
private struct Desktop<Island: View>: View {
    @ViewBuilder let island: () -> Island

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x141833), Color(hex: 0x2B1E4A), Color(hex: 0x4A1F45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0x5B6CFF).opacity(0.35)).frame(width: 520).blur(radius: 120).offset(x: -380, y: 260)
            Circle().fill(Color(hex: 0xE0589E).opacity(0.28)).frame(width: 480).blur(radius: 120).offset(x: 420, y: 320)
            MenuBar()
            island().scaleEffect(Promo.islandZoom, anchor: .top)
        }
    }
}

private struct MenuBar: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text("Finder").font(.system(size: 13, weight: .bold))
            Spacer()
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            Image(systemName: "battery.75percent").font(.system(size: 15))
            Text("9:41").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 22)
        .frame(height: 32)
        .background(Color.white.opacity(0.06))
    }
}

private struct CaptionView: View {
    let caption: Caption
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            Text(caption.title)
                .font(.system(size: compact ? 26 : Promo.vertical ? 44 : 40, weight: .bold))
                .foregroundStyle(.white)
            Text(caption.subtitle)
                .font(.system(size: compact ? 15 : Promo.vertical ? 22 : 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.35), radius: 12)
    }
}

private struct Cursor: View {
    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(.black)
            .background(Image(systemName: "cursorarrow").font(.system(size: 26, weight: .black)).foregroundStyle(.white))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

/// Um arquivo sendo arrastado, com o cursor.
private struct DraggedFile: View {
    let icon: NSImage

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 64, height: 64)
                .opacity(0.9)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            Cursor().offset(x: 30, y: 30)
        }
        .frame(width: 90, height: 90)
    }
}

/// Lado a lado: a tela de quem apresenta (com a ilha) e a que aparece na reunião (sem ela).
private struct HiddenComparison: View {
    let text: PromoText
    let island: IslandFrame

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            HStack(spacing: 40) {
                screen(label: text.youSee, symbol: "eye", withIsland: true)
                screen(label: text.theySee, symbol: "eye.slash", withIsland: false)
            }
            .offset(y: Promo.vertical ? 200 : -40)
        }
    }

    private func screen(label: String, symbol: String, withIsland: Bool) -> some View {
        VStack(spacing: 14) {
            Desktop {
                if withIsland { island }
            }
            .frame(width: Promo.canvas.width, height: Promo.canvas.height)
            .scaleEffect(0.42)
            .frame(width: Promo.canvas.width * 0.42, height: Promo.canvas.height * 0.42)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.2)))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            Label(label, systemImage: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// A janela do desinstalador, com barra de título.
private struct UninstallWindow: View {
    let model: Uninstaller

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { Circle().fill(Color(hex: UInt32($0))).frame(width: 12) }
                    Spacer()
                }
                Text(L(.uninstallerTitle)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            UninstallerView(model: model, onClose: {}, scrolls: false)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 600, alignment: .top)
        }
        .frame(width: 600)
        .background(Color(hex: 0xECECEC))
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
    }
}

/// Tela final: ícone, nome, frase e o link.
private struct EndCard: View {
    let text: PromoText
    let icon: NSImage?
    let progress: Double

    var body: some View {
        let p = spring(progress)
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E1024), Color(hex: 0x23153A)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0x8352CC).opacity(0.35)).frame(width: 600).blur(radius: 140)
            VStack(spacing: 18) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 168, height: 168)
                        .scaleEffect(0.8 + 0.2 * p)
                }
                Text("Marquise")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(.white)
                Text(text.tagline)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("github.com/rpissardini-br/Marquise")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xC9B6FF))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .padding(.top, 6)
                Text(text.requirement)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .opacity(span(progress, 0, 0.5))
            .offset(y: 12 * (1 - p))
        }
    }
}

extension MediaController {
    /// A música de exemplo tocando na posição `position` (segundos).
    func loadDemo(position: Double) {
        guard var state = track, let artwork else { return loadDemo() }
        state.position = position
        state.anchor = Date()
        injectDemo(state, artwork: artwork)
    }
}

private extension View {
    /// Posição entre dois pontos, com progresso `p`.
    func position(_ a: CGPoint, to b: CGPoint, _ p: Double) -> some View {
        position(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p))
    }
}
#endif
