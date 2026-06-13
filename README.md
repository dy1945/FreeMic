# FreeMic

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
- 🤖 **会议结束自动切回**：检测到蓝牙耳机麦克风被释放（视频会议 / 通话结束）后，自动把输入切回内置麦克风，让耳机回到 A2DP 高音质——**App 无关**，钉钉 / 飞书 / Zoom / 系统电话通吃（默认开启，可在面板关闭）
- 🔄 插拔耳机、系统切换设备时**自动刷新**（CoreAudio 监听，无需手动点）
- 🪶 常驻菜单栏，无 Dock 图标（`LSUIElement`），纯系统 API、零第三方依赖

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
| `Info.plist` / `build.sh` | 打包成 `.app` 的配置与脚本 |

## 说明

切换默认输入设备使用 CoreAudio 公共 API，不采集音频，因此**无需麦克风权限**。
