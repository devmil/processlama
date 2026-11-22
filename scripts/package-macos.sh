#!/usr/bin/env bash
# Builds ProcessLama.app and a DMG on macOS: the Rust/QML executable, the Qt
# frameworks, plugins and QML modules (macdeployqt), the bundled remote
# helpers and the icon. Signs with MAC_SIGN_IDENTITY (hardened runtime) or
# ad hoc when it is unset.
#
#   QMAKE                Qt's qmake (default: qmake6 on PATH)
#   MACDEPLOYQT          macdeployqt (default: next to qmake, then PATH)
#   MAC_SIGN_IDENTITY    Developer ID Application identity; unset signs ad hoc
#   MAC_UNIVERSAL=1      build arm64 and x86_64 and merge them (release builds)
#   MAC_SPARKLE=0        leave Sparkle out (updates then use the release manifest)
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
minimum_system="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
export MACOSX_DEPLOYMENT_TARGET="$minimum_system"

binary=rust-core/target/release/processlama
if [[ "${MAC_UNIVERSAL:-0}" == 1 ]]; then
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
  for triple in aarch64-apple-darwin x86_64-apple-darwin; do
    PROCESSLAMA_RELEASE_CHANNEL="$channel" cargo build --release --locked \
      --manifest-path rust-core/Cargo.toml -p processlama --target "$triple"
  done
  binary=rust-core/target/universal/processlama
  mkdir -p "$(dirname "$binary")"
  lipo -create -output "$binary" \
    rust-core/target/aarch64-apple-darwin/release/processlama \
    rust-core/target/x86_64-apple-darwin/release/processlama
else
  PROCESSLAMA_RELEASE_CHANNEL="$channel" cargo build --release --locked --manifest-path rust-core/Cargo.toml -p processlama
fi

out="$ROOT/build/macos"
app="$out/ProcessLama.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/ProcessLama"
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

"$MACDEPLOYQT" "$app" -qmldir="$ROOT/qml/ProcessLama" -qmlimport="$ROOT/qml" -always-overwrite

# macdeployqt copies every SQL driver (some link libraries the build host
# lacks); ProcessLama uses no Qt SQL.
rm -rf "$app/Contents/PlugIns/sqldrivers"

# Development builds also look in Qt's own lib folder; the bundle must not.
qt_libs="$("$QMAKE" -query QT_INSTALL_LIBS)"
install_name_tool -delete_rpath "$qt_libs" "$app/Contents/MacOS/ProcessLama" 2>/dev/null || true
otool -l "$app/Contents/MacOS/ProcessLama" | grep -q '@executable_path/../Frameworks' || {
  echo "package-macos.sh: the executable lacks the Frameworks rpath" >&2
  exit 1
}


if [[ "${MAC_SPARKLE:-1}" != 0 ]]; then
  # shellcheck source=lib/sparkle-tools.sh
  source scripts/lib/sparkle-tools.sh
  sparkle="$(mim_sparkle_fetch)"
  ditto "$sparkle/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
fi

# Inside out: nested code first, the app last. Sparkle's helpers keep their
# own identifiers; everything gets the hardened runtime when signing for
# distribution.
if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  sign=(codesign --force --timestamp --options runtime --sign "$MAC_SIGN_IDENTITY")
else
  sign=(codesign --force --sign -)
fi
sparkle_app="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle_app" ]]; then
  for nested in Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc \
    Versions/B/Autoupdate Versions/B/Updater.app; do
    [[ -e "$sparkle_app/$nested" ]] || continue
    if [[ "$nested" == *Downloader.xpc ]]; then
      "${sign[@]}" --preserve-metadata=entitlements "$sparkle_app/$nested"
    else
      "${sign[@]}" "$sparkle_app/$nested"
    fi
  done
  "${sign[@]}" "$sparkle_app"
fi
while IFS= read -r -d '' code; do
  "${sign[@]}" "$code"
done < <(find "$app/Contents/Frameworks" "$app/Contents/PlugIns" "$app/Contents/Resources" \
  \( -name '*.dylib' -o -name '*.so' \) -type f -print0)
# The macOS helpers ship with the Developer ID too; their descriptors then
# describe the re-signed bytes. Linux helpers are ELF and stay as built.
if [[ -n "${MAC_SIGN_IDENTITY:-}" ]]; then
  for helper in "$app"/Contents/Resources/remote-helper/macos-*/processlama-remote-helper; do
    [[ -f "$helper" ]] && "${sign[@]}" "$helper"
  done
  python3 scripts/package_remote_helper.py refresh --dir "$app/Contents/Resources/remote-helper"
fi
while IFS= read -r -d '' framework; do
  [[ "$framework" == "$sparkle_app" ]] && continue
  "${sign[@]}" "$framework"
done < <(find "$app/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0)
"${sign[@]}" --entitlements packaging/macos/ProcessLama.entitlements "$app"
codesign --verify --deep --strict "$app"

dmg="$ROOT/build/archive/$(mim_dmg_filename)"
mkdir -p "$ROOT/build/archive"
staging="$(mktemp -d)"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
# hdiutil intermittently fails with "Resource busy" on CI runners while
# Spotlight or a previous image still holds the device; retry a few times.
for attempt in 1 2 3 4 5; do
  if hdiutil create -volname ProcessLama -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg" >/dev/null; then
    break
  fi
  rm -f "$dmg"
  if [[ "$attempt" == 5 ]]; then
    echo "package-macos.sh: hdiutil create failed $attempt times" >&2
    exit 1
  fi
  echo "package-macos.sh: hdiutil create failed (attempt $attempt), retrying" >&2
  sleep $((attempt * 5))
done
rm -rf "$staging"
echo "==> $dmg" >&2
