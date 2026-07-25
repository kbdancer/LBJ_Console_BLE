# LBJ Console BLE

基于上游 [undef-i/LBJ_Console](https://github.com/undef-i/LBJ_Console)（`flutter` 分支）的 **BLE 精简** 变体。

桌面显示名：**LBJ BLE**  
包名：`org.noxylva.lbjconsole.flutter.ble`

## 上游来源

| 项 | 说明 |
|----|------|
| 上游仓库 | https://github.com/undef-i/LBJ_Console |
| 上游分支 | `flutter` |
| 许可证 | 与上游一致（GPLv3，见 `LICENSE`） |

## 相对上游 / 相对完整版的主要修改

1. **仅蓝牙通道**：通过 BLE（`LBJReceiver` / FFE0 / FFE1）接收列车 JSON；无 NetJSON TCP 客户端。
2. **去除 App 侧接收机 WiFi 配网 UI**（本变体不包含 NetJSON / `wifi_*` 设置页能力）。
3. **保留**：BLE、RTL-TCP、音频输入、地图/历史/合并、SD 相关 BLE 命令（`sd_status` / `sync` 等，取决于固件）。
4. **应用标识**：独立 `applicationId` 与显示名，可与 WiFi 版并装。

## 配套固件

需刷写带 **BLE** 的接收机固件（例如本地工程中的 `SX1276_Receive_LBJ_fusion` 精简版）。带 NetJSON 的固件也可仅用 BLE 通道对接本 App。

## 构建

```bash
flutter pub get
flutter build apk --debug --target-platform android-arm64
```

## 致谢

感谢 [undef-i/LBJ_Console](https://github.com/undef-i/LBJ_Console) 及上游文档中列出的相关项目作者。
