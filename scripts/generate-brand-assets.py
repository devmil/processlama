#!/usr/bin/env python3
"""Vendor pinned Lama masters and generate app/website derivatives.

Generation needs rsvg-convert and ImageMagick. --check uses Python only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "resources/brand"
MANIFEST = BRAND / "manifest.json"
MASTERS = [
    "app-icon-mimameidr.svg", "app-icon-mimameidr-desktop.svg", "tile-mimameidr-small.svg",
    # About shows the app tile, like the installed icon.
    "tile-mimameidr.svg",
    "lama-signature.svg", "lama-proud.svg", "lama-resting.svg",
    "lama-standing-nod.svg", "herd-mimameidr.svg",
    # The website hero's antics: extra poses and the shared script.
    "lama-standing.svg", "lama-nod.svg", "lama-proud-shades-up.svg",
    "web/lama-antics.js", "web/lama-antics.css",
    "icon-composer/mimameidr/01-background.svg",
    "icon-composer/mimameidr/02-lama.svg",
    "icon-composer/mimameidr/03-prop.svg",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(source):
    if source:
        source = source.resolve()
        revision = subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
        ).strip()
        for name in MASTERS:
            path = BRAND / name
            path.parent.mkdir(parents=True, exist_ok=True)
            # Copy committed bytes, so local edits cannot be attributed to HEAD.
            folder = "assets" if name.startswith("web/") else "assets/lama"
            path.write_bytes(subprocess.check_output([
                "git", "-C", str(source), "show", f"{revision}:{folder}/{name}"
            ]))
    else:
        revision = json.loads(MANIFEST.read_text())["sourceCommit"]
    outputs = {}

    def record(path, size=None):
        entry = {"sha256": digest(path)}
        if size:
            entry["dimensions"] = list(size)
        outputs[str(path.relative_to(ROOT))] = entry

    def copy(name, dest):
        path = ROOT / dest
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(BRAND / name, path)
        record(path)

    def png(name, dest, size):
        path = ROOT / dest
        path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            "rsvg-convert", "-w", str(size), "-h", str(size),
            "-o", str(path), str(BRAND / name),
        ], check=True)
        record(path, (size, size))
        return path

    icon = "app-icon-mimameidr.svg"
    # Linux, Windows and the macOS fallback apply no mask: use the rounded source.
    desktop = "app-icon-mimameidr-desktop.svg"
    # The icon ground comes from the vendored background layer, never a copy.
    ground = re.search(r'fill="(#[0-9A-Fa-f]{6})"', (BRAND / "icon-composer/mimameidr/01-background.svg").read_text()).group(1)
    srgb = ",".join(f"{int(ground[i:i + 2], 16) / 255:.5f}" for i in (1, 3, 5))
    for name in ["processlama-icon.svg", "processlama-icon-app.svg"]:
        copy(icon, f"resources/logo/{name}")
    copy(icon, "website/assets/brand/processlama-icon.svg")
    for name in [
        "lama-proud.svg", "lama-standing-nod.svg", "lama-signature.svg",
        "lama-standing.svg", "lama-resting.svg", "lama-nod.svg", "lama-proud-shades-up.svg",
        "web/lama-antics.js", "web/lama-antics.css",
    ]:
        copy(name, f"website/assets/lama/{Path(name).name}")
    png(icon, "resources/logo/processlama-icon-app.png", 1024)
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        png("tile-mimameidr-small.svg" if size <= 24 else desktop,
            f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", size)
    png(desktop, "linux/packaging/de.devmil.processlama.png", 512)
    for filename, size in [
        ("favicon-16.png", 16), ("favicon-32.png", 32),
        ("apple-touch-icon.png", 180), ("icon-192.png", 192),
        ("icon-512.png", 512), ("icon-512-maskable.png", 512),
    ]:
        png("tile-mimameidr-small.svg" if size <= 24 else icon,
            f"website/assets/icons/{filename}", size)
    for dest, inputs in [
        ("website/favicon.ico", ["website/assets/icons/favicon-16.png", "website/assets/icons/favicon-32.png"]),
        ("windows/runner/resources/app_icon.ico", [f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png" for size in [16, 32, 64, 128, 256]]),
    ]:
        path = ROOT / dest
        subprocess.run(["magick", *[str(ROOT / p) for p in inputs], str(path)], check=True)
        record(path)
    # Layer package is staged for Icon Composer review. The release still uses
    # the fallback AppIcon catalog until older-system acceptance is complete.
    for name in MASTERS:
        if name.startswith("icon-composer/"):
            copy(name, f"resources/logo/iconapp_icon.icon/Assets/{Path(name).name}")
    composer = ROOT / "resources/logo/iconapp_icon.icon/icon.json"
    composer.write_text(json.dumps({
        "fill": {"solid": f"extended-srgb:{srgb},1.00000"},
        "groups": [{"layers": [
            {"image-name": Path(n).name, "name": Path(n).stem}
            for n in MASTERS if n.startswith("icon-composer/")
        ]}],
        "supported-platforms": {"squares": "shared"},
    }, indent=2) + "\n")
    record(composer)
    # Social image has its own reproducible SVG composition.
    feature = ROOT / "resources/logo/processlama-feature-graphic.svg"
    shutil.copyfile(ROOT / "resources/marketing/feature-graphic.svg", feature)
    record(feature)
    logo = ROOT / "resources/logo/processlama-logo.svg"
    logo.write_text(feature.read_text())
    record(logo)
    feature_png = feature.with_suffix(".png")
    subprocess.run(["rsvg-convert", "-o", str(feature_png), str(feature)], check=True)
    record(feature_png, (1024, 500))
    for path in [feature, feature_png]:
        dest = ROOT / "website/assets/brand" / path.name
        shutil.copyfile(path, dest)
        record(dest, (1024, 500) if path.suffix == ".png" else None)
    MANIFEST.write_text(json.dumps({
        "productName": "ProcessLama", "sourceCommit": revision,
        "sourceRepository": "Devmil/brand, vendored committed masters",
        "generator": "scripts/generate-brand-assets.py",
        "masters": {name: digest(BRAND / name) for name in MASTERS},
        "outputs": outputs,
    }, indent=2) + "\n")


def check():
    from check_marketing_assets import check as check_marketing
    check_marketing()
    manifest = json.loads(MANIFEST.read_text())
    if len(manifest["sourceCommit"]) != 40:
        raise SystemExit("Brand source must name a full Git commit")
    for name, expected in manifest["masters"].items():
        if digest(BRAND / name) != expected:
            raise SystemExit(f"Changed brand master: {name}")
    for name, entry in manifest["outputs"].items():
        path = ROOT / name
        if digest(path) != entry["sha256"]:
            raise SystemExit(f"Stale brand derivative: {name}; run python3 scripts/generate-brand-assets.py")
        if path.suffix == ".png":
            data = path.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n" or list(struct.unpack(">II", data[16:24])) != entry["dimensions"]:
                raise SystemExit(f"Wrong PNG dimensions: {name}")
    print(f"Pinned Lama masters and {len(manifest['outputs'])} derivatives match.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="brand checkout to vendor at its committed HEAD")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check()
    else:
        generate(args.source)
        check()
