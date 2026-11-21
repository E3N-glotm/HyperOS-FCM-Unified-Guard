## 修复 FCM 假在线与长连接积压

11 月 21 日实机复现了 GMS 显示在线、多个软件实际收不到推送的情况。22:10 的原生心跳触发断开重连，随后立即收到 9 条积压消息，微信、Gmail 和 ChatGPT 均受影响。真实 TCP socket 未启用 keepalive，系统默认空闲探测时间为 7200 秒。

alpha30 在 GMS 在线状态下，核对 GcmService 的 mtalk 地址、实际 TCP 端口、应用 UID、进程名及 socket inode；仅针对明确匹配的连接启用 TCP keepalive（空闲最多 180 秒、重试最多 30 秒、次数最多 4 次）。不修改全局 sysctl，不发送主动 GMS 心跳，不增加后台线程、轮询或唤醒定时器，不重启 GMS 或代理。重连后由既有守护流程重新识别 socket；内核或权限不支持时退回原生机制，不因未核验显示黄灯。

已在实机成功设置并回读目标 socket 参数。该机制能帮助识别失效的 TCP 连接、维持空闲连接的网络状态，但不保证解决应用层缓冲、服务端投递或所有网络问题。长期锁屏真实推送与功耗仍需观察。

## English

Adds narrowly scoped kernel TCP keepalive to the verified Google MCS connection (up to 180s idle, 30s interval, four retries), without forced application heartbeats or global network changes. Unsupported devices retain native behavior. Device-level socket option verification has passed; long-term delivery and power validation remain pending.
