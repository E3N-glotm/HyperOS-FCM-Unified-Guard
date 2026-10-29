#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/bin/static_common.sh"
echo '=== FCM Unified Guard：状态检查与自动适配重试 ==='
backend_read_state
case "$phase" in
  ACTIVE|MOUNTED|READY) build_mode=auto;;
  *) build_mode=retry;;
esac
/system/bin/sh "$MODDIR/bin/build_backend.sh" "$build_mode" </dev/null
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null
echo '=== 基础守护 ==='
cat /data/adb/fcm_unified_guard/startup-status.txt 2>/dev/null
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status </dev/null
echo '=== 最近适配日志 ==='
tail -n 25 "$MODDIR/backend/build.log" 2>/dev/null
echo '仅“待重启生效”需要下一次正常重启；“启动确认中”请稍候，无需再次重启。'
