import AppKit
import Observation
import SwiftUI

struct ShelfItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Prateleira: guarda referências a arquivos (nada é copiado) até você arrastá-los para o destino.
/// Ao soltar no Finder, ele move no mesmo disco e copia entre discos (segure ⌘ para mover).
@Observable final class Shelf {
    /// Desligado no modo `--snapshot`: não mexe na prateleira salva e troca as views
    /// AppKit/ScrollView (que o ImageRenderer não desenha) por equivalentes estáticos.
    static var persistent = true

    private(set) var items: [ShelfItem] = []
    /// Arrasto saindo da própria prateleira (não deve abrir a área de soltar).
    @ObservationIgnored var isDraggingOut = false
    @ObservationIgnored private var source: ShelfDragSource!

    init() {
        let paths = Self.persistent ? UserDefaults.standard.stringArray(forKey: "shelf.paths") ?? [] : []
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        source = ShelfDragSource(shelf: self)
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
        save()
    }

    func remove(_ ids: Set<URL>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func removeAll() {
        items = []
        save()
    }

    /// Tira da prateleira o que foi apagado ou movido por fora.
    func prune() {
        let before = items.count
        items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        if items.count != before { save() }
    }

    func beginDrag(_ dragged: [ShelfItem], event: NSEvent, from view: NSView) {
        guard !dragged.isEmpty else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let draggingItems = dragged.enumerated().map { index, item -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            draggingItem.setDraggingFrame(
                NSRect(x: point.x - 24 + offset, y: point.y - 24 - offset, width: 48, height: 48),
                contents: NSWorkspace.shared.icon(forFile: item.url.path))
            return draggingItem
        }
        source.draggedIDs = Set(dragged.map(\.id))
        isDraggingOut = true
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    private func save() {
        guard Self.persistent else { return }
        UserDefaults.standard.set(items.map(\.url.path), forKey: "shelf.paths")
    }
}

/// Envia arquivos pelo AirDrop com a janela do próprio macOS (escolha de quem está perto).
enum AirDrop {
    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else {
            NSSound.beep()
            return
        }
        // A Marquise não aparece no Dock: sem ativar, a janela do AirDrop abre atrás dos outros apps.
        NSApp.activate()
        service.perform(withItems: urls)
        shelfLog.notice("AirDrop: \(urls.count, privacy: .public) arquivo(s)")
    }
}

final class ShelfDragSource: NSObject, NSDraggingSource {
    weak var shelf: Shelf?
    var draggedIDs: Set<URL> = []

    init(shelf: Shelf) { self.shelf = shelf }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        shelf?.isDraggingOut = false
        // Entregue no destino: sai da prateleira. Cancelado: continua guardado.
        shelfLog.notice("arrasto para fora terminou; operação=\(operation.rawValue, privacy: .public)")
        if operation != [] { shelf?.remove(draggedIDs) }
        draggedIDs = []
    }
}

// MARK: - Arrasto (AppKit), para saber quando o item foi entregue

final class ShelfDragNSView: NSView {
    var onBegin: (NSEvent, NSView) -> Void = { _, _ in }
    var onDoubleClick: () -> Void = {}
    private var downEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { onDoubleClick() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        downEvent = nil
        onBegin(down, self)
    }

    override func mouseUp(with event: NSEvent) { downEvent = nil }
}

struct ShelfDragArea: NSViewRepresentable {
    let onBegin: (NSEvent, NSView) -> Void
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> ShelfDragNSView { ShelfDragNSView() }

    func updateNSView(_ view: ShelfDragNSView, context: Context) {
        view.onBegin = onBegin
        view.onDoubleClick = onDoubleClick
    }
}

// MARK: - Views

struct ShelfView: View {
    let shelf: Shelf

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24, weight: .medium))
                Text(L(.shelfEmptyTitle))
                    .font(.system(size: 12, weight: .medium))
                Text(L(.shelfEmptySubtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    if shelf.items.count > 1 {
                        DragAllTile(shelf: shelf)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 70).padding(.top, 8)
                    }
                    let row = HStack(spacing: 4) {
                        ForEach(shelf.items) { ShelfItemView(shelf: shelf, item: $0) }
                    }
                    if Shelf.persistent {
                        ScrollView(.horizontal, showsIndicators: false) { row }
                    } else {
                        row
                    }
                }
                HStack(spacing: 12) {
                    Text(L(.shelfHint))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Button { AirDrop.send(shelf.items.map(\.url)) } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.up.forward")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .help(L(.sendAirDrop))
                    Button(L(.clear)) { shelf.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

struct ShelfItemView: View {
    let shelf: Shelf
    let item: ShelfItem

    var body: some View {
        let hoverID = "shelf-\(item.url.path)"
        let hovering = HoverState.shared.id == hoverID
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 70, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay {
            if Shelf.persistent {
                ShelfDragArea(
                    onBegin: { event, view in shelf.beginDrag([item], event: event, from: view) },
                    onDoubleClick: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) })
            }
        }
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { AirDrop.send([item.url]) } label: {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color(white: 0.3)))
                }
                .buttonStyle(.plain)
                .help(L(.sendAirDrop))
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { shelf.remove([item.id]) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                }
                .buttonStyle(.plain)
                .help(L(.removeFromShelf))
            }
        }
        .onHover { HoverState.shared.set(hoverID, $0) }
        .help(item.url.path)
    }
}

struct DragAllTile: View {
    let shelf: Shelf

    var body: some View {
        let icons = shelf.items.prefix(3).map { NSWorkspace.shared.icon(forFile: $0.url.path) }
        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 38, height: 38)
                        .rotationEffect(.degrees(Double(index - 1) * 8))
                        .offset(x: CGFloat(index - 1) * 5)
                }
            }
            .frame(width: 44, height: 44)
            Text(L(.allCount, shelf.items.count))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 70, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
        .overlay {
            if Shelf.persistent {
                ShelfDragArea(onBegin: { event, view in shelf.beginDrag(shelf.items, event: event, from: view) })
            }
        }
        .help(L(.dragAll))
    }
}

/// Área de soltar: guardar na prateleira, mandar por AirDrop e, se for um app, desinstalar.
struct DropZoneView: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            HStack(spacing: 10) {
                ForEach(model.dropActions, id: \.self) { action in
                    DropTile(model: model, action: action, targeted: model.dropTarget == action)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .animation(.easeOut(duration: 0.15), value: model.dropTarget)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.dropActions)
    }
}

struct DropTile: View {
    let model: IslandModel
    let action: DropAction
    let targeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(targeted ? 0.1 : 0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(targeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .overlay(VStack(spacing: 5) {
                icon.frame(height: 28)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .foregroundStyle(.white))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    @ViewBuilder private var icon: some View {
        switch action {
        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
        case .airDrop:
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
        case .uninstall:
            if let app = model.dropApp {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.red)
                            .offset(x: 3, y: 3)
                    }
                    .scaleEffect(targeted ? 1.1 : 1)
            }
        }
    }

    private var title: String {
        switch action {
        case .shelf: L(.dropShelf)
        case .airDrop: "AirDrop"
        case .uninstall: L(.dropUninstall)
        }
    }

    private var subtitle: String {
        switch action {
        case .shelf:
            let count = model.shelf.items.count
            return count == 0 ? L(.dropShelfHint) : count == 1 ? L(.oneItemKept) : L(.itemsKept, count)
        case .airDrop:
            return L(.airDropHint)
        case .uninstall:
            return model.dropApp?.deletingPathExtension().lastPathComponent ?? ""
        }
    }
}
