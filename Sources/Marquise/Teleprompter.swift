import AppKit
import Observation
import os
import SwiftUI

/// Só estados e posição no roteiro; o que a pessoa fala nunca vai para o log.
let voiceLog = Logger(subsystem: "com.marquise.app", category: "voice")

/// Estado do teleprompter: o texto rola para cima logo abaixo da câmera,
/// para você ler mantendo o olhar perto da lente. Pode rolar numa velocidade fixa
/// ou seguir a sua voz, palavra por palavra.
@Observable final class Teleprompter {
    static let baseSpeed = 40.0  // pontos por segundo = "1,0×"
    static let glideDuration = 0.45
    /// Desligado no modo `--snapshot` (não pede microfone).
    static var voiceEnabled = true

    /// O texto de exemplo não é salvo, para poder acompanhar o idioma escolhido.
    var text: String = UserDefaults.standard.string(forKey: "prompter.text") ?? L(.sampleScript) {
        didSet {
            textVersion += 1
            if Self.isSample(text) {
                UserDefaults.standard.removeObject(forKey: "prompter.text")
            } else {
                UserDefaults.standard.set(text, forKey: "prompter.text")
            }
        }
    }
    var speed: Double = Teleprompter.stored("prompter.speed", default: baseSpeed) {
        didSet { UserDefaults.standard.set(speed, forKey: "prompter.speed") }
    }
    /// Coluna estreita = os olhos quase não se movem para os lados enquanto você lê.
    var columnWidth: Double = Teleprompter.stored("prompter.columnWidth", default: 380) {
        didSet { UserDefaults.standard.set(columnWidth, forKey: "prompter.columnWidth") }
    }
    /// Esconde a Marquise (e a janela do roteiro) de gravações e compartilhamento de tela.
    var hiddenFromCapture: Bool = UserDefaults.standard.object(forKey: "prompter.hidden") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hiddenFromCapture, forKey: "prompter.hidden")
            onCaptureVisibilityChange?()
        }
    }
    var fontSize: Double = Teleprompter.stored("prompter.fontSize", default: 24) {
        didSet { UserDefaults.standard.set(fontSize, forKey: "prompter.fontSize") }
    }
    var mirrored: Bool = UserDefaults.standard.bool(forKey: "prompter.mirrored") {
        didSet { UserDefaults.standard.set(mirrored, forKey: "prompter.mirrored") }
    }
    /// O texto anda conforme você fala, em vez de numa velocidade fixa.
    var followVoice: Bool = UserDefaults.standard.object(forKey: "prompter.followVoice") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(followVoice, forKey: "prompter.followVoice")
            if followVoice != oldValue { voiceModeChanged() }
        }
    }
    /// `nil` = detecta pelo idioma do roteiro.
    var voiceLanguageChoice: AppLanguage? = UserDefaults.standard.string(forKey: "prompter.voiceLanguage")
        .flatMap(AppLanguage.init(rawValue:)) {
        didSet {
            UserDefaults.standard.set(voiceLanguageChoice?.rawValue, forKey: "prompter.voiceLanguage")
            if isActive && followVoice { startListening() }
        }
    }

    private(set) var isActive = false
    private(set) var isRunning = false
    private(set) var countdown: Int?
    var hovering = false

    private(set) var anchorOffset: CGFloat = 0
    private(set) var anchorDate = Date()

    private(set) var voiceStatus: VoiceStatus = .off
    /// Última palavra do roteiro que você já falou (-1 = nenhuma).
    private(set) var spokenIndex = -1
    private(set) var glideFrom: CGFloat = 0
    private(set) var glideTo: CGFloat = 0
    private(set) var glideStart = Date.distantPast

    @ObservationIgnored var onActiveChange: (() -> Void)?
    @ObservationIgnored var onCaptureVisibilityChange: (() -> Void)?
    @ObservationIgnored private var countdownWork: [DispatchWorkItem] = []
    @ObservationIgnored private var endTimer: Timer?
    @ObservationIgnored private var textVersion = 0
    @ObservationIgnored private var layoutCache: (key: String, value: PrompterLayout)?
    @ObservationIgnored private var matcher = VoiceMatcher(words: [])
    @ObservationIgnored private var matcherVersion = -1
    @ObservationIgnored private var listener: AnyObject?

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var speedLabel: String {
        let multiplier = (speed / Self.baseSpeed)
            .formatted(.number.precision(.fractionLength(1)).locale(Localization.shared.locale))
        return multiplier + "×"
    }

    var detectedVoiceLanguage: AppLanguage {
        AppLanguage.ofScript(text, preferring: Localization.shared.language)
    }

    var voiceLanguage: AppLanguage { voiceLanguageChoice ?? detectedVoiceLanguage }

    /// Linhas e palavras do roteiro, medidas com a mesma fonte e largura da ilha.
    var layout: PrompterLayout {
        _ = text  // registra a dependência para a interface
        let key = "\(fontSize)|\(columnWidth)|\(textVersion)"
        if let cache = layoutCache, cache.key == key { return cache.value }
        let value = PrompterLayout.make(text: text, fontSize: CGFloat(fontSize), width: CGFloat(columnWidth))
        layoutCache = (key, value)
        return value
    }

    /// Deslocamento máximo: a última linha na altura da câmera.
    var contentHeight: CGFloat { layout.maxOffset }

    func languageChanged() {
        if Self.isSample(text) { text = L(.sampleScript) }
    }

    private static func isSample(_ text: String) -> Bool {
        AppLanguage.allCases.contains { L(.sampleScript, in: $0) == text }
    }

    func offset(at date: Date) -> CGFloat {
        min(max(followVoice ? voiceOffset(at: date) : manualOffset(at: date), 0), contentHeight)
    }

    private func manualOffset(at date: Date) -> CGFloat {
        isRunning ? anchorOffset + CGFloat(speed * date.timeIntervalSince(anchorDate)) : anchorOffset
    }

    private func voiceOffset(at date: Date) -> CGFloat {
        let t = min(max(date.timeIntervalSince(glideStart) / Self.glideDuration, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        return glideFrom + (glideTo - glideFrom) * CGFloat(eased)
    }

    private func glide(to target: CGFloat, animated: Bool = true) {
        let now = Date()
        glideFrom = animated ? offset(at: now) : target
        glideTo = target
        glideStart = animated ? now : .distantPast
    }

    // MARK: - Ações

    func begin() {
        guard !isActive else { return }
        isActive = true
        anchorOffset = 0
        resetVoicePosition()
        onActiveChange?()
        if followVoice { startListening() }
        startCountdown()
    }

    func end() {
        guard isActive else { return }
        cancelCountdown()
        stopRunning()
        stopListening()
        isActive = false
        hovering = false
        onActiveChange?()
    }

    func toggleRunning() {
        if countdown != nil {
            cancelCountdown()
        } else if isRunning {
            stopRunning()
        } else {
            if offset(at: Date()) >= contentHeight - 1 {
                anchorOffset = 0
                resetVoicePosition()
            }
            run()
        }
    }

    func restart() {
        stopRunning()
        anchorOffset = 0
        resetVoicePosition()
        startCountdown()
    }

    /// Avança (positivo) ou volta (negativo) no texto. Seguindo a voz, ela continua dali.
    func nudge(by delta: CGFloat) {
        let target = min(max(offset(at: Date()) + delta, 0), contentHeight)
        if followVoice {
            glide(to: target, animated: false)
            let layout = self.layout
            let line = min(max(Int((target / layout.lineHeight).rounded()), 0), max(layout.lines.count - 1, 0))
            spokenIndex = layout.lines.isEmpty ? -1 : layout.lines[line].firstWord - 1
            matcher.reset(to: spokenIndex)
        } else {
            anchorOffset = target
            anchorDate = Date()
        }
    }

    func adjustSpeed(by step: Double) {
        anchorOffset = manualOffset(at: Date())
        anchorDate = Date()
        speed = min(max(speed + step, 10), 200)
    }

    private func run() {
        anchorDate = Date()
        isRunning = true
        endTimer?.invalidate()
        guard !followVoice else { return }
        endTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.contentHeight > 0, self.offset(at: Date()) >= self.contentHeight else { return }
            self.stopRunning()
        }
    }

    private func stopRunning() {
        if isRunning, !followVoice { anchorOffset = manualOffset(at: Date()) }
        isRunning = false
        endTimer?.invalidate()
        endTimer = nil
    }

    private func startCountdown() {
        cancelCountdown()
        for (i, n) in [3, 2, 1].enumerated() {
            schedule(after: Double(i) * 0.8) { [weak self] in self?.countdown = n }
        }
        schedule(after: 2.4) { [weak self] in
            self?.countdown = nil
            self?.run()
        }
    }

    private func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        countdownWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelCountdown() {
        countdownWork.forEach { $0.cancel() }
        countdownWork = []
        countdown = nil
    }

    // MARK: - Voz

    private func resetVoicePosition() {
        spokenIndex = -1
        matcher.reset()
        glide(to: 0, animated: false)
        if #available(macOS 26, *) { (listener as? VoiceListener)?.resetTranscript() }
    }

    /// Troca entre velocidade fixa e seguir a voz sem dar salto no texto.
    private func voiceModeChanged() {
        let now = Date()
        if followVoice {
            let current = min(max(manualOffset(at: now), 0), contentHeight)
            glide(to: current, animated: false)
            let layout = self.layout
            let line = min(Int(current / max(layout.lineHeight, 1)), max(layout.lines.count - 1, 0))
            spokenIndex = layout.lines.isEmpty ? -1 : layout.lines[line].firstWord - 1
            matcher.reset(to: spokenIndex)
            endTimer?.invalidate()
            if isActive { startListening() }
        } else {
            anchorOffset = min(max(voiceOffset(at: now), 0), contentHeight)
            anchorDate = now
            spokenIndex = -1
            stopListening()
            if isRunning { run() }
        }
    }

    private func startListening() {
        guard Self.voiceEnabled else { return }
        guard #available(macOS 26, *) else {
            voiceStatus = .needsNewerMac
            return
        }
        let voice = (listener as? VoiceListener) ?? VoiceListener()
        voice.onStatus = { [weak self] status in
            if self?.voiceStatus != status { voiceLog.notice("estado: \(String(describing: status), privacy: .public)") }
            self?.voiceStatus = status
        }
        voice.onTranscript = { [weak self] transcript in self?.heard(transcript) }
        listener = voice
        voiceLog.notice("ouvindo em \(self.voiceLanguage.rawValue, privacy: .public) (escolha: \(self.voiceLanguageChoice?.rawValue ?? "automático", privacy: .public))")
        voice.start(locale: voiceLanguage.speechLocale)
    }

    private func stopListening() {
        if #available(macOS 26, *) { (listener as? VoiceListener)?.stop() }
        voiceStatus = .off
    }

    private func heard(_ transcript: String) {
        guard isRunning, followVoice else { return }
        let layout = self.layout
        if matcherVersion != textVersion || matcher.words.count != layout.words.count {
            matcher = VoiceMatcher(words: layout.words.map(\.normalized))
            matcher.reset(to: spokenIndex)
            matcherVersion = textVersion
        }
        let recent = SpeechText.words(in: transcript).suffix(10).map(\.normalized)
        guard let index = matcher.update(heard: Array(recent)) else { return }
        voiceLog.notice("posição: palavra \(index + 1, privacy: .public) de \(layout.words.count, privacy: .public), linha \(layout.line(ofWord: index) + 1, privacy: .public)")
        spokenIndex = index
        glide(to: layout.offset(forWord: index))
    }

    /// Para as imagens de conferência (`--snapshot`).
    func showDemo(spokenThrough index: Int, status: VoiceStatus) {
        spokenIndex = index
        voiceStatus = status
        glide(to: layout.offset(forWord: index), animated: false)
    }

    private static func stored(_ key: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? value
    }
}

// MARK: - Linhas do roteiro

struct PrompterLine {
    let range: NSRange
    let firstWord: Int
    let wordCount: Int
}

struct PrompterLayout {
    let text: NSString
    let lines: [PrompterLine]
    let words: [ScriptWord]
    let lineHeight: CGFloat

    var maxOffset: CGFloat { CGFloat(max(lines.count - 1, 0)) * lineHeight }

    static func make(text: String, fontSize: CGFloat, width: CGFloat) -> PrompterLayout {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var ranges: [NSRange] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) {
            _, _, _, glyphRange, _ in
            ranges.append(manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
        }

        let words = SpeechText.words(in: text)
        var lines: [PrompterLine] = []
        var next = 0
        for range in ranges {
            let first = next
            while next < words.count, words[next].range.location < NSMaxRange(range) { next += 1 }
            lines.append(PrompterLine(range: range, firstWord: first, wordCount: next - first))
        }
        let lineHeight = ceil(manager.defaultLineHeight(for: font) + fontSize * 0.25)
        return PrompterLayout(text: text as NSString, lines: lines, words: words, lineHeight: lineHeight)
    }

    func line(ofWord index: Int) -> Int {
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].firstWord <= index { low = mid } else { high = mid - 1 }
        }
        return max(low, 0)
    }

    /// Onde parar o texto quando você acabou de falar a palavra `index`: a linha atual
    /// sobe aos poucos conforme você avança nela.
    func offset(forWord index: Int) -> CGFloat {
        guard index >= 0, !lines.isEmpty else { return 0 }
        let lineIndex = line(ofWord: index)
        let line = lines[lineIndex]
        let fraction = line.wordCount > 0 ? CGFloat(index - line.firstWord + 1) / CGFloat(line.wordCount) : 0
        return (CGFloat(lineIndex) + fraction * 0.5) * lineHeight
    }

    /// Parte já lida e parte ainda por ler de uma linha.
    func split(_ line: PrompterLine, spokenThrough spoken: Int) -> (read: String, unread: String) {
        let end = NSMaxRange(line.range)
        guard line.wordCount > 0, spoken >= line.firstWord else {
            return ("", Self.trimTrailing(text.substring(with: line.range)))
        }
        let last = min(spoken, line.firstWord + line.wordCount - 1)
        let cut = NSMaxRange(words[last].range)
        let read = text.substring(with: NSRange(location: line.range.location, length: cut - line.range.location))
        let unread = text.substring(with: NSRange(location: cut, length: end - cut))
        return (read, Self.trimTrailing(unread))
    }

    private static func trimTrailing(_ s: String) -> String {
        var s = s
        while let last = s.last, last.isWhitespace || last.isNewline { s.removeLast() }
        return s
    }
}

// MARK: - Na ilha

struct PrompterContent: View {
    let model: IslandModel
    /// Ações que abrem janelas ou fecham o modo (tratadas pelo AppDelegate).
    let onEdit: () -> Void

    var body: some View {
        let prompter = model.prompter
        let size = model.prompterSize
        let textHeight = size.height - model.geometry.notchSize.height
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(prompter.isRunning ? Color.red : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text(L(.teleprompter))
                }
                Spacer(minLength: model.geometry.notchSize.width + 20)
                if prompter.followVoice {
                    VoiceBadge(prompter: prompter)
                } else {
                    Text(prompter.speedLabel).monospacedDigit()
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .frame(height: model.geometry.notchSize.height)
            .padding(.horizontal, 18)

            ZStack(alignment: .bottom) {
                if prompter.isEmpty {
                    Text(L(.noScript))
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PrompterText(prompter: prompter, width: CGFloat(prompter.columnWidth), height: textHeight)
                }

                if let n = prompter.countdown {
                    Text("\(n)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 92)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(n)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                }

                PrompterControls(prompter: prompter, onEdit: onEdit, onClose: { prompter.end() })
                    .padding(.bottom, 12)
                    .opacity(prompter.hovering || !prompter.isRunning ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: prompter.hovering || !prompter.isRunning)
            }
            .frame(width: size.width, height: textHeight)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: prompter.countdown)
        }
    }
}

struct VoiceBadge: View {
    let prompter: Teleprompter

    var body: some View {
        let code = prompter.voiceLanguage.shortCode
        HStack(spacing: 4) {
            switch prompter.voiceStatus {
            case .off:
                Image(systemName: "mic")
                Text(code)
            case .preparing:
                Image(systemName: "waveform")
                Text(L(.voicePreparing))
            case .downloading(let fraction):
                Image(systemName: "arrow.down.circle")
                Text(L(.voiceDownloading, Int(fraction * 100))).monospacedDigit()
            case .listening:
                Image(systemName: "mic.fill").foregroundStyle(.green)
                Text(code)
            case .micDenied:
                Image(systemName: "mic.slash.fill").foregroundStyle(.red)
                Text(L(.voiceMicDenied))
            case .unsupported:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(L(.voiceUnsupported))
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(L(.voiceFailed)).help(message)
            case .needsNewerMac:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(L(.voiceNeedsNewerMac))
            }
        }
    }
}

struct PrompterText: View {
    let prompter: Teleprompter
    let width: CGFloat
    let height: CGFloat

    /// Onde fica a linha de leitura (logo abaixo da câmera).
    private let readingLine: CGFloat = 18

    var body: some View {
        let layout = prompter.layout
        let spoken = prompter.followVoice ? prompter.spokenIndex : -1
        let fontSize = CGFloat(prompter.fontSize)
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !prompter.isRunning)) { context in
            let offset = prompter.offset(at: context.date)
            let first = max(0, Int(floor((offset - readingLine) / layout.lineHeight)) - 1)
            let last = min(layout.lines.count, first + Int(ceil(height / layout.lineHeight)) + 3)
            ZStack(alignment: .top) {
                ForEach(first..<max(first, last), id: \.self) { index in
                    PrompterLineView(layout: layout, line: layout.lines[index], spoken: spoken, fontSize: fontSize)
                        .frame(width: width, height: layout.lineHeight)
                        .offset(y: readingLine + CGFloat(index) * layout.lineHeight - offset)
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipped()
        }
        .mask(LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.36), .init(color: .black.opacity(0.3), location: 0.62),
                    .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom))
        .scaleEffect(x: prompter.mirrored ? -1 : 1, y: 1)
    }
}

struct PrompterLineView: View {
    let layout: PrompterLayout
    let line: PrompterLine
    let spoken: Int
    let fontSize: CGFloat

    var body: some View {
        let parts = layout.split(line, spokenThrough: spoken)
        var read = AttributedString(parts.read)
        read.foregroundColor = .white.opacity(0.35)
        var unread = AttributedString(parts.unread)
        unread.foregroundColor = .white
        return Text(read + unread)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .animation(.easeOut(duration: 0.2), value: spoken)
    }
}

struct PrompterControls: View {
    let prompter: Teleprompter
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        let playing = prompter.isRunning || prompter.countdown != nil
        HStack(spacing: 4) {
            ControlButton(id: "p-voice", symbol: prompter.followVoice ? "mic.fill" : "mic.slash", size: 12) {
                prompter.followVoice.toggle()
            }
            .help(L(.voiceToggle))
            if !prompter.followVoice {
                ControlButton(id: "p-slower", symbol: "tortoise.fill", size: 12) { prompter.adjustSpeed(by: -10) }
                    .help(L(.slower))
            }
            ControlButton(id: "p-play", symbol: playing ? "pause.fill" : "play.fill", size: 16) { prompter.toggleRunning() }
            if !prompter.followVoice {
                ControlButton(id: "p-faster", symbol: "hare.fill", size: 12) { prompter.adjustSpeed(by: 10) }
                    .help(L(.faster))
            }
            Divider().frame(height: 18).overlay(Color.white.opacity(0.2)).padding(.horizontal, 4)
            ControlButton(id: "p-restart", symbol: "arrow.counterclockwise", size: 12) { prompter.restart() }
                .help(L(.restart))
            ControlButton(id: "p-edit", symbol: "pencil", size: 12) { onEdit() }
                .help(L(.editScript))
            ControlButton(id: "p-close", symbol: "xmark", size: 12) { onClose() }
                .help(L(.closePrompter))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color(white: 0.14)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
    }
}

// MARK: - Janela do roteiro

struct PrompterEditorView: View {
    let prompter: Teleprompter
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L(.script))
                    .font(.headline)
                Spacer()
                Button {
                    let copied = NSPasteboard.general.string(forType: .string) ?? ""
                    if copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NSSound.beep()
                    } else {
                        prompter.text = copied
                    }
                } label: {
                    Label(L(.pasteScript), systemImage: "doc.on.clipboard")
                }
                .help(L(.pasteScriptHelp))
            }
            TextEditor(text: Binding(get: { prompter.text }, set: { prompter.text = $0 }))
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L(.followVoice), isOn: Binding(get: { prompter.followVoice }, set: { prompter.followVoice = $0 }))
                HStack {
                    Text(L(.voiceLanguage))
                    Picker("", selection: Binding(
                        get: { prompter.voiceLanguageChoice?.rawValue ?? "auto" },
                        set: { prompter.voiceLanguageChoice = AppLanguage(rawValue: $0) })) {
                        Text(L(.voiceAuto, prompter.detectedVoiceLanguage.nativeName)).tag("auto")
                        Divider()
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.nativeName).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                }
                .disabled(!prompter.followVoice)
                Text(L(.voiceCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(L(.speed))
                    Slider(value: Binding(get: { prompter.speed }, set: { prompter.speed = $0 }), in: 10...160)
                    Text(prompter.speedLabel).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(prompter.followVoice)
                GridRow {
                    Text(L(.columnWidth))
                    Slider(value: Binding(get: { prompter.columnWidth }, set: { prompter.columnWidth = $0 }), in: 280...640)
                    Text("\(Int(prompter.columnWidth)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                GridRow {
                    Text(L(.textSize))
                    Slider(value: Binding(get: { prompter.fontSize }, set: { prompter.fontSize = $0 }), in: 16...48)
                    Text("\(Int(prompter.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Toggle(L(.hideFromCapture),
                   isOn: Binding(get: { prompter.hiddenFromCapture }, set: { prompter.hiddenFromCapture = $0 }))
            Text(L(.hideCaption))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L(.mirror),
                   isOn: Binding(get: { prompter.mirrored }, set: { prompter.mirrored = $0 }))

            HStack(alignment: .bottom) {
                Text(L(.shortcuts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L(.start), action: onStart)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(prompter.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 640)
        .environment(\.locale, Localization.shared.locale)
    }
}
