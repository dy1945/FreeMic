import SwiftUI
import AppKit

/// The clean, fresh-styled panel shown when clicking the menu bar icon.
struct PopoverView: View {
    @ObservedObject var audio: AudioManager
    @ObservedObject private var loc = Localization.shared

    /// Soft mint accent — the "fresh" look.
    private let accent = Color(red: 0.18, green: 0.78, blue: 0.66)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 12)

            sectionTitle(loc.t("输入设备", "Input Devices"))

            if audio.inputDevices.isEmpty {
                Text(loc.t("未发现可用输入设备", "No input devices found"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(audio.inputDevices) { dev in
                        inputRow(dev)
                    }
                }
            }

            Divider().padding(.vertical, 12)

            settingsSection

            Divider().padding(.vertical, 12)

            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(loc.t("设置", "Settings"))

            settingRow(loc.t("禁用蓝牙麦克风", "Disable Bluetooth Mic"),
                       isOn: $audio.lockBuiltInMic)

            // Lock subsumes auto-revert: when it's on, show this switch forced
            // on and disabled, so the linkage reads visually — no extra text.
            settingRow(loc.t("会议结束后切回内置麦", "Revert to built-in after calls"),
                       isOn: audio.lockBuiltInMic ? .constant(true) : $audio.autoRevertEnabled,
                       disabled: audio.lockBuiltInMic)

            languageRow

            if audio.autoRevertNotice {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accent)
                    Text(loc.t("已自动切回内置麦克风", "Switched back to built-in mic"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: audio.lockBuiltInMic)
        .animation(.easeInOut(duration: 0.2), value: audio.autoRevertNotice)
    }

    /// A settings row with the label on the left and the switch right-aligned,
    /// so every toggle lines up on the same edge.
    private func settingRow(_ title: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .opacity(disabled ? 0.4 : 1)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .controlSize(.small)
                .disabled(disabled)
        }
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            Text(loc.t("语言", "Language"))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Picker("", selection: $loc.language) {
                Text(loc.t("跟随系统", "System")).tag(AppLanguage.system)
                Text("中文").tag(AppLanguage.zh)
                Text("English").tag(AppLanguage.en)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .tint(accent)
            .fixedSize()
        }
    }

    // MARK: - Header (current output / Bluetooth headphone)

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: audio.outputIsBluetooth ? "airpodspro" : "headphones")
                    .font(.system(size: 21))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(audio.outputIsBluetooth ? audio.outputName : loc.t("未连接蓝牙耳机", "No Bluetooth headphones"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(audio.outputIsBluetooth ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(audio.outputIsBluetooth
                         ? loc.t("已连接 · 正在输出", "Connected · Output")
                         : loc.t("当前输出：", "Output: ") + audio.outputName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            batteryBadge
        }
    }

    // MARK: - Battery badge

    /// Compact battery indicator, shown only when a Bluetooth headphone is the
    /// output and it reports a level — so the header is unchanged otherwise.
    @ViewBuilder
    private var batteryBadge: some View {
        if audio.outputIsBluetooth, let pct = audio.battery.primary {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: batterySymbol(pct))
                        .font(.system(size: 13))
                        .foregroundStyle(batteryColor(pct))
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                if let detail = batteryDetail {
                    Text(detail)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .help(loc.t("耳机电量", "Headphone battery"))
            .transition(.opacity)
        }
    }

    /// Caption that disambiguates what the number means:
    ///  • per-bud / case detail when the device reports it (e.g. "左 90 · 右 85 · 仓 70"),
    ///  • else the form factor itself ("耳机" / "头戴") so a lone value is never
    ///    mistaken for the charging case.
    private var batteryDetail: String? {
        let b = audio.battery
        var parts: [String] = []
        if let l = b.left  { parts.append(loc.t("左", "L") + " \(l)") }
        if let r = b.right { parts.append(loc.t("右", "R") + " \(r)") }
        if let c = b.caseLevel { parts.append(loc.t("仓", "Case") + " \(c)") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        switch b.form {
        case .earbuds: return loc.t("耳机", "Earbuds")   // single value = the buds, not the case
        case .overEar: return loc.t("头戴", "Headphones")
        case .unknown: return nil
        }
    }

    /// Tiered SF Symbol battery glyph for the level.
    private func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    /// Green when healthy, amber when low, red when critical.
    private func batteryColor(_ pct: Int) -> Color {
        switch pct {
        case ..<20: return .red
        case ..<40: return .orange
        default:    return accent
        }
    }

    // MARK: - Input device row

    private func inputRow(_ dev: AudioManager.Device) -> some View {
        let selected = dev.id == audio.currentInputID
        // Under lock mode, every row except the locked (selected) one is disabled.
        let locked = audio.lockBuiltInMic && !selected
        return Button {
            audio.selectInput(dev.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: dev))
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? accent : .secondary)
                    .frame(width: 20)
                Text(dev.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .help(locked ? loc.t("已锁定内置麦克风，禁止切换到此设备", "Locked to built-in mic; switching disabled") : "")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { audio.refresh() } label: {
                Label(loc.t("刷新", "Refresh"), systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button { showAbout() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "info.circle")
                    Text("FreeMic \(appVersion)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(loc.t("关于", "About"))

            Spacer()

            Button(loc.t("退出", "Quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// App version from the bundle, e.g. "v0.0.3".
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(v)"
    }

    /// Opens the standard macOS About panel with the app icon, version, and a
    /// short description (localized).
    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let body = loc.isEnglish
            ? "Menu-bar microphone / Bluetooth switcher.\nKeeps your headset in high-quality A2DP audio by keeping the mic on the built-in input.\n\nhttps://github.com/dy1945/FreeMic"
            : "菜单栏麦克风 / 蓝牙耳机切换工具。\n把麦克风留在内置输入，让耳机始终保持 A2DP 高音质。\n\nhttps://github.com/dy1945/FreeMic"
        let credits = NSAttributedString(string: body, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "FreeMic",
        ])
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }

    private func icon(for dev: AudioManager.Device) -> String {
        if dev.isBuiltIn { return "laptopcomputer" }
        if dev.isBluetooth { return "airpods" }
        return "mic"
    }
}
