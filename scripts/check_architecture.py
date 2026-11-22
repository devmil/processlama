#!/usr/bin/env python3
"""Enforces ProcessLama's dependency directions.

Rust crates under rust-core/desktop (Cargo dependencies and `use` paths):
- domain depends on no other ProcessLama crate and no Qt bridge.
- application (the use cases and their ports) depends only on domain.
- presentation depends only on domain and application.
- infra-* adapters depend on domain and application (plus the telemetry,
  wire and transport crates), never on each other, presentation or Qt.
- qt (the bridge objects) depends on domain, application and presentation,
  never on an adapter.
- app is the composition root: the only crate that names adapters and Qt.
- The shared transport crate devmil_remote imports no processlama_* crate.

QML (qml/ProcessLama):
- The UI reaches the core only through the AppState bridge (`Store.app`) and
  the tree model; no QML file loads a native plugin or imports a module of
  its own beyond Meridian.

Usage: check_architecture.py [--root DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CRATE_USE = re.compile(r"\b(processlama_[a-z_]+|qtbridge)::")
CARGO_DEPENDENCY = re.compile(r"^\s*([A-Za-z0-9_-]+)\s*=", re.M)
QML_IMPORT = re.compile(r"^\s*import\s+([A-Za-z][\w.]*)", re.M)


# Which ProcessLama crates (and the Qt bridge) each layer may use.
ALLOWED = {
    "domain": set(),
    "application": {"processlama_domain"},
    "presentation": {"processlama_domain", "processlama_application"},
    "infra-local": {"processlama_domain", "processlama_application", "processlama_telemetry"},
    "infra-remote": {"processlama_domain", "processlama_application", "processlama_wire", "devmil_remote"},
    "infra-storage": {"processlama_domain", "processlama_application"},
    "infra-platform": {"processlama_domain", "processlama_application"},
    "qt": {"processlama_domain", "processlama_application", "processlama_presentation", "qtbridge"},
    "app": None,  # the composition root
}

QML_ALLOWED_IMPORTS = re.compile(r"^(Qt\w*(\.\w+)*|Meridian|ProcessLama)$")


def normalize(name: str) -> str:
    return name.replace("-", "_")


def rust_sources(directory: Path):
    for path in sorted(directory.rglob("*.rs")):
        if "target" not in path.relative_to(directory).parts:
            yield path


def dependencies(manifest: Path) -> set[str]:
    text = manifest.read_text(encoding="utf-8")
    names: set[str] = set()
    section = None
    for line in text.splitlines():
        header = re.match(r"^\s*\[([^\]]+)\]", line)
        if header:
            section = header.group(1)
            continue
        if section and section.endswith("dependencies") and not section.startswith("dev-"):
            if "dev-dependencies" in section:
                continue
            match = CARGO_DEPENDENCY.match(line)
            if match:
                names.add(normalize(match.group(1)))
    return names


def check_rust(root: Path) -> list[str]:
    errors: list[str] = []
    desktop = root / "rust-core" / "desktop"
    if desktop.is_dir():
        for crate in sorted(path for path in desktop.iterdir() if (path / "Cargo.toml").is_file()):
            allowed = ALLOWED.get(crate.name)
            if crate.name not in ALLOWED:
                errors.append(f"{crate.relative_to(root)}: unknown desktop layer; add it to check_architecture.py")
                continue
            if allowed is None:
                continue
            own = normalize(f"processlama-{crate.name}")
            for name in sorted(dependencies(crate / "Cargo.toml")):
                if (name.startswith("processlama_") or name == "qtbridge") and name not in allowed and name != own:
                    errors.append(f"{crate.relative_to(root)}/Cargo.toml: {crate.name} must not depend on {name}")
            for source in rust_sources(crate / "src"):
                for name in sorted(set(CRATE_USE.findall(source.read_text(encoding="utf-8")))):
                    if name not in allowed and name != own:
                        errors.append(f"{source.relative_to(root)}: {crate.name} must not use {name}")
    transport = root / "rust-core" / "devmil-remote"
    if transport.is_dir():
        for source in rust_sources(transport / "src"):
            if re.search(r"\bprocesslama_[a-z_]+::", source.read_text(encoding="utf-8")):
                errors.append(f"{source.relative_to(root)}: devmil_remote must not import processlama_* crates")
    return errors


def check_qml(root: Path) -> list[str]:
    errors: list[str] = []
    qml = root / "qml" / "ProcessLama"
    if qml.is_dir():
        for source in sorted(qml.rglob("*.qml")):
            text = source.read_text(encoding="utf-8")
            for uri in QML_IMPORT.findall(text):
                if not QML_ALLOWED_IMPORTS.match(uri):
                    errors.append(f"{source.relative_to(root)}: imports {uri}")
            if re.search(r"Qt\.createQmlObject|loadLibrary|Qt\.include\s*\(", text):
                errors.append(f"{source.relative_to(root)}: loads code at run time")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    root = parser.parse_args().root
    errors = check_rust(root) + check_qml(root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("architecture: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
