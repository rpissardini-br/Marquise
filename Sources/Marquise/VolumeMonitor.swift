import AudioToolbox
import CoreAudio

/// Observa o volume da saída padrão via CoreAudio (não precisa de permissão).
final class VolumeMonitor {
    var onChange: ((Float, Bool) -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let unknown = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var last: (volume: Float, muted: Bool)?

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }

    func start() {
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultDeviceAddress, .main) { [weak self] _, _ in
            self?.bindDefaultDevice()
        }
        bindDefaultDevice()
    }

    private func bindDefaultDevice() {
        if device != unknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, listener)
        }

        var id = unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(systemObject, &defaultDeviceAddress, 0, nil, &size, &id)
        device = id
        guard id != unknown else { return }

        if AudioObjectHasProperty(id, &volumeAddress) {
            AudioObjectAddPropertyListenerBlock(id, &volumeAddress, .main, listener)
        }
        if AudioObjectHasProperty(id, &muteAddress) {
            AudioObjectAddPropertyListenerBlock(id, &muteAddress, .main, listener)
        }
        last = read()
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
        guard let now = read() else { return }
        if let last, abs(last.volume - now.volume) < 0.001, last.muted == now.muted { return }
        last = now
        onChange?(now.volume, now.muted)
    }
}
