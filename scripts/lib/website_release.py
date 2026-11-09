#!/usr/bin/env python3
"""Publish release metadata and render the static downloads page."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
from datetime import date
from pathlib import Path
from urllib.parse import urlparse


def release_name(item: dict) -> str:
    # Older entries predate explicit product metadata. Their immutable artifact
    # names retain the publication identity. Never relabel those releases.
    return str(item.get("productName") or "Mimameidr")


def load_data(path: Path) -> dict:
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    else:
        data = {"latest": None, "history": [], "beta": {"latest": None, "history": []}}
    data["schemaVersion"] = 2
    data.setdefault("history", [])
    data.setdefault("beta", {"latest": None, "history": []})
    data["beta"].setdefault("history", [])
    return data


def artifacts(item: dict) -> list[dict]:
    result = list(item.get("artifacts") or [])
    filename = item.get("file")
    if filename and not any(entry.get("file") == filename for entry in result):
        result.append({
            "file": filename,
            "downloadPath": item.get("downloadPath", f"/download/{filename}"),
            "sha256": item.get("sha256", ""),
            "sizeBytes": item.get("sizeBytes", 0),
            "platform": "macos",
            "format": "dmg",
            "architectures": item.get("architectures", "Apple Silicon & Intel"),
            "minimumSystem": f"macOS {item.get('minMacOS', '14.0')}",
        })
    return result


def publish(args: argparse.Namespace) -> None:
    path = Path(args.data)
    data = load_data(path)
    artifact_path = Path(args.artifact)
    payload = artifact_path.read_bytes()
    new_artifact = {
        "file": artifact_path.name,
        "downloadPath": args.download_url or f"/download/{artifact_path.name}",
        "sha256": hashlib.sha256(payload).hexdigest(),
        "sizeBytes": len(payload),
        "platform": args.platform,
        "format": args.format,
        "architectures": args.architectures,
        "minimumSystem": args.minimum_system,
    }
    if args.sparkle_signature:
        if args.platform != "macos" or args.format != "dmg":
            raise SystemExit("--sparkle-signature is valid only for a macOS DMG")
        new_artifact["sparkleSignature"] = args.sparkle_signature
    track = data if args.channel == "stable" else data["beta"]
    build = int(args.build)
    candidates = [track.get("latest"), *(track.get("history") or [])]
    entry = next((item for item in candidates if item and item.get("version") == args.version and int(item.get("build", 0)) == build), None)
    if entry is None:
        previous = track.get("latest")
        if previous:
            track["history"] = [previous] + [item for item in track["history"] if not (item.get("version") == previous.get("version") and item.get("build") == previous.get("build"))]
        entry = {"version": args.version, "build": build, "released": date.today().isoformat(), "notesPath": args.notes_path, "channel": args.channel, "productName": "ProcessLama", "artifacts": []}
        if args.channel == "beta":
            entry["supersededByStable"] = False
        track["latest"] = entry
    elif track.get("latest") is not entry:
        track["history"] = [item for item in track["history"] if item is not entry]
        previous = track.get("latest")
        if previous:
            track["history"].insert(0, previous)
        track["latest"] = entry

    entry["notesPath"] = args.notes_path
    entry["artifacts"] = [item for item in artifacts(entry) if not (item.get("platform") == args.platform and item.get("format") == args.format and item.get("architectures") == args.architectures)]
    entry["artifacts"].append(new_artifact)
    for key in ("file", "downloadPath", "sha256", "sizeBytes", "minMacOS", "architectures"):
        entry.pop(key, None)

    if args.channel == "stable":
        base = args.version.split("-", 1)[0]
        beta = data["beta"]
        for item in [beta.get("latest"), *(beta.get("history") or [])]:
            if item and str(item.get("version", "")).split("-", 1)[0] == base and int(item.get("build", 0)) < build:
                item["supersededByStable"] = True
    track["history"] = track["history"][:4]
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def size_label(value: int | None) -> str:
    size = float(value or 0)
    units = ["B", "KB", "MB", "GB"]
    unit = 0
    while size >= 1024 and unit < len(units) - 1:
        size /= 1024
        unit += 1
    return f"{size:.1f} {units[unit]}" if unit else f"{int(size)} B"


FORMAT_LABELS = {
    "appimage": "AppImage",
    "rpm": "RPM",
    "deb": "DEB",
    "tar": "Portable tarball",
    "dmg": "DMG",
    "msi": "Windows installer",
    "zip": "Portable ZIP",
}
# Who a format is for, and the marks shown beside it (CSS classes `os-<name>`
# in website/styles.css).
FORMAT_HINTS = {
    "appimage": "Single file, no install",
    "rpm": "Fedora",
    "deb": "Debian, Ubuntu",
    "tar": "Unpack and run",
    "dmg": "Disk image",
    "msi": "Installer",
    "zip": "Unpack and run",
}
FORMAT_ICONS = {
    "appimage": ("package",),
    "rpm": ("fedora",),
    "deb": ("debian", "ubuntu"),
    "tar": ("archive",),
    "dmg": ("apple",),
    "msi": ("windows",),
    "zip": ("archive",),
}
INSTALL_COMMANDS = {
    "appimage": "chmod +x {file} && ./{file}",
    "rpm": "sudo dnf install ./{file}",
    "deb": "sudo apt install ./{file}",
    "tar": "tar -xzf {file}",
}
PLATFORM_LABELS = {"linux": "Linux", "macos": "macOS", "windows": "Windows", "linux-network": "Network service for remote Linux hosts"}
PLATFORM_DETAILS = {
    "linux": "RPM and DEB include the service for per-process network figures. The portable builds can install it from the app.",
    "macos": "Signed and notarized. Updates are installed from inside the app.",
    "windows": "The app checks for new builds and links back to this page.",
    "linux-network": "Install on a Linux host you watch from ProcessLama to see per-process network rates there. Machines with the ProcessLama RPM or DEB already have it.",
}
PLATFORM_ICONS = {"linux": "linux", "macos": "apple", "windows": "windows", "linux-network": "linux"}
# German copy for the downloads page. English stays the page source; site.js
# swaps in these strings from `data-de` attributes when German is chosen.
GERMAN = {
    "Portable tarball": "Portables Tar-Archiv",
    "Windows installer": "Windows-Installationsprogramm",
    "Portable ZIP": "Portables ZIP",
    "Single file, no install": "Eine Datei, ohne Installation",
    "Unpack and run": "Entpacken und starten",
    "Disk image": "Disk-Image",
    "Installer": "Installationsprogramm",
    PLATFORM_DETAILS["linux"]: "RPM und DEB enthalten den Dienst für Netzwerkwerte pro Prozess. Bei den portablen Builds lässt er sich aus der App heraus installieren.",
    PLATFORM_DETAILS["macos"]: "Signiert und notarisiert. Updates werden direkt in der App installiert.",
    PLATFORM_DETAILS["windows"]: "Die App sucht nach neuen Builds und verweist dann auf diese Seite.",
    PLATFORM_LABELS["linux-network"]: "Netzwerkdienst für entfernte Linux-Hosts",
    PLATFORM_DETAILS["linux-network"]: "Installiere ihn auf einem Linux-Host, den du mit ProcessLama beobachtest, um dort Netzwerkwerte pro Prozess zu sehen. Rechner mit dem RPM oder DEB von ProcessLama haben ihn bereits.",
    "Desktop release bundle.": "Desktop-Release-Paket.",
    "Your system": "Dein System",
    "Copy": "Kopieren",
    "Shell": "Shell",
    "Stable": "Stabil",
    "Beta": "Beta",
    "No build published yet.": "Noch kein Build veröffentlicht.",
    "Release notes": "Versionshinweise",
    "superseded by stable": "durch stabile Version ersetzt",
    "Released": "Veröffentlicht am",
    "Build": "Build",
    "build": "Build",
    "Bundles are being built for this release.": "Die Pakete für dieses Release werden gerade gebaut.",
    "bundles pending": "Pakete folgen",
    "Earlier stable builds": "Frühere stabile Builds",
    "Earlier beta builds": "Frühere Beta-Builds",
}


def german(text: str, attribute: str = "") -> str:
    """A `data-de` attribute carrying the German form of `text`, if known."""
    value = GERMAN.get(text)
    if value is None:
        return ""
    name = f"data-de-{attribute}" if attribute else "data-de"
    return f' {name}="{html.escape(value, quote=True)}"'


def german_words(text: str) -> str:
    """German for a phrase made of known parts, e.g. `Download DMG`."""
    return html.escape(GERMAN.get(text, text), quote=True)


FOOTER_LEGAL_LINKS = (
    '<a href="imprint.html" data-de="Impressum" data-de-href="de/imprint.html">Imprint</a>'
    '<a href="privacy.html" data-de="Datenschutz" data-de-href="de/privacy.html">Privacy</a>'
)
LANGUAGE_SWITCH = (
    '<div class="lang-switch seg" role="group" aria-label="Language" data-de-aria-label="Sprache" data-needs-js>'
    '<button type="button" lang="en" data-lang="en" aria-pressed="true">EN</button>'
    '<button type="button" lang="de" data-lang="de" aria-pressed="false">DE</button></div>'
)
DOWNLOAD_ICON = '<svg class="icon" viewBox="0 0 24 24"><path d="M12 15V3"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/></svg>'


def os_icon(name: str) -> str:
    return f'<span class="os-icon os-{html.escape(name)}"></span>'


def copy_row(label: str, value: str) -> str:
    escaped = html.escape(value, quote=True)
    return f'<div class="copy-row"><span>{label}</span><code>{escaped}</code><button class="copy" type="button" data-copy="{escaped}" aria-label="Copy {label}" data-de-aria-label="{label} kopieren"{german("Copy")}>Copy</button></div>'


def minimum_system(item: dict) -> str:
    """The minimum system, unless it only repeats the platform heading."""
    value = str(item.get("minimumSystem", ""))
    return "" if value == PLATFORM_LABELS.get(str(item.get("platform", ""))) else value


def artifact_html(item: dict) -> str:
    kind = str(item.get("format", ""))
    path = html.escape(str(item.get("downloadPath", "#")).lstrip("/"))
    english_label = FORMAT_LABELS.get(kind, kind.upper() or "file")
    label = html.escape(english_label)
    parts = (FORMAT_HINTS.get(kind, ""), str(item.get("architectures", "")), minimum_system(item), size_label(item.get("sizeBytes")))
    detail = " · ".join(part for part in parts if part)
    # German writes a decimal comma and keeps the number with its unit.
    german_parts = (*parts[:-1], parts[-1].replace(".", ",").replace(" ", " "))
    german_detail = " · ".join(GERMAN.get(part, part) for part in german_parts if part)
    icons = "".join(os_icon(name) for name in FORMAT_ICONS.get(kind, ("archive",)))
    rows = []
    if item.get("sha256"):
        rows.append(copy_row("SHA-256", str(item["sha256"])))
    if kind in INSTALL_COMMANDS and item.get("file"):
        command = INSTALL_COMMANDS[kind].format(file=item["file"])
        if item.get("platform") == "linux-network" and kind == "tar":
            # The service archive unpacks into a directory with its installer.
            command += f" && sudo ./{str(item['file']).removesuffix('.tar.gz')}/install.sh"
        rows.append(copy_row("Shell", command))
    extra = f'<div class="file-extra">{"".join(rows)}</div>' if rows else ""
    return f'''<li class="file">
      <a class="file-link" href="{path}"><span class="file-icons" aria-hidden="true">{icons}</span><span class="file-main"><strong data-de="{german_words(english_label)} herunterladen">Download {label}</strong><span data-de="{html.escape(german_detail, quote=True)}">{html.escape(detail)}</span></span><span class="file-get" aria-hidden="true">{DOWNLOAD_ICON}</span></a>
      {extra}
    </li>'''


def platform_heading(platform: str) -> str:
    label = html.escape(PLATFORM_LABELS.get(platform, platform.title()))
    english_detail = PLATFORM_DETAILS.get(platform, "Desktop release bundle.")
    detail = html.escape(english_detail)
    icon = os_icon(PLATFORM_ICONS.get(platform, "archive"))
    return f'''<div class="os-head">
      <span class="os-mark" aria-hidden="true">{icon}</span>
      <div><h3{german(PLATFORM_LABELS.get(platform, ""))}>{label}</h3></div>
      <span class="chip accent" data-yours hidden{german("Your system")}>Your system</span>
      <p class="os-note"{german(english_detail)}>{detail}</p>
    </div>'''


def release_card(item: dict | None, heading: str) -> str:
    if not item:
        return f'<section class="release-empty"><h2{german(heading)}>{heading}</h2><p{german("No build published yet.")}>No build published yet.</p></section>'
    grouped: dict[str, list[dict]] = {}
    for artifact in artifacts(item):
        grouped.setdefault(str(artifact.get("platform", "other")), []).append(artifact)
    order = {"msi": 0, "rpm": 0, "dmg": 0, "deb": 1, "zip": 1, "appimage": 2, "tar": 3}
    downloads = []
    leading = ("macos", "linux", "windows", "linux-network")
    for platform in (*leading, *sorted(set(grouped) - set(leading))):
        if platform in grouped:
            rows = "".join(artifact_html(entry) for entry in sorted(grouped[platform], key=lambda entry: order.get(str(entry.get("format")), 9)))
            downloads.append(f'<section class="os-card island" data-platform="{html.escape(platform)}">{platform_heading(platform)}<ul class="file-list">{rows}</ul></section>')
    notes = html.escape(str(item.get("notesPath", "")).lstrip("/"))
    notes_link = f' · <a href="{notes}"{german("Release notes")}>Release notes</a>' if notes else ""
    superseded = f' · <span{german("superseded by stable")}>superseded by stable</span>' if item.get("supersededByStable") else ""
    return f'''<section class="release-card">
      <div class="release-card-heading"><h2>{html.escape(release_name(item))} {html.escape(str(item.get("version", "")))}</h2><span class="chip"{german(heading)}>{heading}</span><span class="chip">Build {html.escape(str(item.get("build", "")))}</span></div>
      <p class="release-meta"><span{german("Released")}>Released</span> {html.escape(str(item.get("released", "")))}{superseded}{notes_link}</p>
      {'<div class="os-list">' + ''.join(downloads) + '</div>' if downloads else f'<p{german("Bundles are being built for this release.")}>Bundles are being built for this release.</p>'}
    </section>'''


def history_list(items: list[dict], title: str) -> str:
    if not items:
        return ""
    rows = []
    for item in items:
        platforms = ", ".join(PLATFORM_LABELS.get(key, key.title()) for key in sorted({str(a.get("platform")) for a in artifacts(item)})) or "bundles pending"
        german_platforms = german(platforms)
        links = "".join(
            f'<a class="chip" href="{html.escape(str(artifact.get("downloadPath", "#")).lstrip("/"))}"{german(FORMAT_LABELS.get(str(artifact.get("format", "")), ""))}>{html.escape(FORMAT_LABELS.get(str(artifact.get("format", "")), str(artifact.get("format", "")).upper()))}</a>'
            for artifact in artifacts(item)
        )
        rows.append(f'<li><div class="history-version">{html.escape(str(item.get("version", "")))}<span><span{german("build")}>build</span> {html.escape(str(item.get("build", "")))} · {html.escape(str(item.get("released", "")))}</span><span{german_platforms}>{html.escape(platforms)}</span></div><div class="history-files">{links}</div></li>')
    return f'<section class="release-history"><h2{german(title)}>{title}</h2><ul class="island">{"".join(rows)}</ul></section>'


# Every mutable resource a page or its manifest names: styles, scripts, the
# manifest, favicons, brand artwork and icons. Absolute URLs (social images)
# are versioned too, so recoloured artwork never waits for cache expiry.
SITE_URL = "https://devmil.de/processlama/"
VERSIONED_ASSET = r'styles\.css|site\.js|site\.webmanifest|favicon\.ico|assets/(?:lama|brand|icons)/[A-Za-z0-9._-]+\.(?:css|js|svg|png)'


def version_asset_references(document: str, root: Path, pending: dict[str, str] | None = None) -> str:
    """Name each asset with its content digest; `pending` holds unwritten text."""
    def replace(match: re.Match) -> str:
        attribute, prefix, name = match.groups()
        asset = root / name
        if pending and name in pending:
            payload = pending[name].encode("utf-8")
        elif asset.is_file():
            payload = asset.read_bytes()
        else:
            return match.group(0)
        return f'{attribute}="{prefix}{name}?v={hashlib.sha256(payload).hexdigest()[:12]}"'

    # Pages in a language folder (de/) climb to the root with `../`.
    return re.sub(rf'(href|src|content)="({re.escape(SITE_URL)}|(?:\.\./)*)({VERSIONED_ASSET})(?:\?[^"]*)?"', replace, document)


def version_manifest_icons(manifest: str, root: Path) -> str:
    def replace(match: re.Match) -> str:
        name = match.group(1)
        asset = root / name
        if not asset.is_file():
            return match.group(0)
        return f'"src": "{name}?v={hashlib.sha256(asset.read_bytes()).hexdigest()[:12]}"'

    return re.sub(r'"src": "(assets/icons/[A-Za-z0-9._-]+\.png)(?:\?[^"]*)?"', replace, manifest)


# Every hand-written or generated page that names versioned assets. The legal
# pages exist once per language; German lives in de/.
PAGES = ("index.html", "releases.html", "remote-hosts.html", "imprint.html", "privacy.html", "de/remote-hosts.html", "de/imprint.html", "de/privacy.html")


def versioned_site(root: Path) -> dict[Path, str]:
    """Return the manifest and every page with current content digests.

    The manifest versions its icons first; its final text then names it.
    """
    result, pending = {}, {}
    manifest = root / "site.webmanifest"
    if manifest.is_file():
        result[manifest] = pending[manifest.name] = version_manifest_icons(manifest.read_text(encoding="utf-8"), root)
    for page in [root / name for name in PAGES]:
        if page.is_file():
            result[page] = version_asset_references(page.read_text(encoding="utf-8"), root, pending)
    return result


def version_site(root: Path) -> None:
    for path, text in versioned_site(root).items():
        path.write_text(text, encoding="utf-8")


def render(args: argparse.Namespace) -> None:
    data = load_data(Path(args.data))
    beta = data.get("beta") or {}
    # The channel that has a build leads; an empty channel is a one-line note.
    cards = [release_card(data.get("latest"), "Stable"), release_card(beta.get("latest"), "Beta")]
    if not data.get("latest") and beta.get("latest"):
        cards.reverse()
    document = f'''<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="description" content="Download ProcessLama for macOS, Linux, and Windows." data-de-content="ProcessLama für macOS, Linux und Windows herunterladen."><title data-de="ProcessLama herunterladen">Download ProcessLama</title><link rel="canonical" href="https://devmil.de/processlama/releases.html"><link rel="icon" href="favicon.ico" sizes="any"><link rel="icon" href="assets/brand/processlama-icon.svg" type="image/svg+xml"><link rel="apple-touch-icon" sizes="180x180" href="assets/icons/apple-touch-icon.png"><meta name="theme-color" content="#e8ecee" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#0b151a" media="(prefers-color-scheme: dark)"><link rel="stylesheet" href="styles.css"><script>document.documentElement.classList.add("js");</script><script src="site.js" defer></script></head>
  <body>
    <a class="skip-link" href="#main" data-de="Zum Inhalt springen">Skip to content</a>
    <header class="site-header"><nav aria-label="Main" data-de-aria-label="Hauptnavigation"><a class="brand" href="index.html"><img class="brand-mark" src="assets/brand/processlama-icon.svg" alt="" width="28" height="28"><span class="brand-name">ProcessLama</span></a><div class="nav-links"><a class="nav-section" href="index.html#window" data-de="Fenster">Window</a><a class="nav-section" href="index.html#features" data-de="Funktionen">Features</a><a class="nav-cta" href="releases.html" aria-current="page">Download</a></div>{LANGUAGE_SWITCH}</nav></header>
    <main id="main"><section class="page-hero"><div class="page"><p class="eyebrow">Downloads</p><h1><span data-de="ProcessLama herunterladen.">Download ProcessLama.</span> <span class="soft" data-de="Jede Datei, jeder Build.">Every file, every build.</span></h1><p class="lede" data-de="Dateien für macOS, Linux und Windows, jeweils mit SHA-256-Prüfsumme. Unter macOS aktualisiert sich die App selbst; unter Linux und Windows verweist sie hierher, sobald ein neuer Build bereitsteht.">Files for macOS, Linux, and Windows, each with its SHA-256 checksum. macOS updates itself; on Linux and Windows the app links back here when a new build is ready.</p></div></section><section class="page release-page">{"".join(cards)}{history_list(data.get("history") or [], "Earlier stable builds")}{history_list(beta.get("history") or [], "Earlier beta builds")}</section></main>
    <footer class="site-footer"><span class="footer-brand"><img src="assets/brand/processlama-icon.svg" alt="" width="20" height="20">ProcessLama</span><span class="footer-links"><a href="index.html" data-de="Startseite">Home</a><a href="download/appcast.xml" data-de="macOS-Appcast">macOS appcast</a>{FOOTER_LEGAL_LINKS}</span><span class="footer-maker"><span class="signature" aria-hidden="true"></span><span data-de="by Devmil Solutions. Basiert auf Meridian. Zu jedem Download gibt es eine SHA-256-Prüfsumme.">by Devmil Solutions. Built on Meridian. Every download has a SHA-256 checksum.</span></span></footer>
  </body>
</html>
'''
    output = Path(args.output)
    output.write_text(document, encoding="utf-8")
    version_site(output.parent)
    if output.name != "releases.html":
        output.write_text(version_asset_references(document, output.parent), encoding="utf-8")


def render_inline(source: str) -> str:
    token_re = re.compile(r"(`[^`]+`|\*\*.+?\*\*|\[[^\]]+\]\([^)]+\))")
    chunks, position = [], 0
    for match in token_re.finditer(source):
        chunks.append(html.escape(source[position:match.start()]))
        token = match.group(0)
        if token.startswith("`"):
            chunks.append(f"<code>{html.escape(token[1:-1])}</code>")
        elif token.startswith("**"):
            chunks.append(f"<strong>{render_inline(token[2:-2])}</strong>")
        else:
            link = re.match(r"^\[([^\]]+)\]\(([^)]+)\)$", token)
            parsed = urlparse(link.group(2).strip()) if link else None
            chunks.append(f'<a href="{html.escape(link.group(2), quote=True)}">{render_inline(link.group(1))}</a>' if link and (not parsed.scheme or parsed.scheme in {"http", "https", "mailto"}) else html.escape(token))
        position = match.end()
    chunks.append(html.escape(source[position:]))
    return "".join(chunks)


# Release notes are English; Sparkle shows them inside the app as well.
RELEASE_NOTES_LEGAL_LINKS = '<p><a href="../imprint.html">Imprint</a> · <a href="../privacy.html">Privacy</a></p>'


def notes(args: argparse.Namespace) -> None:
    source = Path(args.notes).read_text(encoding="utf-8")
    match = re.search(rf"^## \[{re.escape(args.version)}\][^\n]*\n(.*?)(?=^## \[|\Z)", source, re.M | re.S)
    if not match:
        raise SystemExit(f"release-notes-html: no [{args.version}] section in {args.notes}")
    chunks, list_items = [], []
    def flush() -> None:
        if list_items:
            chunks.append("<ul>" + "".join(list_items) + "</ul>"); list_items.clear()
    for raw in match.group(1).strip().splitlines():
        line = raw.rstrip()
        if not line:
            flush()
        elif line.startswith("### "):
            flush(); chunks.append(f"<h3>{render_inline(line[4:].strip())}</h3>")
        elif line.startswith("- "):
            list_items.append(f"<li>{render_inline(line[2:].strip())}</li>")
        elif not re.match(r"^\[[^\]]+\]:", line):
            flush(); chunks.append(f"<p>{render_inline(line)}</p>")
    flush()
    output = "\n".join(["<!doctype html>", '<html lang="en">', f'<head><meta charset="utf-8"><title>ProcessLama {html.escape(args.version)}</title></head>', "<body>", f"<h2>ProcessLama {html.escape(args.version)}</h2>", *chunks, '<p><a href="../releases.html">Full release archive</a></p>', RELEASE_NOTES_LEGAL_LINKS, "</body>", "</html>", ""])
    Path(args.output).write_text(output, encoding="utf-8")


def make_parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    command = commands.add_parser("publish")
    for name in ("data", "version", "build", "channel", "artifact", "platform", "format", "architectures", "minimum-system", "notes-path"):
        command.add_argument(f"--{name}", required=name != "minimum-system", default="")
    command.add_argument("--download-url", default="")
    command.add_argument("--sparkle-signature", default="")
    command.set_defaults(func=publish)
    command = commands.add_parser("render"); command.add_argument("--data", required=True); command.add_argument("--output", required=True); command.set_defaults(func=render)
    command = commands.add_parser("notes"); command.add_argument("--notes", required=True); command.add_argument("--version", required=True); command.add_argument("--output", required=True); command.set_defaults(func=notes)
    return root


if __name__ == "__main__":
    arguments = make_parser().parse_args()
    arguments.func(arguments)
