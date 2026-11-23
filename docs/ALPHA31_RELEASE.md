# v0.4.0-alpha.31

修复长连接关闭后出现 Android 原生 DNS 持续解析失败，导致 FCM 数小时无法重连的问题。实机发现：运营商 DNS 独立查询成功，但 GMS 原生解析持续报 UNKNOWN_HOST；刷新缓存、蜂窝网络恢复及受控代理恢复未能及时解除故障。

- 仅在已确认的持续断连与原生解析失败后尝试，蜂窝网络、关闭 Private DNS 且无实际 VPN 网络才启用；不依赖 Box。
- 通过当前网络配置的 DNS 查询 mtalk.google.com，再以 GMS UID 验证 TLS 证书与域名；不存在固定 IP 列表。
- 临时在系统 DNS 服务的挂载命名空间映射该单一域名，保留原 hosts 内容，短时尝试一次原生重连，随后撤销；异常退出有清理机制。已有自定义映射不覆盖。
- 每次断连最多尝试三次，每次间隔至少 15 分钟；保留 alpha30 的 TCP keepalive，不强制心跳、不清除应用数据。可在 /data/adb/fcm_unified_guard/unified.conf 添加 FCM_DNS_HOSTS_FALLBACK=0 禁用新路径。
- 此版本针对已复现的 DNS 重连故障；正常在线不触发恢复，不承诺消除所有网络 IO_FIN 或所有应用的推送延迟。整夜验证仍需进行。

## English

Adds a bounded, evidence-gated native resolver recovery for prolonged MCS disconnections caused by persistent UNKNOWN_HOST despite working independent carrier DNS. It uses a freshly resolved, certificate-validated endpoint only on cellular networks with Private DNS off and no active VPN. A transient exact-name resolver hosts overlay is removed after one native reconnect attempt; existing mappings are preserved. At most three attempts per outage and at least 15 minutes apart. Alpha30 scoped TCP keepalive remains intact. Disable with FCM_DNS_HOSTS_FALLBACK=0 in /data/adb/fcm_unified_guard/unified.conf. Overnight and end-to-end push validation remain pending.
