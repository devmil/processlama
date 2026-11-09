# Release Shape

ProcessLama has one immutable release identity (`VERSION`, global build number,
release commit, and annotated `vVERSION-BUILD` tag) and separate native build
jobs. Linux and macOS artifacts must originate from the exact prepared commit.

The GitHub Actions workflow publishes these assets:

```text
ProcessLama-1.2.0-17.dmg
ProcessLama-1.2.0-17-linux-x86_64.rpm
ProcessLama-1.2.0-17-linux-x86_64.AppImage
ProcessLama-1.2.0-17-linux-x86_64.deb
ProcessLama-1.2.0-17-linux-x86_64.tar.gz
ProcessLama-1.2.0-17-windows-x86_64.msi
ProcessLama-1.2.0-17-windows-x86_64.zip
processlama-network-service-1.2.0-17-linux-{x86_64,aarch64}.{rpm,deb,tar.gz}
```

Every app bundle carries the four remote helpers (`linux-x86_64`,
`linux-arm64`, `macos-arm64`, `macos-x86_64`), built once per release by the
`remote-helper-linux` and `remote-helper-macos` jobs and checked with
`scripts/check_bundled_helpers.py`; the macOS app re-signs them with its
Developer ID. The `network-service` job builds the standalone network
service packages natively per architecture (arm64 under qemu); the website
lists them under "Network service for remote Linux hosts".

GitHub Releases host the retained assets and back public website links. `website/_data/releases.json` contains platform,
format, architecture, minimum system, size, checksum, URL, and (for the DMG)
Sparkle signature. Only metadata, HTML release notes, the downloads page, and
the appcast are committed after publication.

Linux bundles include the scoped network telemetry service. RPM and DEB install
it automatically; AppImage and portable tar offer an authorized in-app install
action. Flatpak and Snap are still
deferred because their PID namespaces cannot safely provide the full process
explorer behavior under the same product name.

See `docs/RELEASE.md` for the operator flow and `docs/release_ci_setup.md` for
the protected setup checklist.
