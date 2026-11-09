#!/bin/bash
# Runs inside packaging/network-service/Containerfile: builds the helper for this
# architecture and writes rpm, deb and tar packages to /out.
#   VERSION_LABEL  marketing version, e.g. 1.0.0-beta.27
#   BUILD_NUMBER   build number
set -euo pipefail

arch="$(uname -m)"
case "$arch" in
  x86_64) deb_arch=amd64; rpm_arch=x86_64 ;;
  aarch64) deb_arch=arm64; rpm_arch=aarch64 ;;
  *) echo "unsupported architecture $arch" >&2; exit 1 ;;
esac
version="${VERSION_LABEL:?}"
build="${BUILD_NUMBER:?}"
name="processlama-network-service"
base="$name-$version-$build-linux-$arch"

export CARGO_TARGET_DIR="/work/target"
export CARGO_HOME="/work/cargo-home"
rm -rf /work/network-helper
cp -r /src/linux/network-helper /work/network-helper
cargo build --release --locked --manifest-path /work/network-helper/Cargo.toml
helper="$CARGO_TARGET_DIR/release/processlama-network-helper"
service=/src/linux/packaging/processlama-network.service
installer=/src/packaging/network-service/install.sh

stage="/work/stage-$arch"
rm -rf "$stage"
install -D -m 0755 "$helper" "$stage/usr/libexec/processlama/processlama-network-helper"
install -D -m 0644 "$service" "$stage/usr/lib/systemd/system/processlama-network.service"

python3 /src/scripts/package_licenses.py "$stage/usr/share/licenses/processlama-network-service"

# tar: the files and the installer.
tar_root="/work/$base"
rm -rf "$tar_root"
mkdir -p "$tar_root"
install -m 0755 "$helper" "$tar_root/processlama-network-helper"
install -m 0644 "$service" "$tar_root/processlama-network.service"
install -m 0755 "$installer" "$tar_root/install.sh"
python3 /src/scripts/package_licenses.py "$tar_root"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 \
  -C /work -czf "/out/$base.tar.gz" "$base"

# deb
deb_root="/work/deb-$arch"
rm -rf "$deb_root"
cp -a "$stage" "$deb_root"
mkdir -p "$deb_root/DEBIAN"
cat >"$deb_root/DEBIAN/control" <<CONTROL
Package: $name
Version: $version-$build
Architecture: $deb_arch
Maintainer: Devmil Solutions <info@devmil.de>
Depends: libelf1, zlib1g, systemd
Conflicts: processlama
Section: admin
Priority: optional
Description: ProcessLama per-process network accounting service
 Lets ProcessLama show per-process network rates for this host, also when
 the host is watched as a remote host. Installs a narrowly scoped eBPF sampler.
CONTROL
cat >"$deb_root/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl enable --now processlama-network.service || true
  systemctl try-restart processlama-network.service || true
fi
SCRIPT
cat >"$deb_root/DEBIAN/prerm" <<'SCRIPT'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now processlama-network.service || true
fi
SCRIPT
cat >"$deb_root/DEBIAN/postrm" <<'SCRIPT'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
SCRIPT
chmod 0755 "$deb_root/DEBIAN/postinst" "$deb_root/DEBIAN/prerm" "$deb_root/DEBIAN/postrm"
dpkg-deb --root-owner-group --build "$deb_root" "/out/$base.deb"

# rpm
rpm_version="${version%%-*}"
rpm_release="$build"
[[ "$version" != "$rpm_version" ]] && rpm_release="0.${version#*-}.$build"
rpm_root="/work/rpmbuild-$arch"
rm -rf "$rpm_root"
mkdir -p "$rpm_root"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
tar -C "$stage" -czf "$rpm_root/SOURCES/root.tar.gz" .
cat >"$rpm_root/SPECS/$name.spec" <<SPEC
Name: $name
Version: $rpm_version
Release: $rpm_release
Summary: ProcessLama per-process network accounting service
License: MIT AND GPL-2.0-only AND BSD-2-Clause
URL: https://devmil.de/processlama/
Source0: root.tar.gz
Requires: systemd
Conflicts: processlama
%global debug_package %{nil}
%global _build_id_links none

%description
Lets ProcessLama show per-process network rates for this host, also when the
host is watched as a remote host. Installs a narrowly scoped eBPF sampler.

%prep
%build
%install
mkdir -p %{buildroot}
tar -xzf %{SOURCE0} -C %{buildroot}

%post
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable --now processlama-network.service >/dev/null 2>&1 || true
systemctl try-restart processlama-network.service >/dev/null 2>&1 || true

%preun
if [ \$1 -eq 0 ]; then
  systemctl disable --now processlama-network.service >/dev/null 2>&1 || true
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || true

%files
%license /usr/share/licenses/processlama-network-service/LICENSE
%license /usr/share/licenses/processlama-network-service/LICENSES/*
/usr/libexec/processlama/processlama-network-helper
/usr/lib/systemd/system/processlama-network.service
SPEC
rpmbuild --define "_topdir $rpm_root" --target "$rpm_arch" -bb "$rpm_root/SPECS/$name.spec" >/dev/null
cp "$(find "$rpm_root/RPMS" -type f -name '*.rpm' -print -quit)" "/out/$base.rpm"
ls -l /out
