import CoreAudio
import AudioToolbox
import Foundation

/// Thin, typed wrappers over the CoreAudio HAL property API.
/// All functions are read-only except `ca_setDefaultInput`.

let kSystemObject = AudioObjectID(kAudioObjectSystemObject)

/// Returns the device ID for a system-level default selector
/// (e.g. `kAudioHardwarePropertyDefaultOutputDevice`).
func ca_defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(kSystemObject, &address, 0, nil, &size, &dev)
    return dev
}

/// Sets the system default input device. Returns true on success.
func ca_setDefaultInput(_ id: AudioDeviceID) -> Bool {
    var dev = id
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectSetPropertyData(
        kSystemObject, &address, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
    return status == noErr
}

/// All hardware audio devices known to the system.
func ca_allDevices() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(kSystemObject, &address, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    guard count > 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(kSystemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

/// Human-readable device name. Falls back to a placeholder if unavailable.
func ca_name(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
    guard status == noErr, let n = name else { return "未知设备" }
    return n.takeRetainedValue() as String
}

/// Number of audio channels a device exposes in the given scope.
private func ca_channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let ptr = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { ptr.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr) == noErr else { return 0 }
    let abl = UnsafeMutableAudioBufferListPointer(ptr.assumingMemoryBound(to: AudioBufferList.self))
    var channels = 0
    for buffer in abl { channels += Int(buffer.mNumberChannels) }
    return channels
}

/// True if the device has at least one input channel (i.e. it's a microphone source).
func ca_hasInput(_ id: AudioDeviceID) -> Bool {
    ca_channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0
}

/// Transport type, e.g. `kAudioDeviceTransportTypeBluetooth` / `...BuiltIn`.
func ca_transportType(_ id: AudioDeviceID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var t: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &address, 0, nil, &size, &t)
    return t
}

/// Registers a main-queue listener for a system-object property change.
func ca_addSystemListener(_ selector: AudioObjectPropertySelector,
                          _ handler: @escaping () -> Void) {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    _ = AudioObjectAddPropertyListenerBlock(kSystemObject, &address, DispatchQueue.main) { _, _ in
        handler()
    }
}

/// True if *any* process is currently running IO on the device. For a Bluetooth
/// headset this flips to `true` while its mic is in use (HFP call) and back to
/// `false` once released — the signal we use to detect "the meeting ended".
func ca_isRunningSomewhere(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

/// Registers a main-queue listener on a *specific device's* property and returns
/// the block, which must be passed back to `ca_removeDeviceListener` to detach.
func ca_addDeviceListener(_ id: AudioDeviceID,
                          _ selector: AudioObjectPropertySelector,
                          _ handler: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
    AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block)
    return block
}

/// Detaches a listener previously registered with `ca_addDeviceListener`.
func ca_removeDeviceListener(_ id: AudioDeviceID,
                             _ selector: AudioObjectPropertySelector,
                             _ block: @escaping AudioObjectPropertyListenerBlock) {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
}
