# AlexToolBox

macOS 26+ 菜单栏工具，合并 Macouse 与 HeyMelodyBar：

- **鼠标**：Windows 指针模型（加速开关 + 1…11 档速度），写入 Apple HID 驱动读取的指针加速属性。
- **耳机**：OPPO / OnePlus 耳机私有 SPP 协议，切换自适应 / 降噪 / 通透 / 关闭。

窗口用 SwiftUI `MenuBarExtra(.window)`，Liquid Glass（`glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)`）与弹簧、matched-geometry 动画。

## 构建与运行

```bash
./build.sh                 # release → build/AlexToolBox.app → ad-hoc 签名
open build/AlexToolBox.app
```

需要 Xcode 工具链（SwiftUI 宏插件不在 Command Line Tools 里）。`build.sh` 默认使用
`/Applications/Xcode.app/Contents/Developer`。

最低系统：macOS 26.0。首次启动需在「系统设置 → 隐私与安全性 → 蓝牙」授权。

## 测试

```bash
swift test
```

- `MouseControlTests`：加速表字节布局、驱动解码后的增益/断点、参数化曲线、档位倍率、目标选择。
- `HeadsetControlTests`：OPOv1 帧编码、LEB128、拆帧/分片、降噪位图、上报子模式映射。

## 结构

| 路径 | 内容 |
| --- | --- |
| `Sources/MouseControl/` | Windows 指针模型、加速表编码、HID 服务读写、快照/设置存储 |
| `Sources/HeadsetControl/` | OPO 协议编解码、RFCOMM 链路管理 |
| `Sources/AlexToolBox/` | SwiftUI App、菜单栏 UI、鼠标/耳机面板 |
| `Sources/MacouseSPI/` | 私有 IOKit SPI 声明 |
| `Tests/` | 两套 XCTest |

## 行为说明

- 鼠标设置只作用于外接鼠标，不改写内置触控板；没有外接鼠标时不做写入。
- 指针原值快照保存在 `~/Library/Application Support/AlexToolBox/originals.plist`，退出时恢复。
- 耳机通过 SDP UUID `0000079A-D102-11E1-9B23-00025B00A5A5` 识别已配对设备，通道号由 SDP 给出。
- 耳机首次打开 RFCOMM 可能超时，代码有次数上限与退避，避免打断 ACL 链路。
