import CoreAudio
import AppKit
import Foundation

/// One process currently running audio *input* on a specific device.
struct MicUser: Equatable {
    let pid: pid_t
    /// Best-effort display name: app name → bundle id → "PID x".
    let name: String
}

/// Who is holding the microphone? Enumerates CoreAudio *process objects*
/// (macOS 12+) and returns every process running input IO on `deviceID`.
///
/// This answers the question `DeviceIsRunningSomewhere` can't: *which app*
/// opened the Bluetooth mic directly — bypassing the default-input lock — and
/// dragged the headset into HFP (degraded output).
func audioProcessesRunningInput(on deviceID: AudioDeviceID) -> [MicUser] {
    processObjectIDs().compactMap { obj -> MicUser? in
        guard processUInt32(obj, kAudioProcessPropertyIsRunningInput) == 1,
              processDeviceList(obj).contains(deviceID),
              let pid = processPID(obj) else { return nil }
        return MicUser(pid: pid, name: displayName(for: pid, fallback: processBundleID(obj)))
    }
}

// MARK: - AudioProcessObject plumbing

private func processObjectIDs() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(kSystemObject, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(kSystemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

private func processPropertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain)
}

private func processUInt32(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var address = processPropertyAddress(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(obj, &address, 0, nil, &size, &value) == noErr else { return 0 }
    return value
}

private func processPID(_ obj: AudioObjectID) -> pid_t? {
    var address = processPropertyAddress(kAudioProcessPropertyPID)
    var pid: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    guard AudioObjectGetPropertyData(obj, &address, 0, nil, &size, &pid) == noErr, pid > 0 else { return nil }
    return pid
}

private func processBundleID(_ obj: AudioObjectID) -> String? {
    var address = processPropertyAddress(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &address, 0, nil, &size, &value) == noErr,
          let s = value else { return nil }
    return s.takeRetainedValue() as String
}

private func processDeviceList(_ obj: AudioObjectID) -> [AudioObjectID] {
    // Apple documents this property as scope-sensitive: input scope returns
    // devices used for capture, output scope returns devices used for playback.
    // Global scope can return no usable match and made real mic holders appear
    // as the generic "an app" fallback.
    var address = processPropertyAddress(
        kAudioProcessPropertyDevices,
        scope: kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

/// Resolves a pid to something worth showing: the app's localized name when it
/// has one, else the CoreAudio-reported bundle id, else a bare "PID x".
private func displayName(for pid: pid_t, fallback bundleID: String?) -> String {
    if let app = NSRunningApplication(processIdentifier: pid),
       let name = app.localizedName, !name.isEmpty {
        return name
    }
    if let bundleID, !bundleID.isEmpty { return bundleID }
    return "PID \(pid)"
}
