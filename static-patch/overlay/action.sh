#!/system/bin/sh
MODDIR=${0%/*}
echo '=== FCM Unified Guard：状态检查与自动适配重试 ==='
/system/bin/sh "$MODDIR/bin/build_backend.sh" retry </dev/null
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null
echo '=== 基础守护 ==='
cat /data/adb/fcm_unified_guard/startup-status.txt 2>/dev/null
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status </dev/null
echo '=== 最近适配日志 ==='
tail -n 25 "$MODDIR/backend/build.log" 2>/dev/null
echo '模块不会自动卸载、禁用或重启；黄色待重启表示新补丁会在下次正常重启加载。'
