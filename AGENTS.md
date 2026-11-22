# Contributor instructions

ProcessLama is a Rust and Qt Quick (QML) desktop process explorer.

- QML talks only to the bridge objects (`Store.app`, the tree model); the bridge posts
  commands to the application core; the core reaches native code through ports that the
  `infra-*` adapters implement. `scripts/check_architecture.py` enforces the layering.
- Each port has one owning use case in `application`; adapters never call each other.
- Use Meridian primitives, tokens and icons for UI (`qml/Meridian`, vendored from
  meridian_ui with `scripts/sync-meridian.sh`; change Meridian upstream, then sync).
  Add English and German strings to `l10n/*.arb` and run `tooling/l10n/generate.py`.
- Run `cargo fmt`, `qmllint` and the tests; run `./scripts/verify.sh` before submitting.
  Never disable tests to hide failures.
- Update CHANGELOG.md and RELEASE_NOTES.md in both unreleased channels for shipped behavior.
- Update tooling/remote_wire/contract.json through its generator, and record helper
  compatibility decisions (`scripts/check_helper_compatibility.py`).
- Keep secrets, signing material, personal data and local machine configuration out of Git.
