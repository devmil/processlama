#!/bin/sh
# Install the fixed Linux network sampler shipped with this build.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Network telemetry installation requires system authorization.' >&2
  exit 1
fi

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$source_dir/processlama-network-helper"
service="$source_dir/processlama-network.service"

if [ ! -f "$helper" ] || [ ! -f "$service" ]; then
  echo 'This ProcessLama bundle does not contain the network service.' >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo 'The network service requires systemd.' >&2
  exit 1
fi

install -D -m 0755 "$helper" /usr/libexec/processlama/processlama-network-helper
install -D -m 0644 "$service" /usr/lib/systemd/system/processlama-network.service
if [ -d "$source_dir/LICENSES" ]; then
  mkdir -p "/usr/share/licenses/processlama-network-service"
  cp -R "$source_dir/LICENSES" "/usr/share/licenses/processlama-network-service/"
  cp "$source_dir/LICENSE" "/usr/share/licenses/processlama-network-service/LICENSE"
fi
systemctl daemon-reload
systemctl enable processlama-network.service
systemctl restart processlama-network.service
systemctl is-active --quiet processlama-network.service
