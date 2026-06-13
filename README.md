# FreeMic

一个清新风格的 macOS 菜单栏小工具：显示当前蓝牙耳机与所有输入设备，一键切换麦克风输入（含切回内置麦克风）。

![menubar app](https://img.shields.io/badge/macOS-13%2B-mint) ![swift](https://img.shields.io/badge/Swift-SwiftUI-orange)

## 功能

- 🎧 顶部显示当前作为音频输出的**蓝牙耳机**名称与连接状态（绿点 = 已连接）
- 🎙 列出所有**输入设备**（内置麦克风 / 蓝牙耳机麦克风 / 外接设备），点击即切换，当前项打勾
- 🔄 插拔耳机、系统切换设备时**自动刷新**（CoreAudio 监听，无需手动点）
- 🪶 常驻菜单栏，无 Dock 图标（`LSUIElement`），纯系统 API、零第三方依赖

## 构建与运行

需要 Swift 工具链（Xcode 或 Command Line Tools 均可）：

```bash
./build.sh          # 编译 + 打包成 FreeMic.app
open FreeMic.app    # 启动，图标出现在菜单栏
```

调试设备检测（命令行打印，不开界面）：

```bash
.build/release/FreeMic --list
```

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
