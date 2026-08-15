import Foundation
import IOKit
import IOKit.ps

struct BatteryState {
    let percent: Int
    let voltage: Double
    let current: Double
    let powerWatts: Double
    let healthPercent: Int?
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeToFullMinutes: Int
    let timeToEmptyMinutes: Int
}

final class BatteryReader {
    static let shared = BatteryReader()

    func read() -> BatteryState {
        let info = readPowerSourceInfo()
        let smart = readSmartBatteryInfo()

        let percent = info.maxCapacity > 0
            ? max(0, min(100, Int(Double(info.currentCapacity) / Double(info.maxCapacity) * 100.0)))
            : 0
        let volts = Double(smart.voltage) / 1000.0
        let amps = Double(smart.current) / 1000.0
        let power = abs(amps) * volts

        return BatteryState(
            percent: percent,
            voltage: volts,
            current: amps,
            powerWatts: power,
            healthPercent: smart.healthPercent,
            isCharging: info.isCharging,
            isPluggedIn: info.isPluggedIn,
            timeToFullMinutes: info.isCharging ? max(0, info.timeToFull) : 0,
            timeToEmptyMinutes: !info.isCharging && !info.isPluggedIn ? info.timeToEmpty : -1
        )
    }

    private func readPowerSourceInfo() -> (currentCapacity: Int, maxCapacity: Int, isCharging: Bool, isPluggedIn: Bool, timeToFull: Int, timeToEmpty: Int) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return (0, 100, false, false, 0, -1)
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int ?? 0
        // -1 means "still calculating" — pass it through as-is rather than clamping to 0.
        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1

        return (currentCapacity, maxCapacity, isCharging, isPluggedIn, timeToFull, timeToEmpty)
    }

    private func readSmartBatteryInfo() -> (voltage: Int, current: Int, healthPercent: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (0, 0, nil) }
        defer { IOObjectRelease(service) }

        var propertiesUnmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propertiesUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = propertiesUnmanaged?.takeRetainedValue() as? [String: Any]
        else {
            return (0, 0, nil)
        }

        let voltage = properties["Voltage"] as? Int ?? 0
        let current = properties["Amperage"] as? Int ?? properties["InstantAmperage"] as? Int ?? 0

        // Battery health: nominal (calibrated) capacity vs. design capacity — matches
        // the "Maximum Capacity" figure under System Settings > Battery > Battery Health
        // (verified against `system_profiler SPPowerDataType`: NominalChargeCapacity is
        // the field that lines up, not FullChargeCapacity, which reads a few points low).
        var healthPercent: Int?
        if let batteryData = properties["BatteryData"] as? [String: Any],
           let designCapacity = batteryData["DesignCapacity"] as? Int, designCapacity > 0,
           let nominalChargeCapacity = batteryData["NominalChargeCapacity"] as? Int {
            let raw = Double(nominalChargeCapacity) / Double(designCapacity) * 100.0
            healthPercent = min(100, Int(raw.rounded()))
        }

        return (voltage, current, healthPercent)
    }
}
