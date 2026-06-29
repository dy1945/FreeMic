# FreeMic

**English** · [中文](README.md)

A clean, fresh-styled macOS menu bar utility: see your current Bluetooth headphones and every input device, and switch the microphone input in one click (including back to the built-in mic).

![menubar app](https://img.shields.io/badge/macOS-13%2B-mint) ![swift](https://img.shields.io/badge/Swift-SwiftUI-orange)

## The problem it solves

A Bluetooth headset has two mutually exclusive modes:

- **A2DP**: one-way, high-bitrate stereo output — great for music/video, but **no microphone**.
- **HFP / SCO** (hands-free): two-way, the headset mic works, but the whole link is forced down to **mono, 8–16 kHz telephone-grade bitrate** — and the *output* quality collapses with it, sounding muffled.

That's the trap: **the moment any app activates the headset mic** (video meetings and voice calls being the classic cases), macOS forces the headset from A2DP into HFP and audio quality instantly degrades — and **after the call, the system often doesn't switch back**, so you're stuck with muffled sound until you go dig through Sound settings.

FreeMic's idea is simple: **keep the mic input on the built-in microphone so the Bluetooth headset always stays in high-quality A2DP output**. One click toggles between the headset mic and the built-in mic — join meetings normally without sacrificing audio quality.

## Features

- 🎧 Shows the current **Bluetooth headphones** used for output, with connection status (green dot = connected)
- 🎙 Lists every **input device** (built-in mic / Bluetooth headset mic / external), click to switch; the active one is checked
- 🔒 **Disable Bluetooth Mic**: once on, **any time** the input becomes a Bluetooth mic it's **immediately** pulled back to the built-in mic — eliminating HFP at the source so the headset always stays in high-quality A2DP. Stronger than auto-revert (proactive and instant, doesn't wait for the call to end). While on, other input rows are **greyed out and locked** and it takes over the auto-revert toggle (off by default, opt-in)
- 🤖 **Auto-revert after calls**: when the Bluetooth headset mic is released (video meeting / call ends), the input automatically switches back to the built-in mic, returning the headset to high-quality A2DP — **app-agnostic**, works with any conferencing app or system call (on by default, can be turned off in the panel)
- 🏝️ **Dynamic Island volume HUD**: when you change the volume, a pill drops from the top of the screen (notch / Dynamic Island area) showing the current **output device name** and volume (**progress bar + percentage**), auto-dismissing after ~1.6s. A single reused window, event-driven, intentionally lightweight
- 🌐 **中文 / English UI**: follows the system language by default, switchable on the fly via "语言 / Language" in the panel
- 🔄 **Auto-refresh** when devices are plugged/unplugged or the system switches devices (CoreAudio listeners, no manual refresh needed)
- 🪶 Lives in the menu bar with no Dock icon (`LSUIElement`); pure system APIs, zero third-party dependencies
- 🥚 **Easter egg**: global hotkeys to play with the Mac keyboard backlight, with a little pill at the top and no permissions required — `Control + K` toggles on/off, `Control + Option + ↑` brightens and `Control + Option + ↓` dims (20% per step)

## Build & run

Requires a Swift toolchain (Xcode or Command Line Tools both work):

```bash
./build.sh          # compile + package into FreeMic.app (arm64 + x86_64 universal binary)
open FreeMic.app    # launch; the icon appears in the menu bar
```

Debug device detection (prints to the command line, no UI):

```bash
FreeMic.app/Contents/MacOS/FreeMic --list
```

## Install & first launch

A `FreeMic.app` you built yourself can be `open`ed directly. But a build **downloaded from the internet** is only **ad-hoc signed** (no Apple notarization), so Gatekeeper blocks the first launch ("cannot verify the developer"). Allow it one of two ways:

- **Right-click** the app → **Open** → click "Open" in the dialog; or go to `System Settings → Privacy & Security → Open Anyway`
- Or run in Terminal: `xattr -dr com.apple.quarantine /path/to/FreeMic.app`

> For a zero-warning double-click experience you need an Apple Developer account ($99/yr) for **Developer ID signing + notarization** — `build.sh` has a commented template for those steps at the end. No App Store needed.

## Launch at login (optional)

Drag `FreeMic.app` into `System Settings → General → Login Items`.

## Structure

| File | Role |
|------|------|
| `Sources/FreeMic/FreeMicApp.swift` | Entry point, `MenuBarExtra` menu bar scene |
| `Sources/FreeMic/AudioManager.swift` | Observable state model wrapping read/switch/listen |
| `Sources/FreeMic/CoreAudioHelpers.swift` | Typed wrappers over the CoreAudio HAL property API |
| `Sources/FreeMic/PopoverView.swift` | The fresh-styled panel UI |
| `Sources/FreeMic/VolumeHUD.swift` | Dynamic-Island-style volume HUD (`NSPanel` + SwiftUI) |
| `Sources/FreeMic/Localization.swift` | Lightweight in-code 中文 / English string table |
| `icon_build/MakeIcon.swift` | Script generating the app icon + menu-bar template via CoreGraphics |
| `Resources/AppIcon.icns` | App icon bundled into the `.app` |
| `Info.plist` / `build.sh` | Config and script for packaging the `.app` |

## Notes

Switching the default input device uses the public CoreAudio API and does not capture audio, so **no microphone permission is required**.

### How auto-revert detects "the call ended"

It doesn't identify specific apps (fragile and requires per-app adaptation); it listens to the audio session state directly:

1. It listens to `kAudioDevicePropertyDeviceIsRunningSomewhere` on every **Bluetooth input device** — `true` while the headset mic is in use (an HFP call), `false` once released.
2. On a `true → false` transition (the mic was just released), it **debounces 1.8s** and re-checks, to ride out HFP→A2DP teardown jitter and brief mid-meeting mutes.
3. It only reverts when the **default input is still a Bluetooth device**, that device is **genuinely idle**, and a **built-in mic exists**.

So it's **conferencing-app-agnostic** — works with any app that grabs the headset mic; the whole path only reads CoreAudio properties, so it likewise **needs no permission**. It's **on by default** and can be toggled off in the panel (persisted in `UserDefaults`, key `autoRevertToBuiltInMic`).

## License

Released under the [MIT License](LICENSE) — free to use, modify, and distribute.
