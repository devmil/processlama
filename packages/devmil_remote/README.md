# devmil_remote

Product-neutral transport mechanics for a desktop client that starts a helper
on another machine over the system OpenSSH client and talks to it over the
helper's standard input and output.

Adapted from GitLama's remote workspaces (`gitlama/lib/repositories/impl/remote/`),
keeping their security properties: argument arrays instead of shells, fixed
SSH options (`BatchMode=yes`, `StrictHostKeyChecking=yes`, no forwarding, no
connection sharing), bounded strict frames, last-line bootstrap markers.

- `ssh_command.dart`: executable resolution, `ssh -V` probe, fixed options,
  alias validation and argument arrays.
- `frame_codec.dart`, `wire_json.dart`: 4-byte big-endian length frames of
  strict UTF-8 JSON.
- `bootstrap.dart`: last non-empty line markers and the pre-hello probe.
- `remote_channel.dart`: handshake, request IDs, deadlines, cancellation,
  subscriptions with credit, ping/liveness and off-isolate decoding.
- `reconnector.dart`: the bounded reconnect schedule.
- `testing/`: `FakeRemoteProcess` and `FakeRemoteHelper` for tests.

The package must not import an application package; ProcessLama's
`scripts/check_architecture.py` enforces that. Run its tests with `dart test`.
