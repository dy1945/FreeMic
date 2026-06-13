# FreeMic

[English](README.en.md) · **中文**

一个清新风格的 macOS 菜单栏小工具：显示当前蓝牙耳机与所有输入设备，一键切换麦克风输入（含切回内置麦克风）。

![menubar app](https://img.shields.io/badge/macOS-13%2B-mint) ![swift](https://img.shields.io/badge/Swift-SwiftUI-orange)

## 解决什么问题

蓝牙耳机有两套互斥的工作模式：

- **A2DP**：单向高码率立体声输出，音乐 / 视频音质好，但**没有麦克风**。
- **HFP / SCO**（免提通话）：双向，能用耳机麦克风，但整条链路被强制降到**单声道、8–16 kHz 的电话级低码率**——这时连*输出*音质也一起垮掉，声音发闷。

问题就出在这里：**只要有 App 激活了耳机麦克风**（视频会议、语音通话最典型），macOS 会把整副耳机从 A2DP 强制切到 HFP，音质瞬间劣化；而**会议结束后系统往往不会自动切回**高码率模式，于是你得一直忍受闷糊的声音，直到手动去「声音」设置里折腾。

FreeMic 的思路很简单：**把麦克风输入留给内置麦克风，让蓝牙耳机始终待在 A2DP 高音质输出模式**。一键就能在「耳机麦克风」和「内置麦克风」之间切换，既能正常开会，又不牺牲听感。

## 功能

- 🎧 顶部显示当前作为音频输出的**蓝牙耳机**名称与连接状态（绿点 = 已连接）
- 🎙 列出所有**输入设备**（内置麦克风 / 蓝牙耳机麦克风 / 外接设备），点击即切换，当前项打勾
- 🔒 **禁用蓝牙麦克风**：开启后**任何时刻**输入只要变成蓝牙麦就被**立刻**拽回内置麦——从源头杜绝 HFP，耳机永远停在 A2DP 高音质。比"自动切回"更强势（主动、即时，不等会议结束）。开启时面板里其他输入设备**置灰上锁**、自动切回开关交由它接管（默认关闭，opt-in）
- 🤖 **会议结束自动切回**：检测到蓝牙耳机麦克风被释放（视频会议 / 通话结束）后，自动把输入切回内置麦克风，让耳机回到 A2DP 高音质——**App 无关**，钉钉 / 飞书 / Zoom / 系统电话通吃（默认开启，可在面板关闭）
- 🏝️ **灵动岛音量提示**：调节音量时在屏幕顶部（刘海 / 灵动岛位置）弹出一枚悬浮胶囊，显示当前**输出设备名称**与音量（**进度条 + 百分比**），约 1.6 秒自动消失。单窗口复用、事件驱动，尽量轻量（默认开启，可在面板关闭）
- 🌐 **中文 / English 界面**：默认跟随系统语言，也可在面板「语言 / Language」里手动切换，即时生效
- 🔄 插拔耳机、系统切换设备时**自动刷新**（CoreAudio 监听，无需手动点）
- 🪶 常驻菜单栏，无 Dock 图标（`LSUIElement`），纯系统 API、零第三方依赖
<img width="306" height="329" alt="iShot_2026-06-13_19 34 39" src="https://github.com/user-attachments/assets/7a4ebb53-2cfe-4092-8d6d-11e964128cf9" />
<img width="306" height="329" alt="iShot_2026-06-13_19 32 54" src="https://github.com/user-attachments/assets/b0c73b82-f443-4c79-96b5-adae65137c21" />


## 构建与运行

需要 Swift 工具链（Xcode 或 Command Line Tools 均可）：

```bash
./build.sh          # 编译 + 打包成 FreeMic.app（arm64 + x86_64 通用二进制）
open FreeMic.app    # 启动，图标出现在菜单栏
```

调试设备检测（命令行打印，不开界面）：

```bash
FreeMic.app/Contents/MacOS/FreeMic --list
```

## 安装与首次打开

自己编译出来的 `FreeMic.app` 可直接 `open`。但如果是**从网上下载**别人发布的版本，由于本项目目前只做了**临时签名（ad-hoc）**、未经 Apple 公证，首次打开会被 Gatekeeper 拦下（提示「无法验证开发者」）。放行方式二选一：

- **右键** App → **打开** → 在弹窗里再点「打开」；或到 `系统设置 → 隐私与安全性 → 仍要打开`
- 或终端执行：`xattr -dr com.apple.quarantine /路径/FreeMic.app`

> 想做到双击零警告，需要 Apple 开发者账号（$99/年）做 **Developer ID 签名 + 公证**——`build.sh` 末尾已留好对应步骤的注释模板。无需上架 App Store。

## 开机自启（可选）

把 `FreeMic.app` 拖到 `系统设置 → 通用 → 登录项` 即可。

## 结构

| 文件 | 作用 |
|------|------|
| `Sources/FreeMic/FreeMicApp.swift` | 入口，`MenuBarExtra` 菜单栏场景 |
| `Sources/FreeMic/AudioManager.swift` | 可观察状态模型，封装读取/切换/监听 |
| `Sources/FreeMic/CoreAudioHelpers.swift` | CoreAudio HAL 属性读写的类型化封装 |
| `Sources/FreeMic/PopoverView.swift` | 清新风格面板 UI |
| `Sources/FreeMic/VolumeHUD.swift` | 灵动岛风格音量悬浮窗（`NSPanel` + SwiftUI） |
| `icon_build/MakeIcon.swift` | 用 CoreGraphics 生成 App 图标与菜单栏模板图的脚本 |
| `Resources/AppIcon.icns` | 打包进 `.app` 的应用图标 |
| `Info.plist` / `build.sh` | 打包成 `.app` 的配置与脚本 |

## 说明

切换默认输入设备使用 CoreAudio 公共 API，不采集音频，因此**无需麦克风权限**。

### 自动切回是怎么判断「会议结束」的

不靠识别具体 App（钉钉 / 飞书 / Zoom……那样既脆弱又要逐个适配），而是直接听音频会话状态：

1. 监听每个**蓝牙输入设备**的 `kAudioDevicePropertyDeviceIsRunningSomewhere`——耳机麦克风被占用（进入 HFP 通话）时为 `true`，被释放时变 `false`。
2. 捕捉到 `true → false`（麦克风刚被放开）后，**去抖 1.8 秒**再复检，避开 HFP→A2DP 拆链抖动和会议中途的短暂静音。
3. 仅当此刻**默认输入仍是蓝牙设备**、它**确已空闲**、且**存在内置麦克风**时，才切回内置麦克风。

因此它**与会议软件无关**，钉钉 / 飞书 / Zoom / 系统电话乃至任何占用耳机麦克风的程序都适用；整条链路只读 CoreAudio 属性，**同样无需任何权限**。该配置**默认开启**，可在面板开关随时关闭（持久化在 `UserDefaults`，键 `autoRevertToBuiltInMic`）。

## 许可协议

本项目基于 [MIT License](LICENSE) 开源，可自由使用、修改与分发。
