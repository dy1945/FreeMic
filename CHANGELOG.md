# 更新日志 · Changelog

## v0.0.7 — A2DP / HFP 状态感知与占用归因 / A2DP / HFP awareness & offender attribution

- 🚦 **实时 profile 显示**：面板头部与菜单栏图标直接告诉你耳机此刻是 **A2DP 高音质**（绿色）还是 **HFP 通话模式**（琥珀色，音质降级）。判定用双重信号：蓝牙输出的 CoreAudio 采样率（< 32kHz 即通话模式）+ 蓝牙麦的 IO 占用状态，任一成立即判 HFP，避免单一信号滞后。
  **Live profile display**: the panel header and menu-bar glyph now show whether the headset is in **A2DP high-quality** (green) or **HFP call mode** (amber, degraded). Detection ORs two signals — the output's CoreAudio sample rate (< 32kHz means call mode) and the Bluetooth mic's running state — so neither signal's lag leaves a blind spot.
- 🔍 **占用归因**：有 App **绕过默认输入锁定、直接打开蓝牙麦**时，面板弹出琥珀色横幅**点名占用者**（macOS 12+ AudioProcessObject API），并可推送系统通知（默认开启，首次真正触发时才请求通知权限）；占用结束后保留「上次占用」记录。`--list` 的 "HFP suspect" 与 `--watch` 日志也同步点名。
  **Offender attribution**: when an app opens the Bluetooth mic *directly* — bypassing the default-input lock — an amber banner **names the culprit** (macOS 12+ AudioProcessObject API), with an optional system notification (on by default; permission is only requested on the first real event). A "last mic grab" note lingers after the episode ends. `--list`'s "HFP suspect" and `--watch` logs name names too.
- 新增设置项「音质降级（HFP）时通知我」（`UserDefaults` 键 `hfpDegradeNotify`，默认开）。
  New setting “Notify when audio degrades (HFP)” (`UserDefaults` key `hfpDegradeNotify`, default on).

---

## v0.0.6 — 键盘灯：开灯始终最低亮度 / Keyboard light: always turn on at minimum brightness

- `Control + K` 开灯时不再恢复上次的亮度，而是固定用最低亮度（1/16 ≈ 6.25%，即系统 F 键调节的最低一档），需要更亮再用 `Control + Option + =` 逐档调高。
  `Control + K` no longer restores the last brightness when turning on; it always lands on the minimum level (1/16 ≈ 6.25%, the system's lowest F-key step). Brighten from there with `Control + Option + =` if needed.

---

## v0.0.5 — 🥚 键盘灯彩蛋 / Keyboard-light easter egg

一个纯属玩乐的隐藏小彩蛋：用全局快捷键点亮 / 调节 Mac 的键盘背光，屏幕顶部还会掉下一枚灵动岛风格的胶囊提示。

A hidden, just-for-fun easter egg: use global hotkeys to toggle and dial the Mac's keyboard backlight, with a Dynamic-Island-style pill dropping from the top of the screen for feedback.

**快捷键 / Hotkeys**

| 快捷键 / Hotkey | 功能 / Action |
| --- | --- |
| `Control + K` | 开 / 关键盘背光 · Toggle backlight on/off |
| `Control + Option + =`（+ 键） | 调亮一档（+20%）· Brighten one step (+20%) |
| `Control + Option + -` | 调暗一档（−20%）· Dim one step (−20%) |

**说明 / Notes**

- 全局生效，App 在后台也能用；基于 Carbon `RegisterEventHotKey`，**无需辅助功能 / 输入监控权限**。
  Works system-wide even when the app is in the background; built on Carbon `RegisterEventHotKey`, so **no Accessibility / Input-Monitoring permission** is needed.
- 背光通过私有的 `CoreBrightness` 接口控制，尽力而为：没有背光键盘的机型会静默忽略。开 / 关会记住上次的非零亮度并恢复。
  The backlight is driven through the private `CoreBrightness` API on a best-effort basis: Macs without a backlit keyboard simply no-op. The on/off toggle remembers and restores your last non-zero level.

**另外 / Also in this release**

- 🔋 头部新增蓝牙耳机**电量徽章**：当蓝牙耳机作为输出且上报电量时，显示总电量与左 / 右 / 仓的分项。
  🔋 A Bluetooth-headphone **battery badge** in the header: when a Bluetooth headphone is the output and reports a level, it shows the overall charge plus per-bud / case detail.

---

## v0.0.4

- 状态感知的菜单栏图标（蓝牙输出转绿、内置麦锁定显示小锁）。
  State-aware menu-bar icon (green for Bluetooth output, lock badge when the built-in mic is locked).
