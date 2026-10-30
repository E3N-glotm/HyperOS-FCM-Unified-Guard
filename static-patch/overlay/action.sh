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
echo '=== PowerKeeper 动态接口探测（仅扫描，不修改系统） ==='
/system/bin/sh "$MODDIR/bin/powerkeeper_probe.sh" </dev/null || true
# Scan first, so this very same Action shows fresh per-ROM capabilities.
# Never conflate a detected method with an activated runtime hook.
/system/bin/sh "$MODDIR/bin/health_status.sh" --fresh </dev/null
echo '=== 基础守护 ==='
cat /data/adb/fcm_unified_guard/startup-status.txt 2>/dev/null
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status </dev/null
echo '=== 静态框架阶段（如为 ERROR，请同时提供以下日志） ==='
cat "$MODDIR/backend/state" 2>/dev/null || echo 'backend/state unavailable'
echo '=== 当前框架代际及能力报告 ==='
backend_read_state
if cache_load && [ -s "$CACHE_DIR/capabilities.tsv" ]; then
  echo "当前框架缓存: $generation"
  echo "当前阶段: $phase"
  echo '以下是当前缓存的能力报告；是否已挂载以健康检查中的 BACKEND 和逐项状态为准：'
  cat "$CACHE_DIR/capabilities.tsv"
elif [ -s "$MODDIR/backend/last-capabilities.tsv" ]; then
  echo '当前框架缓存能力报告不可用，仅显示上次生成记录（不代表当前已加载）：'
  cat "$MODDIR/backend/last-capabilities.tsv"
else
  echo '未找到可用的功能报告。仅在框架状态 ERROR/QUARANTINED 时才应判断适配异常。'
  echo '请核对 backend/state、backend/current 和构建日志。'
fi
echo '=== 最近一次构建日志（历史记录，并非当前故障） ==='
if [ -s "$MODDIR/backend/build.log" ]; then
  tail -n 40 "$MODDIR/backend/build.log"
else
  echo '没有历史构建日志；如果当前框架已加载则无需重新适配。'
fi
echo '仅“待重启生效”需要下一次正常重启；“启动确认中”请稍候，无需再次重启。'
