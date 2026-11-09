#!/usr/bin/env python3
"""Keeps the remote helper's compatibility version honest.

Adapted from GitLama's scripts/check_helper_compatibility.py.

ProcessLama connects only to a helper whose build ID equals its own. The ID is the
compatibility version in rust-core/remote-helper/COMPATIBILITY as 40 decimal digits, not
the source commit, so a release that leaves the helper alone keeps working with the helpers
hosts already run.

The file also records a fingerprint of everything the helper is built from in this
repository: its own sources, the wire contract and its generated code, the telemetry use
cases and the shared transport. When any of them changes, the version must rise; this check
fails until it does. The desktop bridge facade (rust-core/core) is outside the fingerprint,
since the helper never builds it. A change inside the fingerprint that cannot change what the
helper does (tests, documentation, a refactor with identical output) keeps the version only
by an explicit decision: record it with --keep-version.

The helper also runs processtree, so the file records the processtree revision pinned in
rust-core/Cargo.toml. Moving that pin needs an explicit decision: raise the version and
record, or record with --keep-shared-git when the move cannot change what the helper does.

  check_helper_compatibility.py                      fail when the record is stale
  check_helper_compatibility.py --record             record the fingerprint
  check_helper_compatibility.py --record --keep-shared-git
  check_helper_compatibility.py --record --keep-version
  check_helper_compatibility.py --self-test          run the checker's own tests
"""
from __future__ import annotations

import hashlib
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPATIBILITY = ROOT / "rust-core" / "remote-helper" / "COMPATIBILITY"

# Everything the helper is built from in this repository, apart from processtree (pinned below).
CONTRACT_GLOBS = (
    "rust-core/remote-helper/Cargo.toml",
    "rust-core/remote-helper/src/**/*.rs",
    "rust-core/wire/Cargo.toml",
    "rust-core/wire/build.rs",
    "rust-core/wire/src/**/*.rs",
    "rust-core/telemetry/Cargo.toml",
    "rust-core/telemetry/src/**/*.rs",
    "rust-core/devmil-remote/Cargo.toml",
    "rust-core/devmil-remote/src/**/*.rs",
    "tooling/remote_wire/contract.json",
)
EXCLUDED_GLOBS: tuple[str, ...] = ()

HEADER = (
    "# The remote helper compatibility version and the fingerprint of the sources it is built from.\n"
    "# Raise the version for any change to what the helper accepts, returns or does; read\n"
    "# \"Remote helper compatibility\" in AGENTS.md. Record with\n"
    "# scripts/check_helper_compatibility.py --record.\n"
)

MAX_VERSION = 999_999

_PROCESSTREE_REV = re.compile(r'processtree\s*=\s*\{[^}]*rev\s*=\s*"([0-9a-f]{7,40})"')


class CompatibilityError(Exception):
    pass


def contract_files(root: Path = ROOT) -> list[Path]:
    files = {path for pattern in CONTRACT_GLOBS for path in root.glob(pattern) if path.is_file()}
    files -= {path for pattern in EXCLUDED_GLOBS for path in root.glob(pattern)}
    return sorted(files, key=lambda path: path.relative_to(root).as_posix())


def fingerprint(root: Path = ROOT) -> str:
    digest = hashlib.sha256()
    for path in contract_files(root):
        digest.update(path.relative_to(root).as_posix().encode("utf-8") + b"\0")
        # Line endings depend on the checkout, not on the contract.
        content = path.read_bytes().replace(b"\r\n", b"\n")
        digest.update(len(content).to_bytes(8, "big") + content)
    return digest.hexdigest()


def read(path: Path = COMPATIBILITY) -> tuple[int, str | None, int | None]:
    """The declared version, the recorded fingerprint and the version it was recorded for."""
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition(" ")
        values[key] = value.strip()
    version = values.get("version", "")
    if not re.fullmatch(r"[1-9][0-9]*", version) or int(version) > MAX_VERSION:
        raise CompatibilityError(f"{path.name}: 'version' must be a positive integer")
    recorded = values.get("contract")
    if recorded is not None and not re.fullmatch(r"[0-9a-f]{64}", recorded):
        raise CompatibilityError(f"{path.name}: 'contract' must be a SHA-256")
    recorded_for = values.get("recorded-for")
    if recorded_for is not None and not re.fullmatch(r"[1-9][0-9]*", recorded_for):
        raise CompatibilityError(f"{path.name}: 'recorded-for' must be a version")
    return int(version), recorded, None if recorded_for is None else int(recorded_for)


def recorded_shared_git(path: Path = COMPATIBILITY) -> str | None:
    """The processtree revision the record was made for, if any."""
    for line in path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.strip().partition(" ")
        if key == "processtree":
            return value.strip()
    return None


def shared_git_pin(root: Path = ROOT) -> str | None:
    """The processtree revision pinned in rust-core/Cargo.toml."""
    manifest = root / "rust-core" / "Cargo.toml"
    if not manifest.is_file():
        return None
    match = _PROCESSTREE_REV.search(manifest.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def shared_git_decision(previous: str | None, current: str | None, version: int) -> str:
    return (
        f"The processtree pin moved from {(previous or 'none')[:12]} to {(current or 'none')[:12]}.\n"
        "The helper runs processtree's telemetry. If the move changes what the helper\n"
        f"does, raise 'version' to {version + 1} and run\n"
        "  python3 scripts/check_helper_compatibility.py --record\n"
        "If it cannot, keep the version with\n"
        "  python3 scripts/check_helper_compatibility.py --record --keep-shared-git"
    )


def helper_id(version: int) -> str:
    """The 40-digit ID a helper of ``version`` reports and is installed under."""
    return str(version).rjust(40, "0")


def check(root: Path = ROOT, path: Path = COMPATIBILITY) -> str:
    version, recorded, recorded_for = read(path)
    current = fingerprint(root)
    pin = shared_git_pin(root)
    recorded_pin = recorded_shared_git(path)
    if recorded == current and recorded_for == version and pin != recorded_pin:
        raise CompatibilityError(shared_git_decision(recorded_pin, pin, version))
    if recorded == current and recorded_for == version:
        return f"remote helper compatibility {version}: contract unchanged"
    if recorded != current and recorded_for == version:
        raise CompatibilityError(
            "The remote helper's contract changed but its compatibility version did not.\n"
            f"Raise 'version' in {path.relative_to(root)} to {version + 1}, then run\n"
            "  python3 scripts/check_helper_compatibility.py --record\n"
            "Hosts then receive the new helper on their next connection. If the change cannot\n"
            "alter what the helper does (tests, documentation, a refactor with identical\n"
            "output), keep the version with\n"
            "  python3 scripts/check_helper_compatibility.py --record --keep-version"
        )
    raise CompatibilityError(
        f"The compatibility record in {path.relative_to(root)} is stale; run\n"
        "  python3 scripts/check_helper_compatibility.py --record"
    )


def record(
    root: Path = ROOT,
    path: Path = COMPATIBILITY,
    *,
    keep_shared_git: bool = False,
    keep_version: bool = False,
) -> str:
    version, recorded, recorded_for = read(path)
    current = fingerprint(root)
    if recorded is not None and recorded != current and recorded_for == version and not keep_version:
        raise CompatibilityError(
            "The helper's contract changed: raise 'version' before recording.\n"
            "A changed contract with an unchanged version would connect new clients to\n"
            "helpers that do not understand them. If the change cannot alter what the\n"
            "helper does (tests, documentation, a refactor with identical output), keep the\n"
            "version with\n"
            "  python3 scripts/check_helper_compatibility.py --record --keep-version"
        )
    pin = shared_git_pin(root)
    recorded_pin = recorded_shared_git(path)
    if (
        recorded is not None
        and recorded_for == version
        and pin != recorded_pin
        and not keep_shared_git
    ):
        raise CompatibilityError(shared_git_decision(recorded_pin, pin, version))
    shared = "" if pin is None else f"processtree {pin}\n"
    path.write_text(
        f"{HEADER}version {version}\ncontract {current}\nrecorded-for {version}\n{shared}",
        encoding="utf-8",
    )
    return f"recorded remote helper compatibility {version}"


def self_test() -> str:
    """Exercises check and record on a scratch copy of the fingerprinted tree."""
    with tempfile.TemporaryDirectory(prefix="processlama-compat-") as scratch:
        root = Path(scratch)
        for path in contract_files(ROOT):
            target = root / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        shutil.copy2(ROOT / "rust-core" / "Cargo.toml", root / "rust-core" / "Cargo.toml")
        compat = root / "rust-core" / "remote-helper" / "COMPATIBILITY"
        compat.write_text(HEADER + "version 3\n", encoding="utf-8")

        def expect_failure(action, fragment: str) -> None:
            try:
                action()
            except CompatibilityError as error:
                assert fragment in str(error), str(error)
                return
            raise AssertionError(f"expected a failure containing {fragment!r}")

        expect_failure(lambda: check(root, compat), "stale")
        record(root, compat)
        assert "unchanged" in check(root, compat)
        source = root / "rust-core" / "remote-helper" / "src" / "main.rs"
        source.write_text(source.read_text(encoding="utf-8") + "\n// change\n", encoding="utf-8")
        expect_failure(lambda: check(root, compat), "Raise 'version'")
        expect_failure(lambda: record(root, compat), "raise 'version'")
        record(root, compat, keep_version=True)
        assert "unchanged" in check(root, compat)
        compat.write_text(compat.read_text(encoding="utf-8").replace("version 3", "version 4"), encoding="utf-8")
        expect_failure(lambda: check(root, compat), "stale")
        record(root, compat)
        assert "compatibility 4" in check(root, compat)
        manifest = root / "rust-core" / "Cargo.toml"
        text = manifest.read_text(encoding="utf-8")
        current = shared_git_pin(root)
        assert current is not None
        manifest.write_text(text.replace(current, "0" * 40), encoding="utf-8")
        expect_failure(lambda: check(root, compat), "processtree pin moved")
        record(root, compat, keep_shared_git=True)
        assert "unchanged" in check(root, compat)
        assert helper_id(4) == "0" * 39 + "4"
    return "compatibility checker self-test passed"


def main(arguments: list[str]) -> int:
    try:
        if arguments == ["--self-test"]:
            print(self_test())
        elif arguments == ["--record"]:
            print(record())
        elif arguments == ["--record", "--keep-shared-git"]:
            print(record(keep_shared_git=True))
        elif arguments == ["--record", "--keep-version"]:
            print(record(keep_version=True))
        elif not arguments:
            print(check())
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except CompatibilityError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
