# HyperOS FCM Unified Guard v0.4.0-alpha.33

## 本次修复：持续断连能够自动恢复

目标是允许短暂网络抖动，但尽量避免 GMS/FCM 在休眠后停留数小时都没有有效恢复动作；**并不承诺彻底不断连或零延迟推送**。

- **识别备用 MCS 连接**：支持 Google Play 服务实际使用的 `mtalk.google.com` 及 `alt1–alt3-mtalk.google.com`，可用端口包括 TCP 5228–5230、443。只检查动态 GMS UID 对应的合法 MCS 地址，不把普通 HTTPS 443 当作 FCM 可达。
- **不再把假在线当作恢复成功**：软重连及受限 GMS 恢复必须在内核中找到匹配 UID、对端 IP、端口的 `ESTABLISHED` MCS Socket，才能清除断连计时。
- **持续 DNS 失败分级恢复**：保留原有 DNS Resolver、Box4Magisk、临时 hosts 等受限恢复流程；长时间仍无法恢复时，在网络条件满足的情况下进入有冷却时间和次数上限的 GMS-only 兜底处理。不会自动重启 Wi-Fi、蜂窝网络、全局 Box 或清理应用数据。
- **Android 17 网络验证修复**：从 `dumpsys connectivity` 流式匹配当前默认 NetID 的真实 `INTERNET + VALIDATED` 能力，避免系统转储过大造成 `Argument list too long`，也不会把历史 `EVER_VALIDATED` 当作当前联网。
- **已有深度休眠唤醒机制保留**：继续使用 alpha32 内置的 ARM64 内核 alarmtimer / 短时执行保护，不增加第二套常驻唤醒进程。

## 兼容性与升级

本次由已发布的 **alpha32 完整集成包** 做差分重建，原来的 Zygisk、PowerKeeper Runtime DEX、原生闹钟与 TCP keepalive、安装脚本、健康评估和静态试验组件均逐文件保持不变。仅替换 `bin/fcm_guard.sh`、更新 `module.prop`，并增加此版本说明。

**不可与旧版 Millet Guard 同时启用。** 统一模块会在检测到原版 Millet Guard 仍启用时拒绝启动自己的守护进程，防止重复写入。已有 FCM Live 应用和 LSPosed 作用域不会被本 ZIP 自动卸载或改动；完整系统 Hook 是否生效仍取决于对应 APK、设备接口及 LSPosed 配置。此 ZIP **不包含 FCM Live APK**，因为本次目标是修复统一模块的恢复核心，不自动替换带有不同签名的 APK。

## 验证范围

- 按 GitHub Release 中发布的 alpha32 ZIP SHA256 核验来源；保证 70 个原始条目中除上述两项外其他内容字节不变，额外新增 1 项说明文档。
- GitHub CI 检查脚本、DNS/MCS 443、网络能力辨别、自动恢复边界和 ZIP 完整性。
- 本轮尚未在装有统一模块的设备上完成一整夜实测；**不能把源码测试通过解读成跨机型实测稳定性达标**。

如果出现实际故障，优先确认原生 GMS 连接历史、默认网络 VALIDATED、真实 MCS Socket 和模块自己的受控恢复记录；无需发送私人应用数据。
