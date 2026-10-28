import Foundation
import Observation

enum AppLanguage: String, CaseIterable {
    case ptBR = "pt-BR", ptPT = "pt-PT", enUS = "en-US", enGB = "en-GB", es = "es"

    /// Nome do idioma escrito no próprio idioma (como no macOS).
    var nativeName: String {
        switch self {
        case .ptBR: "Português (Brasil)"
        case .ptPT: "Português (Portugal)"
        case .enUS: "English (US)"
        case .enGB: "English (UK)"
        case .es: "Español"
        }
    }

    var locale: Locale {
        switch self {
        case .ptBR: Locale(identifier: "pt_BR")
        case .ptPT: Locale(identifier: "pt_PT")
        case .enUS: Locale(identifier: "en_US")
        case .enGB: Locale(identifier: "en_GB")
        case .es: Locale(identifier: "es_ES")
        }
    }

    /// Idioma do qual herda os textos que não tiver traduzido.
    var fallback: AppLanguage? {
        switch self {
        case .ptPT: .ptBR
        case .enGB: .enUS
        default: nil
        }
    }

    /// Primeiro idioma preferido do sistema que a Marquise suporta (inglês americano se nenhum).
    static func detect(from preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        let britishRegions: Set<String> = ["GB", "IE", "AU", "NZ", "IN", "ZA"]
        for identifier in preferred {
            let locale = Locale(identifier: identifier)
            let region = locale.region?.identifier
            switch locale.language.languageCode?.identifier {
            case "pt": return region == "PT" ? .ptPT : .ptBR
            case "en": return region.map(britishRegions.contains) == true ? .enGB : .enUS
            case "es": return .es
            default: continue
            }
        }
        return .enUS
    }
}

@Observable final class Localization {
    static let shared = Localization()

    /// `nil` = automático (segue o sistema).
    var choice: AppLanguage? = UserDefaults.standard.string(forKey: "app.language").flatMap(AppLanguage.init(rawValue:)) {
        didSet {
            UserDefaults.standard.set(choice?.rawValue, forKey: "app.language")
            onChange?()
        }
    }
    @ObservationIgnored var onChange: (() -> Void)?

    var language: AppLanguage { choice ?? AppLanguage.detect() }

    /// No automático, datas e horas seguem o formato regional do sistema.
    var locale: Locale { choice?.locale ?? .current }
}

/// Texto traduzido para o idioma atual da Marquise.
func L(_ key: LKey) -> String {
    L(key, in: Localization.shared.language)
}

func L(_ key: LKey, in language: AppLanguage) -> String {
    var language: AppLanguage? = language
    while let current = language {
        if let text = translations[current]?[key] { return text }
        language = current.fallback
    }
    return translations[.enUS]?[key] ?? key.rawValue
}

/// Texto traduzido com um número (`%d`) ou texto (`%@`) dentro.
func L(_ key: LKey, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Localization.shared.locale, arguments: args)
}

enum LKey: String {
    case untitled, nothingPlaying, teleprompter, noScript
    case slower, faster, restart, editScript, closePrompter
    case script, speed, columnWidth, textSize, hideFromCapture, hideCaption, mirror, shortcuts, start
    case shelfEmptyTitle, shelfEmptySubtitle, shelfHint, clear, removeFromShelf, allCount, dragAll
    case oneItemKept, itemsKept
    case dropShelf, dropShelfHint, dropUninstall, airDropHint, sendAirDrop
    case menuUninstall, chooseAppToUninstall, uninstallerTitle, scanning, movingToTrash
    case kindApp, kindSupport, kindContainers, kindCaches, kindPreferences, kindLogs, kindLaunch
    case needsPassword, showInFinder, selectedSummary, moveToTrash, cancel, trashNote, noLeftovers
    case appIsRunning, quitApp, otherCopies, refusedApple, refusedSelf, refusedNoID, refusedInside
    case doneTitle, doneDetail, partialTitle, protectedHelp, askFinder, showTrash, closeButton, restartNote
    case menuTeleprompter, openAtLogin, quit, language, automatic, options
    case sampleScript
    case followVoice, voiceLanguage, voiceAuto, voiceCaption, voiceToggle
    case edit, undo, redo, cut, copy, paste, selectAll, closeWindow, pasteScript, pasteScriptHelp
    case voicePreparing, voiceDownloading, voiceMicDenied, voiceUnsupported, voiceFailed, voiceNeedsNewerMac
    case cameraMirror, closeMirror, cameraDenied, openCameraSettings, noCamera
    case islandScreen, screenMain, screenNotch
    case lidClosedUseIPhone, noMacCameraUseIPhone, useIPhone, notNow, lidClosedNoCamera
}

private let translations: [AppLanguage: [LKey: String]] = [
    .ptBR: [
        .dropShelf: "Guardar",
        .dropShelfHint: "Na prateleira",
        .dropUninstall: "Desinstalar",
        .airDropHint: "Para quem está perto",
        .sendAirDrop: "Enviar por AirDrop",
        .menuUninstall: "Desinstalar um app…",
        .chooseAppToUninstall: "Escolha o app que você quer desinstalar",
        .uninstallerTitle: "Desinstalador",
        .scanning: "Procurando os arquivos do app…",
        .movingToTrash: "Movendo para o Lixo…",
        .kindApp: "Aplicativo",
        .kindSupport: "Dados do app",
        .kindContainers: "Contêineres",
        .kindCaches: "Caches",
        .kindPreferences: "Preferências e estado das janelas",
        .kindLogs: "Registros e relatórios de falha",
        .kindLaunch: "Itens que abrem sozinhos",
        .needsPassword: "Fora da sua pasta pessoal: o macOS vai pedir a sua senha",
        .showInFinder: "Mostrar no Finder",
        .selectedSummary: "%d itens selecionados · %@",
        .moveToTrash: "Mover para o Lixo",
        .cancel: "Cancelar",
        .trashNote: "Nada é apagado de vez: tudo vai para o Lixo, e dá para recuperar de lá.",
        .noLeftovers: "Nenhum outro arquivo deste app foi encontrado.",
        .appIsRunning: "O app está aberto. Feche-o antes de desinstalar.",
        .quitApp: "Fechar o app",
        .otherCopies: "Há outra cópia deste app em %@. Ela usa os mesmos dados, então só o app veio marcado.",
        .refusedApple: "Os apps da Apple fazem parte do macOS e não podem ser desinstalados.",
        .refusedSelf: "Para desinstalar a Marquise, saia dela e arraste-a para o Lixo.",
        .refusedNoID: "Este app não tem identificador, então não dá para achar os arquivos dele com segurança.",
        .refusedInside: "Este app faz parte de outro (%@) e só sai junto com ele.",
        .doneTitle: "Desinstalação concluída",
        .doneDetail: "%d itens (%@) foram para o Lixo.",
        .partialTitle: "Alguns itens ficaram",
        .protectedHelp: "O macOS protege estes itens. O Finder pode movê-los para o Lixo pedindo a sua senha.",
        .askFinder: "Mover com o Finder",
        .showTrash: "Abrir o Lixo",
        .closeButton: "Fechar",
        .restartNote: "Alguns serviços do app continuam rodando até você reiniciar o Mac.",
        .edit: "Editar",
        .undo: "Desfazer",
        .redo: "Refazer",
        .cut: "Recortar",
        .copy: "Copiar",
        .paste: "Colar",
        .selectAll: "Selecionar Tudo",
        .closeWindow: "Fechar Janela",
        .pasteScript: "Colar roteiro",
        .pasteScriptHelp: "Substitui o roteiro pelo texto copiado",
        .followVoice: "Seguir minha voz (o texto anda conforme você fala)",
        .voiceLanguage: "Idioma da voz",
        .voiceAuto: "Automático pelo roteiro (%@)",
        .voiceCaption: "O reconhecimento acontece no próprio Mac: o áudio não sai do computador. Na primeira vez, o macOS baixa o modelo de voz do idioma.",
        .voiceToggle: "Seguir minha voz",
        .voicePreparing: "Preparando voz…",
        .voiceDownloading: "Baixando voz %d%%",
        .voiceMicDenied: "Sem microfone",
        .voiceUnsupported: "Idioma sem voz",
        .voiceFailed: "Erro na voz",
        .voiceNeedsNewerMac: "Requer macOS 26",
        .untitled: "Sem título",
        .nothingPlaying: "Nada tocando",
        .teleprompter: "Teleprompter",
        .noScript: "Sem roteiro. Clique no lápis para escrever.",
        .slower: "Mais devagar",
        .faster: "Mais rápido",
        .restart: "Recomeçar",
        .editScript: "Editar roteiro",
        .closePrompter: "Fechar teleprompter",
        .cameraMirror: "Espelho",
        .closeMirror: "Fechar espelho",
        .cameraDenied: "A Marquise não tem acesso à câmera",
        .openCameraSettings: "Abrir Ajustes",
        .noCamera: "Nenhuma câmera encontrada",
        .lidClosedUseIPhone: "O MacBook está fechado. Usar o iPhone como câmera?",
        .noMacCameraUseIPhone: "A câmera do Mac não está disponível. Usar o iPhone como câmera?",
        .useIPhone: "Usar o iPhone",
        .notNow: "Agora não",
        .lidClosedNoCamera: "O MacBook está fechado. Aproxime seu iPhone para usá-lo como câmera.",
        .islandScreen: "Mostrar a ilha em",
        .screenMain: "Tela principal (com a barra de menus)",
        .screenNotch: "Tela do MacBook (com o notch)",
        .script: "Roteiro",
        .speed: "Velocidade",
        .columnWidth: "Largura da coluna",
        .textSize: "Tamanho do texto",
        .hideFromCapture: "Esconder a Marquise em gravações e compartilhamento de tela",
        .hideCaption: "Ligado: quem assiste à reunião ou ao vídeo não vê a ilha nem esta janela. Coluna estreita e texto logo abaixo da câmera deixam o olhar natural.",
        .mirror: "Espelhar o texto (para vidro de teleprompter)",
        .shortcuts: "⌃⌥T abre/fecha · ⌃⌥Espaço pausa · ⌃⌥↑/↓ velocidade · role o trackpad para avançar ou voltar",
        .start: "Iniciar",
        .shelfEmptyTitle: "Arraste arquivos até a ilha para guardá-los",
        .shelfEmptySubtitle: "Depois é só arrastar daqui para a pasta ou disco de destino",
        .shelfHint: "Arraste para o destino · segure ⌘ ao soltar para mover entre discos",
        .clear: "Limpar",
        .removeFromShelf: "Tirar da prateleira",
        .allCount: "Todos (%d)",
        .dragAll: "Arrastar todos de uma vez",
        .oneItemKept: "1 item já guardado",
        .itemsKept: "%d itens já guardados",
        .menuTeleprompter: "Teleprompter…",
        .openAtLogin: "Abrir ao iniciar sessão",
        .quit: "Sair da Marquise",
        .language: "Idioma",
        .automatic: "Automático (%@)",
        .options: "Opções",
        .sampleScript: """
        Olá! Este é o teleprompter da Marquise.

        Cole o seu roteiro na janela do teleprompter e clique em Iniciar. \
        O texto rola logo abaixo da câmera, então você lê olhando quase direto para a lente.

        Passe o mouse sobre a ilha para pausar, mudar a velocidade ou recomeçar. \
        Role o trackpad para avançar ou voltar no texto.

        Atalhos: Control-Option-T abre e fecha, Control-Option-Espaço pausa, \
        e Control-Option com as setas para cima e para baixo muda a velocidade.
        """,
    ],
    // Só o que muda em relação ao português do Brasil.
    .ptPT: [
        .airDropHint: "Para quem está por perto",
        .menuUninstall: "Desinstalar uma app…",
        .chooseAppToUninstall: "Escolha a app que pretende desinstalar",
        .scanning: "A procurar os ficheiros da app…",
        .movingToTrash: "A mover para o Lixo…",
        .kindApp: "Aplicação",
        .kindSupport: "Dados da app",
        .kindContainers: "Contentores",
        .kindLogs: "Registos e relatórios de falhas",
        .kindLaunch: "Itens que abrem automaticamente",
        .needsPassword: "Fora da sua pasta pessoal: o macOS vai pedir a sua palavra-passe",
        .trashNote: "Nada é apagado definitivamente: tudo vai para o Lixo, de onde pode recuperar.",
        .noLeftovers: "Não foi encontrado mais nenhum ficheiro desta app.",
        .appIsRunning: "A app está aberta. Feche-a antes de desinstalar.",
        .quitApp: "Fechar a app",
        .otherCopies: "Há outra cópia desta app em %@. Usa os mesmos dados, por isso só a app ficou marcada.",
        .refusedApple: "As apps da Apple fazem parte do macOS e não podem ser desinstaladas.",
        .refusedSelf: "Para desinstalar a Marquise, feche-a e arraste-a para o Lixo.",
        .refusedNoID: "Esta app não tem identificador, por isso não é possível encontrar os ficheiros dela com segurança.",
        .refusedInside: "Esta app faz parte de outra (%@) e só sai com ela.",
        .protectedHelp: "O macOS protege estes itens. O Finder pode movê-los para o Lixo pedindo a sua palavra-passe.",
        .restartNote: "Alguns serviços da app continuam a funcionar até reiniciar o Mac.",
        .undo: "Anular",
        .cut: "Cortar",
        .selectAll: "Selecionar tudo",
        .closeWindow: "Fechar janela",
        .pasteScript: "Colar guião",
        .pasteScriptHelp: "Substitui o guião pelo texto copiado",
        .followVoice: "Seguir a minha voz (o texto avança à medida que fala)",
        .voiceAuto: "Automático pelo guião (%@)",
        .voiceCaption: "O reconhecimento acontece no próprio Mac: o áudio não sai do computador. Na primeira vez, o macOS descarrega o modelo de voz do idioma.",
        .voiceToggle: "Seguir a minha voz",
        .voiceDownloading: "A descarregar voz %d%%",
        .nothingPlaying: "Nada a tocar",
        .noScript: "Sem guião. Clique no lápis para escrever.",
        .editScript: "Editar guião",
        .script: "Guião",
        .hideFromCapture: "Ocultar a Marquise em gravações e na partilha de ecrã",
        .cameraDenied: "A Marquise não tem acesso à câmara",
        .openCameraSettings: "Abrir Definições",
        .noCamera: "Nenhuma câmara encontrada",
        .lidClosedUseIPhone: "O MacBook está fechado. Usar o iPhone como câmara?",
        .noMacCameraUseIPhone: "A câmara do Mac não está disponível. Usar o iPhone como câmara?",
        .lidClosedNoCamera: "O MacBook está fechado. Aproxime o iPhone para o usar como câmara.",
        .screenMain: "Ecrã principal (com a barra de menus)",
        .screenNotch: "Ecrã do MacBook (com o notch)",
        .hideCaption: "Ligado: quem assiste à reunião ou ao vídeo não vê a ilha nem esta janela. Uma coluna estreita e o texto logo abaixo da câmara mantêm o olhar natural.",
        .shortcuts: "⌃⌥T abre/fecha · ⌃⌥Espaço pausa · ⌃⌥↑/↓ velocidade · deslize no trackpad para avançar ou recuar",
        .shelfEmptyTitle: "Arraste ficheiros até à ilha para os guardar",
        .shelfEmptySubtitle: "Depois basta arrastá-los daqui para a pasta ou disco de destino",
        .shelfHint: "Arraste para o destino · mantenha ⌘ premido ao largar para mover entre discos",
        .removeFromShelf: "Retirar da prateleira",
        .sampleScript: """
        Olá! Este é o teleprompter da Marquise.

        Cole o seu guião na janela do teleprompter e clique em Iniciar. \
        O texto desliza logo abaixo da câmara, por isso lê quase a olhar diretamente para a lente.

        Passe o rato sobre a ilha para pausar, mudar a velocidade ou recomeçar. \
        Deslize no trackpad para avançar ou recuar no texto.

        Atalhos: Control-Option-T abre e fecha, Control-Option-Espaço pausa, \
        e Control-Option com as setas para cima e para baixo muda a velocidade.
        """,
    ],
    .enUS: [
        .dropShelf: "Hold",
        .dropShelfHint: "On the shelf",
        .dropUninstall: "Uninstall",
        .airDropHint: "To someone nearby",
        .sendAirDrop: "Send with AirDrop",
        .menuUninstall: "Uninstall an App…",
        .chooseAppToUninstall: "Choose the app you want to uninstall",
        .uninstallerTitle: "Uninstaller",
        .scanning: "Looking for the app's files…",
        .movingToTrash: "Moving to the Trash…",
        .kindApp: "App",
        .kindSupport: "App data",
        .kindContainers: "Containers",
        .kindCaches: "Caches",
        .kindPreferences: "Preferences and window state",
        .kindLogs: "Logs and crash reports",
        .kindLaunch: "Background items",
        .needsPassword: "Outside your home folder: macOS will ask for your password",
        .showInFinder: "Show in Finder",
        .selectedSummary: "%d items selected · %@",
        .moveToTrash: "Move to Trash",
        .cancel: "Cancel",
        .trashNote: "Nothing is deleted for good: everything goes to the Trash, where you can get it back.",
        .noLeftovers: "No other files from this app were found.",
        .appIsRunning: "The app is open. Quit it before uninstalling.",
        .quitApp: "Quit App",
        .otherCopies: "Another copy of this app is in %@. It uses the same data, so only the app is selected.",
        .refusedApple: "Apple apps are part of macOS and can't be uninstalled.",
        .refusedSelf: "To uninstall Marquise, quit it and drag it to the Trash.",
        .refusedNoID: "This app has no bundle identifier, so its files can't be found safely.",
        .refusedInside: "This app is part of another app (%@) and can only be removed with it.",
        .doneTitle: "Uninstall complete",
        .doneDetail: "%d items (%@) were moved to the Trash.",
        .partialTitle: "Some items were left",
        .protectedHelp: "macOS protects these items. Finder can move them to the Trash after asking for your password.",
        .askFinder: "Move with Finder",
        .showTrash: "Open Trash",
        .closeButton: "Close",
        .restartNote: "Some of the app's services keep running until you restart your Mac.",
        .edit: "Edit",
        .undo: "Undo",
        .redo: "Redo",
        .cut: "Cut",
        .copy: "Copy",
        .paste: "Paste",
        .selectAll: "Select All",
        .closeWindow: "Close Window",
        .pasteScript: "Paste script",
        .pasteScriptHelp: "Replace the script with the copied text",
        .followVoice: "Follow my voice (the text moves as you speak)",
        .voiceLanguage: "Voice language",
        .voiceAuto: "Automatic from script (%@)",
        .voiceCaption: "Recognition runs on your Mac: audio never leaves the computer. The first time, macOS downloads the voice model for the language.",
        .voiceToggle: "Follow my voice",
        .voicePreparing: "Preparing voice…",
        .voiceDownloading: "Downloading voice %d%%",
        .voiceMicDenied: "No mic access",
        .voiceUnsupported: "Language not supported",
        .voiceFailed: "Voice error",
        .voiceNeedsNewerMac: "Requires macOS 26",
        .untitled: "Untitled",
        .nothingPlaying: "Nothing playing",
        .teleprompter: "Teleprompter",
        .noScript: "No script yet. Click the pencil to write one.",
        .slower: "Slower",
        .faster: "Faster",
        .restart: "Restart",
        .editScript: "Edit script",
        .closePrompter: "Close teleprompter",
        .cameraMirror: "Mirror",
        .closeMirror: "Close mirror",
        .cameraDenied: "Marquise can't access the camera",
        .openCameraSettings: "Open Settings",
        .noCamera: "No camera found",
        .lidClosedUseIPhone: "Your MacBook is closed. Use your iPhone as the camera?",
        .noMacCameraUseIPhone: "The Mac's camera isn't available. Use your iPhone as the camera?",
        .useIPhone: "Use iPhone",
        .notNow: "Not Now",
        .lidClosedNoCamera: "Your MacBook is closed. Bring your iPhone close to use it as the camera.",
        .islandScreen: "Show Island On",
        .screenMain: "Main Display (with the menu bar)",
        .screenNotch: "MacBook Display (with the notch)",
        .script: "Script",
        .speed: "Speed",
        .columnWidth: "Column width",
        .textSize: "Text size",
        .hideFromCapture: "Hide Marquise from screen recordings and screen sharing",
        .hideCaption: "When on, people watching your meeting or video can't see the island or this window. A narrow column right below the camera keeps your gaze natural.",
        .mirror: "Mirror text (for teleprompter glass)",
        .shortcuts: "⌃⌥T open/close · ⌃⌥Space pause · ⌃⌥↑/↓ speed · scroll the trackpad to move forward or back",
        .start: "Start",
        .shelfEmptyTitle: "Drag files to the island to hold them",
        .shelfEmptySubtitle: "Then drag them from here to the destination folder or disk",
        .shelfHint: "Drag to the destination · hold ⌘ when dropping to move between disks",
        .clear: "Clear",
        .removeFromShelf: "Remove from shelf",
        .allCount: "All (%d)",
        .dragAll: "Drag all at once",
        .oneItemKept: "1 item on the shelf",
        .itemsKept: "%d items on the shelf",
        .menuTeleprompter: "Teleprompter…",
        .openAtLogin: "Open at Login",
        .quit: "Quit Marquise",
        .language: "Language",
        .automatic: "Automatic (%@)",
        .options: "Options",
        .sampleScript: """
        Hi! This is Marquise's teleprompter.

        Paste your script into the teleprompter window and click Start. \
        The text scrolls right below the camera, so you read while looking almost straight into the lens.

        Hover over the island to pause, change the speed or restart. \
        Scroll the trackpad to move forward or back in the text.

        Shortcuts: Control-Option-T opens and closes, Control-Option-Space pauses, \
        and Control-Option with the up and down arrows changes the speed.
        """,
    ],
    // Só o que muda em relação ao inglês americano (datas e horas já seguem o formato britânico).
    .enGB: [
        .movingToTrash: "Moving to the Bin…",
        .moveToTrash: "Move to Bin",
        .trashNote: "Nothing is deleted for good: everything goes to the Bin, where you can get it back.",
        .refusedSelf: "To uninstall Marquise, quit it and drag it to the Bin.",
        .doneDetail: "%d items (%@) were moved to the Bin.",
        .protectedHelp: "macOS protects these items. Finder can move them to the Bin after asking for your password.",
        .showTrash: "Open Bin",
        .openAtLogin: "Open at Log-in",
        .sampleScript: """
        Hello! This is Marquise's teleprompter.

        Paste your script into the teleprompter window and click Start. \
        The text scrolls just below the camera, so you read whilst looking almost straight into the lens.

        Hover over the island to pause, change the speed or restart. \
        Scroll the trackpad to move forwards or backwards through the text.

        Shortcuts: Control-Option-T opens and closes, Control-Option-Space pauses, \
        and Control-Option with the up and down arrows changes the speed.
        """,
    ],
    .es: [
        .dropShelf: "Guardar",
        .dropShelfHint: "En la bandeja",
        .dropUninstall: "Desinstalar",
        .airDropHint: "A alguien cercano",
        .sendAirDrop: "Enviar por AirDrop",
        .menuUninstall: "Desinstalar una app…",
        .chooseAppToUninstall: "Elige la app que quieres desinstalar",
        .uninstallerTitle: "Desinstalador",
        .scanning: "Buscando los archivos de la app…",
        .movingToTrash: "Trasladando a la Papelera…",
        .kindApp: "Aplicación",
        .kindSupport: "Datos de la app",
        .kindContainers: "Contenedores",
        .kindCaches: "Cachés",
        .kindPreferences: "Preferencias y estado de las ventanas",
        .kindLogs: "Registros e informes de fallos",
        .kindLaunch: "Elementos en segundo plano",
        .needsPassword: "Fuera de tu carpeta personal: macOS te pedirá la contraseña",
        .showInFinder: "Mostrar en Finder",
        .selectedSummary: "%d elementos seleccionados · %@",
        .moveToTrash: "Trasladar a la Papelera",
        .cancel: "Cancelar",
        .trashNote: "No se borra nada definitivamente: todo va a la Papelera, de donde puedes recuperarlo.",
        .noLeftovers: "No se encontraron otros archivos de esta app.",
        .appIsRunning: "La app está abierta. Ciérrala antes de desinstalar.",
        .quitApp: "Cerrar la app",
        .otherCopies: "Hay otra copia de esta app en %@. Usa los mismos datos, así que solo se marcó la app.",
        .refusedApple: "Las apps de Apple forman parte de macOS y no se pueden desinstalar.",
        .refusedSelf: "Para desinstalar Marquise, ciérrala y arrástrala a la Papelera.",
        .refusedNoID: "Esta app no tiene identificador, así que no se pueden encontrar sus archivos con seguridad.",
        .refusedInside: "Esta app forma parte de otra (%@) y solo se elimina con ella.",
        .doneTitle: "Desinstalación completada",
        .doneDetail: "%d elementos (%@) se trasladaron a la Papelera.",
        .partialTitle: "Algunos elementos no se movieron",
        .protectedHelp: "macOS protege estos elementos. Finder puede trasladarlos a la Papelera pidiéndote la contraseña.",
        .askFinder: "Trasladar con Finder",
        .showTrash: "Abrir la Papelera",
        .closeButton: "Cerrar",
        .restartNote: "Algunos servicios de la app siguen activos hasta que reinicies el Mac.",
        .edit: "Edición",
        .undo: "Deshacer",
        .redo: "Rehacer",
        .cut: "Cortar",
        .copy: "Copiar",
        .paste: "Pegar",
        .selectAll: "Seleccionar todo",
        .closeWindow: "Cerrar ventana",
        .pasteScript: "Pegar guion",
        .pasteScriptHelp: "Reemplaza el guion por el texto copiado",
        .followVoice: "Seguir mi voz (el texto avanza mientras hablas)",
        .voiceLanguage: "Idioma de la voz",
        .voiceAuto: "Automático según el guion (%@)",
        .voiceCaption: "El reconocimiento ocurre en el propio Mac: el audio no sale del ordenador. La primera vez, macOS descarga el modelo de voz del idioma.",
        .voiceToggle: "Seguir mi voz",
        .voicePreparing: "Preparando voz…",
        .voiceDownloading: "Descargando voz %d%%",
        .voiceMicDenied: "Sin micrófono",
        .voiceUnsupported: "Idioma no compatible",
        .voiceFailed: "Error de voz",
        .voiceNeedsNewerMac: "Requiere macOS 26",
        .untitled: "Sin título",
        .nothingPlaying: "No suena nada",
        .teleprompter: "Teleprompter",
        .noScript: "Sin guion. Haz clic en el lápiz para escribir uno.",
        .slower: "Más lento",
        .faster: "Más rápido",
        .restart: "Reiniciar",
        .editScript: "Editar guion",
        .closePrompter: "Cerrar teleprompter",
        .cameraMirror: "Espejo",
        .closeMirror: "Cerrar espejo",
        .cameraDenied: "Marquise no tiene acceso a la cámara",
        .openCameraSettings: "Abrir Ajustes",
        .noCamera: "No se encontró ninguna cámara",
        .lidClosedUseIPhone: "El MacBook está cerrado. ¿Usar el iPhone como cámara?",
        .noMacCameraUseIPhone: "La cámara del Mac no está disponible. ¿Usar el iPhone como cámara?",
        .useIPhone: "Usar el iPhone",
        .notNow: "Ahora no",
        .lidClosedNoCamera: "El MacBook está cerrado. Acerca tu iPhone para usarlo como cámara.",
        .islandScreen: "Mostrar la isla en",
        .screenMain: "Pantalla principal (con la barra de menús)",
        .screenNotch: "Pantalla del MacBook (con el notch)",
        .script: "Guion",
        .speed: "Velocidad",
        .columnWidth: "Ancho de columna",
        .textSize: "Tamaño del texto",
        .hideFromCapture: "Ocultar Marquise en grabaciones y al compartir pantalla",
        .hideCaption: "Activado: quien vea la reunión o el vídeo no verá la isla ni esta ventana. Una columna estrecha justo debajo de la cámara mantiene la mirada natural.",
        .mirror: "Reflejar el texto (para cristal de teleprompter)",
        .shortcuts: "⌃⌥T abrir/cerrar · ⌃⌥Espacio pausa · ⌃⌥↑/↓ velocidad · desliza en el trackpad para avanzar o retroceder",
        .start: "Empezar",
        .shelfEmptyTitle: "Arrastra archivos a la isla para guardarlos",
        .shelfEmptySubtitle: "Después arrástralos desde aquí a la carpeta o disco de destino",
        .shelfHint: "Arrastra al destino · mantén ⌘ al soltar para mover entre discos",
        .clear: "Vaciar",
        .removeFromShelf: "Quitar de la bandeja",
        .allCount: "Todos (%d)",
        .dragAll: "Arrastrar todos a la vez",
        .oneItemKept: "1 elemento guardado",
        .itemsKept: "%d elementos guardados",
        .menuTeleprompter: "Teleprompter…",
        .openAtLogin: "Abrir al iniciar sesión",
        .quit: "Salir de Marquise",
        .language: "Idioma",
        .automatic: "Automático (%@)",
        .options: "Opciones",
        .sampleScript: """
        ¡Hola! Este es el teleprompter de Marquise.

        Pega tu guion en la ventana del teleprompter y haz clic en Empezar. \
        El texto se desplaza justo debajo de la cámara, así lees mirando casi directamente a la lente.

        Pasa el ratón sobre la isla para pausar, cambiar la velocidad o reiniciar. \
        Desliza en el trackpad para avanzar o retroceder en el texto.

        Atajos: Control-Opción-T abre y cierra, Control-Opción-Espacio pausa, \
        y Control-Opción con las flechas arriba y abajo cambia la velocidad.
        """,
    ],
]
