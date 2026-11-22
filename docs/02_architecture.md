# Architecture

ProcessLama is a Rust application with a Qt Quick (QML) user interface. Rust owns all
state and behaviour; QML renders projections of that state and sends commands back. The
main window holds tabs: Local and one tab per remote host, each with its own explorer
state.

```text
qml/ProcessLama/        the window: toolbar, tabs, sidebar, process table, inspector,
                        status bar and dialogs; reads Store.app and the tree model
qml/Meridian/           the vendored Meridian QML library (scripts/sync-meridian.sh)

rust-core/desktop/      the desktop application (Cargo workspace members)
  domain/               records, identities, search, settings, remote host profiles,
                        snapshot documents; no I/O
  application/          AppCore: tabs, ProcessSession per tab, snapshots, settings,
                        updates, network service, remote host workflows, icon service,
                        diagnostics; the ports adapters implement
  presentation/         display formats and column definitions shared by the bridge
  infra-local/          local telemetry adapter over processlama_telemetry
  infra-storage/        settings, snapshot store, remote icon cache, Flutter settings import
  infra-platform/       update checks (Sparkle on macOS), Linux network service setup,
                        macOS window chrome
  infra-remote/         OpenSSH client, helper channel, scripts, telemetry decoding,
                        bundled helpers
  qt/                   qtbridge objects (AppState, ProcessTreeModel, Pump), the inbox,
                        worker pool and timer thread
  app/                  the composition root; embeds QML, fonts and art as a Qt resource

rust-core/telemetry/    process enumeration, metrics, inspection, icons (processtree)
rust-core/wire/         the generated remote wire contract and helper build ID
rust-core/devmil-remote/ the framed helper transport
rust-core/remote-helper/ processlama-remote-helper, run on remote hosts
```

`scripts/check_architecture.py` enforces the direction: `domain` depends on nothing,
`application` only on `domain`, adapters only on `domain` and `application` (and the
telemetry, wire and transport crates), `qt` never on an adapter; only `app` names
everything.

## Threads and the event loop

The core runs synchronously on the GUI thread. Everything that blocks runs elsewhere and
reports back as a `CoreEvent` posted to the `Inbox`:

- a sampler thread per local source (cadence from the session), an inspector thread for
  details, a worker pool for snapshots, settings, updates, SSH and icons;
- a timer thread that posts `Tick` at the core's next deadline (debounced settings
  saves, order-lock release, detail refresh, reconnects);
- QML commands, which the AppState slots post as `CoreEvent::Command` rather than calling
  into the core while a bridge object is borrowed.

The inbox coalesces wake-ups into one queued `pump` call. `Driver::pump` drains the inbox
into `AppCore::handle`, then `sync` projects only what changed (`CoreChanges`) onto the
bridge objects, one borrow at a time.

## Tabs and sessions

- `AppCore` keeps one `ProcessSession` per tab. Local is always first and cannot be
  closed. Hidden sessions keep their selection, expansion, freeze and pins and sample at
  the background cadence (5 s by default for remote tabs).
- A `ProcessSession` consumes samples from one `SessionSource` and never polls. Sources
  report their phase (connecting, live, stale, failed) and `HostCapabilities`; features
  of a remote tab come from the helper's hello, never from the local platform.
- Remote hosts share one connection per profile among the tabs that use it; telemetry is
  credit-limited and re-subscribed after a reconnect. A dropped connection makes the tab
  stale (last sample kept, history gap), never removes processes.

## Rendering the tree

`ProcessTreeModel` is a flat `QAbstractItemModel` over the session's visible rows and
visible columns. Each publication is reconciled by identity: the changed middle range is
removed and inserted, and `dataChanged` covers only the cells whose text or state changed,
so the `TableView` recycles delegates and repaints the minimum. Selection, hover, heat and
search fills are drawn per cell from model roles; sparklines are `Shape` multilines with
gaps where samples are missing.

## Network streaming

Network telemetry belongs in Rust. On Linux the core reads the eBPF service's snapshot
file; macOS samples `nettop`; remote helpers report the same rates in their telemetry.
