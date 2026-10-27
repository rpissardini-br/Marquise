// Desenha o ícone da Marquise (claro e escuro) e gera Resources/AppIcon.icns.
// Uso: swift Icon/make-icon.swift   (na pasta do projeto)
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Mesmo formato da ilha no app: topo reto com abas côncavas e cantos inferiores arredondados.
func islandPath(in r: CGRect, flare f: CGFloat, bottomRadius b: CGFloat) -> NSBezierPath {
    // Coordenadas do AppKit: y cresce para cima, então o "topo" é maxY.
    let p = NSBezierPath()
    p.move(to: CGPoint(x: r.minX, y: r.maxY))
    p.curve(to: CGPoint(x: r.minX + f, y: r.maxY - f),
            controlPoint1: CGPoint(x: r.minX + f * 0.55, y: r.maxY),
            controlPoint2: CGPoint(x: r.minX + f, y: r.maxY - f * 0.45))
    p.line(to: CGPoint(x: r.minX + f, y: r.minY + b))
    p.curve(to: CGPoint(x: r.minX + f + b, y: r.minY),
            controlPoint1: CGPoint(x: r.minX + f, y: r.minY + b * 0.45),
            controlPoint2: CGPoint(x: r.minX + f + b * 0.45, y: r.minY))
    p.line(to: CGPoint(x: r.maxX - f - b, y: r.minY))
    p.curve(to: CGPoint(x: r.maxX - f, y: r.minY + b),
            controlPoint1: CGPoint(x: r.maxX - f - b * 0.45, y: r.minY),
            controlPoint2: CGPoint(x: r.maxX - f, y: r.minY + b * 0.45))
    p.line(to: CGPoint(x: r.maxX - f, y: r.maxY - f))
    p.curve(to: CGPoint(x: r.maxX, y: r.maxY),
            controlPoint1: CGPoint(x: r.maxX - f, y: r.maxY - f * 0.45),
            controlPoint2: CGPoint(x: r.maxX - f * 0.55, y: r.maxY))
    p.close()
    return p
}

/// O ícone é uma tela de Mac: moldura preta, a tela com o degradê da marca e a ilha descendo da
/// moldura como o notch de verdade. `dark`: versão do modo escuro (padrão do macOS 27), com a
/// tela mais profunda para combinar com os ícones escuros do sistema.
/// `fullBleed`: arte de borda a borda, sem margem, cantos nem sombra, para o formato do
/// Icon Composer (o macOS aplica o formato, o vidro e a sombra dele).
func drawIcon(dark: Bool = false, fullBleed: Bool = false) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Corpo no grid de ícones do macOS: 824 px com margem de 100 px.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    let bezel: UInt32 = 0x08080A

    if fullBleed {
        // O corpo de 824 px passa a ocupar a tela toda; os cantos ficam com a cor da moldura.
        color(bezel).setFill()
        CGRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        let transform = NSAffineTransform()
        transform.scale(by: canvas / body.width)
        transform.translateX(by: -body.minX, yBy: -body.minY)
        transform.concat()
    }

    // Sombra do ícone sobre a mesa.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(fullBleed ? 0 : 0.35)
    drop.shadowBlurRadius = 28
    drop.shadowOffset = NSSize(width: 0, height: -12)
    drop.set()
    color(bezel).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Moldura: vidro preto, um pouco mais claro no alto.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x232326), color(bezel)])!.draw(in: body, angle: -90)

    // A tela, dentro da moldura.
    let screen = body.insetBy(dx: 54, dy: 54)
    let screenShape = NSBezierPath(roundedRect: screen, xRadius: 134, yRadius: 134)
    NSGraphicsContext.saveGraphicsState()
    screenShape.addClip()
    let colors = dark ? [color(0x34409E), color(0x55358F), color(0x8E3463)]
                      : [color(0x4F60E0), color(0x8352CC), color(0xD8589A)]
    NSGradient(colors: colors, atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: screen, angle: -60)
    // Reflexo de vidro na metade de cima da tela.
    NSGradient(colors: [NSColor.white.withAlphaComponent(dark ? 0.10 : 0.20), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2), angle: -90)

    // A ilha desce da moldura, da mesma cor, como o notch.
    let island = CGRect(x: canvas / 2 - 196, y: screen.maxY - 350, width: 392, height: 350)
    let islandShape = islandPath(in: island, flare: 30, bottomRadius: 130)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.40)
    glow.shadowBlurRadius = 36
    glow.shadowOffset = NSSize(width: 0, height: -14)
    glow.set()
    color(bezel).setFill()
    islandShape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    // Câmera no notch, logo abaixo da moldura.
    let lensCenter = CGPoint(x: canvas / 2, y: screen.maxY - 38)
    color(0x1D1E26).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x - 17, y: lensCenter.y - 17, width: 34, height: 34)).fill()
    color(0x3B4A78).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x - 8, y: lensCenter.y - 8, width: 16, height: 16)).fill()
    // Luz verde: a câmera do espelho.
    color(0x34D399).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x + 32, y: lensCenter.y - 6, width: 12, height: 12)).fill()

    // Linhas do teleprompter: a atual em destaque, as seguintes se apagando.
    let lines: [(width: CGFloat, alpha: CGFloat)] = [(276, 1), (224, 0.42), (152, 0.2)]
    var y = screen.maxY - 128
    for line in lines {
        NSColor.white.withAlphaComponent(line.alpha).setFill()
        NSBezierPath(roundedRect: CGRect(x: canvas / 2 - line.width / 2, y: y - 16, width: line.width, height: 32),
                     xRadius: 16, yRadius: 16).fill()
        y -= 62
    }
    NSGraphicsContext.restoreGraphicsState()

    // Borda de fora, como o alumínio da tampa do Mac (no Icon Composer, o macOS desenha a dele).
    guard !fullBleed else { return rep }
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    edge.lineWidth = 4
    (dark ? NSColor.white.withAlphaComponent(0.14) : color(0x9A9AA0, 0.9)).setStroke()
    edge.stroke()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = root.appendingPathComponent("Icon")
let master = iconDir.appendingPathComponent("AppIcon.png")
try! drawIcon().representation(using: .png, properties: [:])!.write(to: master)
try! drawIcon(dark: true).representation(using: .png, properties: [:])!
    .write(to: iconDir.appendingPathComponent("AppIcon-dark.png"))

// Ícone do macOS 26+ (Icon Composer): uma camada clara e uma escura, trocadas pelo sistema.
let assets = iconDir.appendingPathComponent("Marquise.icon/Assets")
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try! drawIcon(fullBleed: true).representation(using: .png, properties: [:])!
    .write(to: assets.appendingPathComponent("Marquise.png"))
try! drawIcon(dark: true, fullBleed: true).representation(using: .png, properties: [:])!
    .write(to: assets.appendingPathComponent("Marquise-dark.png"))

// Tamanhos que o macOS usa (Finder, Dock, Spotlight…), empacotados num .icns.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let source = NSImage(contentsOf: master)!
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Pronto: \(master.path) e \(icns.path)" : "iconutil falhou")
