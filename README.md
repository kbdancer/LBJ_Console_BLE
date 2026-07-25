# LBJ Console BLE

基于上游 [undef-i/LBJ_Console](https://github.com/undef-i/LBJ_Console)（`flutter` 分支）裁剪/扩展的 **BLE 精简** 变体。

| 项 | 值 |
|----|----|
| 显示名 | **LBJ BLE** |
| applicationId | `org.noxylva.lbjconsole.flutter.ble` |
| 对照上游 | https://github.com/undef-i/LBJ_Console/tree/flutter |
| 许可证 | 与上游一致（见 `LICENSE`，GPLv3） |

> **说明：** 本仓库相对上游的功能修改与文档整理，**全部由 AI 编程工具（Cursor Agent）完成**。

## 上游基线能力（保留）

上游 `flutter` 分支本身具备：

- BLE 收包（`LBJReceiver` / FFE0·FFE1）
- RTL-TCP、音频输入
- 列车记录 / 实时监控 / 地图 / 设置
- 后台保活与本地通知

## 相对上游的功能修改（本仓库）

### 新增 / 增强

1. **BLE 命令通道扩展**（相对上游 `ble_service`）  
   - 连接后可请求 `sd_status`、`sync`、`sd_clear` 等  
   - 设置页增加接收机 **SD 卡状态 / 同步 / 清除**（经 BLE JSON 命令）  
2. **桌面端数据库**：增加 `sqflite_common_ffi` / `sqlite3_flutter_libs`，便于 Linux 等桌面运行  

### 删除 / 关闭

1. **去除定位相关**  
   - 删除 `location_service.dart`、依赖 `geolocator` / `geolocator_android`  
   - Manifest / MSIX 去掉 location 能力  
2. **不含 NetJSON / 接收机 WiFi 配网页**（与 WiFi 变体分工；上游亦无 NetJSON）

### 调整

1. 独立包名与显示名 **LBJ BLE**，可与 [LBJ_Console_WiFi](https://github.com/kbdancer/LBJ_Console_WiFi) 并装  
2. 信号源仍为：蓝牙（默认）/ RTL-TCP / 音频  

## 信号源对照

| 信号源 | 上游 | 本仓库 |
|--------|------|--------|
| 蓝牙 BLE | ✅ | ✅（默认，并扩展 SD/sync 命令） |
| NetJSON (WiFi TCP) | ❌ | ❌ |
| RTL-TCP | ✅ | ✅ |
| 音频输入 | ✅ | ✅ |
| App 内 GPS 定位 | ✅（geolocator） | ❌ |

## 配套固件

请使用姊妹固件 **[SX1276_Receive_LBJ_BLE](https://github.com/kbdancer/SX1276_Receive_LBJ_BLE)**（纯 BLE）。  
WiFi 固件 / WiFi App 为另一套配对，本 App 不走 NetJSON。

## 命名对照

| 变体 | App | 固件 |
|------|-----|------|
| BLE | `LBJ_Console_BLE` | `SX1276_Receive_LBJ_BLE` |
| WiFi | `LBJ_Console_WiFi` | `SX1276_Receive_LBJ_WiFi` |

## 构建

```bash
flutter pub get
flutter build apk --debug --target-platform android-arm64
```

## 致谢

感谢 [undef-i/LBJ_Console](https://github.com/undef-i/LBJ_Console) 及其 README 中列出的相关项目作者。本变体在其 `flutter` 分支之上修改。

姊妹仓库：[LBJ_Console_WiFi](https://github.com/kbdancer/LBJ_Console_WiFi)（无蓝牙、走 NetJSON）。
