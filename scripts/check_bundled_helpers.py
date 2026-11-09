#!/usr/bin/env python3
"""Checks that every Linux package in a directory bundles all four remote helpers.

Each package is unpacked into a temporary directory (tar.gz with tarfile, deb with
dpkg-deb, rpm with rpm2cpio/cpio, AppImage with its --appimage-extract), its
lib/remote-helper tree is located, and every helper is verified against its descriptor
and this tree's build ID. Prints the package sizes.

Usage: check_bundled_helpers.py ARCHIVE_DIR
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "package_remote_helper", ROOT / "scripts" / "package_remote_helper.py"
)
helpers = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helpers)


def extract(package: Path, into: Path) -> None:
    name = package.name
    if name.endswith(".tar.gz"):
        with tarfile.open(package, "r:gz") as archive:
            archive.extractall(into, filter="data")
    elif name.endswith(".deb"):
        subprocess.run(["dpkg-deb", "-x", str(package), str(into)], check=True)
    elif name.endswith(".rpm"):
        rpm2cpio = subprocess.Popen(["rpm2cpio", str(package)], stdout=subprocess.PIPE)
        subprocess.run(["cpio", "-idm", "--quiet"], stdin=rpm2cpio.stdout, cwd=into, check=True)
        if rpm2cpio.wait() != 0:
            raise RuntimeError(f"rpm2cpio failed for {name}")
    elif name.endswith(".AppImage"):
        copy = into / name
        shutil.copy2(package, copy)
        copy.chmod(0o755)
        subprocess.run(
            [str(copy), "--appimage-extract"],
            cwd=into,
            check=True,
            stdout=subprocess.DEVNULL,
            env=dict(os.environ, APPIMAGE_EXTRACT_AND_RUN="1"),
        )
        copy.unlink()
    else:
        raise RuntimeError(f"unknown package {name}")


def helper_root(tree: Path) -> Path:
    matches = [path for path in tree.rglob("remote-helper") if path.is_dir() and path.parent.name == "lib"]
    if len(matches) != 1:
        raise RuntimeError(f"expected one lib/remote-helper directory, found {len(matches)}")
    return matches[0]


def main(arguments: list[str]) -> int:
    if len(arguments) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    archive_dir = Path(arguments[0])
    packages = sorted(
        path
        for path in archive_dir.iterdir()
        if path.name.endswith((".tar.gz", ".deb", ".rpm", ".AppImage"))
    )
    if not packages:
        print(f"no Linux packages in {archive_dir}", file=sys.stderr)
        return 1
    failures = 0
    for package in packages:
        with tempfile.TemporaryDirectory(prefix="processlama-bundle-check-") as scratch:
            try:
                extract(package, Path(scratch))
                root = helper_root(Path(scratch))
                for target in helpers.targets():
                    helpers.verify(root, target)
            except Exception as error:  # noqa: BLE001 - report every package
                failures += 1
                print(f"FAIL  {package.name}: {error}")
                continue
        size = package.stat().st_size
        print(f"ok    {package.name}: all four helpers verified ({size / 1048576:.1f} MiB)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
