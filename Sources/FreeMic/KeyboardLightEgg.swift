import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - 🥚 Easter egg: ⌃K toggles the Mac keyboard backlight
//
// A tiny hidden treat. A system-wide ⌃K hotkey flips the built-in keyboard's
// backlight on/off, with a little Dynamic-Island-style pill for feedback —
// echoing the volume HUD. Everything here is best-effort: on a Mac without a
// backlit keyboard (or if the private API ever disappears) it simply no-ops.

/// Owns the global hotkey and wires it to the backlight toggle + HUD.
/// A single shared instance, started once at launch.
final class KeyboardLightEgg {
    static let shared = KeyboardLightEgg()

    private let backlight = KeyboardBacklight()
    private lazy var hud = KeyboardLightHUDController()
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// Shared 4-char signature ('FrMc'); each action gets its own id.
    private let signature = OSType(0x46724D63)
    private static let hkToggle: UInt32 = 1     // ⌃K   → on/off
    private static let hkBrighten: UInt32 = 2   // ⌃⌥↑  → +1 step
    private static let hkDim: UInt32 = 3        // ⌃⌥↓  → −1 step
    /// One brightness step for the brighten / dim hotkeys (20%).
    private let step: Float = 0.2

    private init() {}

    /// Registers the system-wide hotkeys. Idempotent. Carbon hot keys work
    /// app-wide without Accessibility / Input-Monitoring permission, which keeps
    /// this a zero-friction easter egg.
    ///   ⌃K   toggle on/off
    ///   ⌃⌥↑  brighten one step
    ///   ⌃⌥↓  dim one step
    func start() {
        guard handler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The handler is a bare C function pointer (no captures); we pass `self`
        // through `userData`, read which hot key fired, then bounce back to it.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            Unmanaged<KeyboardLightEgg>.fromOpaque(userData)
                .takeUnretainedValue()
                .handle(hkID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let ctrl = UInt32(controlKey)
        let ctrlOpt = UInt32(controlKey | optionKey)
        register(keyCode: UInt32(kVK_ANSI_K),    modifiers: ctrl,    id: Self.hkToggle)
        register(keyCode: UInt32(kVK_UpArrow),   modifiers: ctrlOpt, id: Self.hkBrighten)
        register(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt, id: Self.hkDim)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if let ref { hotKeys.append(ref) }
    }

    /// Called on the main thread from the Carbon hot-key handler.
    private func handle(_ id: UInt32) {
        let level: Float
        switch id {
        case Self.hkToggle:   level = backlight.toggle()
        case Self.hkBrighten: level = backlight.step(by: step)
        case Self.hkDim:      level = backlight.step(by: -step)
        default: return
        }
        hud.show(on: level > 0.01, level: level)
    }
}

// MARK: - Keyboard backlight (private CoreBrightness API)

/// Objective-C surface of the private `KeyboardBrightnessClient`. We declare
/// just the two methods we call; the real object satisfies this protocol so we
/// can message it through an `unsafeBitCast` proxy without a bridging header.
@objc private protocol KeyboardBrightnessClientProtocol {
    func brightnessForKeyboard(_ keyboard: UInt64) -> Float
    func setBrightness(_ brightness: Float, forKeyboard keyboard: UInt64) -> Bool
}

/// Reads / sets the built-in keyboard backlight via the private
/// `CoreBrightness.KeyboardBrightnessClient`. Best-effort: if the framework or
/// class is unavailable, every call is a silent no-op.
final class KeyboardBacklight {
    private let client: AnyObject?
    private let keyboardID: UInt64 = 1
    /// Remembers the last non-zero level so toggling back on restores it,
    /// rather than always snapping to full brightness.
    private var lastOnLevel: Float = 1.0

    init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
                   RTLD_LAZY)
        if let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
            client = cls.init()
        } else {
            client = nil
        }
    }

    private var proxy: KeyboardBrightnessClientProtocol? {
        guard let client else { return nil }
        return unsafeBitCast(client, to: KeyboardBrightnessClientProtocol.self)
    }

    /// Toggles the backlight, returning the resulting brightness in `0...1`.
    @discardableResult
    func toggle() -> Float {
        guard let proxy else { return 0 }
        let current = proxy.brightnessForKeyboard(keyboardID)
        if current > 0.01 {
            lastOnLevel = current
            _ = proxy.setBrightness(0, forKeyboard: keyboardID)
            return 0
        } else {
            let target = lastOnLevel > 0.01 ? lastOnLevel : 1.0
            _ = proxy.setBrightness(target, forKeyboard: keyboardID)
            return target
        }
    }

    /// Nudges the backlight by `delta` (negative dims), clamped to `0...1`, and
    /// returns the resulting brightness. Remembers the latest non-zero level so
    /// the on/off toggle restores it.
    @discardableResult
    func step(by delta: Float) -> Float {
        guard let proxy else { return 0 }
        let target = max(0, min(1, proxy.brightnessForKeyboard(keyboardID) + delta))
        _ = proxy.setBrightness(target, forKeyboard: keyboardID)
        if target > 0.01 { lastOnLevel = target }
        return target
    }
}

// MARK: - Feedback HUD (mirrors the volume pill)

/// A borderless pill that drops from the screen top to confirm the toggle —
/// the same lightweight, single-reused-panel approach as `VolumeHUDController`.
final class KeyboardLightHUDController {
    private let model = KeyboardLightHUDModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    private let hudWidth: CGFloat = 320
    private let hudHeight: CGFloat = 78

    func show(on: Bool, level: Float) {
        model.on = on
        model.level = Double(max(0, min(1, level)))

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func hide() {
        withAnimation(.easeOut(duration: 0.24)) { model.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: KeyboardLightHUDView(model: model))
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

/// Observable backing store for the keyboard-light HUD.
final class KeyboardLightHUDModel: ObservableObject {
    @Published var on = false
    @Published var level: Double = 0
    @Published var shown = false
}

/// The pill: keyboard glyph + on/off caption + brightness bar, pinned to the
/// top so it hangs flush from the screen's top edge (notch / Dynamic Island).
struct KeyboardLightHUDView: View {
    @ObservedObject var model: KeyboardLightHUDModel
    @ObservedObject private var loc = Localization.shared
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
            Image(systemName: model.on ? "keyboard.fill" : "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("键盘灯", "Keyboard Light"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(model.on ? accent : Color.white.opacity(0.4))
                            .frame(width: max(4, geo.size.width * (model.on ? model.level : 0)))
                    }
                }
                .frame(height: 5)
            }

            Text(model.on ? loc.t("开", "On") : loc.t("关", "Off"))
                .font(.system(size: 12, weight: .semibold))
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
