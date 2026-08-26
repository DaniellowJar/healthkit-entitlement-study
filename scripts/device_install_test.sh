#!/usr/bin/env bash
# device_install_test.sh <udid> <file.ipa> [syslog-filter]
# Installs an ipa via pymobiledevice3 and captures the exact installd verdict,
# then optionally tails filtered syslog while you manually launch the app.
set -uo pipefail
UDID="$1"; IPA="$2"; FILTER="${3:-}"
PMD3="${PMD3:-$HOME/Projects/healthkit-study/.venv/bin/pymobiledevice3}"

echo "### install attempt: $IPA"
"$PMD3" apps install --udid "$UDID" "$IPA" 2>&1 | tee "/tmp/opencode/install-$(basename "$IPA").log"
rc=${PIPESTATUS[0]}
echo "### pymobiledevice3 exit=$rc"

if [[ -n "$FILTER" ]]; then
  echo "### streaming syslog (filter: $FILTER) — Ctrl-C to stop"
  "$PMD3" syslog live --udid "$UDID" 2>&1 | grep --line-buffered -iE "$FILTER"
fi
