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

    /// Current default-output volume in `0...1`, whether it exposes a volume
    /// control at all, and its mute state — surfaced in the volume HUD.
    @Published var outputVolume: Double = 0
    @Published var outputHasVolume: Bool = false
    @Published var outputMuted: Bool = false

    /// SF Symbol representing the current output, used by the HUD.
    var outputSymbolName: String { outputIsBluetooth ? "headphones" : "speaker.wave.2.fill" }

    /// Battery level of the current Bluetooth headphone (empty when the output
    /// isn't Bluetooth or the device reports nothing). Read off the main thread
    /// and published back on it.
    @Published var battery = BatteryReading()
    private let batteryQueue = DispatchQueue(label: "com.vibe.freemic.battery", qos: .utility)
    private var batteryTimer: Timer?

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

    /// Setting: never let a Bluetooth mic become the input. Stronger than
    /// auto-revert — it enforces *immediately* (and proactively) rather than
    /// after the mic is released, so the headset never enters HFP at all.
    /// Persisted; defaults OFF (opt-in).
    @Published var lockBuiltInMic: Bool {
        didSet {
            UserDefaults.standard.set(lockBuiltInMic, forKey: Self.lockKey)
            if lockBuiltInMic { enforceLockIfNeeded() }
        }
    }
    private static let lockKey = "lockBuiltInMic"

    /// `DeviceIsRunningSomewhere` listeners + last-seen running state, keyed by the
    /// Bluetooth input devices we're currently monitoring.
    private var runningMonitors: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var runningState: [AudioDeviceID: Bool] = [:]
    private var pendingRevert: DispatchWorkItem?

    /// Volume-change listeners bound to the *current* default output device.
    private var volumeListeners: [(AudioObjectPropertySelector, AudioObjectPropertyScope, AudioObjectPropertyListenerBlock)] = []
    private var volumeMonitorID: AudioDeviceID = 0
    /// Created lazily on the first volume change, so launch stays cheap.
    private lazy var volumeHUD = VolumeHUDController()

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoRevertKey) == nil {
            defaults.set(true, forKey: Self.autoRevertKey)   // default ON
        }
        autoRevertEnabled = defaults.bool(forKey: Self.autoRevertKey)
        lockBuiltInMic = defaults.bool(forKey: Self.lockKey)   // absent → false

        refresh()
        ca_addSystemListener(kAudioHardwarePropertyDevices) { [weak self] in self?.refresh() }
        ca_addSystemListener(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.refresh() }
        ca_addSystemListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.refresh() }

        // Battery changes slowly; a light periodic poll keeps the badge fresh.
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    deinit { batteryTimer?.invalidate() }

    /// Re-reads the full audio state from CoreAudio.
    func refresh() {
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        outputName = ca_name(outID)
        outputIsBluetooth = isBluetooth(ca_transportType(outID))
        updateOutputVolumeState(outID)   // silent — no HUD on device refresh
        reconcileVolumeMonitor(outID)

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
        enforceLockIfNeeded()
        refreshBattery()
    }

    /// Refreshes the Bluetooth battery reading. Clears it immediately when the
    /// output isn't Bluetooth; otherwise reads on a background queue (the
    /// `system_profiler` fallback can block) and publishes back on the main thread.
    func refreshBattery() {
        guard outputIsBluetooth else {
            if !battery.isEmpty { battery = BatteryReading() }
            return
        }
        let name = outputName
        batteryQueue.async { [weak self] in
            let reading = bt_readBattery(matching: name)
            DispatchQueue.main.async {
                guard let self, self.outputIsBluetooth else { return }
                if self.battery != reading { self.battery = reading }
            }
        }
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
            ca_removeDeviceListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere, block: block)
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

    // MARK: - Volume HUD (Dynamic-Island-style overlay on volume changes)

    /// Reads the current output volume / mute into the published state without
    /// triggering the HUD (used by `refresh`).
    private func updateOutputVolumeState(_ outID: AudioDeviceID) {
        if let v = ca_outputVolume(outID) {
            outputVolume = Double(v)
            outputHasVolume = true
        } else {
            outputHasVolume = false
        }
        outputMuted = ca_outputMuted(outID)
    }

    /// Binds volume / mute listeners to the current default output device,
    /// re-binding whenever that device changes.
    private func reconcileVolumeMonitor(_ outID: AudioDeviceID) {
        guard outID != volumeMonitorID else { return }
        for (sel, scope, block) in volumeListeners {
            ca_removeDeviceListener(volumeMonitorID, sel, scope: scope, block: block)
        }
        volumeListeners.removeAll()
        volumeMonitorID = outID
        guard outID != 0 else { return }

        let specs: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
            (kVirtualMainVolumeSelector, kAudioObjectPropertyScopeOutput),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput),
            (kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput),
        ]
        for (sel, scope) in specs {
            let block = ca_addDeviceListener(outID, sel, scope: scope) { [weak self] in
                self?.handleVolumeChange(outID)
            }
            volumeListeners.append((sel, scope, block))
        }
    }

    /// Fires on an actual volume / mute change on the current output device —
    /// updates state and, if the value really moved, shows the HUD.
    private func handleVolumeChange(_ outID: AudioDeviceID) {
        guard outID == volumeMonitorID else { return }
        let newVolume = ca_outputVolume(outID)
        let newMuted = ca_outputMuted(outID)
        let volumeMoved = newVolume.map { abs(Double($0) - outputVolume) > 0.0005 } ?? false
        let changed = volumeMoved || newMuted != outputMuted

        if let v = newVolume {
            outputVolume = Double(v)
            outputHasVolume = true
        }
        outputMuted = newMuted

        guard changed, outputHasVolume else { return }
        volumeHUD.show(deviceName: outputName,
                       volume: outputVolume,
                       muted: outputMuted,
                       symbol: outputSymbolName)
    }

    // MARK: - Lock to built-in mic (never use a Bluetooth mic)

    /// Where lock mode pins the input: the built-in mic, else the first
    /// non-Bluetooth input (handles Macs without an internal mic).
    var lockTargetInput: Device? {
        builtInInput ?? inputDevices.first { !$0.isBluetooth }
    }

    /// If lock mode is on and the current input is a Bluetooth mic, immediately
    /// switch back to the lock target. Returns true if it switched.
    @discardableResult
    private func enforceLockIfNeeded() -> Bool {
        guard lockBuiltInMic else { return false }
        guard let current = inputDevices.first(where: { $0.id == currentInputID }),
              current.isBluetooth else { return false }
        guard let target = lockTargetInput, target.id != currentInputID else { return false }
        selectInput(target.id)
        flashAutoRevertNotice()
        return true
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
        print("Lock built-in : \(lockBuiltInMic ? "on" : "off")")
        print("Auto-revert   : \(autoRevertEnabled ? "on" : "off")")
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let vol = ca_outputVolume(outID).map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        print("Output device : \(ca_name(outID))  (bluetooth=\(isBluetooth(ca_transportType(outID))) volume=\(vol))")
        if isBluetooth(ca_transportType(outID)) {
            let b = bt_readBattery(matching: ca_name(outID))
            let parts = [
                b.single.map { "main=\($0)%" },
                b.left.map { "L=\($0)%" },
                b.right.map { "R=\($0)%" },
                b.caseLevel.map { "case=\($0)%" },
            ].compactMap { $0 }
            let form: String
            switch b.form {
            case .earbuds: form = "earbuds(分体)"
            case .overEar: form = "over-ear(头戴)"
            case .unknown: form = "unknown"
            }
            print("Battery       : \(parts.isEmpty ? "n/a" : parts.joined(separator: " "))  form=\(form)")
        }
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
