#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-debug}"
FLAGS=()

if [[ "$PROFILE" == "release" ]]; then
  FLAGS+=(--release)
elif [[ "$PROFILE" != "debug" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 64
fi

cargo build --manifest-path rust-core/Cargo.toml --package processlama_core ${FLAGS+"${FLAGS[@]}"}
