# Remote host architecture

ProcessLama connects to Linux and macOS hosts over the system SSH client. Each host
opens in its own process-session tab. See [setup](remote_hosts_setup.md) for installation.

## Layers

The UI uses ProcessSession and RemoteHostService. Shared Dart transport lives in
packages/devmil_remote and shared Rust transport in rust-core/devmil-remote; neither
imports ProcessLama application code. The helper shares rust-core/telemetry with the
local core. Native access remains behind repositories and flutter_rust_bridge.

## Protocol and compatibility

The wire contract is tooling/remote_wire/contract.json. Run
`python3 tooling/remote_wire/generate.py` after editing it and commit the generated
Rust and Dart files. CI checks generator output. Framed typed messages carry requests,
responses, process batches and icons, with limits and cancellation owned by transport.

Helper build identity comes from rust-core/remote-helper/COMPATIBILITY. Run
`python3 scripts/check_helper_compatibility.py` after helper changes. Raise the version
and record the fingerprint when behavior changes; record with --keep-version only
when output cannot change or the version was already raised in the release train.
Installed hosts offer an Update helper action when replacement is needed.

## Packaging and testing

Release builds bundle Linux x86_64/arm64 and macOS arm64/x86_64 helpers. Linux helpers
are built with zigbuild in the packaging/remote-helper container. Network service
packages are separate from the SSH helper and require explicit privileged installation.

`python3 scripts/verify_remote_hosts.py --protocol --helper --ssh-loopback` runs the
local lanes. Optional --containers, --mac, --disconnect-matrix, --performance, --ui and
--soak lanes need suitable disposable hosts. Supply the Mac through
PROCESSLAMA_TEST_MAC_HOST. Remove every helper installed for testing.

Diagnostics must exclude SSH credentials, private host content and process data.
