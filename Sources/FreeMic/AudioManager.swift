import SwiftUI
import CoreAudio
import AudioToolbox
import UserNotifications

/// Bluetooth output profile, inferred from CoreAudio signals. The headset is
/// `.hfp` (call mode — degraded, telephony-grade output) while any Bluetooth
/// mic is running IO or the output's sample rate sits at telephony rates;
/// otherwise it's `.a2dp` (high-quality stereo).
enum HeadphoneProfile: Equatable {
    case notBluetooth, a2dp, hfp
}

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

    /// Current A2DP/HFP profile of the Bluetooth headphone output. Drives the
    /// menu-bar glyph tint, the header status line, and the HFP banner.
    @Published var headphoneProfile: HeadphoneProfile = .notBluetooth

    /// Whether a Bluetooth *input* device is actually running IO. HFP can also
    /// be selected for output-only playback, so the UI must not equate every
    /// telephony-rate output with microphone use.
    @Published private(set) var bluetoothMicIsRunning = false

    /// Display names of the apps currently holding a Bluetooth mic (normally
    /// zero or one). Empty while attribution finds nothing identifiable.
    @Published var hfpMicUsers: [String] = []

    /// In-memory note about the last HFP episode ("微信 · 14:32"), so you can
    /// tell afterwards who dragged the headset into call mode. Not persisted.
    @Published var lastHFPNote: String?

    /// Setting: post a system notification when the headset drops into HFP.
    /// Persisted; defaults ON, but the permission prompt is deferred until the
    /// first HFP event actually happens (never at launch).
    @Published var hfpNotifyEnabled: Bool {
        didSet { UserDefaults.standard.set(hfpNotifyEnabled, forKey: Self.hfpNotifyKey) }
    }
    private static let hfpNotifyKey = "hfpDegradeNotify"
    private var didRequestNotifyAuth = false

    /// Nominal-sample-rate listener bound to the current output device — fires
    /// when a Bluetooth headset flips between A2DP (44.1/48kHz) and HFP (8/16kHz).
    private var profileListener: AudioObjectPropertyListenerBlock?
    private var profileMonitorID: AudioDeviceID = 0

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
        if defaults.object(forKey: Self.hfpNotifyKey) == nil {
            defaults.set(true, forKey: Self.hfpNotifyKey)      // default ON
        }
        hfpNotifyEnabled = defaults.bool(forKey: Self.hfpNotifyKey)

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
        reconcileProfileMonitor(outID)
        enforceLockIfNeeded()
        recomputeProfile()
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
        recomputeProfile()   // keep the A2DP/HFP state + offender banner live
        guard wasRunning, !nowRunning else { return }
        scheduleAutoRevert()
    }

    // MARK: - A2DP / HFP profile awareness

    /// Telephony-rate ceiling: a Bluetooth output below this is in call mode
    /// (HFP), not music mode (A2DP). 44.1↔48kHz renegotiation stays above it.
    private static let hfpSampleRateCeiling: Double = 32_000

    /// Recomputes the profile from two independent live signals:
    ///  1. any Bluetooth *input* running IO — a mic grab forces HFP immediately,
    ///  2. the Bluetooth *output* sitting at a telephony sample rate.
    /// Either alone is sufficient, so brief windows where one signal lags the
    /// other are still covered.
    private func recomputeProfile() {
        guard outputIsBluetooth else {
            updateBluetoothMicActivity(false)
            applyProfile(.notBluetooth)
            return
        }
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let rate = ca_nominalSampleRate(outID)
        let telephonyRate = rate > 0 && rate < Self.hfpSampleRateCeiling
        let micBusy = inputDevices.contains { $0.isBluetooth && runningState[$0.id] == true }
        updateBluetoothMicActivity(micBusy)
        applyProfile((telephonyRate || micBusy) ? .hfp : .a2dp)
    }

    /// Keeps the microphone-specific state separate from the output profile.
    /// In particular, an output-only app can negotiate a 16kHz HFP route while
    /// every input stream remains idle.
    private func updateBluetoothMicActivity(_ isRunning: Bool) {
        guard isRunning != bluetoothMicIsRunning else { return }
        bluetoothMicIsRunning = isRunning

        if isRunning {
            updateHFPMicUsers()
            // Process-object attribution can appear shortly after the device's
            // running flag, so retry once while the mic is still genuinely busy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.bluetoothMicIsRunning, self.hfpMicUsers.isEmpty else { return }
                self.updateHFPMicUsers()
            }
        } else {
            rememberCurrentHFPMicUsers()
            hfpMicUsers = []
        }
    }

    /// Publishes a profile change and runs its side effects: the "last grab"
    /// note on leaving HFP and the degradation notification (only on a live
    /// A2DP → HFP flip — not for the state discovered at launch). Microphone
    /// attribution follows its own activity signal above.
    private func applyProfile(_ new: HeadphoneProfile) {
        let old = headphoneProfile
        guard new != old else { return }
        headphoneProfile = new

        if new == .hfp {
            if old == .a2dp { notifyHFPDegraded() }
        } else if old == .hfp {
            rememberCurrentHFPMicUsers()
            hfpMicUsers = []
        }
    }

    private func rememberCurrentHFPMicUsers() {
        guard !hfpMicUsers.isEmpty else { return }
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        lastHFPNote = hfpMicUsers.joined(separator: "、") + " · " + time
    }

    /// Fills `hfpMicUsers` with the names of processes running input on any
    /// Bluetooth mic right now. Empty when nothing identifiable shows up
    /// (e.g. the grabber is a faceless system daemon).
    private func updateHFPMicUsers() {
        let busyBTInputs = inputDevices.filter {
            $0.isBluetooth && (runningState[$0.id] ?? ca_isRunningSomewhere($0.id))
        }
        var names: [String] = []
        for dev in busyBTInputs {
            for user in audioProcessesRunningInput(on: dev.id) where !names.contains(user.name) {
                names.append(user.name)
            }
        }
        hfpMicUsers = names
    }

    /// Binds the sample-rate listener to the current output device, re-binding
    /// whenever that device changes.
    private func reconcileProfileMonitor(_ outID: AudioDeviceID) {
        guard outID != profileMonitorID else { return }
        if let block = profileListener {
            ca_removeDeviceListener(profileMonitorID, kAudioDevicePropertyNominalSampleRate, block: block)
            profileListener = nil
        }
        profileMonitorID = outID
        guard outID != 0 else { return }
        profileListener = ca_addDeviceListener(outID, kAudioDevicePropertyNominalSampleRate) { [weak self] in
            self?.recomputeProfile()
        }
    }

    /// Posts the "dropped into HFP" notification, requesting permission lazily
    /// on the very first event. No-op when the setting is off or when running
    /// unbundled (a bare SPM debug binary has no notification identity).
    private func notifyHFPDegraded() {
        guard hfpNotifyEnabled else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let micWasRunning = bluetoothMicIsRunning
        let micUser = hfpMicUsers.first
        let deliver = {
            let loc = Localization.shared
            let content = UNMutableNotificationContent()
            content.title = "FreeMic · " + loc.t("音质已降级（HFP）", "Audio degraded (HFP)")
            if micWasRunning {
                let who = micUser ?? loc.t("某个 App", "An app")
                content.body = String(
                    format: loc.t("%@ 正在占用耳机麦克风", "%@ is using the headphone mic"),
                    who)
            } else {
                content.body = loc.t(
                    "蓝牙输出已切换到电话音质模式，未检测到麦克风占用",
                    "Bluetooth output switched to call quality; no mic use detected")
            }
            content.sound = nil   // silent — the user is likely on a call already
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if didRequestNotifyAuth {
            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized { deliver() }
            }
        } else {
            didRequestNotifyAuth = true
            center.requestAuthorization(options: [.alert]) { granted, _ in
                if granted { deliver() }
            }
        }
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
            let rate = ca_nominalSampleRate(outID)
            let rateStr = rate > 0 ? "\(Int(rate)) Hz" : "n/a"
            let desc: String
            switch headphoneProfile {
            case .a2dp: desc = "A2DP（高音质）"
            case .hfp: desc = "HFP（通话模式 · 音质降级）"
            case .notBluetooth: desc = "n/a"
            }
            print("Profile       : \(desc)  (output rate \(rateStr))")
            if !hfpMicUsers.isEmpty {
                print("Mic holders   : \(hfpMicUsers.joined(separator: ", "))")
            }
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
        var hijackers: [String] = []
        for d in ca_allDevices() where ca_hasInput(d) {
            let t = ca_transportType(d)
            let mark = d == inID ? "✔︎" : " "
            let bt = isBluetooth(t)
            let running = ca_isRunningSomewhere(d)
            print("  \(mark) \(ca_name(d))  (builtin=\(t == kAudioDeviceTransportTypeBuiltIn) bt=\(bt) running=\(running))")
            // The smoking gun: a Bluetooth mic that's *running* while NOT the system
            // default input means some app opened it directly. That alone forces the
            // headset into HFP (low-quality output) — and the built-in-mic lock, which
            // only governs the *default* input, can't prevent it. Name the process.
            if bt, running, d != inID {
                let users = audioProcessesRunningInput(on: d)
                let who = users.isEmpty
                    ? "未识别进程"
                    : users.map { "\($0.name) (pid \($0.pid))" }.joined(separator: ", ")
                hijackers.append("\(ca_name(d)) ← \(who)")
            }
        }
        if !hijackers.isEmpty {
            print("⚠️  HFP suspect : \(hijackers.joined(separator: "; "))")
            print("                蓝牙麦正被占用但不是默认输入 —— 某个 App 直接打开了它，")
            print("                强制耳机进入 HFP、压低输出音量。锁「默认输入」拦不住它。")
            print("                把该 App 的麦克风改成内置麦，或等它结束占用。")
        }
    }
}
