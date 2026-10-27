// Desenha o ícone da Marquise e gera Resources/AppIcon.icns.
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

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Corpo no grid de ícones do macOS: 824 px com margem de 100 px.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    // Sombra do ícone sobre a mesa.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.35)
    drop.shadowBlurRadius = 28
    drop.shadowOffset = NSSize(width: 0, height: -12)
    drop.set()
    color(0x3A3F9E).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Fundo: o mesmo degradê azul-violeta das telas da Marquise.
    NSGradient(colors: [color(0x4757D8), color(0x7A4FC4), color(0xD0548F)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -60)
    // Brilho suave vindo de cima.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // A ilha, presa à borda de cima.
    let island = CGRect(x: canvas / 2 - 226, y: body.maxY - 410, width: 452, height: 410)
    let islandShape = islandPath(in: island, flare: 34, bottomRadius: 150)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    glow.shadowBlurRadius = 40
    glow.shadowOffset = NSSize(width: 0, height: -18)
    glow.set()
    color(0x050507).setFill()
    islandShape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Câmera no topo da ilha.
    let lensCenter = CGPoint(x: canvas / 2, y: body.maxY - 58)
    color(0x1D1E26).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x - 19, y: lensCenter.y - 19, width: 38, height: 38)).fill()
    color(0x3B4A78).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x - 9, y: lensCenter.y - 9, width: 18, height: 18)).fill()
    // Luz verde: a câmera do espelho.
    color(0x34D399).setFill()
    NSBezierPath(ovalIn: CGRect(x: lensCenter.x + 36, y: lensCenter.y - 7, width: 14, height: 14)).fill()

    // Linhas do teleprompter: a atual em destaque, as seguintes se apagando.
    let lines: [(width: CGFloat, alpha: CGFloat)] = [(318, 1), (258, 0.42), (176, 0.2)]
    var y = body.maxY - 168
    for line in lines {
        NSColor.white.withAlphaComponent(line.alpha).setFill()
        NSBezierPath(roundedRect: CGRect(x: canvas / 2 - line.width / 2, y: y - 18, width: line.width, height: 36),
                     xRadius: 18, yRadius: 18).fill()
        y -= 70
    }

    // Borda interna fina, como vidro.
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 185, yRadius: 185)
    rim.lineWidth = 3
    rim.stroke()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDir = root.appendingPathComponent("Icon")
let master = iconDir.appendingPathComponent("AppIcon.png")
try! drawIcon().representation(using: .png, properties: [:])!.write(to: master)

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
