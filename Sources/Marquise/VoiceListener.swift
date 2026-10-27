import AVFoundation
import NaturalLanguage
import Speech

enum VoiceStatus: Equatable {
    case off
    case preparing
    case downloading(Double)
    case listening
    case micDenied
    case unsupported
    case failed(String)
    case needsNewerMac
}

extension AppLanguage {
    var speechLocale: Locale {
        switch self {
        case .ptBR: Locale(identifier: "pt-BR")
        case .ptPT: Locale(identifier: "pt-PT")
        case .enUS: Locale(identifier: "en-US")
        case .enGB: Locale(identifier: "en-GB")
        case .es: Locale(identifier: "es-ES")
        }
    }

    /// Código curto mostrado na ilha enquanto escuta ("PT-BR", "EN-GB", "ES").
    var shortCode: String { rawValue.uppercased() }

    /// Idioma em que o roteiro está escrito; a variante (Brasil/Portugal, EUA/Reino Unido)
    /// segue o idioma da Marquise quando ele é do mesmo grupo.
    static func ofScript(_ text: String, preferring ui: AppLanguage) -> AppLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.portuguese, .english, .spanish]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .portuguese: return ui == .ptPT ? .ptPT : .ptBR
        case .english: return ui == .enGB ? .enGB : .enUS
        case .spanish: return .es
        default: return ui
        }
    }
}

/// Escuta o microfone e transcreve no próprio Mac (SpeechAnalyzer, macOS 26+).
/// Nenhum áudio sai do computador; o modelo do idioma é baixado pelo sistema na primeira vez.
@available(macOS 26, *)
final class VoiceListener {
    var onStatus: (VoiceStatus) -> Void = { _ in }
    /// Texto ouvido recentemente (trecho final já confirmado + trecho ainda provisório).
    var onTranscript: (String) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var setupTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var confirmed = ""
    private var generation = 0

    func start(locale: Locale) {
        stop()
        generation += 1
        let current = generation
        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.run(locale: locale, generation: current)
            } catch let error as VoiceError {
                guard current == self.generation else { return }
                self.onStatus(error.status)
                self.tearDown()
            } catch {
                guard current == self.generation, !Task.isCancelled else { return }
                self.onStatus(.failed(error.localizedDescription))
                self.tearDown()
            }
        }
    }

    func stop() {
        generation += 1
        setupTask?.cancel()
        setupTask = nil
        tearDown()
        onStatus(.off)
    }

    /// Esquece o que já foi ouvido (ao recomeçar o roteiro).
    func resetTranscript() { confirmed = "" }

    private enum VoiceError: Error {
        case micDenied, unsupported, noAudio
        var status: VoiceStatus {
            switch self {
            case .micDenied: .micDenied
            case .unsupported: .unsupported
            case .noAudio: .failed("Sem entrada de áudio")
            }
        }
    }

    @MainActor
    private func run(locale: Locale, generation current: Int) async throws {
        onStatus(.preparing)
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.micDenied }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { done in SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) } }
        }
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else { throw VoiceError.unsupported }
        // Cada `await` pode terminar depois de um stop(): uma sessão encerrada não mexe mais no estado.
        guard current == generation else { return }

        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [])

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            guard current == generation else { return }
            onStatus(.downloading(0))
            let progress = request.progress
            let observation = progress.observe(\.fractionCompleted) { [weak self] p, _ in
                let fraction = p.fractionCompleted
                Task { @MainActor in
                    guard let self, current == self.generation else { return }
                    self.onStatus(.downloading(fraction))
                }
            }
            defer { observation.invalidate() }
            try await request.downloadAndInstall()
        }
        guard current == generation else { return }

        let inputNode = engine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: micFormat)
        else { throw VoiceError.noAudio }
        let converter = micFormat == format ? nil : AVAudioConverter(from: micFormat, to: format)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self, current == self.generation else { return }
                    let text = String(result.text.characters)
                    voiceLog.debug("fala reconhecida: \(text.split(separator: " ").count, privacy: .public) palavra(s)")
                    if result.isFinal {
                        self.confirmed = String((self.confirmed + " " + text).suffix(600))
                        self.onTranscript(self.confirmed)
                    } else {
                        self.onTranscript(self.confirmed + " " + text)
                    }
                }
            } catch {}
        }

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: format) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
        try await analyzer.start(inputSequence: stream)
        guard current == generation else { return }
        onStatus(.listening)
    }

    private func tearDown() {
        resultsTask?.cancel()
        resultsTask = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        input?.finish()
        input = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        confirmed = ""
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
