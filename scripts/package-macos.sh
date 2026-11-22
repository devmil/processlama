#!/usr/bin/env bash
# Builds ProcessLama.app and a DMG on macOS: the Rust/QML executable, the Qt
# frameworks, plugins and QML modules (macdeployqt), the bundled remote
# helpers and the icon. Signs with MAC_SIGN_IDENTITY (hardened runtime) or
# ad hoc when it is unset.
#
#   QMAKE                Qt's qmake (default: qmake6 on PATH)
#   MACDEPLOYQT          macdeployqt (default: next to qmake, then PATH)
#   MAC_SIGN_IDENTITY    Developer ID Application identity; unset signs ad hoc
#   PROCESSLAMA_REMOTE_HELPER_DIR  helpers to bundle (default build/remote-helper)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"
cd "$ROOT"
mim_read_version

[[ "$(uname -s)" == Darwin ]] || { echo "package-macos.sh: macOS required" >&2; exit 1; }
QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake)}"
export QMAKE
qt_bins="$("$QMAKE" -query QT_INSTALL_BINS)"
MACDEPLOYQT="${MACDEPLOYQT:-$(command -v "$qt_bins/macdeployqt" || command -v macdeployqt || true)}"
[[ -n "$MACDEPLOYQT" ]] || { echo "package-macos.sh: macdeployqt not found" >&2; exit 1; }
channel="${MIM_RELEASE_CHANNEL:-stable}"
[[ -z "${MIM_RELEASE_CHANNEL:-}" && "$MIM_MARKETING_VERSION" =~ -(beta|rc)\. ]] && channel=beta
minimum_system="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
export MACOSX_DEPLOYMENT_TARGET="$minimum_system"

PROCESSLAMA_RELEASE_CHANNEL="$channel" cargo build --release --locked --manifest-path rust-core/Cargo.toml -p processlama

out="$ROOT/build/macos"
app="$out/ProcessLama.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp rust-core/target/release/processlama "$app/Contents/MacOS/ProcessLama"
sed -e "s/@VERSION@/$MIM_MARKETING_VERSION/" -e "s/@BUILD@/$MIM_BUILD_NUMBER/" \
  -e "s/@MINIMUM_SYSTEM@/$minimum_system/" packaging/macos/Info.plist.in >"$app/Contents/Info.plist"
printf 'APPL????' >"$app/Contents/PkgInfo"

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
icons=packaging/macos/AppIcon.appiconset
cp "$icons/app_icon_16.png" "$iconset/icon_16x16.png"
cp "$icons/app_icon_32.png" "$iconset/icon_16x16@2x.png"
cp "$icons/app_icon_32.png" "$iconset/icon_32x32.png"
cp "$icons/app_icon_64.png" "$iconset/icon_32x32@2x.png"
cp "$icons/app_icon_128.png" "$iconset/icon_128x128.png"
cp "$icons/app_icon_256.png" "$iconset/icon_128x128@2x.png"
cp "$icons/app_icon_256.png" "$iconset/icon_256x256.png"
cp "$icons/app_icon_512.png" "$iconset/icon_256x256@2x.png"
cp "$icons/app_icon_512.png" "$iconset/icon_512x512.png"
cp "$icons/app_icon_1024.png" "$iconset/icon_512x512@2x.png"
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset"

python3 scripts/package_licenses.py "$app/Contents/Resources"
python3 scripts/package_remote_helper.py bundle \
  --source "${PROCESSLAMA_REMOTE_HELPER_DIR:-$ROOT/build/remote-helper}" \
  --dest "$app/Contents/Resources/remote-helper"

"$MACDEPLOYQT" "$app" -qmldir="$ROOT/qml" -always-overwrite

if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --timestamp --options runtime \
    --entitlements packaging/macos/ProcessLama.entitlements --sign "$MAC_SIGN_IDENTITY" "$app"
else
  codesign --force --deep --sign - --entitlements packaging/macos/ProcessLama.entitlements "$app"
fi
codesign --verify --deep --strict "$app"

dmg="$ROOT/build/archive/$(mim_dmg_filename)"
mkdir -p "$ROOT/build/archive"
staging="$(mktemp -d)"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname ProcessLama -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg" >/dev/null
rm -rf "$staging"
echo "==> $dmg" >&2
