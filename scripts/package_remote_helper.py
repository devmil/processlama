#!/usr/bin/env python3
"""Packages, transfers and bundles processlama-remote-helper builds.

Adapted from GitLama's scripts/package_remote_helper.py.

  package --target T --binary B --output DIR [--no-archive] [--development]
      Writes DIR/T/processlama-remote-helper, its descriptor
      DIR/T/processlama-remote-helper.json and a reproducible
      DIR/processlama-remote-helper-T.tar.gz. Linux binaries must not need a glibc newer
      than 2.35 (checked with objdump -T). --development (the build hook's helper for this
      computer) records the binary's glibc requirement without enforcing the floor.

  unpack --archives DIR --output DIR
      Extracts downloaded processlama-remote-helper-*.tar.gz artifacts.

  bundle --source DIR --dest DIR [--require]
      Verifies every descriptor in DIR against its binary and this tree's build ID and
      copies the helpers into an application package (mode 0644). --require (or
      PROCESSLAMA_REQUIRE_REMOTE_HELPER=1) fails unless all four targets are present.

  refresh --dir DIR
      Rewrites the descriptors after the binaries were re-signed in place (macOS).

The descriptor lets the application validate a helper before installing it: schema,
target, build ID, compatibility version, size and SHA-256.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "tooling" / "remote_wire" / "contract.json"
COMPATIBILITY = ROOT / "rust-core" / "remote-helper" / "COMPATIBILITY"
BINARY = "processlama-remote-helper"
DESCRIPTOR = f"{BINARY}.json"
SCHEMA = 1
GLIBC_FLOOR = (2, 35)
MACOS_MINIMUM = "macOS 13"

OBJDUMPS = {
    "linux-x86_64": ("objdump", "x86_64-linux-gnu-objdump"),
    "linux-arm64": ("aarch64-linux-gnu-objdump", "objdump"),
}
ELF_MACHINES = {"linux-x86_64": 62, "linux-arm64": 183}
MACHO_CPU = {"macos-x86_64": 0x01000007, "macos-arm64": 0x0100000C}


class PackageError(Exception):
    pass


def contract() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


def targets() -> list[str]:
    return [target["name"] for target in contract()["targets"]]


def helper_limit() -> int:
    return int(contract()["limits"]["helperBytes"]["value"])


def compatibility_version(path: Path = COMPATIBILITY) -> int:
    for line in path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.strip().partition(" ")
        if key == "version":
            return int(value)
    raise PackageError("COMPATIBILITY declares no version")


def build_id(version: int) -> str:
    return str(version).rjust(40, "0")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_format(target: str, data: bytes) -> None:
    """The binary's executable format and machine must match the target."""
    if target.startswith("linux-"):
        if data[:4] != b"\x7fELF" or data[4] != 2:
            raise PackageError(f"{target}: not a 64-bit ELF executable")
        machine = int.from_bytes(data[18:20], "little")
        if machine != ELF_MACHINES[target]:
            raise PackageError(f"{target}: ELF machine {machine} does not match")
    else:
        if data[:4] != b"\xcf\xfa\xed\xfe":
            raise PackageError(f"{target}: not a 64-bit Mach-O executable")
        cpu = int.from_bytes(data[4:8], "little")
        if cpu != MACHO_CPU[target]:
            raise PackageError(f"{target}: Mach-O CPU {cpu:#x} does not match")


def glibc_requirement(target: str, binary: Path) -> tuple[int, int] | None:
    """The newest GLIBC symbol version the binary needs."""
    last_error = None
    for name in OBJDUMPS[target]:
        tool = shutil.which(name)
        if tool is None:
            continue
        result = subprocess.run([tool, "-T", str(binary)], capture_output=True, text=True)
        if result.returncode != 0:
            last_error = result.stderr.strip().splitlines()[-1:] or ["objdump failed"]
            continue
        versions = {
            (int(major), int(minor))
            for major, minor in re.findall(r"GLIBC_(\d+)\.(\d+)", result.stdout)
        }
        return max(versions) if versions else None
    raise PackageError(
        f"{target}: no objdump can read the binary to check the glibc floor"
        + (f" ({last_error[0]})" if last_error else "")
    )


def describe(target: str, data: bytes, glibc: tuple[int, int] | None) -> dict:
    version = compatibility_version()
    return {
        "schema": SCHEMA,
        "target": target,
        "buildId": build_id(version),
        "compatibility": version,
        "size": len(data),
        "sha256": sha256(data),
        "glibcFloor": None if glibc is None else f"{glibc[0]}.{glibc[1]}",
        "minimumSystem": "glibc 2.35" if target.startswith("linux-") else MACOS_MINIMUM,
    }


def descriptor_bytes(descriptor: dict) -> bytes:
    return (json.dumps(descriptor, indent=2, sort_keys=True) + "\n").encode("utf-8")


# A fixed member time keeps the archives reproducible. It is later than the ZIP epoch
# (1980): an extractor that keeps member times (Windows tar.exe) would otherwise hand
# 1970 files to the Windows packaging, and Compress-Archive cannot store them.
ARCHIVE_MTIME = 946684800  # 2000-01-01T00:00:00Z


def reproducible_tar(members: list[tuple[str, bytes, int]]) -> bytes:
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name, data, mode in sorted(members):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            info.mtime = ARCHIVE_MTIME
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            archive.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0, filename="") as stream:
        stream.write(raw.getvalue())
    return compressed.getvalue()


def package(
    target: str,
    binary: Path,
    output: Path,
    archive: bool = True,
    development: bool = False,
) -> dict:
    if target not in targets():
        raise PackageError(f"unknown target {target}")
    data = binary.read_bytes()
    if not data:
        raise PackageError(f"{target}: the binary is empty")
    if len(data) > helper_limit():
        raise PackageError(f"{target}: {len(data)} bytes exceed the helper limit")
    check_format(target, data)
    glibc = None
    if target.startswith("linux-"):
        glibc = glibc_requirement(target, binary)
        if glibc is not None and glibc > GLIBC_FLOOR and not development:
            raise PackageError(
                f"{target}: needs glibc {glibc[0]}.{glibc[1]}, newer than the "
                f"{GLIBC_FLOOR[0]}.{GLIBC_FLOOR[1]} floor"
            )
    descriptor = describe(target, data, glibc)
    directory = output / target
    directory.mkdir(parents=True, exist_ok=True)
    helper = directory / BINARY
    helper.write_bytes(data)
    helper.chmod(0o755)
    (directory / DESCRIPTOR).write_bytes(descriptor_bytes(descriptor))
    if archive:
        (output / f"{BINARY}-{target}.tar.gz").write_bytes(
            reproducible_tar(
                [
                    (f"{target}/{BINARY}", data, 0o755),
                    (f"{target}/{DESCRIPTOR}", descriptor_bytes(descriptor), 0o644),
                ]
            )
        )
    return descriptor


def unpack(archives: Path, output: Path) -> list[str]:
    found = []
    names = {f"{target}/{name}" for target in targets() for name in (BINARY, DESCRIPTOR)}
    for path in sorted(archives.rglob(f"{BINARY}-*.tar.gz")):
        with tarfile.open(path, "r:gz") as archive:
            for member in archive.getmembers():
                if member.name not in names or not member.isfile():
                    raise PackageError(f"{path.name}: unexpected member {member.name!r}")
                target_dir = output / member.name.split("/")[0]
                target_dir.mkdir(parents=True, exist_ok=True)
                data = archive.extractfile(member).read()
                destination = output / member.name
                destination.write_bytes(data)
                destination.chmod(0o755 if member.name.endswith(BINARY) else 0o644)
                if member.name.endswith(BINARY):
                    found.append(member.name.split("/")[0])
    return sorted(found)


def verify(directory: Path, target: str) -> dict:
    descriptor_path = directory / target / DESCRIPTOR
    binary_path = directory / target / BINARY
    descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
    data = binary_path.read_bytes()
    expected = build_id(compatibility_version())
    keys = {"schema", "target", "buildId", "compatibility", "size", "sha256", "glibcFloor", "minimumSystem"}
    if set(descriptor) != keys or descriptor["schema"] != SCHEMA:
        raise PackageError(f"{target}: malformed descriptor")
    if descriptor["target"] != target:
        raise PackageError(f"{target}: descriptor names {descriptor['target']}")
    if descriptor["buildId"] != expected:
        raise PackageError(f"{target}: helper build {descriptor['buildId']} is not {expected}")
    if descriptor["size"] != len(data) or descriptor["sha256"] != sha256(data):
        raise PackageError(f"{target}: the binary does not match its descriptor")
    check_format(target, data)
    return descriptor


def bundle(source: Path, dest: Path, require: bool) -> list[str]:
    present = [t for t in targets() if (source / t / BINARY).is_file()]
    missing = [t for t in targets() if t not in present]
    if require and missing:
        raise PackageError("missing remote helpers: " + ", ".join(missing))
    for target in present:
        verify(source, target)
        directory = dest / target
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / target / BINARY, directory / BINARY)
        # Bundled helpers are data: the app streams their bytes to a host and the install
        # script makes them executable there. Non-executable files are also left alone by
        # package build steps that strip executables, which would break the digest.
        (directory / BINARY).chmod(0o644)
        shutil.copy2(source / target / DESCRIPTOR, directory / DESCRIPTOR)
        (directory / DESCRIPTOR).chmod(0o644)
    return present


def refresh(directory: Path) -> list[str]:
    refreshed = []
    for target in targets():
        binary = directory / target / BINARY
        descriptor_path = directory / target / DESCRIPTOR
        if not binary.is_file():
            continue
        previous = json.loads(descriptor_path.read_text(encoding="utf-8"))
        data = binary.read_bytes()
        check_format(target, data)
        previous.update({"size": len(data), "sha256": sha256(data)})
        descriptor_path.write_bytes(descriptor_bytes(previous))
        refreshed.append(target)
    return refreshed


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    package_parser = commands.add_parser("package")
    package_parser.add_argument("--target", required=True)
    package_parser.add_argument("--binary", type=Path, required=True)
    package_parser.add_argument("--output", type=Path, required=True)
    package_parser.add_argument("--no-archive", action="store_true")
    package_parser.add_argument("--development", action="store_true")
    unpack_parser = commands.add_parser("unpack")
    unpack_parser.add_argument("--archives", type=Path, required=True)
    unpack_parser.add_argument("--output", type=Path, required=True)
    bundle_parser = commands.add_parser("bundle")
    bundle_parser.add_argument("--source", type=Path, required=True)
    bundle_parser.add_argument("--dest", type=Path, required=True)
    bundle_parser.add_argument("--require", action="store_true")
    refresh_parser = commands.add_parser("refresh")
    refresh_parser.add_argument("--dir", type=Path, required=True)
    options = parser.parse_args(arguments)
    try:
        if options.command == "package":
            descriptor = package(
                options.target,
                options.binary,
                options.output,
                not options.no_archive,
                options.development,
            )
            print(f"packaged {descriptor['target']}: {descriptor['size']} bytes, sha256 {descriptor['sha256'][:12]}")
        elif options.command == "unpack":
            print("unpacked " + (", ".join(unpack(options.archives, options.output)) or "nothing"))
        elif options.command == "bundle":
            require = options.require or os.environ.get("PROCESSLAMA_REQUIRE_REMOTE_HELPER") == "1"
            present = bundle(options.source, options.dest, require)
            print("bundled remote helpers: " + (", ".join(present) or "none"))
        elif options.command == "refresh":
            print("refreshed " + (", ".join(refresh(options.dir)) or "nothing"))
    except (PackageError, OSError, json.JSONDecodeError, KeyError) as error:
        print(f"package_remote_helper.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
