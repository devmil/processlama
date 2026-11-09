#!/usr/bin/env bash
set -euo pipefail

python3 scripts/check_workflows.py
python3 scripts/generate-brand-assets.py --check
python3 -m unittest discover -s tests/release -v
flutter gen-l10n
flutter pub get
python3 scripts/generate-license-notices.py --check
python3 -m unittest discover -s tests/native_hooks -v
python3 -m unittest discover -s tests/package -v
python3 scripts/check_architecture.py
python3 tooling/remote_wire/generate.py --check
python3 scripts/check_helper_compatibility.py --self-test
python3 scripts/check_helper_compatibility.py
python3 -m unittest discover -s tests/architecture -v
dart format --set-exit-if-changed lib test test_remote packages
(cd packages/devmil_remote && dart pub get && dart analyze --fatal-infos && dart test)
flutter analyze --no-fatal-infos
flutter test
cargo test --manifest-path rust-core/Cargo.toml
python3 scripts/verify_remote_hosts.py --protocol --helper --ssh-loopback
