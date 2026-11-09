# shellcheck shell=bash
# Locate Sparkle's command-line tools from the Swift package artifact that
# `flutter build macos` resolves into build/macos/SourcePackages.

mim_sparkle_sign_update() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local tool="$root/build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
  if [[ ! -x "$tool" ]]; then
    echo "Sparkle sign_update is unavailable at $tool; run flutter build macos first" >&2
    return 1
  fi
  printf '%s\n' "$tool"
}
