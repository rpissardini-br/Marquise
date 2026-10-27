import AudioToolbox
import CoreAudio
import Foundation

/// Volume feito no próprio Mac, para saídas que o macOS não deixa controlar (monitores e TVs por
/// DisplayPort ou HDMI). O som de todos os apps é desviado antes de sair, multiplicado pelo volume
/// e entregue à mesma saída. Nada é gravado: cada pedacinho de som passa e é descartado.
///
/// Usa as "taps" de processo do Core Audio (macOS 14.2+). O som original só fica mudo enquanto a
/// Marquise está repassando: se ela parar ou fechar, o macOS volta a tocar direto na saída.
@available(macOS 14.2, *)
final class SoftwareVolume {
    /// Volume pedido (0…1, já na curva de audição) e o que está sendo aplicado agora.
    /// Lidos na thread de áudio; uma leitura atrasada só deixa a rampa um pedaço mais longa.
    private final class Gain: @unchecked Sendable {
        var target: Float = 1
        var current: Float = 1
    }

    private let outputUID: String
    private let gain = Gain()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "marquise.audio", qos: .userInteractive)

    var isRunning: Bool { procID != nil }

    init(outputUID: String) { self.outputUID = outputUID }

    deinit { stop() }

    /// Volume da barra (0…1). A audição é logarítmica: a curva deixa o meio da barra soar como meio volume.
    func setLevel(_ level: Float) {
        let level = min(max(level, 0), 1)
        gain.target = level * level
    }

    func start() throws {
        guard !isRunning else { return }
        do {
            try createTap()
            try createAggregate()
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    struct Failure: Error {
        let step: String
        let status: OSStatus
    }

    // MARK: - Montagem

    private func createTap() throws {
        // A própria Marquise fica de fora: o som que ela devolve não pode voltar para a tap.
        let me = try Self.ownProcessObject()
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [me])
        description.uuid = UUID()
        description.name = "Marquise volume"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr else { throw Failure(step: "tap", status: status) }
        tapID = id
    }

    private func createAggregate() throws {
        let tapUID = try Self.string(tapID, kAudioTapPropertyUID)
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Marquise",
            kAudioAggregateDeviceUIDKey: "com.marquise.app.volume." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else { throw Failure(step: "aggregate", status: status) }
        aggregateID = id
    }

    private func startIO() throws {
        let gain = gain
        var id: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&id, aggregateID, queue) { _, input, _, output, _ in
            Self.render(input: input, output: output, gain: gain)
        }
        guard status == noErr, let id else { throw Failure(step: "ioproc", status: status) }
        procID = id
        status = AudioDeviceStart(aggregateID, id)
        guard status == noErr else { throw Failure(step: "start", status: status) }
        volumeLog.debug("agregado: rodando=\(Self.uint(self.aggregateID, kAudioDevicePropertyDeviceIsRunning), privacy: .public) entrada=\(Self.channels(self.aggregateID, kAudioDevicePropertyScopeInput), privacy: .public) saída=\(Self.channels(self.aggregateID, kAudioDevicePropertyScopeOutput), privacy: .public) tap=\(self.tapID, privacy: .public)")
    }

    // MARK: - Áudio (thread de tempo real: sem alocação nem travas)

    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Gain) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        // A tap entrega estéreo: um buffer intercalado (L R L R…) ou dois buffers de um canal.
        var left: UnsafeMutablePointer<Float>?
        var right: UnsafeMutablePointer<Float>?
        var stride = 1
        var inputFrames = 0
        if let stereo = inputs.last(where: { $0.mNumberChannels >= 2 }), let data = stereo.mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            stride = Int(stereo.mNumberChannels)
            left = samples
            right = samples + 1
            inputFrames = Int(stereo.mDataByteSize) / (4 * stride)
        } else if inputs.count >= 2, let l = inputs[inputs.count - 2].mData, let r = inputs[inputs.count - 1].mData {
            left = l.assumingMemoryBound(to: Float.self)
            right = r.assumingMemoryBound(to: Float.self)
            inputFrames = Int(inputs[inputs.count - 1].mDataByteSize) / 4
        }

        let start = gain.current
        let target = gain.target
        var outputChannel = 0
        for buffer in outputs {
            guard let data = buffer.mData else { continue }
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / (4 * max(channels, 1))
            let out = data.assumingMemoryBound(to: Float.self)
            // Rampa curta do volume anterior ao novo, para não estalar ao arrastar a barra.
            let step = frames > 0 ? (target - start) / Float(frames) : 0
            for frame in 0..<frames {
                let g = start + step * Float(frame)
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    // Só os dois primeiros canais da saída recebem som, como acontece sem a Marquise.
                    let source: UnsafeMutablePointer<Float>? = switch outputChannel + channel {
                    case 0: left
                    case 1: right
                    default: nil
                    }
                    if let source, frame < inputFrames {
                        out[index] = source[frame * stride] * g
                    } else {
                        out[index] = 0
                    }
                }
            }
            outputChannel += channels
        }
        gain.current = target
    }

    // MARK: - Utilidades

    private static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func channels(_ object: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return -1 }
        let list = AudioBufferList.allocate(maximumBuffers: Int(size) / MemoryLayout<AudioBuffer>.stride + 1)
        defer { free(list.unsafeMutablePointer) }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, list.unsafeMutablePointer) == noErr else { return -2 }
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func ownProcessObject() throws -> AudioObjectID {
        var pid = getpid()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { throw Failure(step: "process", status: status) }
        return object
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { throw Failure(step: "uid", status: status) }
        return value.takeRetainedValue() as String
    }
}

/// Permissão "Gravação de áudio do sistema", exigida pelas taps.
/// O macOS não tem API pública para consultar ou pedir essa permissão; estas funções do TCC
/// (as mesmas usadas por outros apps de áudio) são carregadas na hora e, se faltarem,
/// a Marquise trata como "ainda não decidido" e o próprio macOS pergunta ao criar a tap.
enum SystemAudioPermission {
    enum Status { case authorized, denied, unknown }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void

    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let preflight = dlsym(tcc, "TCCAccessPreflight").map { unsafeBitCast($0, to: Preflight.self) }
    private static let request = dlsym(tcc, "TCCAccessRequest").map { unsafeBitCast($0, to: Request.self) }
    private static let service = "kTCCServiceAudioCapture" as CFString

    static var status: Status {
        guard let preflight else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Mostra o pedido do macOS; a resposta chega na fila principal.
    static func ask(_ completion: @escaping (Bool) -> Void) {
        guard let request else {
            completion(true)  // sem como perguntar antes: o macOS pergunta ao criar a tap
            return
        }
        request(service, nil) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
