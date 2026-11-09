# Contributor instructions

ProcessLama is a Flutter desktop process explorer with a Rust telemetry core.

- UI depends on services; services depend on repositories. Repositories own native access.
- Each repository has one owning service. Other services use that service.
- Keep native access behind flutter_rust_bridge in repository implementations.
- Use Meridian primitives, tokens and icons for UI. Add English and German translations.
- Run dart format on touched Dart files, flutter analyze --no-fatal-infos and flutter test.
- For Rust changes, run cargo test --manifest-path rust-core/Cargo.toml.
- Run ./scripts/verify.sh before submitting. Never disable tests to hide failures.
- Update CHANGELOG.md and RELEASE_NOTES.md in both unreleased channels for shipped behavior.
- Update tooling/remote_wire/contract.json through its generator, and record helper compatibility decisions.
- Keep secrets, signing material, personal data and local machine configuration out of Git.
