# HyperOS FCM Unified Guard

**简体中文 | [English](README_EN.md)**

单个 Magisk 模块，提供 Millet/FCM 基础守护，并根据当前系统接口在设备上生成静态框架策略。当前版本 **v0.4.0-alpha.5**，无需 FCM Live APK、LSPosed 或 Zygisk。

**[Latest Release](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/latest) · [下载 Magisk ZIP](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.5/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.5-static.zip) · [SHA-256](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/releases/download/v0.4.0-alpha.5/HyperOS-FCM-Unified-Guard-v0.4.0-alpha.5-static.zip.sha256)**

> 当前仍为测试版。GitHub 的 Latest 标记用于提供最新下载入口，不代表已完成多机型、真实 OTA、端到端推送或续航验收。详见 [验证记录](static-patch/VALIDATION.md)。

## 功能与兼容性

不写死机型、Android/HyperOS 版本或 ROM 哈希白名单。安装时按实际类、字段、方法及 ART 能力检测，缺少接口仍可安装；不能使用的功能逐项报告，其余功能继续适配。基础守护独立于静态框架后端。

| 功能 | 当前行为 |
| --- | --- |
| Millet/Greeze 免冻结 | 按应用名单维护，保留其他应用的系统管理 |
| FCM 连接恢复 | DNS 感知、主动心跳、重连调度与受限进程恢复，不要求必须运行 sing-box |
| 静态框架策略 | 广播、自启动、临时豁免、GMS 限制及进程/网络名单等十项能力，分别检测、生成和校验 |
| SwipeUpClean | 处理管理名单中的识别事件，清除 stopped 标志，不主动重新启动应用 |
| DeviceIdle | 默认 observe；可选 enforce，仅撤销本模块添加的条目 |
| Magisk 状态 | 名称和描述显示状态灯，点击“操作”查看逐项原因并立即检查、重试适配 |

不设机型限制不等于所有 ROM 都有相同接口。非 HyperOS 或缺少 OEM 接口的系统可能只运行部分功能；实际结果以状态报告为准。静态广播策略包含停止包标志处理，不能承诺完全保留原系统的 Force Stop 推送语义。

## 安装与升级

1. 下载 Release 中的 `HyperOS-FCM-Unified-Guard-v0.4.0-alpha.5-static.zip`，不要把 GitHub 自动生成的 Source code ZIP 当作安装包。
2. 备份 `/data/adb/fcm_unified_guard/`；若从旧 Millet Guard 迁移，同时保留旧名单与所有权记录。升级保留已有 `packages.list` 和 `unified.conf`，仅在首次没有配置时导入旧名单。
3. 在 Magisk 中安装 ZIP。关闭旧 Millet Guard 的重复守护；若此前启用了 FCM Live/LSPosed 桥接，关闭对应功能，避免与静态策略重复处理。
4. 将需要管理的应用逐行写入 `/data/adb/fcm_unified_guard/packages.list`。首次安装后正常重启，等待“自动适配中”变为“待重启生效”，再正常重启一次；已有可用缓存时可能无需这一步等待。
5. 最后一次重启后会先显示“框架已挂载，正在确认启动，无需再次重启”，等待确认完成后显示“框架已加载”。此时不要连续重启；点击“操作”可查看基础核心、FCM、豁免和各项静态功能，正常或待确认的缓存不会因此重复生成。

模块 ID 为 `fcm_unified_guard`。不兼容、检测或生成失败不会自动禁用、卸载整个模块，也不会自动重启手机。与旧核心同时运行时会报告冲突并避免重复写入，由用户决定保留哪一个。旧模块卸载可能撤销其管理记录，迁移时应保留备份。

## 状态灯怎么看

| 状态 | 含义 |
| --- | --- |
| 🟢 正常 | 当前基础进程、FCM 连接、豁免与已适配框架功能检查通过 |
| 🟡 部分可用/待生效 | 部分接口缺失、诊断未知、适配中，或新缓存等待下次正常重启 |
| 🔴 需要查看 | 已观察到断联、工作进程缺失、生成/挂载错误、冲突或补丁启动未确认 |

灰色功能项表示相关 OEM 接口不存在或无法读取。刷新 Magisk 模块列表可查看最近状态；“操作”会立即重新检查，适配失败时重试。启动状态只对应本次开机，上一次的“待重启生效”不会沿用；“正在检查本次启动”或“框架已挂载，正在确认启动”都应等待，无需再次重启。绿灯只说明当前检查通过，不能代替真实消息到达测试；连接异常也可能来自网络或 GMS。

## 系统升级后

开机快速检查当前缓存；框架内容变化后，先让新系统和基础守护正常启动，再自动检测并重建可用功能。新缓存校验成功后，在**下一次正常重启**加载，无需重装相同 ZIP，也不会自动重启。

OTA 后首次启动可能暂处于基础模式。静态框架代码无法可靠地在已运行的 system_server 中替换，因此不会强行把旧系统 JAR 覆盖到新系统上。已有缓存会保留；生成失败不自动卸载模块，上一轮未确认启动只隔离对应缓存，基础核心继续工作。是否禁用或卸载由用户决定。

哈希由设备动态计算，仅用于缓存身份、完整性与生成竞争检查，不是安装白名单。相同输入的失败在一次开机内不反复编译；输入变化或点击“操作”后可再次检测。详细流程见 [自适应机制](static-patch/README.md)。

## 耗电与验证边界

状态检查复用五分钟维护周期及 FCM 健康缓存，没有为状态灯增加常驻进程、AlarmManager 唤醒或专用唤醒锁。核心合并了日志订阅和维护定时循环，并过滤无关设置事件。系统变化后的框架生成会有一次性 CPU 与 I/O 开销，正常运行不会持续编译。

已通过 34 项策略检查、严格字节码契约与按功能降级测试，以及 30 项 Linux 安装/启动/状态/OTA 重建流程测试。当前手机的隔离安装与原厂框架生成得到 10/10 功能，逐项 ART 校验通过；**这不等于新版已完成实际冷启动或真实 OTA 验收**。

端到端消息、跨机型和同条件电池 A/B 尚未完成，不能给出实测省电比例。CPU/RSS 采样也不能直接换算整机耗电。参见 [新版验证记录](static-patch/VALIDATION.md)；旧架构记录在 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 从源码构建

需要 Python、JDK 17 和包含 Android 36 平台及 Build Tools 36.0.0 的本地 Android SDK：

~~~sh
python static-patch/build.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test.py --sdk /path/to/android-sdk --jdk /path/to/jdk
python static-patch/test-adaptive-runtime.py
python static-patch/package.py
~~~

安装包与校验文件输出到 `dist/`。包内不含 APK、LSPosed/Zygisk 桥接或预制厂商 JAR；厂商框架缓存只在设备本地生成。新版构建检查覆盖 `main` 和开发分支。

仓库保留了旧版集成桥接的 `module/`、`bridge-source/` 与根目录 `build.sh`；**根目录 `bash build.sh` 构建的是旧 v0.2.0 包**。旧版安装说明请查看 [v0.2.0 文档](https://github.com/E3N-glotm/HyperOS-FCM-Unified-Guard/blob/v0.2.0/README.md)，不要与新版步骤混用。

## 来源与许可

- 基础守护源于 [E3N Millet Guard](https://github.com/E3N-glotm/HyperOS-Millet-Guard)，保留根目录 [MIT 许可](LICENSE)。
- 静态策略源于 [Howard20181 / HyperOS_FCM_Live](https://github.com/Howard20181/HyperOS_FCM_Live) 及 [E3N 兼容分支](https://github.com/E3N-glotm/HyperOS_FCM_Live)，采用 GPL-3.0-only；对应源码及 [GPL 许可](bridge-source/LICENSE) 保留在 `bridge-source/`，新版实现位于 `static-patch/`。
- 根目录 MIT 不覆盖 GPL 部分。安装包附带两份许可证；原桥接来源可查 [PROVENANCE.txt](module/bridge/PROVENANCE.txt)。

### v0.4.0-alpha.5 故障修复

修复 FCM DNS 规范别名误判、长期断联时有条件的原生软重连，以及部分 OEM DEX 重写发生 `Unsigned short value out of range: 65536` 的问题；静态适配生成的结果仍须经过 ART 校验并在下一次正常重启加载。缺失的 OEM 字段继续独立降级，不会被标记为已适配。更多说明见 [静态适配说明](static-patch/README.md)。

### v0.4.0-alpha.5：跨 ROM 能力探测

新增 PowerKeeper 接口逐项探测，点击 Magisk 模块「操作」即可查看当前 ROM 的 DEX 方法和签名。找不到 PowerKeeper、类名或签名不同均不会禁用原有 FCM 守护。**此版本是诊断与兼容性基础设施升级，尚未增加 PowerKeeper Hook；接口被发现不等于效果已经等效。**

### v0.4.0-alpha.5：修复 FCM 在线却显示未知

修复 2 分钟 FCM 状态采样与 5 分钟 Magisk 状态刷新不同时序下，可能出现 `FCM未知 / 部分功能适配中` 的误报。状态缓存缺失或超过 5 分钟时，在原健康检查周期中追加一次限时检测；有效缓存不增加 GMS 查询。健康页不再改写 FCM 守护进程的观察文件，避免覆盖同时到达的更新。此修复仅改变诊断同步，不更改已有的 10 项静态策略、不添加后台工作进程，也不代表 PowerKeeper 已与原双模块完全等效。
