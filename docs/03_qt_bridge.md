# The Qt bridge

The UI talks to Rust through [qtbridge](https://crates.io/crates/qtbridge) objects created
in `rust-core/desktop/qt` and passed to the QML root as initial properties.

## Objects

- `AppState` (`app` in QML, reached as `Store.app`): JSON projections of settings, tabs,
  the active session, the inspector, snapshots, remote hosts, pinned rows and saved
  filters, plus signals for one-shot UI events (toasts, the update dialog, the helper
  install prompt, clipboard copies, probe and save results). Its slots are the commands;
  each posts a `CoreEvent::Command` to the inbox.
- `ProcessTreeModel` (`treeModel`, `Store.tree`): the visible rows as a table. Roles carry
  the cell text and the row state the delegates need (depth, expansion, marker, history,
  search match ranges, heat, icon URL). Properties expose the selected row and key, the
  CPU scale and the column ids.
- `Pump`: the queued `pump` slot the inbox invokes to drain events.
- `PlatformHooks` (`hooks`, in the app crate): the macOS unified toolbar, reduce motion,
  the GTK text scale and the development screenshot hook.

## Rules

- QML never calls a slot that synchronously re-enters a borrowed object. Commands are
  posted; projections are set by the driver after the core handled the batch.
- Projections are compared before they are published, so an unchanged value never
  notifies QML.
- Strings shown to the user are translated in QML (`L10n`); the core sends message keys
  and arguments. Remote failure codes travel as `@failure:<code>` arguments.
- `rust-core/third_party/qtbridge-interfaces` carries a small aliasing fix for re-entrant
  model calls in release builds; see its `PROCESSLAMA-PATCH.md`.

## Development switches

- `PROCESSLAMA_QML_DIR=<checkout>/qml` loads the QML from disk instead of the embedded
  resource.
- `PROCESSLAMA_DATA_DIR` moves settings, snapshots and caches.
- `PROCESSLAMA_SCREENSHOT=<png>[;<step>...]` saves the window after startup (steps such as
  `preferences:3`, `about`, `licenses`, `select`) and quits; `-` as the path keeps the
  app open after the steps.
