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
    case dropToKeep, dragHere, oneItemKept, itemsKept
    case menuTeleprompter, openAtLogin, quit, language, automatic, options
    case sampleScript
    case followVoice, voiceLanguage, voiceAuto, voiceCaption, voiceToggle
    case edit, undo, redo, cut, copy, paste, selectAll, closeWindow, pasteScript, pasteScriptHelp
    case voicePreparing, voiceDownloading, voiceMicDenied, voiceUnsupported, voiceFailed, voiceNeedsNewerMac
    case cameraMirror, closeMirror, cameraDenied, openCameraSettings, noCamera
    case islandScreen, screenMain, screenNotch
}

private let translations: [AppLanguage: [LKey: String]] = [
    .ptBR: [
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
        .dropToKeep: "Solte para guardar",
        .dragHere: "Arraste até aqui",
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
        .screenMain: "Ecrã principal (com a barra de menus)",
        .screenNotch: "Ecrã do MacBook (com o notch)",
        .hideCaption: "Ligado: quem assiste à reunião ou ao vídeo não vê a ilha nem esta janela. Uma coluna estreita e o texto logo abaixo da câmara mantêm o olhar natural.",
        .shortcuts: "⌃⌥T abre/fecha · ⌃⌥Espaço pausa · ⌃⌥↑/↓ velocidade · deslize no trackpad para avançar ou recuar",
        .shelfEmptyTitle: "Arraste ficheiros até à ilha para os guardar",
        .shelfEmptySubtitle: "Depois basta arrastá-los daqui para a pasta ou disco de destino",
        .shelfHint: "Arraste para o destino · mantenha ⌘ premido ao largar para mover entre discos",
        .removeFromShelf: "Retirar da prateleira",
        .dropToKeep: "Largue para guardar",
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
        .dropToKeep: "Drop to hold",
        .dragHere: "Drag here",
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
        .dropToKeep: "Suelta para guardar",
        .dragHere: "Arrastra hasta aquí",
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
