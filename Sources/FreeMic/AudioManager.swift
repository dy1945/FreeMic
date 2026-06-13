import SwiftUI
import CoreAudio
import AudioToolbox

/// Observable model that mirrors the system audio state and drives the UI.
/// All mutations happen on the main thread (UI calls + main-queue CoreAudio listeners).
final class AudioManager: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let isBuiltIn: Bool
        let isBluetooth: Bool
    }

    /// Current default *output* device (what we report as the "headphone").
    @Published var outputName: String = "未知设备"
    @Published var outputIsBluetooth: Bool = false

    /// Available *input* devices and the currently selected one.
    @Published var inputDevices: [Device] = []
    @Published var currentInputID: AudioDeviceID = 0

    init() {
        refresh()
        ca_addSystemListener(kAudioHardwarePropertyDevices) { [weak self] in self?.refresh() }
        ca_addSystemListener(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.refresh() }
        ca_addSystemListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.refresh() }
    }

    /// Re-reads the full audio state from CoreAudio.
    func refresh() {
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        outputName = ca_name(outID)
        outputIsBluetooth = isBluetooth(ca_transportType(outID))

        currentInputID = ca_defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        inputDevices = ca_allDevices()
            .filter { ca_hasInput($0) }
            .map { id in
                let t = ca_transportType(id)
                return Device(
                    id: id,
                    name: ca_name(id),
                    isBuiltIn: t == kAudioDeviceTransportTypeBuiltIn,
                    isBluetooth: isBluetooth(t))
            }
    }

    /// Switches the system default input device.
    func selectInput(_ id: AudioDeviceID) {
        if ca_setDefaultInput(id) {
            currentInputID = id
        }
    }

    /// The built-in microphone, if present — used by the one-click shortcut.
    var builtInInput: Device? {
        inputDevices.first { $0.isBuiltIn }
    }

    private func isBluetooth(_ t: UInt32) -> Bool {
        t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Prints the current state to stdout — used by the `--list` debug flag.
    func printDebug() {
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        print("Output device : \(ca_name(outID))  (bluetooth=\(isBluetooth(ca_transportType(outID))))")
        let inID = ca_defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        print("Current input : \(ca_name(inID))")
        print("Input devices :")
        for d in ca_allDevices() where ca_hasInput(d) {
            let t = ca_transportType(d)
            let mark = d == inID ? "✔︎" : " "
            print("  \(mark) \(ca_name(d))  (builtin=\(t == kAudioDeviceTransportTypeBuiltIn) bt=\(isBluetooth(t)))")
        }
    }
}
