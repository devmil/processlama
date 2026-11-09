#!/usr/bin/env bash
# Cold-launches a debug build for a few seconds and checks that the native
# core delivered a process snapshot (the debug-only `first_native_snapshot`
# log line). Needs a desktop session.
#
#   scripts/smoke_launch.sh [bundle-executable] [seconds]
set -uo pipefail

executable="${1:-build/linux/x64/debug/bundle/processlama}"
seconds="${2:-20}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

timeout "$seconds" "$executable" >"$log" 2>&1
count="$(grep -a -o 'first_native_snapshot processes=[0-9]*' "$log" | head -1 | cut -d= -f2)"
if [[ -n "$count" && "$count" -gt 0 ]]; then
  echo "ok    cold launch delivered ${count} processes"
  exit 0
fi
echo "FAIL  no native snapshot within ${seconds}s" >&2
tail -20 "$log" >&2
exit 1
