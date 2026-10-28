#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/run"
export FCM_UNIFIED_RUNTIME="$T/run" TEST_FAILURES="$T/writes"
cat > "$T/bin/settings" <<'MOCK'
#!/bin/sh
case "$*" in
  *' get system MILLET_NO_RESTRICT_APP')
    case "$TEST_MODE" in
      error_success) echo 'cmd: Failure calling service settings: Failed transaction (2147483646)'; exit 0 ;;
      error_nonzero) echo 'cmd: Failure calling service settings: Failed transaction (2147483646)' >&2; exit 1 ;;
      valid) echo 'com.google.android.gms, com.tencent.mm'; exit 0 ;;
    esac ;;
  *' put system MILLET_NO_RESTRICT_APP'*|*' delete system MILLET_NO_RESTRICT_APP'*)
    echo "$*" >> "$TEST_FAILURES"; exit 0 ;;
esac
exit 2
MOCK
chmod +x "$T/bin/settings"
export PATH="$T/bin:$PATH"
printf 'com.google.android.gms\n' > "$T/run/packages.list"
printf 'com.google.android.gms\n' > "$T/run/managed.last"
for TEST_MODE in error_success error_nonzero; do
  export TEST_MODE
  sh "$ROOT/module/bin/reconcile.sh" test >/dev/null
  [ ! -e "$TEST_FAILURES" ] || {
    echo 'FAIL: failed Binder read was written to SettingsProvider' >&2
    exit 1
  }
  grep -Fxq 'com.google.android.gms' "$T/run/managed.last"
done
echo 'PASS: Binder errors (including exit 0 with error text) cannot poison whitelist'
