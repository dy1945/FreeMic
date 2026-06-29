import Foundation
import IOKit

/// Battery levels for the connected Bluetooth headphone, in `0...100`.
/// Any field may be `nil` when the device doesn't report that part — AirPods-style
/// buds expose left / right / case separately, while most headsets (e.g. FreeBuds)
/// report a single combined level.
struct BatteryReading: Equatable {
    /// Physical form, used to label the level correctly (and pick the glyph).
    ///  • `earbuds`  分体式 — true-wireless buds (may have L / R / case).
    ///  • `overEar`  头戴式 — a single battery, no case, no per-side.
    ///  • `unknown`  can't tell from the data macOS exposes.
    enum Form: Equatable { case earbuds, overEar, unknown }

    var single: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var form: Form = .unknown

    var isEmpty: Bool { single == nil && left == nil && right == nil && caseLevel == nil }

    /// True when macOS gave us per-bud detail (only Apple/Beats-class devices do).
    var hasPerBud: Bool { left != nil || right != nil }

    /// The single number worth surfacing in the compact badge: an explicit
    /// combined level, else the lower of the two buds (the one to worry about).
    /// Note: this is always the *earphone* level — the case is reported
    /// separately in `caseLevel` and is never folded in here.
    var primary: Int? {
        if let single { return single }
        return [left, right].compactMap { $0 }.min()
    }
}

/// Classifies the headphone form factor from the data macOS exposes. Presence of
/// per-bud / case levels is conclusive; otherwise a small known-model table on
/// the device name decides, falling back to `.unknown` (labelled neutrally so we
/// never mislabel a single value as the charging case).
private func bt_classifyForm(name: String, hasPerBud: Bool, hasCase: Bool) -> BatteryReading.Form {
    if hasPerBud || hasCase { return .earbuds }
    let n = name.lowercased()
    let overEar = ["airpods max", "wh-", "wh1000", "quietcomfort", "qc35", "qc45",
                   "momentum", "px7", "px8", "ath-m", "studio3", "studio pro", "h95", "h9"]
    if overEar.contains(where: n.contains) { return .overEar }
    let earbuds = ["airpods", "freebuds", "wf-", "earbuds", "buds", "pods",
                   "liberty", "melody", "jabra elite", "galaxy buds"]
    if earbuds.contains(where: n.contains) { return .earbuds }
    return .unknown
}

// MARK: - Reading the level

/// Reads the current Bluetooth headphone battery, preferring the instant
/// IORegistry path (Apple HID devices) and falling back to `system_profiler`
/// (which also covers third-party headsets like Huawei FreeBuds).
///
/// Call this OFF the main thread — `system_profiler` spawns a subprocess and can
/// take a second or two.
func bt_readBattery(matching name: String) -> BatteryReading {
    var reading = bt_batteryFromIORegistry()
    if reading.isEmpty { reading = bt_batteryFromSystemProfiler(matching: name) }
    guard !reading.isEmpty else { return reading }
    reading.form = bt_classifyForm(name: name,
                                   hasPerBud: reading.hasPerBud,
                                   hasCase: reading.caseLevel != nil)
    return reading
}

/// Fast path: AirPods / Apple HID accessories publish `BatteryPercent*` keys on
/// their `AppleDeviceManagementHIDEventService` IORegistry entry — the same data
/// `ioreg` shows. Returns empty for devices that don't (most non-Apple headsets).
private func bt_batteryFromIORegistry() -> BatteryReading {
    var reading = BatteryReading()
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return reading
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
        func percent(_ key: String) -> Int? {
            guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue(), let n = cf as? NSNumber else { return nil }
            let v = n.intValue
            return v > 0 ? v : nil   // 0 means "not reported" here, not an empty battery
        }
        if let s = percent("BatteryPercent")     { reading.single = s }
        if let l = percent("BatteryPercentLeft") { reading.left = l }
        if let r = percent("BatteryPercentRight") { reading.right = r }
        if let c = percent("BatteryPercentCase") { reading.caseLevel = c }

        IOObjectRelease(service)
        if !reading.isEmpty { break }
        service = IOIteratorNext(iterator)
    }
    return reading
}

/// Fallback: parse `system_profiler SPBluetoothDataType -json`, which reports
/// `device_batteryLevel*` (e.g. "100%") for connected Bluetooth devices —
/// including third-party headsets that the IORegistry path misses.
private func bt_batteryFromSystemProfiler(matching name: String) -> BatteryReading {
    var reading = BatteryReading()
    guard let data = bt_runSystemProfiler(),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return reading }

    /// "80%" → 80; tolerant of stray spaces.
    func pct(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    for section in sections {
        guard let connected = section["device_connected"] as? [[String: Any]] else { continue }

        // Each entry is [deviceName: properties]. Prefer the device whose name
        // matches the current output; otherwise the first one reporting battery.
        var named: [String: Any]?
        var anyWithBattery: [String: Any]?
        for entry in connected {
            for (devName, value) in entry {
                guard let props = value as? [String: Any] else { continue }
                let hasBattery = props["device_batteryLevelMain"] != nil
                    || props["device_batteryLevelLeft"] != nil
                    || props["device_batteryLevelRight"] != nil
                    || props["device_batteryLevelCase"] != nil
                guard hasBattery else { continue }
                if devName == name { named = props }
                if anyWithBattery == nil { anyWithBattery = props }
            }
        }

        if let props = named ?? anyWithBattery {
            reading.single = pct(props["device_batteryLevelMain"])
            reading.left = pct(props["device_batteryLevelLeft"])
            reading.right = pct(props["device_batteryLevelRight"])
            reading.caseLevel = pct(props["device_batteryLevelCase"])
        }
        if !reading.isEmpty { break }
    }
    return reading
}

/// Runs `system_profiler SPBluetoothDataType -json` and returns its stdout.
private func bt_runSystemProfiler() -> Data? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    task.arguments = ["SPBluetoothDataType", "-json"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return data
}
