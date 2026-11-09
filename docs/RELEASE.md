# Release process

GitHub Actions prepares and publishes desktop releases through the manual
**Publish desktop release** workflow in `.github/workflows/release.yml`.

1. Keep CHANGELOG.md and RELEASE_NOTES.md current in both unreleased channels.
2. Push reviewed main and wait for CI.
3. Dispatch the release workflow on main. Choose stable or beta and a version bump.
   Use beta to advance an existing beta train, promote to make it stable, or
   patch/minor/major to start a new version. Choose none to resume a prepared release.
4. Credentials and the Sparkle trust key are validated before version mutation.
   Preparation verifies source and pushes one canonical release commit. Native jobs
   build that exact commit, including all four remote helpers and standalone Linux
   network service packages. macOS signs and notarizes its DMG.
5. Publication checks that main has not changed, creates or verifies the annotated
   vVERSION-BUILD tag, and verifies artifact sizes and SHA-256 values. New GitHub
   releases stay drafts until their assets pass checksum readback. Published bytes
   are immutable. Website metadata and appcast are committed only afterwards.

A resume resolves an untagged preparation commit from VERSION history or verifies
an existing annotated tag. It rebuilds the candidate with publication tooling from
the dispatched main revision. It does not advance the version or rewrite notes.

## Retention and website

Release metadata retains five stable and five beta releases. Historical assets
already on the destination are checked first; missing historical bytes can be
retrieved from the approved public production release URLs and verified by checksum.
Releases outside the retained union are removed only after the retained set verifies.

Production website deployment is an explicit final job, because pushes using
GITHUB_TOKEN do not trigger a second push workflow. Both that job and the ordinary
Pages workflow deploy only from devmil/processlama. Published updater identities
and immutable release download URLs remain unchanged.


## Compatibility and local packaging

Moving the processtree pin without behavior changes uses
`python3 scripts/check_helper_compatibility.py --record --keep-shared-git`.

Helper changes require a decision recorded in rust-core/remote-helper/COMPATIBILITY.
Raise the version and run scripts/check_helper_compatibility.py --record for behavior
changes; use --keep-version only when behavior cannot change or the version was already
raised in this train. Document a raised helper version in the changelog.

Local packaging commands remain available:

```sh
./scripts/package-linux.sh --formats rpm,tar
./scripts/package-release.sh --skip-sign
./scripts/build-remote-helpers-linux.sh
./scripts/package-network-helper.sh
./scripts/check_network_service_packages.sh x86_64
# Windows PowerShell:
./scripts/package-windows.ps1
```

See [release shape](05_release_shape.md) for the package matrix and
[setup](release_ci_setup.md) for repository credentials and manual acceptance checks.
