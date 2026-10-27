import AppKit
import ApplicationServices

/// Faz as teclas de volume do teclado controlarem o monitor externo.
/// Quando o som sai por DisplayPort ou HDMI, o macOS mostra o aviso de "indisponível" e não muda nada;
/// aqui a Marquise pega essas teclas e manda o volume para o monitor.
///
/// Precisa da permissão de Acessibilidade (para ver as teclas antes do macOS). Só as teclas de
/// volume e mudo são lidas, e só são retidas quando a saída é um monitor; todas as outras passam direto.
final class VolumeKeys {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "volume.keys") }
        set { UserDefaults.standard.set(newValue, forKey: "volume.keys") }
    }

    private let volume: VolumeMonitor
    /// Avisa quando as teclas passam a funcionar ou param (para a barra de volume da ilha).
    var onActiveChange: (Bool) -> Void = { _ in }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var waitTimer: Timer?

    init(volume: VolumeMonitor) { self.volume = volume }

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Liga a escuta; se faltar a permissão, pede uma vez e espera ela ser dada.
    func start(askingPermission: Bool) {
        guard tap == nil else { return }
        if !isTrusted {
            volumeLog.notice("teclas de volume: esperando a permissão de Acessibilidade")
            if askingPermission {
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
            waitForPermission()
            return
        }
        install()
    }

    func stop() {
        waitTimer?.invalidate()
        waitTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        onActiveChange(false)
    }

    private func waitForPermission() {
        waitTimer?.invalidate()
        waitTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, Self.enabled else {
                timer.invalidate()
                return
            }
            if self.isTrusted {
                timer.invalidate()
                self.waitTimer = nil
                self.install()
            }
        }
    }

    private func install() {
        // Teclas de mídia chegam como eventos "definidos pelo sistema" (NX_SYSDEFINED = 14).
        let mask = CGEventMask(1 << 14)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let keys = Unmanaged<VolumeKeys>.fromOpaque(context).takeUnretainedValue()
                return keys.handle(type: type, event: event)
            },
            userInfo: context)
        else {
            volumeLog.error("teclas de volume: o macOS recusou a escuta do teclado")
            return
        }
        volumeLog.notice("teclas de volume: ativas")
        onActiveChange(true)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // O macOS desliga a escuta se ela demorar; liga de novo.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard volume.controlsOutsideMacOS,
              let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let key = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        // NX_KEYTYPE_SOUND_UP = 0, SOUND_DOWN = 1, MUTE = 7.
        guard [0, 1, 7].contains(key) else { return Unmanaged.passUnretained(event) }
        volumeLog.debug("tecla de volume \(key, privacy: .public) \(isDown ? "apertada" : "solta", privacy: .public)")
        if isDown {
            // Como no macOS: ⇧⌥ muda em passos menores.
            let fine = ns.modifierFlags.contains([.shift, .option])
            let step: Float = fine ? 1 / 64 : 1 / 16
            DispatchQueue.main.async { [volume] in
                switch key {
                case 0: volume.step(by: step)
                case 1: volume.step(by: -step)
                default: volume.toggleMute()
                }
            }
        }
        return nil
    }
}
