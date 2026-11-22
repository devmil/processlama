#!/usr/bin/env bash
# Build, sign, and package the macOS release DMG: a universal (arm64 and
# x86_64) Rust/QML app with Sparkle, signed with CODESIGN_IDENTITY.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"

# shellcheck source=lib/load-signing-env.sh
source "$ROOT/scripts/lib/load-signing-env.sh"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"

MIM_SKIP_SIGN=0

usage() {
  cat <<'EOF2'
Usage: ./scripts/package-release.sh [--skip-sign]

Builds the universal macOS release with scripts/package-macos.sh, signs it
with CODESIGN_IDENTITY (hardened runtime) and writes build/archive/ProcessLama.dmg.
EOF2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-sign) MIM_SKIP_SIGN=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "package-release.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
  esac
  shift
done

cd "$ROOT"
mim_read_version
mim_validate_semver "$MIM_MARKETING_VERSION"
mim_validate_build_number "$MIM_BUILD_NUMBER"

if [[ "$MIM_SKIP_SIGN" -eq 0 ]]; then
  [[ -n "${CODESIGN_IDENTITY:-}" ]] || {
    echo "package-release.sh: CODESIGN_IDENTITY required in .env.signing or environment. Use --skip-sign for local unsigned packaging." >&2
    exit 1
  }
  export MAC_SIGN_IDENTITY="$CODESIGN_IDENTITY"
else
  unset MAC_SIGN_IDENTITY
  echo "==> Signing ad hoc (--skip-sign)" >&2
fi
MAC_UNIVERSAL=1 ./scripts/package-macos.sh

APP="$ROOT/build/macos/ProcessLama.app"
lipo "$APP/Contents/MacOS/ProcessLama" -verify_arch arm64 x86_64
[[ "$MIM_SKIP_SIGN" -eq 1 ]] || spctl -a -t exec -vv "$APP" || true
cp "$ROOT/build/archive/$(mim_dmg_filename)" "$ROOT/build/archive/ProcessLama.dmg"
echo "==> Packaged $ROOT/build/archive/ProcessLama.dmg" >&2
