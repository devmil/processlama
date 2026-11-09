#!/usr/bin/env bash
# Builds processlama-network-helper for x86_64 and aarch64 and packages each as rpm, deb
# and tar (docs/10_remote_hosts.md §8.5), natively in an Ubuntu 22.04 container per
# architecture (aarch64 under qemu-user). Output: build/network-service/.
#
#   PROCESSLAMA_CONTAINER_ENGINE  container engine command (default: podman)
#   PROCESSLAMA_NETWORK_ARCHES    space-separated subset of "amd64 arm64"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export MIM_REPO_ROOT="$ROOT"
# shellcheck source=lib/version.sh
source "$ROOT/scripts/lib/version.sh"
mim_read_version

engine="${PROCESSLAMA_CONTAINER_ENGINE:-podman}"
output="$ROOT/build/network-service"
recipe="$ROOT/packaging/network-service/Containerfile"
mkdir -p "$output"

for arch in ${PROCESSLAMA_NETWORK_ARCHES:-amd64 arm64}; do
  image="localhost/processlama-network-builder:$arch-$(sha256sum "$recipe" | cut -c1-16)"
  if ! $engine image exists "$image" 2>/dev/null; then
    $engine build --arch "$arch" --network=host -t "$image" -f "$recipe" "$ROOT/packaging/network-service"
  fi
  # Kept between runs: cargo's registry and target directory make reruns fast.
  work="$ROOT/build/network-service-work/$arch"
  mkdir -p "$work"
  # The build fetches public crates; it never sees credentials.
  $engine run --rm --arch "$arch" --network=host \
    -v "$ROOT:/src:ro,z" \
    -v "$output:/out:z" \
    -v "$work:/work:z" \
    -e VERSION_LABEL="$MIM_MARKETING_VERSION" \
    -e BUILD_NUMBER="$MIM_BUILD_NUMBER" \
    -e OWNER="$(id -u):$(id -g)" \
    "$image" bash -c '/src/packaging/network-service/package-in-container.sh
      if grep -Eq "^ *0 +0 " /proc/self/uid_map; then chown -R "$OWNER" /out /work; fi'
done
echo "==> Network service packages in $output" >&2
