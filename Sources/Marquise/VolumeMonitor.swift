import AudioToolbox
import CoreAudio
import Observation
import os

let volumeLog = Logger(subsystem: "com.marquise.app", category: "volume")

/// Como o volume da saída de som atual pode ser mudado.
enum VolumeBackend: Equatable {
    /// Pelo macOS (alto-falantes do Mac, fones, caixas USB ou Bluetooth…).
    case system
    /// No próprio Mac, antes de o som sair (saídas sem volume, como monitores por DisplayPort ou HDMI).
    case software
    /// Direto no monitor, pelo cabo (DDC).
    case monitor
    /// Saída sem controle de volume.
    case none
}

/// Como controlar saídas que o macOS não controla (monitores e TVs).
enum VolumeMethod: String {
    /// No Mac: funciona com qualquer monitor, mas precisa da permissão de áudio do sistema.
    case mac
    /// No monitor, pelo cabo: sem permissão, mas só se os alto-falantes do monitor obedecerem.
    case monitor

    static var current: VolumeMethod {
        get { UserDefaults.standard.string(forKey: "volume.method").flatMap(VolumeMethod.init(rawValue:)) ?? .mac }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "volume.method") }
    }
}

/// Observa e controla o volume da saída padrão.
@Observable final class VolumeMonitor {
    private(set) var deviceName = ""
    private(set) var backend: VolumeBackend = .none
    private(set) var level: Float = 0
    private(set) var muted = false
    /// A pessoa negou "Gravação de áudio do sistema": o volume pelo Mac não está disponível.
    private(set) var permissionDenied = false
    /// Avisa mudanças de volume (para o indicador na ilha fechada).
    @ObservationIgnored var onChange: ((Float, Bool) -> Void)?

    @ObservationIgnored private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    @ObservationIgnored private let unknown = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var device = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var last: (volume: Float, muted: Bool)?

    @ObservationIgnored private var display: DDCDisplay?
    /// Para o mudo no monitor, que não tem um mudo padrão: guarda o volume e manda 0.
    @ObservationIgnored private var levelBeforeMute: Float = 0.5
    @ObservationIgnored private var monitorMax = 100
    @ObservationIgnored private let pending = Pending()
    @ObservationIgnored private var bindGeneration = 0
    @ObservationIgnored private var deviceUID = ""
    /// `SoftwareVolume` em uso (guardado sem tipo porque só existe no macOS 14.2+).
    @ObservationIgnored private var software: AnyObject?
    @ObservationIgnored private var askingPermission = false

    @ObservationIgnored private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    @ObservationIgnored private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    @ObservationIgnored private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    @ObservationIgnored private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }

    func start() {
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultDeviceAddress, .main) { [weak self] _, _ in
            self?.bindDefaultDevice()
        }
        bindDefaultDevice()
    }

    /// Relê o volume do monitor (pode ter mudado pelos botões dele).
    func refresh() {
        if backend == .monitor { readMonitor(generation: bindGeneration) }
    }

    /// O macOS não muda o volume desta saída: a Marquise faz isso (as teclas de volume também).
    var controlsOutsideMacOS: Bool { backend == .software || backend == .monitor }

    /// Ao sair: devolve o som direto à saída na hora.
    func shutdown() { stopSoftware() }

    /// Mudou o jeito de controlar monitores (menu).
    func methodChanged() { bindDefaultDevice() }

    /// Depois que o Mac acorda, a saída pode ter sido recriada: monta o volume pelo Mac de novo.
    func restartSoftware() {
        guard backend == .software else { return }
        stopSoftware()
        applySoftware(userInitiated: false)
    }

    /// Para as imagens de conferência (`--snapshot`).
    func showDemo(name: String, level: Float) {
        deviceName = name
        backend = .monitor
        self.level = level
    }

    // MARK: - Controle

    func set(_ value: Float) {
        let value = min(max(value, 0), 1)
        switch backend {
        case .system:
            var volume = Float32(value)
            AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            if muted && value > 0 { setSystemMute(false) }
        case .software:
            level = value
            muted = false
            storeSoftwareLevel()
            applySoftware(userInitiated: true)
            onChange?(value, false)
        case .monitor:
            level = value
            muted = false
            sendToMonitor(value)
            onChange?(value, false)
        case .none:
            break
        }
    }

    func step(by delta: Float) {
        set((muted ? 0 : level) + delta)
    }

    func toggleMute() {
        switch backend {
        case .system:
            if canMuteSystem {
                setSystemMute(!muted)
            } else if muted || level == 0 {
                set(levelBeforeMute)
            } else {
                levelBeforeMute = level
                set(0)
            }
        case .software:
            muted.toggle()
            applySoftware(userInitiated: true)
            onChange?(level, muted)
        case .monitor:
            if muted {
                muted = false
                level = max(levelBeforeMute, 0.05)
                sendToMonitor(level)
            } else {
                levelBeforeMute = level
                muted = true
                sendToMonitor(0)
            }
            onChange?(level, muted)
        case .none:
            break
        }
    }

    // MARK: - Saída padrão

    private func bindDefaultDevice() {
        if device != unknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, listener)
        }
        bindGeneration += 1
        display = nil
        stopSoftware()
        permissionDenied = false

        var id = unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(systemObject, &defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        deviceName = Self.name(of: id)
        guard id != unknown else {
            backend = .none
            return
        }

        if isSettable(&volumeAddress) {
            volumeLog.notice("saída \(self.deviceName, privacy: .public): volume pelo macOS")
            backend = .system
            AudioObjectAddPropertyListenerBlock(id, &volumeAddress, .main, listener)
            if AudioObjectHasProperty(id, &muteAddress) {
                AudioObjectAddPropertyListenerBlock(id, &muteAddress, .main, listener)
            }
            last = read()
            if let last { (level, muted) = last }
        } else if VolumeMethod.current == .mac, #available(macOS 14.2, *), SystemAudioPermission.status != .denied {
            useSoftwareVolume()
        } else if Self.isDisplayOutput(id) {
            permissionDenied = VolumeMethod.current == .mac && softwareSupported
            // Fica sem controle até o monitor responder.
            backend = .none
            readMonitor(generation: bindGeneration)
        } else {
            permissionDenied = VolumeMethod.current == .mac && softwareSupported
            backend = .none
        }
    }

    // MARK: - Volume pelo Mac

    private var softwareSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    private func useSoftwareVolume() {
        deviceUID = Self.uid(of: device)
        backend = .software
        muted = false
        level = (UserDefaults.standard.dictionary(forKey: "volume.software")?[deviceUID] as? Double).map(Float.init) ?? 1
        volumeLog.notice("saída \(self.deviceName, privacy: .public): volume pelo Mac")
        applySoftware(userInitiated: false)
    }

    private func storeSoftwareLevel() {
        guard !deviceUID.isEmpty else { return }
        var levels = UserDefaults.standard.dictionary(forKey: "volume.software") ?? [:]
        levels[deviceUID] = Double(level)
        UserDefaults.standard.set(levels, forKey: "volume.software")
    }

    /// Liga o desvio do som só quando é preciso (abaixo de 100% ou mudo); em 100% o som passa direto.
    private func applySoftware(userInitiated: Bool) {
        guard #available(macOS 14.2, *), backend == .software else { return }
        let needed = muted || level < 0.999
        guard needed else {
            stopSoftware()
            return
        }
        if let engine = software as? SoftwareVolume {
            engine.setLevel(muted ? 0 : level)
            return
        }
        switch SystemAudioPermission.status {
        case .authorized:
            startSoftware()
        case .denied:
            permissionDenied = true
            bindDefaultDevice()
        case .unknown:
            // Só pergunta quando a pessoa mexe no volume, nunca ao abrir o app.
            guard userInitiated, !askingPermission else { return }
            askingPermission = true
            SystemAudioPermission.ask { [weak self] granted in
                guard let self else { return }
                self.askingPermission = false
                if granted {
                    self.startSoftware()
                } else {
                    volumeLog.notice("volume pelo Mac: permissão negada")
                    self.bindDefaultDevice()
                }
            }
        }
    }

    private func startSoftware() {
        guard #available(macOS 14.2, *), backend == .software, software == nil, !deviceUID.isEmpty else { return }
        let engine = SoftwareVolume(outputUID: deviceUID)
        engine.setLevel(muted ? 0 : level)
        do {
            try engine.start()
            software = engine
            volumeLog.notice("volume pelo Mac: ativo")
        } catch let failure as SoftwareVolume.Failure {
            volumeLog.error("volume pelo Mac: falhou em \(failure.step, privacy: .public) (\(failure.status, privacy: .public))")
        } catch {
            volumeLog.error("volume pelo Mac: falhou")
        }
    }

    private func stopSoftware() {
        guard #available(macOS 14.2, *), let engine = software as? SoftwareVolume else { return }
        engine.stop()
        software = nil
        volumeLog.notice("volume pelo Mac: som direto (100%)")
    }

    private func read() -> (volume: Float, muted: Bool)? {
        guard device != unknown, AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume)

        var muted: UInt32 = 0
        if AudioObjectHasProperty(device, &muteAddress) {
            size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        }
        return (volume, muted != 0)
    }

    private func changed() {
        guard backend == .system, let now = read() else { return }
        if let last, abs(last.volume - now.volume) < 0.001, last.muted == now.muted { return }
        last = now
        (level, muted) = now
        onChange?(now.volume, now.muted)
    }

    private var canMuteSystem: Bool { isSettable(&muteAddress) }

    private func setSystemMute(_ on: Bool) {
        var value: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func isSettable(_ address: inout AudioObjectPropertyAddress) -> Bool {
        guard device != unknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func name(of id: AudioObjectID) -> String {
        guard id != AudioObjectID(kAudioObjectUnknown) else { return "" }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }

    private static func uid(of id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &uid) == noErr, let uid else { return "" }
        return uid.takeRetainedValue() as String
    }

    private static func isDisplayOutput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI
    }

    // MARK: - Monitor (DDC)

    /// Com mais de um monitor externo, usa o primeiro que responde ao controle de volume.
    private func readMonitor(generation: Int) {
        let known = display
        DDCDisplay.queue.async { [weak self] in
            let candidates = known.map { [$0] } ?? DDCDisplay.external()
            var found: (DDCDisplay, value: Int, max: Int)?
            for candidate in candidates {
                if let reading = candidate.read(.volume) {
                    found = (candidate, reading.value, reading.max)
                    break
                }
            }
            DispatchQueue.main.async {
                guard let self, generation == self.bindGeneration else { return }
                guard let found else {
                    volumeLog.notice("saída \(self.deviceName, privacy: .public): monitor não respondeu ao DDC")
                    self.backend = .none
                    return
                }
                volumeLog.notice("saída \(self.deviceName, privacy: .public): volume pelo monitor (DDC), \(found.value, privacy: .public)/\(found.max, privacy: .public)")
                self.display = found.0
                self.monitorMax = found.max
                self.backend = .monitor
                let level = Float(found.value) / Float(found.max)
                if self.muted && level > 0 { self.muted = false }
                if !self.muted { self.level = level }
            }
        }
    }

    /// Arrastar a barra gera muitos valores: o monitor recebe só o mais recente, um de cada vez.
    private func sendToMonitor(_ value: Float) {
        guard let display else { return }
        let target = Int((value * Float(monitorMax)).rounded())
        guard pending.store(target) else { return }  // já há um envio em andamento
        DDCDisplay.queue.async { [pending] in
            while let next = pending.take() {
                let sent = display.write(.volume, value: next)
                volumeLog.debug("monitor ← volume \(next, privacy: .public): \(sent ? "enviado" : "falhou", privacy: .public)")
                usleep(50_000)
            }
        }
    }
}

/// Valor esperando para ir ao monitor, compartilhado entre a fila principal e a do DDC.
private final class Pending: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?
    private var sending = false

    /// Guarda o valor; devolve true se é preciso começar um envio.
    func store(_ new: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        value = new
        if sending { return false }
        sending = true
        return true
    }

    /// Próximo valor a enviar, ou nil (e encerra o envio) se não há nada novo.
    func take() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let next = value else {
            sending = false
            return nil
        }
        value = nil
        return next
    }
}
