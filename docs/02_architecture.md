# Architecture

ProcessLama combines layered Flutter services with Rust-first
telemetry approach. Since remote hosts (docs/10_remote_hosts.md) the main
window holds tabs: Local and one tab per remote host, each with its own
explorer state.

```text
lib/screens/
  ProcessExplorerScreen, built per tab under ActiveProcessSessionScope
    reads the tab's ProcessService (its ProcessSession)
  workspace_tabs/: tab strip, remote host dialogs, banner, settings section
    read WorkspaceTabsService and RemoteHostService

lib/services/
  WorkspaceTabsService     tabs, order, active tab, one ProcessSession each
  ProcessSession           explorer state of one tab over one ProcessSource
    LocalProcessSource     samples this computer through ProcessRepository
    RemoteProcessSource    subscribes to a remote helper's telemetry
  RemoteHostService        profiles, shared connections, leases, reconnect
  RemoteHostWorkflows      install/remove flows through an interaction port
  ProcessIconService       content-addressed remote icon cache
  SettingsService          preferences and the remote hosts section

lib/repositories/
  ProcessRepository        generated Rust bridge (local telemetry)
  RemoteConnectionRepository  ssh child processes and the helper channel
  ...

rust-core/ (Cargo workspace)
  core/           flutter_rust_bridge facade (processlama_core)
  telemetry/      process enumeration, metrics, inspection, icons
  wire/           generated remote wire contract
  devmil-remote/  generic framed transport for helpers
  remote-helper/  processlama-remote-helper, run on remote hosts
```

## Flutter Layers

- `lib/app/` contains app bootstrap, theme, and desktop window setup.
- `lib/di/` contains the Provider-backed registry copied from VOID Arc's
  pattern.
- `lib/screens/` contains widgets. Widgets never know how telemetry is
  fetched and never touch the Rust bridge, ssh or `devmil_remote`.
- `lib/services/` owns app state and business rules.
- `lib/repositories/` owns IO, FFI, persistence, ssh and platform bridges.
- `lib/models/` is shared Flutter domain state, including the generated
  remote contract enums (`remote_contract.g.dart`).
- `packages/devmil_remote/` is the shared Dart transport (ssh arguments,
  framing, channel, reconnector, fakes); it has no ProcessLama imports.

`scripts/check_architecture.py` enforces these boundaries.

## Repository Pattern

ProcessLama follows Mirroly's repository abstraction style:

- every data source has an interface in `lib/repositories/`;
- implementations live in `lib/repositories/impl/`;
- services receive repositories through constructor injection;
- each repository is owned by exactly one service;
- other services call that owner service instead of bypassing it;
- repository interfaces are exported from `lib/repositories/repositories.dart`.

Current owners:

| Repository | Owner Service | Responsibility |
| ---------- | ------------- | -------------- |
| `ProcessRepository` | `ProcessSessionFactory` (local sources and sessions) | Rust-backed process snapshots, details, signals |
| `SnapshotRepository` | `ProcessSessionFactory` (sessions) | saved and exported snapshot documents |
| `SettingsRepository`, `RemoteHostsSettingsRepository` | `SettingsService` | persisted preferences and the remote hosts section |
| `LinuxNetworkSetupRepository` | `LinuxNetworkSetupService` | the local Linux network service |
| `RemoteConnectionRepository` | `RemoteHostService` | ssh probe, install, prune, uninstall and helper channels |
| `RemoteHelperArtifactRepository` | `RemoteHostService` | the helpers bundled with the app |
| `RemoteIconCacheRepository` | `ProcessIconService` | remote icons on disk |

`RepositoryOperationTracker` mirrors Mirroly's optimization helper and records
repository access patterns without coupling widgets to persistence details.

## Tabs and Sessions

- `WorkspaceTabsService` keeps one `ProcessSession` per tab. The Local tab
  is always first and cannot be closed. Hidden sessions keep their
  selection, expansion, freeze and pins and sample at the background cadence
  (5 s by default for remote tabs).
- `ProcessServiceImpl` is a facade over the active session for code that is
  not tab-aware; the explorer reads the session of its tab directly.
- A `ProcessSession` consumes one `ProcessSource` and never polls a
  repository itself. Sources report `ProcessSourceState` (connecting, live,
  stale, failed) and `HostCapabilities`; features of a remote tab come from
  the helper's `hello`, never from the local platform.
- `RemoteHostService` shares one connection per profile among leases; a tab's
  `RemoteProcessSource` holds a lease, subscribes to telemetry with credit
  flow control and re-subscribes after a reconnect. A dropped connection
  makes the tab stale (last sample kept, history gap), never removes
  processes.

## Rust Layers

- `core` (`processlama_core`): the `flutter_rust_bridge` API in `api.rs`, DTO
  translation, and Rust-owned child processes for ssh.
- `telemetry` (`processlama_telemetry`): process enumeration and metrics
  through processtree, inspection, signals, network rates, icon
  normalization.
- `wire` (`processlama_wire`): the remote contract generated from
  `tooling/remote_wire/contract.json`, and the helper build ID.
- `devmil-remote`: framing, server loop, publishers with credit, watchdog.
- `remote-helper`: the helper binary; telemetry encoder, details, icons,
  host facts.

## State Flow (local tab)

1. `LocalProcessSource` samples at the session's cadence through
   `ProcessRepository.fetchSnapshot()`.
2. `RustProcessRepository` calls generated `flutter_rust_bridge` bindings.
3. Rust returns typed DTOs that the repository maps into domain models.
4. The session applies the snapshot (freeze, order lock, histories) and
   publishes `ValueListenable` state; the UI rebuilds.

A remote tab follows the same path from step 4; its samples arrive as
columnar telemetry frames decoded in `lib/repositories/impl/remote/wire/`.

## Network Streaming

Network telemetry belongs in Rust. The Rust side owns sampler subprocess
lifecycle, parsing, process-start matching, throughput accumulation and
reconnect policy; on Linux it reads the eBPF service's snapshot file.
Remote helpers report the same rates in their telemetry.
