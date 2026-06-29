# 更新日志 · Changelog

## v0.0.5 — 🥚 键盘灯彩蛋 / Keyboard-light easter egg

一个纯属玩乐的隐藏小彩蛋：用全局快捷键点亮 / 调节 Mac 的键盘背光，屏幕顶部还会掉下一枚灵动岛风格的胶囊提示。

A hidden, just-for-fun easter egg: use global hotkeys to toggle and dial the Mac's keyboard backlight, with a Dynamic-Island-style pill dropping from the top of the screen for feedback.

**快捷键 / Hotkeys**

| 快捷键 / Hotkey | 功能 / Action |
| --- | --- |
| `Control + K` | 开 / 关键盘背光 · Toggle backlight on/off |
| `Control + Option + ↑` | 调亮一档（+20%）· Brighten one step (+20%) |
| `Control + Option + ↓` | 调暗一档（−20%）· Dim one step (−20%) |

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
