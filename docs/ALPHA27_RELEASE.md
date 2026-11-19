## alpha.27：蜂窝 DNS 恢复资格和实际状态核验

- 修复晚期 DNS 恢复证据过期后无法再次获得恢复资格的问题。在同一次断连、同一默认网络下，受限复核真实故障，不重复刷新 DNS 缓存。
- 修复系统 Binder 命令返回成功但实际移动数据没有切换时的误判，必须确认关闭和重新打开的实际状态。
- 保留蜂窝网络重建默认关闭、通话/热点/VPN/Private DNS 等保护条件及冷却时间。不依赖 Box，正常连接时不增加主动网络重建。
- 本版守护脚本通过专项回归及实机正常连接测试；真实长时间锁屏断连的自动恢复仍待验证，不能宣称系统 DNS 已根治。
- 集成包基于 alpha.26，仅更新守护脚本、版本元数据及说明，其他载荷保持原样。

English: Fix expiry of cellular DNS recovery evidence and reject false-success mobile data commands. The fallback remains opt-in and gated by current failure evidence and connectivity safeguards. Real overnight recovery is not yet verified. All other integrated payloads are unchanged.
