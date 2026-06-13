import SwiftUI
import AppKit

/// The clean, fresh-styled panel shown when clicking the menu bar icon.
struct PopoverView: View {
    @ObservedObject var audio: AudioManager

    /// Soft mint accent — the "fresh" look.
    private let accent = Color(red: 0.18, green: 0.78, blue: 0.66)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 12)

            sectionTitle("输入设备")

            if audio.inputDevices.isEmpty {
                Text("未发现可用输入设备")
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

            footer
        }
        .padding(16)
        .frame(width: 300)
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
                Text(audio.outputIsBluetooth ? audio.outputName : "未连接蓝牙耳机")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(audio.outputIsBluetooth ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(audio.outputIsBluetooth
                         ? "已连接 · 正在输出"
                         : "当前输出：\(audio.outputName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Input device row

    private func inputRow(_ dev: AudioManager.Device) -> some View {
        let selected = dev.id == audio.currentInputID
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
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { audio.refresh() } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
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
