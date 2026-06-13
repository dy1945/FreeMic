import SwiftUI
import AppKit

/// Lightweight Dynamic-Island-style HUD shown near the top-center of the screen
/// (hugging the notch) whenever the output volume changes. Deliberately frugal:
/// a single borderless panel reused across shows, created lazily on first use,
/// driven entirely by volume events with one per-show auto-hide timer.
final class VolumeHUDController {
    private let model = VolumeHUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    // The panel is larger than the visible pill so the drop shadow has room.
    // The pill is pinned to the very top of the panel, which sits flush against
    // the screen's top edge — so the pill reads as hanging from the bezel/notch.
    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 78

    /// Show (or refresh) the HUD with the current output state and (re)arm the
    /// auto-hide timer.
    func show(deviceName: String, volume: Double, muted: Bool, symbol: String) {
        model.deviceName = deviceName
        model.volume = max(0, min(1, volume))
        model.muted = muted
        model.symbol = symbol

        let panel = ensurePanel()
        position(panel)
        if !panel.isVisible {
            model.shown = false
            panel.orderFrontRegardless()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { model.shown = true }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func hide() {
        withAnimation(.easeOut(duration: 0.24)) { model.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: VolumeHUDView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight)
        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let x = f.midX - hudWidth / 2
        let y = f.maxY - hudHeight        // panel top flush with the screen top edge
        panel.setFrame(NSRect(x: x, y: y, width: hudWidth, height: hudHeight), display: true)
    }
}

/// Observable backing store for the HUD view.
final class VolumeHUDModel: ObservableObject {
    @Published var deviceName = ""
    @Published var volume: Double = 0
    @Published var muted = false
    @Published var symbol = "speaker.wave.2.fill"
    @Published var shown = false
}

/// The HUD: a pill pinned to the top of the panel so it hangs flush from the
/// screen's top edge. Square top corners + rounded bottom give it the
/// "part of the bezel/notch" Dynamic-Island look.
struct VolumeHUDView: View {
    @ObservedObject var model: VolumeHUDModel
    private let accent = Color(red: 0.18, green: 0.78, blue: 0.66)

    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 50
    private var cornerRadius: CGFloat { pillHeight / 2 }

    var body: some View {
        VStack(spacing: 0) {
            pill
            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 78)
    }

    private var pill: some View {
        HStack(spacing: 11) {
            Image(systemName: model.muted ? "speaker.slash.fill" : model.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.deviceName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(model.muted ? Color.white.opacity(0.4) : accent)
                            .frame(width: max(4, geo.size.width * model.volume))
                    }
                }
                .frame(height: 5)
            }

            Text("\(Int((model.volume * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(width: pillWidth, height: pillHeight)
        .background(shape.fill(.black))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 11, x: 0, y: 5)
        .scaleEffect(model.shown ? 1 : 0.9, anchor: .top)
        .opacity(model.shown ? 1 : 0)
    }

    /// Square top, rounded bottom — flush against the screen edge.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0,
                               bottomLeadingRadius: cornerRadius,
                               bottomTrailingRadius: cornerRadius,
                               topTrailingRadius: 0,
                               style: .continuous)
    }
}
