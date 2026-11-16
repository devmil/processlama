# Linux Flutter engine

Linux x64 builds use a patched Flutter 3.50.0 engine. The exact Flutter and
depot_tools revisions, DEPS checksum, ordered patch checksums, builder image
and recipe are in `tooling/linux/flutter.lock.json`. `.fvmrc` must agree.
macOS and Windows continue to use the upstream SDK.

## Changes

1. A resized Wayland EGL drawable is recreated before painting. The old
   `wl_surface` and last committed image remain; no unused resize buffer is
   swapped to the compositor. Failed creation or swap is reported and retried.
   Frame readiness tracks successfully swapped dimensions.
2. An explicit `FlDartProject` API enables eager delivery of pending vsync
   batons after changed window metrics. Ordinary frames use GTK frame-clock
   phase and refresh estimates, with the monitor rate as fallback. It uses
   platform-thread scheduling and only applies to merged UI/platform engines.
   Duplicate metrics do not continuously trigger eager frames. Teardown returns
   pending batons before engine shutdown.
3. Missing accessibility bridge IDs are handled without passing null to ATK;
   the returned ID is freed according to ATK's ownership contract.

The ProcessLama runner enables resize scheduling only on Wayland. The painted
buffer change belongs to the Wayland subsurface renderer. Separate UI-thread
engines retain stock scheduling. This is a private ABI extension, not an upstream
Flutter API. Updating Flutter requires rebasing and requalifying the patch series.

## Local builds

Use `./scripts/flutter.sh pub get` and `./scripts/flutter.sh run -d linux`.
The wrapper prepares the pinned engine in an owned content-addressed cache under
`~/.cache/processlama/linux-toolchain`; it does not patch FVM or the global SDK.
A cold build downloads several GB and compiles native engine tools. Install the
packages listed in `tooling/linux/Containerfile`, including Xvfb, DBus and xauth
for the full GTK tests. `PROCESSLAMA_LINUX_JOBS` defaults to 2.

For reproducible production, build inside the pinned Containerfile. Build one
mode at a time with `python3 scripts/linux/prepare-toolchain.py --mode profile`.
`--offline` requires an already verified exact-mode cache. Debug, profile and
release use matching target and host engines. Caller-provided `--local-engine`
arguments are rejected. Do not use `VPYTHON_BYPASS`.

`PROCESSLAMA_FLUTTER_FRAMEWORK_SDK` can select a matching pristine framework
SDK; its reported revision and version must agree with the lock. Framework
commands such as `pub` do not load the engine overlay.

## CI and portable consumers

`linux-flutter-sdk.yml` builds and tests each requested mode in the pinned Ubuntu
builder. It uses the upstream Debian engine sysroot. The GitHub-hosted cold-build
lane requires 20 GiB free disk and uses two Ninja jobs. Only the portable archive
and exact engine symbols are cached; source and object trees are job-local.
Cache keys include the lock and producer/package scripts. A cache miss reruns
flow and Linux embedder tests before publication. Cache hits are revalidated.

The artifact contains the engine, headers, Dart SDK, frontend server, patched
platform dills, sky_engine, shader include libraries and mode-specific snapshot tools. It contains no
producer source checkout or absolute-path symlinks. Every payload file has a
size, executable flag and SHA-256. Archives are limited to 1 GiB compressed,
4 GiB expanded and 40,000 regular files; links, duplicates and path escapes are
rejected. Install into a new owned destination. Corrupt existing destinations
are preserved and rejected rather than repaired silently.

The `flutter-linux` composite action installs that overlay and prepends the
checked-in Flutter wrapper to PATH. CI builds debug; packaging rehearsal and
release builds use release. Reusable release producers check out the prepared
release SHA. No Linux app build falls back to an upstream engine.

After building, `verify-engine.py` compares the bundled engine to its selected
producer, checks the resize API exports and records engine provenance in the
bundle. Packaging rechecks after loader-path repair and scans the complete
helper closure for numeric ELF ABI requirements and relocatable loader paths.
Ubuntu 24.04 is the application baseline (GLIBC 2.39, GLIBCXX 3.4.32,
CXXABI 1.3.14); the engine's older sysroot does not lower the whole app's floor.

Engine DWARF originals are checked against runtime GNU build IDs and uploaded
separately for 90 days. These are CI transport artifacts, not permanent backup.
Before a public release, retain the exact originals and producer manifests with
release diagnostics in durable private storage. Existing app/Rust/vendor symbol
coverage is separate from this engine integration.

To reproduce a consumer manually:

```sh
python3 scripts/linux/sdk-package.py pack --paths paths.json --output engine.tar.gz
python3 scripts/linux/sdk-package.py install --archive engine.tar.gz \
  --checksum-file engine.tar.gz.sha256 --destination /new/owned/sdk --mode profile
export PROCESSLAMA_LINUX_SDK_DIR=/new/owned/sdk
./scripts/flutter.sh build linux --profile
python3 scripts/linux/verify-engine.py build/linux/x64/profile/bundle \
  --mode profile --write-provenance
```

## Qualification and rollback

Unit tests and archive verification do not prove presentation timing or GPU
compatibility. Qualify the actual extracted package on native Wayland: continuous
grow/shrink, maximize/restore, multiple monitor refresh rates and scales, suspend/
resume, repeated open/close, ordinary animations, and X11 fallback. Capture
painted presentation feedback separately from intrusive pixel reads. Do not
attribute old prototype measurements to a rebuilt candidate.

Rollback is a reviewed source change: disable the runner opt-in to revert pacing
while retaining the painted-buffer correction, or revert the complete custom SDK
integration. Never replace a cache artifact under an existing identity. Update
pins/checksums and rerun all mode builds after changing a patch, recipe or producer.
