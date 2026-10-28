#!/system/bin/sh
# Read-only aggregate resource sample. No tokens, message text or account IDs.
case "${1:-}" in
  old) RUN=/data/adb/millet_guard; names='inotifyd safety fcm fcm_event swipe_unstop';;
  new) RUN=/data/adb/fcm_unified_guard; names='settings maintenance events';;
  *) echo 'Usage: device_observe.sh old|new'; exit 2;;
esac
roots=
for name in $names; do
  read -r p rest < "$RUN/$name.pid" 2>/dev/null || continue
  case "$p" in ''|*[!0-9]*) continue;; esac
  roots="$roots $p"
done
pids=$(ps -A -o PID,PPID | awk -v roots="$roots" '
  NR>1 {parent[$1]=$2}
  END {
    n=split(roots,r," "); for(i=1;i<=n;i++) if(r[i]!="") selected[r[i]]=1;
    for(k=0;k<20;k++) {
      changed=0;
      for(p in parent)
        if ((p+0)>2 && (parent[p]+0)>2 && selected[parent[p]] && !selected[p]) {
          selected[p]=1; changed=1;
        }
      if (!changed) break;
    }
    for(p in selected) if ((p+0)>2 && p in parent) print p;
  }')
count=0
ticks=0
rss_pages=0
for p in $pids; do
  IFS= read -r st < /proc/$p/stat 2>/dev/null || continue
  tail=${st##*) }
  set -- $tail
  [ "$#" -ge 22 ] || continue
  shift 11
  ticks=$((ticks+$1+$2+$3+$4))
  shift 10
  rss_pages=$((rss_pages+$1))
  count=$((count+1))
done
read -r uptime_value rest < /proc/uptime
echo "uptime=$uptime_value processes=$count cpu_ticks=$ticks rss_pages=$rss_pages"
echo "clock_ticks=$(getconf CLK_TCK) page_size=$(getconf PAGE_SIZE)"
dumpsys battery | grep -E 'AC powered:|USB powered:|Wireless powered:|level:|temperature:|Charge counter:'
