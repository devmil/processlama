#!/bin/sh
# Installs the ProcessLama network service from this archive.
# Derived from linux/packaging/install-network-service.sh.
#
#   sudo ./install.sh            install, enable and start the service
#   ./install.sh --root DIR      stage the files under DIR only (no systemd), for checks
set -eu

root=""
if [ "${1:-}" = "--root" ]; then
  root="${2:?--root needs a directory}"
elif [ "$(id -u)" -ne 0 ]; then
  echo 'Installing the network service requires root (sudo).' >&2
  exit 1
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$source_dir/processlama-network-helper"
service="$source_dir/processlama-network.service"
if [ ! -f "$helper" ] || [ ! -f "$service" ]; then
  echo 'This archive does not contain the network service.' >&2
  exit 1
fi

install -D -m 0755 "$helper" "$root/usr/libexec/processlama/processlama-network-helper"
install -D -m 0644 "$service" "$root/usr/lib/systemd/system/processlama-network.service"
if [ -d "$source_dir/LICENSES" ]; then
  mkdir -p "${root}/usr/share/licenses/processlama-network-service"
  cp -R "$source_dir/LICENSES" "${root}/usr/share/licenses/processlama-network-service/"
  cp "$source_dir/LICENSE" "${root}/usr/share/licenses/processlama-network-service/LICENSE"
fi
[ -z "$root" ] || exit 0

if ! command -v systemctl >/dev/null 2>&1; then
  echo 'The network service requires systemd.' >&2
  exit 1
fi
systemctl daemon-reload
systemctl enable processlama-network.service
systemctl restart processlama-network.service
systemctl is-active --quiet processlama-network.service
echo 'The ProcessLama network service is running.'
