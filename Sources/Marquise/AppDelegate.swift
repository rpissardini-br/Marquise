import AppKit
import Carbon.HIToolbox
import os
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // A janela precisa ficar sobre a barra de menus / o notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let shelfLog = Logger(subsystem: "com.marquise.app", category: "shelf")

/// View de fundo da ilha que recebe os arquivos soltos (a interface SwiftUI fica por cima).
final class DropTargetView: NSView {
    var acceptsDrop: () -> Bool = { false }
    /// O que está sendo arrastado (lido quando o arrasto entra na ilha).
    var onDragContents: ([URL]) -> Void = { _ in }
    var onDropTargetChange: (Bool) -> Void = { _ in }
    var onDropFiles: ([URL]) -> Bool = { _ in false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrop() else {
            onDropTargetChange(false)
            return []
        }
        onDropTargetChange(true)
        // A Marquise só guarda a referência; nada é copiado ou movido ao soltar aqui.
        let mask = sender.draggingSourceOperationMask
        if mask.contains(.generic) { return .generic }
        if mask.contains(.link) { return .link }
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragContents(sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
        let operation = dropOperation(sender)
        shelfLog.notice("draggingEntered: aceita=\(operation != [], privacy: .public)")
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        shelfLog.notice("draggingExited")
        onDropTargetChange(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { acceptsDrop() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        shelfLog.notice("performDragOperation: \(urls.count, privacy: .public) arquivo(s)")
        onDropTargetChange(false)
        return onDropFiles(urls)
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = IslandModel()
    private var panel: IslandPanel!
    private var editorWindow: NSWindow?
    private var uninstallerWindow: NSWindow?
    private var hotKeys: HotKeys?
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var trackTimer: Timer?
    private var refreshTimer: Timer?
    private var menuIsOpen = false
    private var dragPollTimer: Timer?
    private var dragChangeCount = 0
    private var fileDragActive = false
    /// `--open` mantém a ilha expandida (útil para testar o layout).
    private let pinnedOpen = CommandLine.arguments.contains("--open")

    private var prompter: Teleprompter { model.prompter }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let language = args.dropFirst(i + 2).first.flatMap(AppLanguage.init(rawValue:)) ?? .ptBR
            MainActor.assumeIsolated { Snapshot.run(into: args[i + 1], language: language) }
            exit(0)
        }
        // `--leftovers <app>` mostra o que o desinstalador encontraria, sem mexer em nada.
        if let i = args.firstIndex(of: "--leftovers"), i + 1 < args.count {
            exit(LeftoverScanner.printReport(for: URL(fileURLWithPath: args[i + 1])))
        }

        panel = IslandPanel()
        let host = FirstMouseHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        let dropTarget = DropTargetView(frame: .zero)
        host.frame = dropTarget.bounds
        host.autoresizingMask = [.width, .height]
        dropTarget.addSubview(host)
        panel.contentView = dropTarget
        dropTarget.acceptsDrop = { [weak self] in
            guard let self else { return false }
            return self.model.shelfDropMode && self.model.hitRect.contains(NSEvent.mouseLocation)
        }
        dropTarget.onDragContents = { [weak self] urls in
            let app = urls.count == 1 && urls[0].pathExtension == "app" ? urls[0] : nil
            if self?.model.dropApp != app { self?.model.dropApp = app }
        }
        dropTarget.onDropTargetChange = { [weak self] targeted in
            guard let self else { return }
            let target = targeted ? self.model.dropAction(atX: NSEvent.mouseLocation.x) : nil
            if self.model.dropTarget != target { self.model.dropTarget = target }
        }
        dropTarget.onDropFiles = { [weak self] urls in
            guard let self else { return false }
            return self.received(urls, action: self.model.dropAction(atX: NSEvent.mouseLocation.x))
        }
        applyCaptureVisibility()
        layoutPanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.mouseMoved()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] e in
            self?.mouseMoved()
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            self?.mouseDown(e) ?? e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.closeMirrorIfOutside()
            self?.watchForFileDrag()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            self?.scrolled(e) ?? e
        }) { monitors.append(m) }

        model.showPrompterEditor = { [weak self] in self?.showEditor() }
        model.showOptionsMenu = { [weak self] in self?.showMenu() }
        Localization.shared.onChange = { [weak self] in
            self?.prompter.languageChanged()
            self?.installEditMenu()
        }
        installEditMenu()
        prompter.onActiveChange = { [weak self] in self?.prompterChanged() }
        model.mirror.onActiveChange = { [weak self] in self?.mirrorChanged() }
        prompter.onCaptureVisibilityChange = { [weak self] in self?.applyCaptureVisibility() }
        registerHotKeys()

        model.volume.start()
        model.media.start()

        if pinnedOpen { open() }
        // `--mirror` abre o espelho ao iniciar (útil para testar a câmera).
        if args.contains("--mirror") { model.mirror.start() }
    }

    // MARK: - Posicionamento

    private func targetScreen() -> NSScreen? {
        // A primeira tela da lista é a principal (a da barra de menus), não a da janela ativa.
        let main = NSScreen.screens.first
        switch IslandScreen.current {
        case .main: return main
        case .notch: return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? main
        }
    }

    private func layoutPanel() {
        guard let screen = targetScreen() else { return }
        model.geometry = NotchGeometry(screen: screen)
        let size = CGSize(width: 760, height: 340)
        panel.setFrame(
            CGRect(x: model.geometry.centerX - size.width / 2,
                   y: screen.frame.maxY - size.height,
                   width: size.width, height: size.height),
            display: true)
    }

    @objc private func screensChanged() {
        layoutPanel()
        panel.orderFrontRegardless()
    }

    @objc private func spaceChanged() {
        panel.orderFrontRegardless()
    }

    // MARK: - Mouse

    private func mouseMoved() {
        guard !menuIsOpen, !model.shelfDropMode else { return }
        let inside = model.hitRect.contains(NSEvent.mouseLocation)

        // No espelho e no teleprompter a ilha fica fixa; só recebe cliques quando o cursor está sobre ela.
        if model.mirror.isActive {
            panel.ignoresMouseEvents = !inside
            return
        }
        if prompter.isActive {
            panel.ignoresMouseEvents = !inside
            if prompter.hovering != inside { prompter.hovering = inside }
            return
        }
        guard !pinnedOpen else { return }

        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !model.isOpen && openWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.openWork = nil
                    if self.model.hitRect.contains(NSEvent.mouseLocation) { self.open() }
                }
                openWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
        } else {
            openWork?.cancel()
            openWork = nil
            if model.isOpen && closeWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.closeWork = nil
                    self?.close()
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        }
    }

    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, model.isExpanded else { return event }
        guard model.hitRect.contains(NSEvent.mouseLocation) else {
            closeMirrorIfOutside()
            close()
            return event
        }
        if event.type == .rightMouseDown {
            showMenu()
            return nil
        }
        return event
    }

    private func scrolled(_ event: NSEvent) -> NSEvent? {
        guard prompter.isActive, !model.mirror.isActive, event.window === panel || model.hitRect.contains(NSEvent.mouseLocation)
        else { return event }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        prompter.nudge(by: -delta)
        return nil
    }

    private func open() {
        guard !model.isOpen, !model.mirror.isActive, !prompter.isActive else { return }
        model.isOpen = true
        panel.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        model.shelf.prune()
        model.media.refreshAll()
        startTracking()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.media.refreshAll() }
    }

    private func close() {
        guard model.isOpen, !pinnedOpen else { return }
        model.isOpen = false
        panel.ignoresMouseEvents = true
        stopTracking()
        refreshTimer?.invalidate()
    }

    private func startTracking() {
        guard trackTimer == nil else { return }
        trackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.mouseMoved() }
    }

    private func stopTracking() {
        trackTimer?.invalidate()
        trackTimer = nil
    }

    // MARK: - Prateleira (arrastar e soltar)

    /// Enquanto o botão do mouse está pressionado em outro app, verifica se começou
    /// um arrasto de arquivos e se ele chegou perto da ilha.
    private func watchForFileDrag() {
        guard dragPollTimer == nil else { return }
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        fileDragActive = false
        dragPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.pollFileDrag() }
        RunLoop.main.add(timer, forMode: .common)
        dragPollTimer = timer
    }

    private func pollFileDrag() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            dragPollTimer?.invalidate()
            dragPollTimer = nil
            fileDragActive = false
            // O "soltar" chega logo depois do botão ser solto.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.leaveDropMode() }
            return
        }
        if !fileDragActive {
            // Um arrasto (de arquivo, texto…) começou quando o "pasteboard de arrasto" muda.
            // Não depende de ler o conteúdo: o macOS pode restringir essa leitura em segundo plano.
            // Se não for arquivo, a área de soltar simplesmente não aceita.
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragChangeCount, !model.shelf.isDraggingOut, !prompter.isActive,
                  !model.mirror.isActive
            else { return }
            fileDragActive = true
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "ilegível"
            shelfLog.notice("arrasto detectado; tipos: \(types, privacy: .public)")
        }
        // Depois de aberta, a área só fecha quando o cursor sai das duas zonas (evita piscar na borda).
        let zone = model.shelfDropMode ? model.dropZoneRect.union(model.hitRect) : model.dropZoneRect
        let near = zone.contains(NSEvent.mouseLocation)
        if near && !model.shelfDropMode {
            enterDropMode()
        } else if !near && model.shelfDropMode {
            leaveDropMode()
        }
    }

    private func enterDropMode() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        if model.isOpen {
            model.isOpen = false
            stopTracking()
            refreshTimer?.invalidate()
        }
        model.shelfDropMode = true
        panel.ignoresMouseEvents = false
        shelfLog.notice("área de soltar aberta")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func leaveDropMode() {
        guard model.shelfDropMode else { return }
        model.shelfDropMode = false
        model.dropTarget = nil
        model.dropApp = nil
        if !model.isOpen && !prompter.isActive { panel.ignoresMouseEvents = true }
    }

    private func received(_ urls: [URL], action: DropAction) -> Bool {
        // Só a quantidade: nomes de arquivos não vão para o log do sistema.
        shelfLog.notice("recebido(s): \(urls.count, privacy: .public) arquivo(s), ação=\(String(describing: action), privacy: .public)")
        guard !urls.isEmpty else { return false }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        switch action {
        case .shelf:
            model.shelf.add(urls)
            model.tab = .shelf
            model.shelfDropMode = false
            model.dropTarget = nil
            model.dropApp = nil
            open()
        case .airDrop:
            leaveDropMode()
            // Depois do arrasto terminar, senão a janela do AirDrop abre com o arrasto ainda em curso.
            DispatchQueue.main.async { AirDrop.send(urls) }
        case .uninstall:
            leaveDropMode()
            DispatchQueue.main.async { [weak self] in self?.showUninstaller(urls[0]) }
        }
        return true
    }

    // MARK: - Desinstalador

    private func showUninstaller(_ app: URL) {
        let uninstaller = Uninstaller()
        let window = uninstallerWindow ?? {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center()
            uninstallerWindow = window
            return window
        }()
        window.title = L(.uninstallerTitle)
        window.contentView = NSHostingView(rootView: UninstallerView(
            model: uninstaller, onClose: { [weak window] in window?.close() })
            .environment(\.locale, Localization.shared.locale))
        uninstaller.load(app)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func uninstallMenuItem() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.treatsFilePackagesAsDirectories = false
        panel.message = L(.chooseAppToUninstall)
        panel.prompt = L(.dropUninstall)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        showUninstaller(url)
    }

    // MARK: - Teleprompter

    private func applyCaptureVisibility() {
        let sharing: NSWindow.SharingType = prompter.hiddenFromCapture ? .none : .readOnly
        panel.sharingType = sharing
        editorWindow?.sharingType = sharing
    }

    private func prompterChanged() {
        if prompter.isActive { model.mirror.stop() }
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        refreshTimer?.invalidate()
        model.isOpen = false

        if prompter.isActive {
            startTracking()
            mouseMoved()
        } else {
            stopTracking()
            panel.ignoresMouseEvents = true
        }
    }

    // MARK: - Espelho

    private func mirrorChanged() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        refreshTimer?.invalidate()
        model.isOpen = false

        if model.mirror.isActive {
            // O teleprompter fica por baixo, pausado, e volta quando o espelho fecha.
            if prompter.isRunning { prompter.toggleRunning() }
            startTracking()
            mouseMoved()
        } else if prompter.isActive {
            mouseMoved()
        } else {
            stopTracking()
            panel.ignoresMouseEvents = true
        }
    }

    /// Um clique fora da ilha fecha o espelho, como um popover.
    private func closeMirrorIfOutside() {
        guard model.mirror.isActive, !model.hitRect.contains(NSEvent.mouseLocation) else { return }
        model.mirror.stop()
    }

    private func startPrompter() {
        editorWindow?.close()
        NSApp.deactivate()
        if prompter.isActive { prompter.restart() } else { prompter.begin() }
    }

    private func showEditor() {
        if prompter.isRunning { prompter.toggleRunning() }
        if editorWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "Teleprompter"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PrompterEditorView(
                prompter: prompter, onStart: { [weak self] in self?.startPrompter() }))
            window.center()
            editorWindow = window
            applyCaptureVisibility()
        }
        NSApp.activate()
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    private func togglePrompter() {
        if prompter.isActive {
            prompter.end()
        } else if prompter.isEmpty {
            showEditor()
        } else {
            prompter.begin()
        }
    }

    private func registerHotKeys() {
        let keys = HotKeys()
        let mods = controlKey | optionKey
        keys.register(keyCode: kVK_ANSI_T, modifiers: mods) { [weak self] in self?.togglePrompter() }
        keys.register(keyCode: kVK_Space, modifiers: mods) { [weak self] in
            guard let self, self.prompter.isActive else { return }
            self.prompter.toggleRunning()
        }
        keys.register(keyCode: kVK_UpArrow, modifiers: mods) { [weak self] in self?.prompter.adjustSpeed(by: 10) }
        keys.register(keyCode: kVK_DownArrow, modifiers: mods) { [weak self] in self?.prompter.adjustSpeed(by: -10) }
        keys.register(keyCode: kVK_ANSI_M, modifiers: mods) { [weak self] in self?.model.mirror.toggle() }
        hotKeys = keys
    }

    // MARK: - Menu Editar

    /// A Marquise não mostra barra de menus, mas os atalhos ⌘C, ⌘V, ⌘X, ⌘A e ⌘Z do macOS
    /// passam pelo menu Editar do app. Sem ele, copiar e colar não chegam à janela do roteiro.
    private func installEditMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L(.closeWindow), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: L(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: L(.edit))
        edit.addItem(withTitle: L(.undo), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L(.redo), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L(.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L(.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L(.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L(.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: L(.edit), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: - Menu

    /// Menu de opções: aberto pelo clique direito ou pela engrenagem da ilha.
    private func showMenu() {
        guard let view = panel.contentView else { return }
        let menu = NSMenu()
        let prompterItem = NSMenuItem(
            title: prompter.isActive ? L(.closePrompter) : L(.menuTeleprompter),
            action: #selector(prompterMenuItem), keyEquivalent: "")
        prompterItem.target = self
        menu.addItem(prompterItem)
        let mirrorItem = NSMenuItem(
            title: model.mirror.isActive ? L(.closeMirror) : L(.cameraMirror),
            action: #selector(mirrorMenuItem), keyEquivalent: "")
        mirrorItem.target = self
        menu.addItem(mirrorItem)
        let uninstallItem = NSMenuItem(title: L(.menuUninstall), action: #selector(uninstallMenuItem), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)
        menu.addItem(.separator())

        let languageMenu = NSMenu()
        let localization = Localization.shared
        let automatic = NSMenuItem(
            title: L(.automatic, AppLanguage.detect().nativeName),
            action: #selector(chooseLanguage(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.state = localization.choice == nil ? .on : .off
        languageMenu.addItem(automatic)
        languageMenu.addItem(.separator())
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.nativeName, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = localization.choice == language ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: L(.language), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let screenMenu = NSMenu()
        for (choice, title) in [(IslandScreen.main, L(.screenMain)), (.notch, L(.screenNotch))] {
            let item = NSMenuItem(title: title, action: #selector(chooseScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = IslandScreen.current == choice ? .on : .off
            screenMenu.addItem(item)
        }
        let screenItem = NSMenuItem(title: L(.islandScreen), action: nil, keyEquivalent: "")
        screenItem.submenu = screenMenu
        menu.addItem(screenItem)

        let login = NSMenuItem(title: L(.openAtLogin), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L(.quit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menuIsOpen = true
        menu.popUp(positioning: nil, at: view.convert(panel.mouseLocationOutsideOfEventStream, from: nil), in: view)
        menuIsOpen = false
        mouseMoved()
    }

    @objc private func chooseLanguage(_ item: NSMenuItem) {
        Localization.shared.choice = (item.representedObject as? String).flatMap(AppLanguage.init(rawValue:))
    }

    @objc private func chooseScreen(_ item: NSMenuItem) {
        guard let choice = (item.representedObject as? String).flatMap(IslandScreen.init(rawValue:)) else { return }
        IslandScreen.current = choice
        layoutPanel()
        panel.orderFrontRegardless()
    }

    @objc private func mirrorMenuItem() {
        model.mirror.toggle()
    }

    @objc private func prompterMenuItem() {
        if prompter.isActive { prompter.end() } else { showEditor() }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Marquise: não foi possível alterar o item de início: \(error)")
            NSSound.beep()
        }
    }
}
