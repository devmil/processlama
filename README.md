# ProcessLama

ProcessLama is a desktop process explorer for Windows, Linux and macOS, built with Rust and
Qt Quick (QML).

Explore a live process tree, filter and freeze it, inspect processes, export snapshots,
and monitor Linux and macOS hosts through SSH. Linux supports an optional eBPF network service.

## Development

Install stable Rust and Qt 6.11 or newer (Qt Base, Qt Declarative, Qt SVG and, on Linux,
Qt Wayland) so that `qmake6` (or `QMAKE`) is found. On Linux, install Clang and pkg-config;
building the network service also requires libelf development headers.

```sh
cargo run --manifest-path rust-core/Cargo.toml -p processlama
```

The QML is embedded in the executable. While working on the UI, point the app at the
checkout to skip rebuilding: `PROCESSLAMA_QML_DIR=$PWD/qml cargo run ...`.
`PROCESSLAMA_DATA_DIR` keeps settings and snapshots in a scratch folder.

Install the Python CI tools with `python3 -m pip install -r tooling/requirements-ci.txt`.
Run `./scripts/verify.sh` for the QML lint and tests, Rust formatting, Clippy and tests, and
the generated-contract and architecture checks. The remote helper's end-to-end channel tests
run against a local helper build; `cargo test -p processlama-infra-remote --test ssh_host
-- --ignored` exercises a real SSH host (see the file for its environment).

## Architecture

QML calls the bridge objects; the bridge posts commands to the application core; the core
owns its adapters through ports. The crates under `rust-core/desktop` are layered and
`scripts/check_architecture.py` enforces it:

- `domain`: records, search, settings, remote host profiles and snapshot documents.
- `application`: the process session, tabs, snapshots, remote host workflows and their ports.
- `presentation`: display formats and column definitions.
- `infra-*`: local telemetry, storage, platform services and SSH remote hosts.
- `qt`: the AppState and tree model bridge objects (qtbridge) and the event pump.
- `app`: the composition root and the embedded QML resources.

The UI uses the vendored Meridian QML library (`qml/Meridian`, synced with
`scripts/sync-meridian.sh`). See [architecture](docs/02_architecture.md),
[the Qt bridge](docs/03_qt_bridge.md) and [remote setup](docs/remote_hosts_setup.md).

## CI and releases

GitHub Actions builds on hosted Linux, macOS and Windows runners. Linux packages carry an
application-private Qt runtime (`scripts/stage_linux_bundle.py`); formats are AppImage,
DEB, RPM, Arch and a portable tar. Release credentials are repository secrets. See
[release setup](docs/release_ci_setup.md) and [release procedure](docs/RELEASE.md).

Source and releases are hosted at https://github.com/devmil/processlama.
The product website and update feeds are at https://devmil.de/processlama/.

## License

Application source: MIT. The Linux eBPF program retains GPL-2.0-only, bundled fonts retain
SIL OFL 1.1, and Qt and qtbridge are used under LGPL-3.0. See [LICENSE](LICENSE) and
[component notices](LICENSES/NOTICE.txt).
