#!/system/bin/sh
# Diagnostic only. No ROM-version strings, writes, app launches, or restarts.
probe() {
  title="$1"; shift
  printf '%s: ' "$title"
  if "$@" >/dev/null 2>&1; then echo available; else echo unavailable; fi
}
echo '=== FCM Unified Guard runtime interface audit (read-only) ==='
probe 'Android Settings.System' settings --user 0 list system
probe 'DeviceIdle allowlist' cmd deviceidle whitelist
probe 'Wi-Fi/Connectivity service' service check connectivity
if command -v dumpsys >/dev/null 2>&1; then
  if dumpsys greezer >/dev/null 2>&1; then
    echo 'OEM Greeze dumpsys: available'
    dumpsys greezer 2>/dev/null | grep -m1 'mGmsLimitEnabled' || true
  else
    echo 'OEM Greeze dumpsys: unavailable (may use narrower Android fallbacks)'
  fi
fi
printf 'MCS TCP sessions (5228/5229/5230 only; other ports such as 443 possible):\n'
ss -nt 2>/dev/null |grep -E ':(5228|5229|5230)[[:space:]]' | head -5 || true
echo 'Do not infer push delivery success from port presence alone.'
