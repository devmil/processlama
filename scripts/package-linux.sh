#!/usr/bin/env bash
# Build Linux AppImage, RPM, DEB, and portable tar bundles.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"

MIM_ARCHIVE_DIR="$ROOT/build/archive"
MIM_FORMATS="appimage,rpm,deb,tar"

usage() {
  cat <<'EOF'
Usage: ./scripts/package-linux.sh [--formats appimage,rpm,deb,tar]

Builds the Flutter/Rust Linux application and the selected x86_64/aarch64
bundles in build/archive. The default builds all four distribution formats.

Required tools by format:
  All:      patchelf
  All:      clang, pkg-config, libelf development headers (network service)
  AppImage: appimagetool
  RPM:      rpmbuild
  DEB:      dpkg-deb
  tar:      tar
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --formats) shift; MIM_FORMATS="${1:?--formats requires a comma-separated list}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "package-linux.sh: unknown option $1" >&2; usage >&2; exit 64 ;;
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

machine_arch="$(uname -m)"
case "$machine_arch" in
  x86_64) deb_arch="amd64"; rpm_arch="x86_64" ;;
  aarch64|arm64) machine_arch="aarch64"; deb_arch="arm64"; rpm_arch="aarch64" ;;
  *) echo "package-linux.sh: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

IFS=',' read -r -a formats <<<"$MIM_FORMATS"
command -v patchelf >/dev/null || { echo "package-linux.sh: patchelf is required" >&2; exit 1; }
for format in "${formats[@]}"; do
  case "$format" in
    appimage) command -v appimagetool >/dev/null || { echo "package-linux.sh: appimagetool is required for AppImage" >&2; exit 1; } ;;
    rpm) command -v rpmbuild >/dev/null || { echo "package-linux.sh: rpmbuild is required for RPM" >&2; exit 1; } ;;
    deb) command -v dpkg-deb >/dev/null || { echo "package-linux.sh: dpkg-deb is required for DEB" >&2; exit 1; } ;;
    tar) command -v tar >/dev/null || { echo "package-linux.sh: tar is required" >&2; exit 1; } ;;
    *) echo "package-linux.sh: unknown format '$format'" >&2; exit 64 ;;
  esac
done
command -v clang >/dev/null || { echo "package-linux.sh: clang is required for the eBPF network helper" >&2; exit 1; }
command -v pkg-config >/dev/null || { echo "package-linux.sh: pkg-config is required for the eBPF network helper" >&2; exit 1; }
pkg-config --exists libelf || {
  echo "package-linux.sh: libelf development headers are required (Fedora: elfutils-libelf-devel)" >&2
  exit 1
}

./scripts/build-rust.sh release
cargo build --release --manifest-path linux/network-helper/Cargo.toml
flutter pub get
flutter build linux --release \
  --build-name "$MIM_MARKETING_VERSION" \
  --build-number "$MIM_BUILD_NUMBER" \
  --dart-define "PROCESSLAMA_RELEASE_CHANNEL=$MIM_BUILD_RELEASE_CHANNEL"

bundle="$(find "$ROOT/build/linux" -type d -path '*/release/bundle' -print -quit)"
[[ -x "$bundle/processlama" ]] || {
  echo "package-linux.sh: expected Flutter bundle at $bundle" >&2
  exit 1
}

# Flutter plugins retain absolute RUNPATH entries for the imported engine in
# flutter/ephemeral. Replace only those build-tree paths; preserve the
# executable's valid $ORIGIN/lib RUNPATH.
while IFS= read -r -d '' elf; do
  current_rpath="$(patchelf --print-rpath "$elf" 2>/dev/null || true)"
  if [[ "$current_rpath" == *"$ROOT"* ]]; then
    patchelf --set-rpath '$ORIGIN' "$elf"
  fi
done < <(find "$bundle" -type f -print0)

mkdir -p "$MIM_ARCHIVE_DIR"
work="$(mktemp -d "$ROOT/build/processlama-linux-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
desktop="$ROOT/linux/packaging/de.devmil.processlama.desktop"
metainfo_template="$ROOT/linux/packaging/de.devmil.processlama.metainfo.xml"
metainfo="$work/de.devmil.processlama.metainfo.xml"
icon="$ROOT/linux/packaging/de.devmil.processlama.png"
network_helper="$ROOT/linux/network-helper/target/release/processlama-network-helper"
network_service="$ROOT/linux/packaging/processlama-network.service"
network_installer="$ROOT/linux/packaging/install-network-service.sh"
mkdir -p "$bundle/network"
cp "$network_helper" "$bundle/network/processlama-network-helper"
cp "$network_service" "$bundle/network/processlama-network.service"
cp "$network_installer" "$bundle/network/install-network-service.sh"
chmod 0755 "$bundle/network/install-network-service.sh"
python3 "$ROOT/scripts/package_licenses.py" "$bundle"
python3 "$ROOT/scripts/package_licenses.py" "$bundle/network"
# Remote helpers for every host target (docs/10_remote_hosts.md §8.2). Release CI sets
# PROCESSLAMA_REQUIRE_REMOTE_HELPER=1 so a missing target fails the package.
rm -rf "$bundle/lib/remote-helper"
python3 "$ROOT/scripts/package_remote_helper.py" bundle \
  --source "${PROCESSLAMA_REMOTE_HELPER_DIR:-$ROOT/build/remote-helper}" \
  --dest "$bundle/lib/remote-helper"
release_date="$(git log -1 --format=%cs HEAD)"
release_type="stable"
[[ "$MIM_BUILD_RELEASE_CHANNEL" == "beta" ]] && release_type="development"
awk -v version="$MIM_MARKETING_VERSION" -v date="$release_date" -v type="$release_type" '
  /<content_rating/ {
    print "  <releases>"
    print "    <release version=\"" version "\" date=\"" date "\" type=\"" type "\" />"
    print "  </releases>"
  }
  { print }
' "$metainfo_template" >"$metainfo"

stage_tree() {
  local stage="$1"
  mkdir -p "$stage/opt/processlama" "$stage/usr/bin" \
    "$stage/usr/libexec/processlama" "$stage/usr/lib/systemd/system" \
    "$stage/usr/share/applications" "$stage/usr/share/metainfo" \
    "$stage/usr/share/icons/hicolor/512x512/apps"
  cp -a "$bundle/." "$stage/opt/processlama/"
  cp "$network_helper" "$stage/usr/libexec/processlama/processlama-network-helper"
  cp "$network_service" "$stage/usr/lib/systemd/system/processlama-network.service"
  python3 "$ROOT/scripts/package_licenses.py" "$stage/usr/share/licenses/processlama"
  ln -s ../../opt/processlama/processlama "$stage/usr/bin/processlama"
  cp "$desktop" "$stage/usr/share/applications/de.devmil.processlama.desktop"
  cp "$metainfo" "$stage/usr/share/metainfo/de.devmil.processlama.metainfo.xml"
  cp "$icon" "$stage/usr/share/icons/hicolor/512x512/apps/de.devmil.processlama.png"
}

for format in "${formats[@]}"; do
  case "$format" in
    tar)
      tar_root="$work/tar/ProcessLama"
      mkdir -p "$tar_root"
      cp -a "$bundle/." "$tar_root/"
      cp "$desktop" "$metainfo" "$icon" "$tar_root/"
      tar -C "$work/tar" -czf "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_filename tar "$machine_arch")" ProcessLama
      ;;
    deb)
      deb_root="$work/deb"
      stage_tree "$deb_root"
      mkdir -p "$deb_root/DEBIAN"
      installed_size="$(du -sk "$deb_root/opt" | awk '{print $1}')"
      cat >"$deb_root/DEBIAN/control" <<EOF
Package: processlama
Version: ${MIM_MARKETING_VERSION}-${MIM_BUILD_NUMBER}
Architecture: $deb_arch
Maintainer: devmil <software@devmil.de>
Installed-Size: $installed_size
Depends: libgtk-3-0, libblkid1, liblzma5, libelf1, zlib1g, systemd
Section: utils
Priority: optional
Homepage: https://devmil.de/processlama/
Description: Flutter and Rust process explorer
 A dense desktop process explorer with live metrics and process inspection.
EOF
      cat >"$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl enable --now processlama-network.service || true
  systemctl try-restart processlama-network.service || true
fi
EOF
      cat >"$deb_root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now processlama-network.service || true
fi
EOF
      cat >"$deb_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
EOF
      chmod 0755 "$deb_root/DEBIAN/postinst" "$deb_root/DEBIAN/prerm" "$deb_root/DEBIAN/postrm"
      dpkg-deb --root-owner-group --build "$deb_root" "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_filename deb "$machine_arch")"
      ;;
    rpm)
      rpm_root="$work/rpmbuild"
      mkdir -p "$rpm_root"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
      rpm_stage="$work/rpm-stage"
      stage_tree "$rpm_stage"
      tar -C "$rpm_stage" -czf "$rpm_root/SOURCES/processlama-root.tar.gz" .
      rpm_version="${MIM_MARKETING_VERSION%%-*}"
      rpm_release="$MIM_BUILD_NUMBER"
      [[ "$MIM_MARKETING_VERSION" != "$rpm_version" ]] && rpm_release="0.${MIM_MARKETING_VERSION#*-}.${MIM_BUILD_NUMBER}"
      cat >"$rpm_root/SPECS/processlama.spec" <<EOF
Name: processlama
Version: $rpm_version
Release: $rpm_release
Summary: Flutter and Rust process explorer
License: MIT AND GPL-2.0-only AND BSD-2-Clause
URL: https://devmil.de/processlama/
Source0: processlama-root.tar.gz
Requires: systemd

%description
A dense desktop process explorer with live metrics and process inspection.

%prep
%build
%install
mkdir -p %{buildroot}
tar -xzf %{SOURCE0} -C %{buildroot}

%post
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now processlama-network.service >/dev/null 2>&1 || true
  systemctl try-restart processlama-network.service >/dev/null 2>&1 || true
fi

%preun
if [ \$1 -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now processlama-network.service >/dev/null 2>&1 || true
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [ \$1 -ge 1 ]; then
    systemctl try-restart processlama-network.service >/dev/null 2>&1 || true
  fi
fi

%files
%license /usr/share/licenses/processlama/LICENSE
%license /usr/share/licenses/processlama/LICENSES/*
/opt/processlama
/usr/bin/processlama
/usr/libexec/processlama
/usr/lib/systemd/system/processlama-network.service
/usr/share/applications/de.devmil.processlama.desktop
/usr/share/metainfo/de.devmil.processlama.metainfo.xml
/usr/share/icons/hicolor/512x512/apps/de.devmil.processlama.png
EOF
      rpmbuild --define "_topdir $rpm_root" --target "$rpm_arch" -bb "$rpm_root/SPECS/processlama.spec"
      rpm_file="$(find "$rpm_root/RPMS" -type f -name '*.rpm' -print -quit)"
      cp "$rpm_file" "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_filename rpm "$machine_arch")"
      ;;
    appimage)
      appdir="$work/ProcessLama.AppDir"
      mkdir -p "$appdir/usr/bin" "$appdir/usr/lib/processlama" \
        "$appdir/usr/share/applications" "$appdir/usr/share/metainfo" \
        "$appdir/usr/share/icons/hicolor/512x512/apps"
      cp -a "$bundle/." "$appdir/usr/lib/processlama/"
      ln -s ../lib/processlama/processlama "$appdir/usr/bin/processlama"
      cp "$desktop" "$appdir/de.devmil.processlama.desktop"
      cp "$desktop" "$appdir/usr/share/applications/de.devmil.processlama.desktop"
      cp "$metainfo" "$appdir/usr/share/metainfo/de.devmil.processlama.appdata.xml"
      cp "$icon" "$appdir/de.devmil.processlama.png"
      cp "$icon" "$appdir/usr/share/icons/hicolor/512x512/apps/de.devmil.processlama.png"
      cat >"$appdir/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/processlama/processlama" "$@"
EOF
      chmod +x "$appdir/AppRun"
      ARCH="$machine_arch" appimagetool "$appdir" "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_filename appimage "$machine_arch")"
      ;;
  esac
  echo "==> Packaged $format bundle" >&2
done
