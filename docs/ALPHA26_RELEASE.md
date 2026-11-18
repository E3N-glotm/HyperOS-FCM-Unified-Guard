## alpha26：启动早期兼容、唤醒权限和受限蜂窝重建

alpha25 实机重启后原生保护仍被隔离；Magisk Alpha + Zygisk Next 使用不同启动脚本调度路径。改以启动早期可读的系统/厂商 build.prop 摘要识别固件，记录每次启动隔离决策；已完成隔离启动、同固件、存在实际方法、未耗尽尝试预算时，允许明确正常重启或缺失早期重启原因的一次试运行。明确异常重启、手动禁用、固件不一致及重复失败继续隔离。Hook 是否成功仍看实机证据。

修复安装时 alarm helper 被全目录权限设置重置为 0644 的实际错误。实机手动恢复 0755 后，内核 alarmtimer 和有时限的 wakelock 均已确认工作。

新增可选的蜂窝网络重建（默认关闭），仅在 FCM 确认断连、同一默认蜂窝网络、两次 Android DNS cache 刷新均失败但配置的 IPv4 DNS 可用、最近证据、屏幕休眠、无通话/热点/VPN、流量原本打开且 Private DNS 关闭时，可显式启用一次数据连接重建。每次断连至多一次、全局至少6小时；会短时影响蜂窝流量，使用者须自行明确启用 `FCM_CELLULAR_REBIND=1`（持久配置 `/data/adb/fcm_unified_guard/unified.conf`）。不启用时原有网络行为不变。此机制仍需真实故障验证，不能宣称系统 DNS 已根治。

English: Early-boot firmware identity and per-boot gate trace improve standalone Zygisk compatibility. Fix executable permissions for the existing kernel alarm helper. An explicitly opt-in, default-off cellular network recreation fallback is gated by current confirmed native DNS failure, idle device, no calls/tether/VPN and an outage/global cooldown. It can briefly interrupt cellular data, and real overnight recovery is unverified. Existing native libraries and framework payloads remain byte-identical.
