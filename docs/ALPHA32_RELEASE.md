# v0.4.0-alpha.32

修复 alpha31 的 DNS 恢复次数被预检查提前耗尽的问题。实机出现持续 UNKNOWN_HOST 的断连，三个候选准备流程退出后未进入实际临时映射事务，后续数小时不再有恢复资格；其具体失败阶段此前没有日志。

- 预检查最多每 15 分钟执行一次，与实际重连事务单独计数；三次真实事务失败后冷却一小时再允许重新核验。只有真实故障时运行。
- 独立使用当前网络配置的 DNS 服务器，已验证 Box 直连路径不可用时允许普通 DNS 路径提供候选；所有候选仍必须经过 GMS UID 的 TLS 证书及域名验证。不固定 IP、不依赖 Box。
- 增加有自动过期和显式释放的短时唤醒锁，明确记录每个失败阶段；严格复核当前蜂窝网络、VPN、Private DNS、断连及映射清理状态。
- 保留 alpha30 TCP keepalive；健康连接不发强制心跳、不重启 GMS。没有修改正常优先级消息的 Android Doze 机制；Gmail 等应用仍可能因系统投递策略延迟。
- 已通过 Android 实机模拟状态机、TLS 候选回退、Wi-Fi/VPN 门禁和唤醒锁检查。真实长断连及端到端推送仍待验证。

## English

Separates rate-limited DNS candidate preparation from actual recovery transactions, logs precise failure stages, adds a bounded wake lock, and permits a TLS-verified ordinary DNS candidate when a verified Box direct path fails. No hardcoded IP, new daemon, global DNS changes, or Doze override. Three dispatched transactions per burst; one-hour cooldown after exhaustion. Preserves VPN/Private DNS and healthy connection safeguards. Overnight push and cross-device validation remain pending.
