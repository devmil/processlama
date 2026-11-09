# Snapshot Documents

ProcessLama snapshot documents use JSON with a small wrapper around the captured
process snapshot:

- `schema_version`: currently `1`.
- `exported_at_unix_ms`: local export timestamp.
- `source`: producer name.
- `display_name`: optional user-facing saved snapshot name.
- `snapshot`: the `ProcessSnapshot` payload rendered by the app.

The Flutter repository implementation writes files ending in
`.processlama-snapshot.json` under the app support `snapshots/` directory. Import
uses the same document wrapper, copies opened external snapshot documents into
the app support snapshot directory, and rebuilds the process tree through
`ProcessService`, so widgets do not perform file IO.

## Quick Look Plan

The macOS release should register `.processlama-snapshot.json` as a document type
and add a Quick Look extension that renders:

- snapshot timestamp and platform;
- process count and root process count;
- top memory consumers;
- privacy-safe process names when privacy mode is enabled.

Until the extension exists, exported files remain plain JSON so users can inspect
or attach them without a custom viewer.
