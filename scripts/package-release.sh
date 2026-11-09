#!/usr/bin/env bash
# Build, sign, and package a macOS release DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"

# shellcheck source=lib/load-signing-env.sh
source "$ROOT/scripts/lib/load-signing-env.sh"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"

MIM_SKIP_SIGN=0
MIM_ARCHIVE_DIR="$ROOT/build/archive"

usage() {
  cat <<'EOF'
Usage: ./scripts/package-release.sh [--skip-sign]

Builds Rust + Flutter macOS release, optionally signs the app with
CODESIGN_IDENTITY, and creates build/archive/ProcessLama.dmg.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-sign) MIM_SKIP_SIGN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "package-release.sh: unknown option $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

cd "$ROOT"
mim_read_version
mim_validate_semver "$MIM_MARKETING_VERSION"
mim_validate_build_number "$MIM_BUILD_NUMBER"
MIM_BUILD_RELEASE_CHANNEL="${MIM_RELEASE_CHANNEL:-stable}"
if [[ -z "${MIM_RELEASE_CHANNEL:-}" && "$MIM_MARKETING_VERSION" =~ -(beta|rc)\. ]]; then
  MIM_BUILD_RELEASE_CHANNEL="beta"
fi

./scripts/build-rust.sh release
flutter pub get
flutter build macos --release \
  --build-name "$MIM_MARKETING_VERSION" \
  --build-number "$MIM_BUILD_NUMBER" \
  --dart-define "PROCESSLAMA_RELEASE_CHANNEL=$MIM_BUILD_RELEASE_CHANNEL"

APP="$ROOT/build/macos/Build/Products/Release/processlama.app"
[[ -d "$APP" ]] || {
  echo "package-release.sh: expected app bundle at $APP" >&2
  exit 1
}

# Remote helpers for every host target (docs/10_remote_hosts.md §8.2). Release CI sets
# PROCESSLAMA_REQUIRE_REMOTE_HELPER=1 so a missing target fails the package.
helpers="$APP/Contents/Resources/remote-helper"
rm -rf "$helpers"
python3 "$ROOT/scripts/package_remote_helper.py" bundle \
  --source "${PROCESSLAMA_REMOTE_HELPER_DIR:-$ROOT/build/remote-helper}" \
  --dest "$helpers"

python3 "$ROOT/scripts/package_licenses.py" "$APP/Contents/Resources"

if [[ "$MIM_SKIP_SIGN" -eq 0 ]]; then
  [[ -n "${CODESIGN_IDENTITY:-}" ]] || {
    echo "package-release.sh: CODESIGN_IDENTITY required in .env.signing or environment. Use --skip-sign for local unsigned packaging." >&2
    exit 1
  }
  # The macOS helpers are Mach-O code inside Resources: sign them with the Developer ID
  # for notarization, then describe the signed bytes the app will install.
  for helper in "$helpers"/macos-*/processlama-remote-helper; do
    [[ -f "$helper" ]] || continue
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$helper"
  done
  python3 "$ROOT/scripts/package_remote_helper.py" refresh --dir "$helpers"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT/macos/Runner/Release.entitlements" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP"
  codesign --verify --strict --deep "$APP"
  spctl -a -t exec -vv "$APP" || true
else
  echo "==> Skipping app signing (--skip-sign)" >&2
fi

mkdir -p "$MIM_ARCHIVE_DIR"
DMG="$MIM_ARCHIVE_DIR/ProcessLama.dmg"
DMG_ROOT="$MIM_ARCHIVE_DIR/dmg-root"
rm -f "$DMG"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "ProcessLama" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG"
rm -rf "$DMG_ROOT"

echo "==> Packaged $DMG" >&2
