#!/usr/bin/env bash
# Checks the network service packages of one architecture in containers:
# the rpm installs into a Fedora database (rpm -i --nodeps --justdb) with the expected
# file list, the deb lists the same files, and the tar's installer stages them with
# --root (no systemd needed).
#   check_network_service_packages.sh [x86_64|aarch64]
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
arch="${1:-x86_64}"
engine="${PROCESSLAMA_CONTAINER_ENGINE:-podman}"
packages="$ROOT/build/network-service"
podman_arch=$([[ "$arch" == aarch64 ]] && echo arm64 || echo amd64)
expected=$'/usr/lib/systemd/system/processlama-network.service\n/usr/libexec/processlama/processlama-network-helper'
# Compare the exact installed file set, including all required component notices.
[[ -s "$ROOT/LICENSE" && -s "$ROOT/LICENSES/GPL-2.0-only.txt" ]]
expected="$(
  printf '%s\n' "$expected" /usr/share/licenses/processlama-network-service/LICENSE
  for notice in "$ROOT"/LICENSES/*; do
    printf '/usr/share/licenses/processlama-network-service/LICENSES/%s\n' "$(basename "$notice")"
  done
)"
expected="$(printf '%s\n' "$expected" | sort)"


rpm="$(ls "$packages"/processlama-network-service-*-linux-"$arch".rpm)"
deb="$(ls "$packages"/processlama-network-service-*-linux-"$arch".deb)"
tarball="$(ls "$packages"/processlama-network-service-*-linux-"$arch".tar.gz)"

rpm_files="$($engine run --rm --arch "$podman_arch" --network=none -v "$packages:/p:ro,z" \
  registry.fedoraproject.org/fedora:44 sh -c \
  "rpm -i --nodeps --justdb /p/$(basename "$rpm") && rpm -ql processlama-network-service" | sort)"
[[ "$rpm_files" == "$expected" ]] || { echo "rpm file list differs:"; echo "$rpm_files"; exit 1; }
echo "ok    rpm installs into the database with the expected files"

deb_files="$($engine run --rm --arch "$podman_arch" --network=none -v "$packages:/p:ro,z" \
  docker.io/library/ubuntu:22.04 sh -c \
  "dpkg-deb -c /p/$(basename "$deb") | awk '{print \$6}' | grep -v '/\$' | sed 's#^\\.##'" | sort)"
[[ "$deb_files" == "$expected" ]] || { echo "deb file list differs:"; echo "$deb_files"; exit 1; }
echo "ok    deb lists the expected files"

tar_files="$($engine run --rm --arch "$podman_arch" --network=none -v "$packages:/p:ro,z" \
  docker.io/library/ubuntu:22.04 sh -c \
  "mkdir /x && tar -xzf /p/$(basename "$tarball") -C /x && /x/*/install.sh --root /staged && cd /staged && find . -type f | sed 's#^\\.##'" | sort)"
[[ "$tar_files" == "$expected" ]] || { echo "tar install differs:"; echo "$tar_files"; exit 1; }
echo "ok    tar installer stages the expected files with --root"
