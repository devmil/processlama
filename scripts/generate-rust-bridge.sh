#!/usr/bin/env bash
set -euo pipefail

# Must match the flutter_rust_bridge pins in pubspec.yaml and
# rust-core/core/Cargo.toml; a newer codegen silently upgrades both.
required_version="2.12.0"

if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  echo "flutter_rust_bridge_codegen is not installed." >&2
  echo "Install it with: cargo install flutter_rust_bridge_codegen --version ${required_version}" >&2
  exit 127
fi

installed_version="$(flutter_rust_bridge_codegen --version | awk '{print $2}')"
if [[ "$installed_version" != "$required_version" ]]; then
  echo "flutter_rust_bridge_codegen ${installed_version} found, ${required_version} required." >&2
  echo "Install it with: cargo install flutter_rust_bridge_codegen --version ${required_version} --locked --root <dir>" >&2
  echo "and put <dir>/bin first on PATH." >&2
  exit 1
fi

flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
