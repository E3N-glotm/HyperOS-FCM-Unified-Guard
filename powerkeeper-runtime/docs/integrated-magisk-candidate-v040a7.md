# 单模块集成候选说明：v0.4.0-alpha.7（非正式版）

## 交付物

`HyperOS-FCM-Unified-Guard-v0.4.0-alpha.7-integrated-candidate.zip` 是一个 **真实 Magisk 安装包**，模块 ID 仍为 `fcm_unified_guard`，而非两个独立模块的叠加。源码及构建可追溯到 PR #15，发布前仍需真实消息投递和跨 ROM 对照。

包含三层相互独立的能力：

1. **基础 FCM/Millet 守护**：事件驱动保持 `MILLET_NO_RESTRICT_APP` 的被管理应用，设备白名单检查、有限 FCM 健康自愈与用户既有设置保护；不因 PowerKeeper Hook 失败而停机。
2. **自适应系统框架**：在手机上检测并按签名验证 services.jar / miui-services.jar 的可用功能，成功后缓存并经下一次正常启动加载；无法兼容时只跳过相应功能，不自动重启。
3. **PowerKeeper 原生专项**：单一 ZIP 内的 `zygisk/arm64-v8a.so` 与 `powerkeeper-runtime.dex`，无需 LSPosed；仅在动态识别的 PowerKeeper 进程做 ART Hook，已验证的 GMS Observer 和 Doze 接口在兼容 ROM 上拦截。针对 DNS 的 UID 精确候选**默认关闭**，不会对其他应用防火墙规则做修改。

**安装不需要用户的 Google Play 微信 APK/LSPosed 模块，也不需要更换或修改 OEM PowerKeeper.apk。**

## 故障隔离和观察

- 仅支持 arm64 原生库；其他 CPU 架构不应宣称 PowerKeeper 专项可用，FCM 基础守护应单独工作。
- 如果某次带 PowerKeeper 原生库的启动未被正常确认，下一次启动前创建 `backend/powerkeeper-hook.disable`，只关闭 PowerKeeper Hook，其他守护照常运行。
- `module.prop` 状态依据 **当前开机**、FCM 诊断、Settings 白名单、Greeze、框架挂载及 PowerKeeper 进程映射生成；native 库已映射不等于 OEM Hook 已安装，也不等于真正收到推送。
- 缺乏 Zygisk/Zygisk Next 或 OEM 方法签名时，PowerKeeper 专项降级；不允许安装脚本自动打开旧 LSPosed 或强制停用其他模块。
- Java 方法日志和 Root Companion 分阶段诊断仅编译进独立实验构建。集成 ZIP 强制使用 `FCMU_PK_EXPERIMENT_DIAGNOSTICS=OFF` 的原生库，不产生每次调用的私有文件审计开销。
- 主线生产模块与此前设备上的 `fcmu_pk_experiment` 实验包不同；后者曾单次自动关闭，不应视为当前统一模块已安装。

## 安装与核对

安装前由 CI 核验 ZIP SHA256、CRC、Magisk 根目录文件、原生 ARM64 ELF、Java DEX、无旧 LSPosed bridge/APK、无实验原生诊断字符串，以及模块的 SELinux/回退脚本。仅在设备可控且具备恢复手段时，在 Magisk 中正常安装并通过 Magisk 页面正常重启。安装后分别查看模块「操作」页、`/data/adb/fcm_unified_guard/health-status.txt` 与 `/data/adb/modules/fcm_unified_guard/backend/` 状态；不需重复安装 ZIP。

如遇异常，在 Magisk 中禁用统一模块并正常重启。若只是 PowerKeeper Hook 触发隔离，可保留基础守护，检查 `backend/pk-boot.status` 和 `backend/powerkeeper-hook.disable`；不要在未经确认时手动清除隔离标志。

## 尚未满足正式版门槛

- 目前的 PowerKeeper 4.2.00 / Android 17 单独实验已验证两个 OEM 方法 Hook 和实际调用，但**尚未直接验证集成版完整启动链路**。
- `mGmsLimitEnabled` 可以独立于 Java Hook；真值以 Greeze 状态和消息送达为准。
- 5228 TCP 已建立不等于端到端 FCM 投递成功，需要受控真实消息连续采样。
- 未取得足以宣称功耗 `<=` 旧 Millet Guard + E3N FCM Live 组合的同设备、同负载对照，也未获得多设备/旧 ROM 全量反馈。因此**本候选包不是稳定 Release，不应以“全功能等效/零耗电增加”宣传**。

研发优先级：先通过单次实机集成测试、确认安全熔断及基础 FCM 不受干扰，再做多个 ROM 签名适配和端到端收发、耗电评测，最后发布正式版。
