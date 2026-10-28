# HyperOS FCM Unified Guard

**简体中文 | [English](README_EN.md)**

v0.2.0 将 Millet Guard 守护核心和经过实机验证的 E3N FCM Live 桥接纳入同一个项目和 Magisk ZIP，目标是保留原组合的作用并减少重复后台工作。**完整功能仍使用 LSPosed；这不是 Magisk-only 版本，也不是新的注入框架。**

## 功能与边界

| 路径 | v0.2.0 实现 |
|---|---|
| Millet/Greeze 免冻结 | 原有按应用名单与所有者感知合并，保留其他应用的系统管理 |
| FCM 假在线与断联 | 原有 15 分钟主动心跳、DNS 判断、重连闹钟恢复及受限进程恢复 |
| FCM 广播、自启动与临时豁免 | 集成 E3N FCM Live v1.4.1-e3n-os4 原始 APK，保留已适配的进程内 Hook |
| PowerKeeper GMS 限制 | 原桥接的接口兼容与原生 limiter 检查 |
| 最近任务 SwipeUpClean | 仅处理识别事件且在管理名单中的包，清除 stopped 标志，不重新启动应用 |
| DeviceIdle | 默认 observe，只读；可选 enforce，撤销时仅移除本模块添加的条目 |

桥接中的具体 Hook 以 ROM 接口和 LSPosed 运行日志为准。原桥接的 `FLAG_INCLUDE_STOPPED_PACKAGES` 逻辑也随原始二进制保留，不能声称整个方案完全不影响 Force Stop 后的推送语义。

## 本次减少了哪些开销

| 原路径 | 现在 |
|---|---|
| 设置目录每个事件都执行 Shell handler | BusyBox 输出事件流，常驻 Shell 先过滤文件名；不为无关事件启动 handler |
| 设置变更连带执行 FCM 检查 | 白名单维护与健康检查分离；保留开机、手动操作、120 秒和 GMS 原生事件检查 |
| 两个 logcat 订阅及管道子 Shell | 一个双缓冲区过滤订阅，分别分发 GMS 和 SwipeUpClean |
| 两个独立定时循环 | 一个按最近截止时间休眠的维护循环，保留 120/300 秒周期 |
| 每次健康检查两次 GcmService 查询 | 未触发心跳时一次，心跳后仍重新查询并处理暴露的断联 |
| 仅凭 PID 停止工作进程 | 新进程记录 PID 和 `/proc` 启动时间，拒绝终止身份不匹配的进程 |

FCM 恢复在事件处理器内异步执行，避免长时间重连检查阻塞 SwipeUpClean。没有新增 AlarmManager 定时唤醒或 wakelock。上述减少的是操作和进程开销，**不是已测得的整机续航提升比例**。

## 安装与迁移

1. 保存旧配置 `/data/adb/millet_guard/packages.list`。安装本 Release 的 ZIP，模块 ID 为 `fcm_unified_guard`。
2. 完整模式需要 LSPosed，桥接作用域为 `system` 与 `com.miui.powerkeeper`。若已使用 E3N FCM Live v1.4.1-e3n-os4，直接复用，勿重复启用原版。
3. 首次安装桥接可执行 `su -c 'sh /data/adb/modules/fcm_unified_guard/bin/bridgectl install'`，然后在 LSPosed 启用并重启。安装脚本不会改写 LSPosed 数据库，也不会覆盖现有不同签名 APK。
4. 将需要管理的应用写入 `/data/adb/fcm_unified_guard/packages.list`。从旧版本迁移时同时备份 `managed.last`；旧模块卸载前必须处理其所有权记录，避免卸载脚本撤回正在使用的名单。
5. 禁用旧 Millet Guard，启用本模块并重启。两个核心不能同时运行；发生冲突时新核心停止自身工作进程并退出。桥接仍由 LSPosed 独立管理。

点击 Magisk **操作**，查看 GMS、白名单、DeviceIdle 与桥接状态。桥接检查区分二进制校验和当前 PID 的 Hook 注册日志；没有日志会显示 UNKNOWN，不能把“已安装”当作“已生效”。

## 回退

禁用融合核心、重新启用旧 Millet Guard并重启。E3N 桥接可继续复用，不必重装或重新设置作用域。卸载融合核心不会自动卸载可能早已存在的桥接。停用桥接需要在 LSPosed 中单独操作并重启。

## 验证与已知限制

见 [实机验证记录](docs/VALIDATION.md)。Connected、Hook 注册成功、合成日志测试分别只证明各自路径，不能代替锁屏端到端消息测试。普通优先级消息还受 Android Doze 和发送端策略影响。

严格 A/B 应在相同网络、屏幕、充电与使用条件下比较多小时消息到达率、P50/P95 延迟、断联时长及电池耗电；`tools/device_observe.sh` 仅为模块进程 CPU/RSS 聚合采样，不是整机电量模型。

## 构建与许可

执行 `bash build.sh` 生成安装包。构建强制校验桥接 APK 的 SHA-256，并且只对文本执行换行规范化，避免损坏二进制。

- 守护 Shell 继承 [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard)，保留根目录 MIT `LICENSE`。
- 桥接为 [Howard20181 原作](https://github.com/Howard20181/HyperOS_FCM_Live) 的 [E3N 兼容分支](https://github.com/E3N-glotm/HyperOS_FCM_Live)，GPL-3.0；完整对应源码、Gradle 构建脚本和 GPL 许可保存在 `bridge-source/`，准确来源见 `module/bridge/PROVENANCE.txt`。
- 根目录 MIT 许可不覆盖 GPL 桥接。ZIP 是两个独立程序的集成分发。桥接为原发布版 Debug 签名，重新编译可能得到不同证书；不要强制覆盖用户已有安装。

桥接源码构建：在 JDK 21 与 Android SDK 37 环境进入 `bridge-source`，运行 `bash gradlew :HyperFCMLive:assembleDebug --no-daemon`。打包默认使用固定校验的原始实测 APK，以保留现有设备签名与行为。
