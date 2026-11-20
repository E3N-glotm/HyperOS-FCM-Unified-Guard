## 蜂窝 DNS 恢复可靠性修复

- 修复部分双卡系统全局 `mobile_data` 与各卡数据开关不同步，导致恢复流程无法执行的问题。
- 仅在已确认原生 DNS 故障且用户开启 `FCM_CELLULAR_REBIND=1` 时，验证当前联网 SIM、默认数据订阅、各卡数据偏好及通话、热点、VPN、休眠条件后，尝试重建蜂窝网络。双卡数据偏好不一致时不执行，避免误开启用户关闭的卡。
- 校验原网络是否实际拆除、原数据偏好是否恢复；失败时执行恢复处理，记录结果和具体拦截条件。
- 网络重建期间使用有超时保护的临时唤醒锁，结束后立即释放；不增加健康连接期间的唤醒频率。
- 不依赖 Box，不修改全局 IPv6 策略，保留其他模块功能和默认关闭的实验性蜂窝恢复开关。

**验证：** 40 项蜂窝恢复及 DNS 相关回归通过，真机验证了双卡设置不同步现象、控制接口、唤醒锁释放及当前 FCM 正常连接。真实夜间故障的自动恢复效果仍需继续观察，不代表已验证所有长时间断连均可解决。

## English

Fixes opt-in cellular DNS recovery on devices with stale global mobile-data settings, with per-slot checks, subscription identity, verified teardown and restoration, bounded wake protection and explicit gate diagnostics. Does not change the default opt-in policy or global IPv6. Forty targeted regression cases passed; live overnight fault recovery is not yet verified.
