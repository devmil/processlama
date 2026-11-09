#!/usr/bin/env bash
# Builds and packages processlama-remote-helper for macos-arm64 and macos-x86_64 with the
# macOS SDK (deployment target macOS 13), signed ad hoc. The macOS app package re-signs its
# copies with the Developer ID. Output: build/remote-helper/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
output="${PROCESSLAMA_REMOTE_HELPER_OUTPUT:-$ROOT/build/remote-helper}"
target_dir="${CARGO_TARGET_DIR:-$ROOT/rust-core/target}"
export MACOSX_DEPLOYMENT_TARGET=13.0

[[ "$(uname -s)" == Darwin ]] || { echo "build-remote-helpers-macos.sh: needs macOS" >&2; exit 1; }
rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null

for pair in macos-arm64:aarch64-apple-darwin macos-x86_64:x86_64-apple-darwin; do
  target="${pair%%:*}"
  triple="${pair#*:}"
  cargo build --locked --release --manifest-path "$ROOT/rust-core/Cargo.toml" \
    -p processlama-remote-helper --target "$triple"
  binary="$target_dir/$triple/release/processlama-remote-helper"
  codesign --force --sign - "$binary"
  python3 "$ROOT/scripts/package_remote_helper.py" package --target "$target" \
    --binary "$binary" --output "$output"
done
echo "==> macOS remote helpers in $output" >&2
