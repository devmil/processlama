#!/usr/bin/env bash
# Build Linux packages of the Rust/QML application: AppImage, RPM, DEB, Arch
# and a portable tar. Every format carries the same bundle: the executable, an
# application-private Qt runtime (scripts/stage_linux_bundle.py), the network
# telemetry service and the remote helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"

MIM_ARCHIVE_DIR="$ROOT/build/archive"
MIM_FORMATS="appimage,rpm,deb,tar"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: ./scripts/package-linux.sh [--formats appimage,rpm,deb,tar,arch] [--skip-build]

Builds the Rust/QML application and the selected bundles in build/archive.
The default builds AppImage, RPM, DEB and tar; add `arch` for an Arch Linux
package (built with makepkg on an Arch host, otherwise in an Arch container).

Required tools:
  All:      cargo, Qt 6 (qmake6 or QMAKE, rcc), patchelf (or PATCHELF), python3
  All:      clang, pkg-config, libelf development headers (network service)
  AppImage: appimagetool
  RPM:      rpmbuild
  DEB:      dpkg-deb
  Arch:     makepkg, or podman/docker

Remote helpers come from PROCESSLAMA_REMOTE_HELPER_DIR (default
build/remote-helper); PROCESSLAMA_REQUIRE_REMOTE_HELPER=1 requires all targets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --formats) shift; MIM_FORMATS="${1:?--formats requires a comma-separated list}" ;;
    --skip-build) SKIP_BUILD=1 ;;
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
PATCHELF="${PATCHELF:-$(command -v patchelf || true)}"
[[ -n "$PATCHELF" ]] || { echo "package-linux.sh: patchelf is required (or set PATCHELF)" >&2; exit 1; }
export PATCHELF
for format in "${formats[@]}"; do
  case "$format" in
    appimage) command -v appimagetool >/dev/null || { echo "package-linux.sh: appimagetool is required for AppImage" >&2; exit 1; } ;;
    rpm) command -v rpmbuild >/dev/null || { echo "package-linux.sh: rpmbuild is required for RPM" >&2; exit 1; } ;;
    deb) command -v dpkg-deb >/dev/null || { echo "package-linux.sh: dpkg-deb is required for DEB" >&2; exit 1; } ;;
    tar) ;;
    arch) command -v makepkg >/dev/null || command -v podman >/dev/null || command -v docker >/dev/null || {
      echo "package-linux.sh: makepkg, podman or docker is required for Arch" >&2; exit 1; } ;;
    *) echo "package-linux.sh: unknown format '$format'" >&2; exit 64 ;;
  esac
done

network_helper="$ROOT/linux/network-helper/target/release/processlama-network-helper"
binary="$ROOT/rust-core/target/release/processlama"
if [[ "$SKIP_BUILD" == 0 ]]; then
  command -v clang >/dev/null || { echo "package-linux.sh: clang is required for the eBPF network helper" >&2; exit 1; }
  pkg-config --exists libelf || {
    echo "package-linux.sh: libelf development headers are required (Fedora: elfutils-libelf-devel)" >&2
    exit 1
  }
  PROCESSLAMA_RELEASE_CHANNEL="$MIM_BUILD_RELEASE_CHANNEL" \
    cargo build --release --locked --manifest-path rust-core/Cargo.toml -p processlama
  cargo build --release --locked --manifest-path linux/network-helper/Cargo.toml
fi
[[ -x "$binary" && -x "$network_helper" ]] || { echo "package-linux.sh: build outputs missing" >&2; exit 1; }

mkdir -p "$MIM_ARCHIVE_DIR"
work="$(mktemp -d "$ROOT/build/processlama-linux-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
bundle="$work/bundle"
python3 "$ROOT/scripts/stage_linux_bundle.py" --binary "$binary" --output "$bundle"

desktop="$ROOT/linux/packaging/de.devmil.processlama.desktop"
metainfo_template="$ROOT/linux/packaging/de.devmil.processlama.metainfo.xml"
metainfo="$work/de.devmil.processlama.metainfo.xml"
icon="$ROOT/linux/packaging/de.devmil.processlama.png"
network_service="$ROOT/linux/packaging/processlama-network.service"
network_installer="$ROOT/linux/packaging/install-network-service.sh"
mkdir -p "$bundle/network"
cp "$network_helper" "$bundle/network/processlama-network-helper"
cp "$network_service" "$bundle/network/processlama-network.service"
cp "$network_installer" "$bundle/network/install-network-service.sh"
chmod 0755 "$bundle/network/install-network-service.sh"
python3 "$ROOT/scripts/package_licenses.py" "$bundle"
python3 "$ROOT/scripts/package_licenses.py" "$bundle/network"
# Remote helpers for every host target. Release CI sets
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

# Host runtimes the private Qt needs; everything Qt-specific is bundled.
deb_depends="libc6, libstdc++6, libgl1, libegl1, libfontconfig1, libfreetype6, libglib2.0-0, libdbus-1-3, libwayland-client0, libwayland-cursor0, libwayland-egl1, libxkbcommon0, libxkbcommon-x11-0, libx11-6, libx11-xcb1, libxcb1, libxcb-cursor0, libxcb-icccm4, libxcb-image0, libxcb-keysyms1, libxcb-randr0, libxcb-render-util0, libxcb-shape0, libxcb-xfixes0, libxcb-xkb1, libpng16-16, zlib1g, libzstd1, libpcre2-16-0, libharfbuzz0b, libelf1, systemd"
arch_depends="'glibc' 'gcc-libs' 'libglvnd' 'fontconfig' 'freetype2' 'glib2' 'dbus' 'wayland' 'libxkbcommon' 'libxkbcommon-x11' 'libx11' 'libxcb' 'xcb-util-cursor' 'xcb-util-wm' 'xcb-util-image' 'xcb-util-keysyms' 'xcb-util-renderutil' 'libpng' 'zlib' 'zstd' 'pcre2' 'harfbuzz' 'libelf' 'openssh' 'systemd'"

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
  # A wrapper, not a symlink: Qt looks for qt.conf (and with it the private
  # plugins and QML modules) next to the path the executable was started by.
  printf '#!/bin/sh\nexec /opt/processlama/processlama "$@"\n' >"$stage/usr/bin/processlama"
  chmod 0755 "$stage/usr/bin/processlama"
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
Depends: $deb_depends
Recommends: openssh-client
Section: utils
Priority: optional
Homepage: https://devmil.de/processlama/
Description: Rust and Qt process explorer
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
# The private Qt runtime lives under /opt/processlama; global build-ID links
# would collide with other applications bundling the same Qt build.
%global _build_id_links none
%global __provides_exclude_from ^/opt/processlama/.*$
%global __requires_exclude ^lib(Qt6|icu|double-conversion|md4c|b2).*$
Name: processlama
Version: $rpm_version
Release: $rpm_release
Summary: Rust and Qt process explorer
License: MIT AND GPL-2.0-only AND BSD-2-Clause AND LGPL-3.0-only
URL: https://devmil.de/processlama/
Source0: processlama-root.tar.gz
Requires: systemd
Recommends: openssh-clients

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
      if rpm -qlp "$rpm_file" | grep -q '^/usr/lib/\.build-id'; then
        echo "package-linux.sh: the RPM owns /usr/lib/.build-id paths" >&2
        exit 1
      fi
      cp "$rpm_file" "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_filename rpm "$machine_arch")"
      ;;
    arch)
      [[ "$machine_arch" == x86_64 ]] || { echo "package-linux.sh: Arch packages are x86_64 only" >&2; exit 1; }
      arch_input="$work/arch"
      mkdir -p "$arch_input/root"
      stage_tree "$arch_input/root"
      arch_version="${MIM_MARKETING_VERSION//-/_}"
      cat >"$arch_input/PKGBUILD" <<EOF
pkgname=processlama
pkgver=$arch_version
pkgrel=$MIM_BUILD_NUMBER
pkgdesc="Process explorer with live metrics, process inspection and remote hosts"
arch=('x86_64')
url="https://devmil.de/processlama/"
license=('MIT' 'GPL-2.0-only' 'BSD-2-Clause' 'LGPL-3.0-only')
depends=($arch_depends)
install=processlama.install
options=('!debug' '!lto' '!purge' '!strip')
source=('root.tar')
sha256sums=('SKIP')

package() {
  cp -a "\$srcdir/root/." "\$pkgdir/"
}
EOF
      cat >"$arch_input/processlama.install" <<'EOF'
post_install() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now processlama-network.service >/dev/null 2>&1 || true
}

post_upgrade() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl try-restart processlama-network.service >/dev/null 2>&1 || true
}

pre_remove() {
  systemctl disable --now processlama-network.service >/dev/null 2>&1 || true
}

post_remove() {
  systemctl daemon-reload >/dev/null 2>&1 || true
}
EOF
      source_date_epoch="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct)}"
      find "$arch_input" -exec touch --no-dereference --date="@$source_date_epoch" {} +
      tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
        -cf "$arch_input/root.tar" -C "$arch_input" root
      rm -rf -- "$arch_input/root"
      if command -v makepkg >/dev/null && [[ -f /etc/arch-release ]]; then
        (cd "$arch_input" && SOURCE_DATE_EPOCH="$source_date_epoch" PKGDEST="$arch_input" makepkg --nodeps --force --noconfirm)
      else
        engine="${PROCESSLAMA_CONTAINER_ENGINE:-$(command -v podman || command -v docker)}"
        chmod -R a+rX,u+w "$arch_input"
        chmod 0777 "$arch_input"
        "$engine" run --rm --security-opt label=disable \
          --mount "type=bind,src=$arch_input,dst=/build" \
          --env "SOURCE_DATE_EPOCH=$source_date_epoch" \
          "${PROCESSLAMA_ARCH_BUILD_IMAGE:-archlinux:base-devel}" bash -euo pipefail -c \
          'useradd --create-home builder; cp -a /build /home/builder/pkg; chown -R builder:builder /home/builder/pkg
           su builder -c "cd /home/builder/pkg && makepkg --nodeps --force --noconfirm"
           install -m 0644 /home/builder/pkg/processlama-*-x86_64.pkg.tar.zst /build/'
      fi
      package="$(find "$arch_input" -maxdepth 1 -name 'processlama-*-x86_64.pkg.tar.zst' -print -quit)"
      [[ -n "$package" ]] || { echo "package-linux.sh: makepkg produced no package" >&2; exit 1; }
      cp "$package" "$MIM_ARCHIVE_DIR/$(mim_linux_artifact_basename "$machine_arch").pkg.tar.zst"
      ;;
    appimage)
      appdir="$work/ProcessLama.AppDir"
      mkdir -p "$appdir/usr/bin" "$appdir/usr/lib/processlama" \
        "$appdir/usr/share/applications" "$appdir/usr/share/metainfo" \
        "$appdir/usr/share/icons/hicolor/512x512/apps"
      cp -a "$bundle/." "$appdir/usr/lib/processlama/"
      printf '#!/bin/sh\nexec "$(dirname "$(readlink -f "$0")")/../lib/processlama/processlama" "$@"\n' \
        >"$appdir/usr/bin/processlama"
      chmod 0755 "$appdir/usr/bin/processlama"
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
