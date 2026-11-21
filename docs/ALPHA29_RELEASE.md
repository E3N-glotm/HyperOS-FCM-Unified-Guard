## 修复大型系统转储导致蜂窝 DNS 自愈失效

- 修复 Android 的外部 printf 在 connectivity、DNS resolver、订阅、设置和防火墙输出超过单参数长度限制时失败的问题，避免将整份转储传入进程参数。
- 恢复门禁从标准输入读取系统快照，明确检查默认网络、蜂窝 Internet 能力、单一订阅和 VPN，拒绝不完整/歧义数据。
- 网络拆除必须由成功读取的系统快照证明，不能将命令执行失败误判为旧网络已经消失；保留数据恢复、限频、临时唤醒锁和用户偏好保护。
- 保持原有可选蜂窝重建开关和默认行为。不依赖 Box，不改全局 IPv6，不增加健康连接的定时心跳或后台唤醒。

真机复现旧版大转储参数过长，并验证新版能正确识别同一默认蜂窝订阅。回归覆盖超过128 KiB的系统转储、VPN、IMS、网络变化、拆除失败及回滚。实际夜间自动恢复和消息时延需进一步实测；不宣称已经消除所有网络导致的推送延迟。

## English

Fixes Android external printf argument-length failures during cellular DNS recovery. Large system snapshots are now consumed via standard input; the gate verifies exact network identity and subscription and fails closed on malformed snapshots or unproven teardown. No change to opt-in defaults or healthy MCS heartbeat behavior.
