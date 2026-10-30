# PowerKeeper 专项保护（跨 ROM 实验主线）

目标：一个 Magisk 模块、不依赖 LSPosed，达到旧 Millet Guard + E3N FCM Live 的实际行为，并减少后台开销。

## 当前已实现

- 无机型、版本及 ROM 哈希白名单，按应用 ClassLoader 内真实方法的参数和返回类型逐项匹配。
- 旧版 GmsObserver 的闹钟、网络、唤醒锁三个 boolean 方法以及 NetdExecutor.initGmsChain 的处理。
- 新版 GmsObserver.updateFrameworkGmsNetStatus(boolean) 的上游参数处理，避免此前尝试在 Greeze Binder 下游修改时产生状态回读不一致。
- PowerKeeper 自有 Doze 名单添加 GMS，保留原厂名单，兼容不可修改的 List。
- 每项功能独立失败、独立报告。找不到某个 OEM 方法不会禁用其他方法，更不会停止基础 FCM 守护。
- Android Java 桥接 DEX 构建，旧/新版、不同签名、缺失方法、异常及不可变 List 的跨 ROM 模拟测试。

## 必须区分的状态

1. 通过 OEM APK DEX 找到候选方法，只说明签名存在。
2. 经原生 ART Hook 安装返回成功，仅说明运行时安装成功，仍不证明方法实际被调用。
3. 旧双模块行为等效必须独立观察调用、返回状态、真正的 FCM 消息送达及能耗。

**目前缺少已在目标 Android 设备验证通过的 Zygisk/LSPlant 原生装载库。**
PowerKeeperRuntimeEntry.nativeHook 只定义 JNI 接口，不会在已有发行模块中调用。
本目录的 DEX 不会进入 alpha.6 的正式 ZIP；当前 Magisk 静态 10/10 维持独立工作。

## 构建与测试

从仓库根目录执行：

    python3 powerkeeper-runtime/test_runtime.py
    python3 powerkeeper-runtime/build.py --sdk "$ANDROID_HOME" --jdk "$JAVA_HOME"

得到 powerkeeper-runtime/build/powerkeeper-runtime.dex，供下一阶段 Zygisk 装载工程离线检查。构建 DEX 不等于启用 Hook。

## 正式启用门槛

- 原生 Zygisk 模块只能选择实际 PowerKeeper 进程，其他进程即时退出，不新增轮询/心跳。
- 动态加载目标应用 ClassLoader 后再装 Hook，找不到接口只降级本项。
- Magisk 无 Zygisk 时，核心可独立运行；不修改任何签名 PowerKeeper.apk 或 GMS Token。
- 必须通过 Android 17 实机 ART Hook、冷启动无崩溃、网络状态读回一致、锁屏通知真实送达及长时间续航基线测试，才考虑正式发布。
