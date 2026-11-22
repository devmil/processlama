#!/usr/bin/env bash
# The checks a change must pass before it is submitted.
set -euo pipefail
cd "$(dirname "$0")/.."

QT_BINS="$( (command -v qmake6 >/dev/null && qmake6 -query QT_INSTALL_BINS) || echo /usr/lib/qt6/bin)"
QMLLINT="${QMLLINT:-$(command -v qmllint6 || command -v "$QT_BINS/qmllint" || command -v qmllint)}"
QMLTESTRUNNER="${QMLTESTRUNNER:-$(command -v qmltestrunner6 || command -v "$QT_BINS/qmltestrunner" || command -v qmltestrunner)}"

python3 scripts/check_workflows.py
python3 scripts/generate-brand-assets.py --check
python3 -m unittest discover -s tests/release -v
python3 -m unittest discover -s tests/native_hooks -v
python3 -m unittest discover -s tests/package -v
python3 -m unittest discover -s tests/architecture -v
python3 scripts/check_architecture.py
python3 tooling/l10n/generate.py --check
python3 scripts/generate-license-notices.py --check
python3 tooling/remote_wire/generate.py --check
python3 scripts/check_helper_compatibility.py --self-test
python3 scripts/check_helper_compatibility.py

# QML: lint the application and the vendored Meridian, run their tests.
"$QMLLINT" -I qml qml/ProcessLama/*.qml
QT_QPA_PLATFORM=offscreen "$QMLTESTRUNNER" -import qml -input qml/tests

cargo fmt --manifest-path rust-core/Cargo.toml --all -- --check
# The remote helper's sources are fingerprinted for helper compatibility; its
# lints are reviewed when its compatibility version changes, not here.
cargo clippy --manifest-path rust-core/Cargo.toml --workspace --exclude processlama-remote-helper --all-targets --locked -- -D warnings
cargo build --manifest-path rust-core/Cargo.toml -p processlama-remote-helper --locked
cargo test --manifest-path rust-core/Cargo.toml --workspace --locked
