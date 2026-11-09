#!/usr/bin/env python3
"""Enforces ProcessLama's dependency directions.

Dart
- Only repository implementations import the generated Rust bridge
  (`lib/rust/`).
- Widgets, app shell, models and repository contracts never import the shared
  transport package `devmil_remote`; services may use its scheduling helpers.
- The shared package `packages/devmil_remote` imports nothing from
  `package:processlama/`.
- Bridge enums are mapped by name, never by indexing `values` with a native
  enum's `index`.

Rust
- No crate except the Flutter build depends on `processlama_core`.
- The shared crate `devmil_remote` imports no `processlama_*` crate.
- Inside `processlama_core`, only the crate root and the generated glue name
  the bridge facade module `crate::api`.

Usage: check_architecture.py [--root DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DART_IMPORT = re.compile(r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""", re.M)
ENUM_INDEX = re.compile(r"\.values\s*\[[^\]]*\.index\s*\]")
RUST_CRATE_USE = re.compile(r"\b(processlama_[a-z_]+)\b")
FACADE_USE = re.compile(r"\bcrate::api\b")
CARGO_DEPENDENCY = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=", re.M)


def dart_files(directory: Path):
    if directory.is_dir():
        yield from sorted(directory.rglob("*.dart"))


def rust_files(directory: Path):
    if directory.is_dir():
        for path in sorted(directory.rglob("*.rs")):
            if "target" not in path.relative_to(directory).parts:
                yield path


def cargo_manifests(workspace: Path):
    if workspace.is_dir():
        for path in sorted(workspace.rglob("Cargo.toml")):
            if "target" not in path.relative_to(workspace).parts:
                yield path


def resolves_into(source: Path, target: str, lib: Path, prefix: Path) -> bool:
    """Whether a Dart import from `source` names a file under `prefix`."""
    if target.startswith("package:processlama/"):
        resolved = lib / target.removeprefix("package:processlama/")
    elif ":" in target:
        return False
    else:
        resolved = (source.parent / target).resolve()
    try:
        resolved.resolve().relative_to(prefix.resolve())
        return True
    except ValueError:
        return False


def dependency_names(manifest: Path) -> set[str]:
    names: set[str] = set()
    section = ""
    for line in manifest.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            section = stripped
            continue
        if "dependencies" in section:
            match = CARGO_DEPENDENCY.match(line)
            if match:
                names.add(match.group(1).replace("-", "_"))
    return names


def check(root: Path) -> list[str]:
    problems: list[str] = []
    lib = root / "lib"
    rust_bridge = lib / "rust"
    repository_impl = lib / "repositories" / "impl"

    transport_free = [
        lib / "screens",
        lib / "widgets",
        lib / "app",
        lib / "models",
        lib / "di",
    ]
    for source in dart_files(lib):
        if source.is_relative_to(rust_bridge):
            continue
        text = source.read_text()
        relative = source.relative_to(root)
        repository_contract = (
            source.parent == lib / "repositories"
        )
        for target in DART_IMPORT.findall(text):
            if not source.is_relative_to(repository_impl):
                if resolves_into(source, target, lib, rust_bridge):
                    problems.append(f"{relative}: imports the Rust bridge ({target})")
            if target.startswith("package:devmil_remote/") and (
                repository_contract
                or any(source.is_relative_to(directory) for directory in transport_free)
            ):
                problems.append(f"{relative}: imports devmil_remote ({target})")
        if ENUM_INDEX.search(text):
            problems.append(f"{relative}: maps an enum through `values[...index]`")

    shared_dart = root / "packages" / "devmil_remote"
    for source in dart_files(shared_dart):
        for target in DART_IMPORT.findall(source.read_text()):
            if target.startswith("package:processlama/"):
                problems.append(
                    f"{source.relative_to(root)}: shared package imports {target}"
                )

    workspace = root / "rust-core"
    core = workspace / "core"
    shared_rust = workspace / "devmil-remote"
    for manifest in cargo_manifests(workspace):
        package_dir = manifest.parent
        names = dependency_names(manifest)
        relative = manifest.relative_to(root)
        if package_dir != core and "processlama_core" in names:
            problems.append(f"{relative}: depends on processlama_core")
        if package_dir == shared_rust:
            for name in sorted(n for n in names if n.startswith("processlama_")):
                problems.append(f"{relative}: shared crate depends on {name}")

    for source in rust_files(workspace):
        text = source.read_text()
        relative = source.relative_to(root)
        crates = set(RUST_CRATE_USE.findall(text))
        if not source.is_relative_to(core) and "processlama_core" in crates:
            problems.append(f"{relative}: uses processlama_core")
        if source.is_relative_to(shared_rust):
            for name in sorted(c for c in crates if c.startswith("processlama")):
                problems.append(f"{relative}: shared crate uses {name}")
        if (
            source.is_relative_to(core / "src")
            and source.name not in {"lib.rs", "frb_generated.rs", "api.rs"}
            and FACADE_USE.search(text)
        ):
            problems.append(f"{relative}: imports the bridge facade crate::api")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    arguments = parser.parse_args()
    problems = check(arguments.root.resolve())
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"architecture check failed: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print("architecture check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
