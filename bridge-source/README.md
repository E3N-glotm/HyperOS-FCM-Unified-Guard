# HyperOS FCM Live · E3N HyperOS 4 Compatibility

Fork of [Howard20181/HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live), licensed under GPL-3.0.

## 中文

适配 **HyperOS 4 / Android 17** 的 LSPosed 模块，用于减少 HyperOS 对 Google FCM 重连和推送广播的限制。基于上游 [PR #30](https://github.com/Howard20181/HyperOS_FCM_Live/pull/30) 的 PowerKeeper 4.2.00 修复，并新增 Greeze 和 ListAppsManager 兼容处理。

### 实机验证

在 Xiaomi `pudding`、`OS4.0.4.0.XPCCNXM`、Android 17、PowerKeeper **4.2.00**、LSPosed **2.2.1/API 102** 上确认：

- `GreezeManagerService.isAllowBroadcast`、`deferBroadcastForMiui`、`triggerGMSLimitAction`：Hook 注册成功
- `ListAppsManager.SYSTEM_BLACK_LIST` 与 `USE_DATA_WHITE_LIST`：Hook 注册成功
- `DomesticPolicyManager.deferBroadcast`：仅对 FCM 相关广播放行，其他广播执行原逻辑
- `GmsObserver.updateFrameworkGmsNetStatus(boolean)`：在新版 PowerKeeper 中 Hook 注册成功
- 已被 HyperOS 4 移除的旧接口：逐项跳过，不影响其他 Hook 注册

**注意：** 以上为实机注册、冷启动、进程稳定性和 Google 长连接的检查，不代表已验证所有 App 的消息送达延迟。HyperOS 其他版本可能不兼容。

### 安装

到 [Releases](https://github.com/E3N-glotm/HyperOS_FCM_Live/releases) 下载 E3N APK，安装后在 **LSPosed → 模块** 启用 **HyperOS FCM Live · E3N OS4**，作用域为「系统框架」和「省电与性能 / PowerKeeper」（`com.miui.powerkeeper`），然后重启。

使用独立包名 `io.github.e3n.hyperos.fcmlive`，与原作者版本并存。**不要同时启用两个版本**，否则可能重复 Hook。出现不稳定时，在 LSPosed 中关闭此测试模块并重启；必要时通过 LSPosed 安全模式恢复。

该模块可能增加后台唤醒和耗电；不会替代 FCM Token 注册修复、Google Play 服务的网络连接或 Millet Guard 的独立连接管理。

完整的修改内容、验证边界和原项目作者致谢见 [兼容性说明](docs/HYPEROS4_COMPAT.md)。

## English

LSPosed compatibility fork for **HyperOS 4 / Android 17**, integrating upstream PR #30 for the `PowerKeeper 4.2.00` `GmsObserver.updateFrameworkGmsNetStatus(boolean)` API. Adds per-method optional Greeze hooking, renamed ListAppsManager field fallbacks, FCM-only broadcast exemption, and immutable whitelist safety.

Runtime hook registration was verified on Xiaomi `pudding` / `OS4.0.4.0.XPCCNXM` / Android 17 / LSPosed API 102. End-to-end message-delivery latency has **not** been independently verified.

The E3N package uses a separate application ID so it can coexist with the original signed module. **Keep the original module disabled** and enable this version in LSPosed with scopes **System Framework** and **com.miui.powerkeeper**, then reboot. Disable the fork and reboot to restore original behavior.

Original author: [Howard20181](https://github.com/Howard20181). HyperOS 4 GmsObserver adaptation credit: [793354162, upstream PR #30](https://github.com/Howard20181/HyperOS_FCM_Live/pull/30). This derivative remains licensed under GPL-3.0.
