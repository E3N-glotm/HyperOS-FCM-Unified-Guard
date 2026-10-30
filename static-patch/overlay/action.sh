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
echo '=== PowerKeeper 动态接口探测（仅扫描，不修改系统） ==='
/system/bin/sh "$MODDIR/bin/powerkeeper_probe.sh" </dev/null || true
echo '=== 基础守护 ==='
cat /data/adb/fcm_unified_guard/startup-status.txt 2>/dev/null
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status </dev/null
echo '=== 静态框架阶段（如为 ERROR，请同时提供以下日志） ==='
cat "$MODDIR/backend/state" 2>/dev/null || echo 'backend/state unavailable'
echo '=== 静态功能适配结果 ==='
report="$MODDIR/backend/last-capabilities.tsv"
[ -r "$report" ] && cat "$report" || echo 'capabilities.tsv unavailable; generation may have failed'
echo '=== 最近适配日志 ==='
if [ -r "$MODDIR/backend/build.log" ]; then
  tail -n 40 "$MODDIR/backend/build.log"
else
  echo 'backend/build.log unavailable; adaptation may not have started'
fi
echo '仅“待重启生效”需要下一次正常重启；“启动确认中”请稍候，无需再次重启。'
