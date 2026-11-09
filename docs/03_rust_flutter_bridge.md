# Rust / Flutter Bridge

ProcessLama standardizes on `flutter_rust_bridge` for the production Rust/Flutter
boundary.

Generated bindings are checked in and are the only bridge; the early JSON
bootstrap adapter no longer exists.

## Why `flutter_rust_bridge`

- It generates Dart/Rust binding code instead of hand-maintaining FFI glue.
- It supports typed Rust structs and enums across the boundary.
- It supports Rust async APIs.
- It supports Rust-to-Dart streams, which fits network telemetry.
- It has zero-copy buffer support for large payloads when profiling proves that
  object transfer is too expensive.

References:

- `flutter_rust_bridge` quickstart:
  <https://cjycode.com/flutter_rust_bridge/quickstart>
- Stream support:
  <https://cjycode.com/flutter_rust_bridge/guides/types/translatable/stream>
- Zero-copy buffers:
  <https://cjycode.com/flutter_rust_bridge/v1/feature/zero_copy.html>

## Current Files

The bridge crate is `rust-core/core` (`processlama_core`) in the Cargo
workspace; telemetry lives in `rust-core/telemetry` and is translated into
bridge DTOs in `api.rs`.

- `rust-core/core/src/api.rs`: public FRB input module, including the
  `child_process_*` API that runs ssh as Rust-owned child processes for the
  remote hosts transport (Windows uses `dart:io`).
- `rust-core/core/src/frb_generated.rs`: generated Rust bridge.
- `lib/rust/`: generated Dart bridge and DTOs.
- `rust-core/core/src/network.rs`: Rust-owned network streaming model.
- `flutter_rust_bridge.yaml`: codegen config.
- `scripts/generate-rust-bridge.sh`: codegen wrapper; it checks that the
  generator is version 2.12.0.
- `lib/repositories/impl/rust_process_repository.dart` and
  `lib/repositories/impl/remote/native_remote_process.dart`: the only Dart
  files that call generated bindings (`scripts/check_architecture.py`).

The remote helper protocol is not a bridge: it is framed JSON over ssh,
defined in `tooling/remote_wire/contract.json` and generated for both sides
(see docs/10_remote_hosts.md §6).

## Generate Bindings

Install the code generator once:

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
```

Generate bindings:

```bash
./scripts/generate-rust-bridge.sh
```

The config writes generated Dart into `lib/rust/` and generated Rust into
`rust-core/core/src/frb_generated.rs`.

## Network Streaming Ownership

ProcessLama
keeps subprocess steering, sampling cadence, state reconciliation, and batching
inside Rust.

The planned generated stream entry point should have this shape after
`frb_generated.rs` exists:

```rust
pub fn stream_network_events(
    config: NetworkStreamConfig,
    sink: crate::frb_generated::StreamSink<NetworkEventBatch>,
) -> Result<(), String> {
    // Start/own the sampler worker in Rust and push batches through `sink`.
    Ok(())
}
```

Dart should only subscribe to the generated `Stream<NetworkEventBatch>` and
render state. It should not own subprocess lifecycle, parser state, or throughput
accumulation.

## Performance Policy

Default to typed `flutter_rust_bridge` models. If profiling shows that frequent
large batches are costly, move that specific payload to zero-copy byte buffers
with a versioned binary layout. Do not fall back to JSON for hot paths.
