#!/usr/bin/env bash
# Builds and packages processlama-remote-helper for linux-x86_64 and linux-arm64 in the
# Ubuntu 22.04 zigbuild container (glibc 2.35 floor). Output: build/remote-helper/.
#
#   PROCESSLAMA_CONTAINER_ENGINE  container engine command (default: podman)
#   CARGO_HOME                    host Cargo home with the prefetched dependencies
#
# Fetch first with `cargo fetch --locked --manifest-path rust-core/Cargo.toml`; the
# container build runs offline. The Cargo home is mounted as an overlay, so the
# container never writes into it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
engine="${PROCESSLAMA_CONTAINER_ENGINE:-podman}"
cargo_home="${CARGO_HOME:-$HOME/.cargo}"
output="${PROCESSLAMA_REMOTE_HELPER_OUTPUT:-$ROOT/build/remote-helper}"
recipe="$ROOT/packaging/remote-helper/Containerfile"
image="localhost/processlama-remote-helper-builder:$(sha256sum "$recipe" | cut -c1-16)"

if ! $engine image exists "$image" 2>/dev/null; then
  $engine build --arch amd64 --network=host -t "$image" -f "$recipe" "$ROOT/packaging/remote-helper"
fi

mkdir -p "$output" "$cargo_home/registry" "$cargo_home/git"
$engine run --rm --arch amd64 --network=none \
  -v "$ROOT:/src:z" \
  -v "$cargo_home/registry:/usr/local/cargo/registry:O" \
  -v "$cargo_home/git:/usr/local/cargo/git:O" \
  -v "$output:/out:z" \
  -e CARGO_TARGET_DIR=/src/rust-core/target/remote-helper-linux \
  -e OWNER="$(id -u):$(id -g)" \
  -w /src/rust-core \
  "$image" \
  bash -euo pipefail -c '
    for triple in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu; do
      cargo zigbuild --locked --offline --release -p processlama-remote-helper \
        --target "$triple.2.35"
    done
    for pair in linux-x86_64:x86_64-unknown-linux-gnu linux-arm64:aarch64-unknown-linux-gnu; do
      target="${pair%%:*}"
      triple="${pair#*:}"
      python3 /src/scripts/package_remote_helper.py package --target "$target" \
        --binary "$CARGO_TARGET_DIR/$triple/release/processlama-remote-helper" \
        --output /out
    done
    # A rootful engine (CI runs Podman through sudo) would leave root-owned files in the
    # checkout; a rootless engine already maps container root to the invoking user.
    if grep -Eq "^ *0 +0 " /proc/self/uid_map; then
      chown -R "$OWNER" /out "$CARGO_TARGET_DIR"
    fi
  '
echo "==> Linux remote helpers in $output" >&2
