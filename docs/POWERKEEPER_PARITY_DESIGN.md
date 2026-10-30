# PowerKeeper 精准等效方案（2026-10-30）

## 目标及不可混同的指标

目标始终为 **一个 Magisk 模块、不依赖 LSPosed，可靠 FCM 不低于旧版 Millet Guard + E3N FCM Live，且尽量降低耗电**。

- **能力验证**：DEX/ART/Hook 是否安装成功，特定类、方法、参数是否符合预期。
- **真实等效**：旧方案对同一事件的参数、返回值、状态反馈、唤醒及后续分发是否一致。
- **性能及功耗**：GMS/PowerKeeper 进程 CPU 时间、额外线程、唤醒锁、网络恢复流量及同条件长时电量，不能以“Magisk 不依赖 LSPosed”直接推出更省电。

## 当前手机的真实约束

- `pudding`、Android 17（SDK 37）、HyperOS `OS4.0.5.0.XPCCNXM`，PowerKeeper `4.2.00`，签名 APK 位于 `/system_ext/app/PowerKeeper/PowerKeeper.apk`。
- 原 E3N FCM Live 在 PowerKeeper 中的 Hook 名单六项；当前 APK 真实存在 `GmsObserver.updateFrameworkGmsNetStatus(Z)Z` 和 `GlobalFeatureConfigureHelper.getDozeWhiteListApps(Bundle)`，而旧命名的三个 GmsObserver 方法与 `NetdExecutor.initGmsChain` 未找到。
- `getDozeWhiteListApps(Bundle)` 从 `Bundle` 键 `dozeWhiteListApps` 读取由冒号分隔的包名列表，不等同于 Android 的 `cmd deviceidle whitelist`。
- Greeze Binder `updateGmsNetStatus(Z)Z` 和 `getGmsNetStatus()` 是 PowerKeeper 前者的实际下游。PowerKeeper 检查方法接受结果及状态回读必须匹配原请求；**仅在 Greeze 端强制 false 会破坏协议自洽**。
- Draft PR #7 的第 11 项静态能力生成和 ART 校验 11/11 虽成功，但属于**不等效实验候选**，禁止并入正式 Release。

## 备选架构 A：仅一处精准调用者 Hook（待 PoC）

优先保留当前轻量 Magisk 核心 + 原有已验证静态 framework 10 项。针对 PowerKeeper 4.2.00 中确有的入口，研究把 **Magisk 自带 Zygisk 运行时模块**内置在同一 ZIP，利用兼容 Android 17 的精简 ART Hook 库仅在 `com.miui.powerkeeper` 进程中生效：

1. 进程白名单唯一匹配 `com.miui.powerkeeper`。其余进程均立即释放注入库，不建立常驻监控线程。
2. 只 Hook 真实存在且通过反射签名验证的 `GmsObserver.updateFrameworkGmsNetStatus(boolean):boolean`，在**调用原方法之前**将布尔参数改为 false，以保留 PowerKeeper 自身返回状态检查。
3. 可选 Hook `GlobalFeatureConfigureHelper.getDozeWhiteListApps(Bundle):List`，仅在结果可变、且确实由 OEM 返回列表时追加 `com.google.android.gms`；不可变列表须安全复制，不能篡改其他包名。
4. 其它旧命名方法只有真机确实存在才启用；PowerKeeper 不存在时独立降级，不影响 Magisk FCM 核心。
5. 初始化必须等待目标应用 ClassLoader 可用；Hook 失败记录一次诊断并退出，不在主线程轮询、不断重试或反复重启 PowerKeeper。
6. Zygisk 不可用时依然安装并运行核心，但明示 PowerKeeper 等效能力未启用。**不能把“单一 ZIP”理解为所有 Magisk 管理器默认启用 Zygisk。**
7. 工程许可需同时遵守 LSPlant LGPL 和使用的 inline-hook 后端许可，源码、构建说明及相关许可证随模块发布。

该方案不依赖 LSPosed，但是否稳定与省电必须靠实测；不要提前承诺零开销。参考：
- https://github.com/LSPosed/LSPlant
- https://github.com/LSPosed/LSPosed/blob/master/magisk-loader/src/main/jni/api/zygisk.h

## 备选架构 B：原生 OEM 配置/服务接口

如能找到**有文档或能实测**、可只影响 GMS 的 PowerKeeper 原生命令或配置 API，优先用一次性策略设置和原来的事件触发重查；切忌用高频轮询或广泛关闭整机温控、应用管理、网络防火墙。特别注意 `deviceidle`、PowerKeeper 的 `dozeWhiteListApps` 与 Greeze 内部白名单是独立数据源。

## 门控验收（缺一不可）

- 离线：真实 APK 方法签名审计；ABI/SDK 适配；JDK/NDK 编译与静态检查；异常回退与不兼容 ROM 诊断。
- 实机但不激活：只读查看目标进程/服务；验证库装载范围；监控额外线程和进程。
- 激活后：首先验证 PowerKeeper 不崩溃、其状态回读与原始调用期望一致；再验证 GMS 5228 连接与真实测试通知送达；覆盖 Wi-Fi/蜂窝切换、强制锁屏、应用切走和夜间待机。
- A/B：同 ROM、同网络与电量区间，以真实旧版双模块作为基线。分别记录离线分钟数、重连耗时、FCM 消息实际延迟、PowerKeeper 限制命中次数、GMS/守护进程 CPU 时间与整机待机功耗。
- 出现 BootLoop、PowerKeeper Crash、消息到达率降低或 CPU/电量显著恶化，自动撤销实验模块并恢复前一稳定包；正式版不得混入尚未通过运行时验证的候选。

**当前结论：** 不启用未验证的第 11 项下游静态变更。正式运行保留 v0.4.0-alpha.3、核心 10/10；本设计仅为后续上游精准等效实现的技术依据。

## 2026-10-30 跨 ROM 兼容实施第一步：只读接口探测器

新增 `PowerKeeperProbe.java` 与 `bin/powerkeeper_probe.sh`：不根据 pudding、SDK 或 ROM Hash 截断，动态从包管理器获取 APK 路径并扫描所有 DEX；对每项旧版功能报告存在、签名变化、缺失或不可判断。实际接口缺失只导致该项降级，不阻断 Magisk 核心；没有 PowerKeeper APK 时也是独立 core-only，而不是安装失败。扫描只在手动“操作”触发，五分钟状态检查不扫描 APK，不增加常驻耗电。该版本**不包含实际 PowerKeeper Hook**，下游强制 false 的 11/11 实验保留为 Draft，不进入发行版。
