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

    /// Setting: after a Bluetooth headset's mic is released (e.g. a video meeting
    /// ends), automatically switch the default input back to the built-in mic so
    /// the headset returns to high-quality A2DP output. Persisted; defaults ON.
    @Published var autoRevertEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRevertEnabled, forKey: Self.autoRevertKey) }
    }

    /// Set briefly when an automatic revert just happened, so the panel can show
    /// a light confirmation note. Self-clears.
    @Published var autoRevertNotice: Bool = false

    private static let autoRevertKey = "autoRevertToBuiltInMic"

    /// `DeviceIsRunningSomewhere` listeners + last-seen running state, keyed by the
    /// Bluetooth input devices we're currently monitoring.
    private var runningMonitors: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var runningState: [AudioDeviceID: Bool] = [:]
    private var pendingRevert: DispatchWorkItem?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoRevertKey) == nil {
            defaults.set(true, forKey: Self.autoRevertKey)   // default ON
        }
        autoRevertEnabled = defaults.bool(forKey: Self.autoRevertKey)

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
        reconcileRunningMonitors()
    }

    /// Switches the system default input device. Manual switches clear any
    /// pending auto-revert and dismiss the confirmation note.
    func selectInput(_ id: AudioDeviceID) {
        pendingRevert?.cancel()
        autoRevertNotice = false
        if ca_setDefaultInput(id) {
            currentInputID = id
        }
    }

    // MARK: - Auto-revert (Plan B: detect mic release on the Bluetooth input)

    /// Keeps a `DeviceIsRunningSomewhere` listener attached to every Bluetooth
    /// input device, adding/removing as devices come and go.
    private func reconcileRunningMonitors() {
        let btInputs = Set(inputDevices.filter { $0.isBluetooth }.map { $0.id })

        for (id, block) in runningMonitors where !btInputs.contains(id) {
            ca_removeDeviceListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere, block)
            runningMonitors[id] = nil
            runningState[id] = nil
        }
        for id in btInputs where runningMonitors[id] == nil {
            runningState[id] = ca_isRunningSomewhere(id)
            let block = ca_addDeviceListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                self?.handleRunningChange(id)
            }
            runningMonitors[id] = block
        }
    }

    /// Fires on a monitored device's running-state change. A `true → false`
    /// transition means the headset mic was just released.
    private func handleRunningChange(_ id: AudioDeviceID) {
        let nowRunning = ca_isRunningSomewhere(id)
        let wasRunning = runningState[id] ?? false
        runningState[id] = nowRunning
        guard wasRunning, !nowRunning else { return }
        scheduleAutoRevert()
    }

    /// Debounce: Bluetooth HFP→A2DP teardown is jittery, and apps briefly drop
    /// the mic mid-meeting. Wait, then re-check the device is genuinely idle.
    private func scheduleAutoRevert() {
        guard autoRevertEnabled else { return }
        pendingRevert?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performAutoRevertIfIdle() }
        pendingRevert = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func performAutoRevertIfIdle() {
        guard autoRevertEnabled else { return }
        // Only act when the *current* default input is a Bluetooth device…
        guard let current = inputDevices.first(where: { $0.id == currentInputID }),
              current.isBluetooth else { return }
        // …that is genuinely idle now (a new call may have started during the wait)…
        guard !ca_isRunningSomewhere(currentInputID) else { return }
        // …and a built-in mic exists to fall back to.
        guard let builtIn = builtInInput, builtIn.id != currentInputID else { return }

        selectInput(builtIn.id)
        flashAutoRevertNotice()
    }

    private func flashAutoRevertNotice() {
        autoRevertNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.autoRevertNotice = false
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
        print("Auto-revert   : \(autoRevertEnabled ? "on" : "off")")
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
