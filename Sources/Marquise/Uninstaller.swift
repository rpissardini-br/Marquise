import AppKit
import Observation
import os

let uninstallLog = Logger(subsystem: "com.marquise.app", category: "uninstaller")

/// O app escolhido para desinstalar, lido do Info.plist dele.
struct AppBundle {
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    let executable: String?
    /// Nomes de pasta que podem ser deste app: o nome do arquivo, o nome e o nome exibido.
    let folderNames: [String]
}

enum UninstallRefusal: Error, Equatable {
    case appleApp, marquise, noBundleID
    /// Faz parte de outro app (nome do app de fora).
    case insideApp(String)

    var message: String {
        switch self {
        case .appleApp: L(.refusedApple)
        case .marquise: L(.refusedSelf)
        case .noBundleID: L(.refusedNoID)
        case .insideApp(let outer): L(.refusedInside, outer)
        }
    }
}

extension AppBundle {
    static func load(_ url: URL) -> Result<AppBundle, UninstallRefusal> {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        if url.path.hasPrefix("/System/") { return .failure(.appleApp) }
        if let outer = url.deletingLastPathComponent().pathComponents.last(where: { $0.hasSuffix(".app") }) {
            return .failure(.insideApp((outer as NSString).deletingPathExtension))
        }
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let id = info["CFBundleIdentifier"] as? String,
              id.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
        else { return .failure(.noBundleID) }
        if id.lowercased().hasPrefix("com.apple.") { return .failure(.appleApp) }
        if [Bundle.main.bundleIdentifier, "com.marquise.app"].contains(where: { id.caseInsensitiveCompare($0 ?? "") == .orderedSame }) {
            return .failure(.marquise)
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        var names: [String] = []
        for name in [fileName, info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String] {
            guard let name, !name.isEmpty, !name.contains("/"), name != ".", name != "..",
                  !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
            else { continue }
            names.append(name)
        }
        return .success(AppBundle(
            url: url, name: (info["CFBundleDisplayName"] as? String) ?? fileName, bundleID: id,
            version: info["CFBundleShortVersionString"] as? String,
            executable: info["CFBundleExecutable"] as? String, folderNames: names))
    }
}

enum LeftoverKind: Int, CaseIterable, Comparable {
    case app, support, containers, caches, preferences, logs, launchItems

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .app: L(.kindApp)
        case .support: L(.kindSupport)
        case .containers: L(.kindContainers)
        case .caches: L(.kindCaches)
        case .preferences: L(.kindPreferences)
        case .logs: L(.kindLogs)
        case .launchItems: L(.kindLaunch)
        }
    }
}

struct Leftover: Identifiable, Hashable {
    let url: URL
    let kind: LeftoverKind
    var size: Int64 = 0
    /// A pasta onde está não é sua: o macOS vai pedir a senha de administrador.
    var needsAdmin = false
    var id: URL { url }
}

/// Procura o que um app deixa na Biblioteca. As regras são conservadoras: na dúvida, o item fica de fora.
/// - Só olha pastas conhecidas da Biblioteca (a sua e a do sistema), nunca o disco inteiro.
/// - O nome tem que ser o identificador do app (com.empresa.app) ou o nome exato dele; nada de "contém".
/// - "com.empresa.app.algo" só conta se não for o identificador de outro app instalado
///   (com.google.Chrome.canary não é do com.google.Chrome).
/// - Nomes curtos, de fabricante ("Google", "Adobe") ou iguais aos de outro app não contam.
/// - Itens que abrem sozinhos (LaunchAgents) contam pelo identificador ou quando apontam para dentro do app.
enum LeftoverScanner {
    private static let vendorNames: Set<String> = [
        "apple", "google", "microsoft", "adobe", "mozilla", "jetbrains", "oracle", "autodesk", "unity",
        "app", "apps", "helper", "updater", "installer", "uninstaller", "setup", "data", "cache", "caches", "logs",
    ]

    static func scan(_ app: AppBundle) -> [Leftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let local = URL(fileURLWithPath: "/Library")
        let id = app.bundleID.lowercased()
        let installed = installedApps().filter { $0.id.lowercased() != id }
        let otherIDs = installed.map { $0.id.lowercased() }
        let otherNames = Set(installed.flatMap(\.names).map { $0.lowercased() })
        let names = app.folderNames.map { $0.lowercased() }
            .filter { $0.count >= 3 && !vendorNames.contains($0) && !otherNames.contains($0) }
        // com.empresa.app.algo só vale com pelo menos três partes (com.empresa sozinho seria a empresa toda).
        let allowsSuffix = id.split(separator: ".").count >= 3
        var found: [URL: LeftoverKind] = [:]

        func children(_ dir: URL) -> [String] { (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] }

        func isOurs(_ stem: String) -> Bool {
            let stem = stem.lowercased()
            if stem == id { return true }
            guard allowsSuffix, stem.hasPrefix(id + ".") else { return false }
            if otherIDs.contains(where: { $0.count > id.count && (stem == $0 || stem.hasPrefix($0 + ".")) }) { return false }
            // Também pergunta ao macOS, que conhece apps fora da pasta Aplicativos.
            var parts = stem.split(separator: ".").map(String.init)
            while parts.count > id.split(separator: ".").count {
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) != nil { return false }
                parts.removeLast()
            }
            return true
        }
        /// Nome com o identificador, seguido de uma das terminações (vazia = pasta ou arquivo com o nome exato).
        func byID(_ endings: [String] = [""]) -> (String) -> Bool {
            { child in
                endings.contains { ending in
                    child.lowercased().hasSuffix(ending.lowercased()) && isOurs(String(child.dropLast(ending.count)))
                }
            }
        }
        func byName(_ child: String) -> Bool { names.contains(child.lowercased()) }

        func look(_ dir: URL, _ kind: LeftoverKind, _ matches: (String) -> Bool) {
            for child in children(dir) where matches(child) {
                found[dir.appendingPathComponent(child)] = kind
            }
        }

        for lib in [home, local] {
            look(lib.appendingPathComponent("Application Support"), .support) { byID()($0) || byName($0) }
            look(lib.appendingPathComponent("Caches"), .caches) { byID()($0) || byName($0) }
            look(lib.appendingPathComponent("Logs"), .logs) { byID()($0) || byName($0) }
            look(lib.appendingPathComponent("Preferences"), .preferences, byID([".plist"]))
            look(lib.appendingPathComponent("WebKit"), .caches, byID())
            look(lib.appendingPathComponent("HTTPStorages"), .caches, byID())
        }
        look(home.appendingPathComponent("Preferences/ByHost"), .preferences) { child in
            // com.empresa.app.<identificador do Mac>.plist
            guard child.hasSuffix(".plist") else { return false }
            let stem = (String(child.dropLast(6)) as NSString).deletingPathExtension
            return stem.lowercased() == id
        }
        look(home.appendingPathComponent("Saved Application State"), .preferences, byID([".savedState"]))
        look(home.appendingPathComponent("Containers"), .containers, byID())
        // Grupos: group.com.empresa.app ou EQUIPE.com.empresa.app, nunca os da empresa toda.
        look(home.appendingPathComponent("Group Containers"), .containers) { $0.lowercased().hasSuffix("." + id) }
        look(home.appendingPathComponent("Application Scripts"), .support, byID())
        look(home.appendingPathComponent("Cookies"), .caches, byID([".binarycookies"]))
        if let exe = app.executable, exe.count >= 3 {
            look(home.appendingPathComponent("Logs/DiagnosticReports"), .logs) { child in
                [".ips", ".crash", ".diag", ".hang", ".spin"].contains { child.hasSuffix($0) }
                    && (child.hasPrefix(exe + "-") || child.hasPrefix(exe + "_"))
            }
        }

        for dir in [home.appendingPathComponent("LaunchAgents"), local.appendingPathComponent("LaunchAgents"),
                    local.appendingPathComponent("LaunchDaemons")] {
            for child in children(dir) where child.hasSuffix(".plist") {
                let plist = dir.appendingPathComponent(child)
                let program = launchProgram(plist)
                guard isOurs(String(child.dropLast(6))) || program?.hasPrefix(app.url.path + "/") == true else { continue }
                found[plist] = .launchItems
                // O ajudante que o serviço abre, se estiver na pasta de ajudantes do sistema.
                if let program, program.hasPrefix("/Library/PrivilegedHelperTools/") {
                    found[URL(fileURLWithPath: program)] = .launchItems
                }
            }
        }
        look(local.appendingPathComponent("PrivilegedHelperTools"), .launchItems, byID())

        var items = [Leftover(url: app.url, kind: .app)]
        items += found.filter { fm.fileExists(atPath: $0.key.path) && $0.key != app.url }
            .map { Leftover(url: $0.key, kind: $0.value) }
            .sorted { ($0.kind, $0.url.path) < ($1.kind, $1.url.path) }
        for i in items.indices {
            items[i].size = size(of: items[i].url)
            items[i].needsAdmin = !fm.isWritableFile(atPath: items[i].url.deletingLastPathComponent().path)
        }
        return items
    }

    /// Outras cópias deste mesmo app (mesmo identificador), que usam os mesmos dados.
    static func otherCopies(of app: AppBundle) -> [URL] {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID)
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { $0 != app.url && !$0.path.contains("/.Trash/") && FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Apps nas pastas de aplicativos (e em uma subpasta delas), com identificador e nomes.
    private static func installedApps() -> [(id: String, names: [String])] {
        let fm = FileManager.default
        var roots = ["/Applications", "/Applications/Utilities", fm.homeDirectoryForCurrentUser.path + "/Applications"]
        var apps: [(String, [String])] = []
        var seen = Set<String>()
        while let root = roots.first {
            roots.removeFirst()
            for child in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let path = root + "/" + child
                if child.hasSuffix(".app") {
                    guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
                          let id = info["CFBundleIdentifier"] as? String, seen.insert(path).inserted
                    else { continue }
                    let names = [(child as NSString).deletingPathExtension, info["CFBundleName"] as? String,
                                 info["CFBundleDisplayName"] as? String].compactMap { $0 }
                    apps.append((id, names))
                } else if root == "/Applications", !child.hasPrefix(".") {
                    // Pastas como "Microsoft Office" ou "Adobe Photoshop 2025".
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue, child != "Utilities" {
                        roots.append(path)
                    }
                }
            }
        }
        return apps
    }

    /// O programa que um LaunchAgent/LaunchDaemon abre.
    static func launchProgram(_ plist: URL) -> String? {
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        return (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let files = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: { _, _ in true })
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// `--leftovers <app>`: imprime o que seria removido. Não move nada.
    static func printReport(for url: URL) -> Int32 {
        switch AppBundle.load(url) {
        case .failure(let refusal):
            print("Recusado: \(refusal.message)")
            return 1
        case .success(let app):
            print("\(app.name) (\(app.bundleID))")
            for item in scan(app) {
                print("[\(item.kind)] \(item.url.path)  \(formatBytes(item.size))\(item.needsAdmin ? "  (senha)" : "")")
            }
            for copy in otherCopies(of: app) { print("Outra cópia: \(copy.path)") }
            return 0
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file).locale(Localization.shared.locale))
}

// MARK: - Desinstalação

@Observable final class Uninstaller {
    enum Phase: Equatable {
        case scanning, review, removing, done
        case refused(UninstallRefusal)
    }

    private(set) var phase: Phase = .scanning
    private(set) var app: AppBundle?
    /// Ícone e nome do que foi escolhido, mesmo quando é recusado.
    private(set) var chosenURL: URL?
    private(set) var items: [Leftover] = []
    var selected: Set<URL> = []
    private(set) var otherCopies: [URL] = []
    private(set) var isRunning = false
    private(set) var removed: [Leftover] = []
    private(set) var failed: [Leftover] = []
    /// Serviços do sistema removidos continuam rodando até reiniciar.
    private(set) var needsRestart = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    deinit { observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }

    func load(_ url: URL) {
        chosenURL = url
        switch AppBundle.load(url) {
        case .failure(let refusal):
            phase = .refused(refusal)
        case .success(let app):
            self.app = app
            phase = .scanning
            watchRunning()
            DispatchQueue.global(qos: .userInitiated).async {
                let items = LeftoverScanner.scan(app)
                let copies = LeftoverScanner.otherCopies(of: app)
                DispatchQueue.main.async {
                    self.items = items
                    self.otherCopies = copies
                    // Com outra cópia instalada, os dados são dela também: só o app vem marcado.
                    self.selected = Set(copies.isEmpty ? items.map(\.id) : [app.url])
                    self.phase = .review
                }
            }
        }
    }

    var selectedItems: [Leftover] { items.filter { selected.contains($0.id) } }

    func quitApp() {
        guard let app else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
    }

    private func watchRunning() {
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshRunning()
            })
        }
    }

    private func refreshRunning() {
        guard let app else { return }
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    /// Move para o Lixo (nada é apagado de vez). O app vai primeiro: se o macOS não deixar,
    /// o resto não é tocado, para não deixar o app instalado sem os dados dele.
    func remove() {
        guard phase == .review, !isRunning else { return }
        let chosen = selectedItems.sorted { $0.kind < $1.kind }
        guard !chosen.isEmpty else { return }
        phase = .removing
        DispatchQueue.global(qos: .userInitiated).async {
            var removed: [Leftover] = []
            var failed: [Leftover] = []
            var restart = false
            for item in chosen {
                if failed.contains(where: { $0.kind == .app }) {
                    failed.append(item)
                    continue
                }
                if item.kind == .launchItems { Self.stopService(item.url) }
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    removed.append(item)
                    if item.kind == .launchItems && item.url.path.hasPrefix("/Library/") { restart = true }
                } catch {
                    uninstallLog.error("não foi para o Lixo: \(error.localizedDescription, privacy: .public)")
                    failed.append(item)
                }
            }
            DispatchQueue.main.async {
                self.removed += removed
                self.failed = failed
                self.needsRestart = self.needsRestart || restart
                self.phase = .done
            }
        }
    }

    /// O Finder pode mover itens protegidos (do sistema ou apps que o macOS protege), pedindo a senha.
    func moveFailedWithFinder() {
        let pending = failed
        guard phase == .done, !pending.isEmpty else { return }
        phase = .removing
        DispatchQueue.global(qos: .userInitiated).async {
            let script = """
            on run argv
                set targets to {}
                repeat with p in argv
                    set end of targets to (POSIX file (contents of p)) as alias
                end repeat
                tell application "Finder" to delete targets
            end run
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script] + pending.map(\.url.path)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                uninstallLog.error("osascript: \(error.localizedDescription, privacy: .public)")
            }
            let gone = pending.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
            DispatchQueue.main.async {
                self.removed += gone
                self.failed = pending.filter { item in !gone.contains(item) }
                if gone.contains(where: { $0.kind == .launchItems && $0.url.path.hasPrefix("/Library/") }) {
                    self.needsRestart = true
                }
                self.phase = .done
            }
        }
    }

    /// Encerra o serviço da sua conta antes de tirá-lo (os do sistema param ao reiniciar).
    private static func stopService(_ plist: URL) {
        guard plist.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/"),
              plist.pathExtension == "plist"
        else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", plist.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Dados de exemplo para o modo `--snapshot`.
    func showDemo(done: Bool) {
        let base = "/Users/demo/Library"
        let app = AppBundle(url: URL(fileURLWithPath: "/Applications/Lumen.app"), name: "Lumen",
                            bundleID: "com.lumen.player", version: "3.2", executable: "Lumen", folderNames: ["Lumen"])
        self.app = app
        chosenURL = app.url
        items = [
            Leftover(url: app.url, kind: .app, size: 182_000_000),
            Leftover(url: URL(fileURLWithPath: "\(base)/Application Support/Lumen"), kind: .support, size: 48_200_000),
            Leftover(url: URL(fileURLWithPath: "\(base)/Containers/com.lumen.player.share"), kind: .containers, size: 1_200_000),
            Leftover(url: URL(fileURLWithPath: "\(base)/Caches/com.lumen.player"), kind: .caches, size: 96_400_000),
            Leftover(url: URL(fileURLWithPath: "\(base)/Preferences/com.lumen.player.plist"), kind: .preferences, size: 4_096),
            Leftover(url: URL(fileURLWithPath: "\(base)/Saved Application State/com.lumen.player.savedState"),
                     kind: .preferences, size: 20_480),
            Leftover(url: URL(fileURLWithPath: "/Library/LaunchDaemons/com.lumen.player.helper.plist"),
                     kind: .launchItems, size: 4_096, needsAdmin: true),
        ]
        selected = Set(items.map(\.id))
        phase = .review
        if done {
            removed = Array(items.dropLast())
            failed = [items[items.count - 1]]
            phase = .done
        }
    }
}
