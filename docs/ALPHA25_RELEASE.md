## alpha25：PowerKeeper 启动隔离恢复 / boot quarantine recovery

修复快速重启或 OTA 后旧版只依据残留 pending 标记将 PowerKeeper 原生保护永久隔离的问题。开机确认先于耗时业务检查；同一次开机重复执行不会被判成上次启动失败。真实未确认启动继续仅隔离可选的原生保护，FCM 基础服务及框架不受影响。

已完成启动且有适用 OEM 方法证据的隔离系统，在相同固件下的明确正常重启时可以获得一次受限恢复机会；失败后不自动循环尝试。手动或来源不明的禁用标记不清除。新固件必须重新建立自身的启动证据，不支持的接口保持降级。未获得证据的项目不作为黄灯故障。原生 Hook 是否真正生效仍由当前进程证据独立核验。

基于已发布 alpha24 校验过的完整 ZIP，保持原生库、DEX、FCM DNS 和核心框架载荷不变。无额外常驻进程、无需 LSPosed 或 Box。此版本不声称根治独立的 Android 蜂窝 DNS 故障。跨版本状态机通过模拟回归，真实设备 Hook 和长期推送仍需要实机核验。

English: Boot-id-aware PowerKeeper quarantine and prompt boot acknowledgement, with one evidence-gated retry after a completed quarantined boot and explicitly normal reboot on the same firmware. Manual disables and repeat failures remain gated; unsupported/unverified interfaces do not generate a false warning. Existing native, static framework and FCM transport payloads remain unchanged. This is not a verified cure for independent cellular DNS outages.
