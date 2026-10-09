import CoreAudio
import AudioToolbox
import Foundation

/// Headless `--watch` diagnostic. Prints every input device's running-state
/// transition next to the current output device + volume, so you can catch the
/// exact moment an app grabs the Bluetooth mic (`running: false → true`) and the
/// output silently drops into HFP — even in the intermittent "just watching a
/// video, no meeting" case that a one-shot `--list` is hard to time. Blocks
/// until Ctrl-C.
func runInputWatch() -> Never {
    // Unbuffered stdout: this never exits normally, so line-buffer flushes would
    // never arrive when piped to a file / `tee`. Emit each line immediately.
    setvbuf(stdout, nil, _IONBF, 0)
    let watcher = InputRunningWatcher()
    watcher.start()
    CFRunLoopRun()
    exit(0)
}

private final class InputRunningWatcher {
    private var listeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var state: [AudioDeviceID: Bool] = [:]

    func start() {
        print("[watch] 监听所有输入设备的占用状态，Ctrl-C 退出。")
        print("[watch] 关注 running: false → true 的那一刻，同时看 output vol 是否被压低。")
        attach()
        // Re-attach when the device set changes (headset connects/disconnects).
        ca_addSystemListener(kAudioHardwarePropertyDevices) { [weak self] in self?.attach() }
        for id in inputs() {
            print("  初始  \(ca_name(id))  running=\(ca_isRunningSomewhere(id))")
        }
        print("        \(outputLine())")
    }

    private func inputs() -> [AudioDeviceID] { ca_allDevices().filter { ca_hasInput($0) } }

    private func attach() {
        let current = Set(inputs())
        for (id, block) in listeners where !current.contains(id) {
            ca_removeDeviceListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere, block: block)
            listeners[id] = nil
            state[id] = nil
        }
        for id in current where listeners[id] == nil {
            state[id] = ca_isRunningSomewhere(id)
            let block = ca_addDeviceListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                self?.handle(id)
            }
            listeners[id] = block
        }
    }

    private func handle(_ id: AudioDeviceID) {
        let now = ca_isRunningSomewhere(id)
        let was = state[id] ?? false
        guard now != was else { return }
        state[id] = now
        let arrow = was ? "true → false" : "false → true"
        print("\(timestamp())  \(ca_name(id))  running: \(arrow)   | \(outputLine())")
        // A Bluetooth mic being grabbed (false → true) drags the headset into
        // HFP — name the culprit. Attribution lags the flag by a beat, so
        // check again shortly after.
        let t = ca_transportType(id)
        let isBT = t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
        if !was, now, isBT {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard ca_isRunningSomewhere(id) else { return }
                let users = audioProcessesRunningInput(on: id)
                let who = users.isEmpty
                    ? "（未识别到占用进程，可能是系统守护进程）"
                    : users.map { "\($0.name) (pid \($0.pid))" }.joined(separator: ", ")
                print("           ↳ 蓝牙麦占用者: \(who)   | \(self.outputLine())")
            }
        }
    }

    private func outputLine() -> String {
        let outID = ca_defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let inID = ca_defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let t = ca_transportType(outID)
        let bt = t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
        let vol = ca_outputVolume(outID).map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        // A Bluetooth output below 32kHz is in HFP call mode, not A2DP.
        let rate = ca_nominalSampleRate(outID)
        let profile = bt ? (rate > 0 && rate < 32_000 ? " HFP" : " A2DP") : ""
        let rateStr = rate > 0 ? String(format: " %.1fkHz", rate / 1000) : ""
        return "default-in=\(ca_name(inID))  output=\(ca_name(outID)) bt=\(bt) vol=\(vol)\(rateStr)\(profile)"
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "[\(f.string(from: Date()))]"
    }
}
