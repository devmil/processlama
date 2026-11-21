# ProcessLama

ProcessLama is a desktop process explorer for Windows, Linux and macOS, built with Flutter and Rust.

Explore a live process tree, filter and freeze it, inspect processes, export snapshots,
and monitor Linux and macOS hosts through SSH. Linux supports an optional eBPF network service.

## Development

Install the Flutter version pinned in `.fvmrc`, stable Rust, and your platform's Flutter desktop build tools.
On Linux, install Clang, CMake, Ninja, pkg-config and GTK3 development headers.
Building the network service also requires libelf development headers.

```sh
flutter pub get
flutter run -d linux # or macos / windows
```

The native-assets hook builds the Rust bridge and development remote helper.
Install the Python CI tools with `python3 -m pip install -r tooling/requirements-ci.txt`.
Run `./scripts/verify.sh` for formatting, analysis, tests and generated-contract checks.
The full remote-host harness has optional container and macOS host lanes; see
[remote hosts](docs/10_remote_hosts.md).

## Architecture

Widgets call services, services own repositories, and repositories access the Rust
bridge. A per-tab process session supports local telemetry and remote helpers.
See [architecture](docs/02_architecture.md), [the bridge](docs/03_rust_flutter_bridge.md)
and [remote setup](docs/remote_hosts_setup.md).

## CI and releases

GitHub Actions builds on hosted Linux, macOS and Windows runners. Release credentials
are repository secrets. See [release setup](docs/release_ci_setup.md) and
[release procedure](docs/RELEASE.md).

Source and releases are hosted at https://github.com/devmil/processlama.
The product website and update feeds are at https://devmil.de/processlama/.

## License

Application source: MIT. The Linux eBPF program retains GPL-2.0-only, and
bundled fonts retain SIL OFL 1.1. See [LICENSE](LICENSE) and [component notices](LICENSES/NOTICE.txt).
