import Foundation
import IOKit.ps
import Observation

@Observable final class BatteryMonitor {
    private(set) var hasBattery = false
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var onAC = true

    @ObservationIgnored var onPowerSourceChange: ((BatteryMonitor) -> Void)?
    @ObservationIgnored var onLowBattery: ((Int) -> Void)?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    var symbol: String {
        if onAC { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    func start() {
        read(notify: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().read(notify: true)
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    private func read(notify: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let capacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : current
            let newAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let oldAC = onAC, oldLevel = level

            hasBattery = true
            level = newLevel
            onAC = newAC
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false

            if notify {
                if newAC != oldAC {
                    onPowerSourceChange?(self)
                } else if !newAC, [20, 10, 5].contains(where: { newLevel <= $0 && oldLevel > $0 }) {
                    onLowBattery?(newLevel)
                }
            }
            return
        }
    }
}
