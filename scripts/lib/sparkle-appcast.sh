# shellcheck shell=bash
# Generate website/download/appcast.xml from signed website release metadata.

# shellcheck source=website-release.sh
source "$(dirname "${BASH_SOURCE[0]}")/website-release.sh"

mim_generate_sparkle_appcast() {
  local require_signing="${1:-1}"
  local data_file appcast_file url_prefix
  data_file="$(mim_website_releases_data)"
  appcast_file="$(mim_website_download_dir)/appcast.xml"
  url_prefix="$(mim_website_release_url_prefix)"
  mkdir -p "$(dirname "$appcast_file")"

  python3 - "$data_file" "$appcast_file" "$url_prefix" "$require_signing" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urljoin

data_path = Path(sys.argv[1])
appcast_path = Path(sys.argv[2])
url_prefix = sys.argv[3]
require_signing = sys.argv[4] == "1"
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)

data = json.loads(data_path.read_text(encoding="utf-8")) if data_path.exists() else {"latest": None, "history": [], "beta": {"latest": None, "history": []}}
items = []
for item in [data.get("latest"), *(data.get("history") or [])]:
    if item:
        items.append(item)
beta = data.get("beta") or {}
for item in [beta.get("latest"), *(beta.get("history") or [])]:
    if item:
        items.append(item)
items.sort(key=lambda item: int(item.get("build", 0)), reverse=True)

rss = ET.Element("rss", {"version": "2.0"})
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "ProcessLama Updates"
ET.SubElement(channel, "link").text = "https://devmil.de/processlama/releases.html"
ET.SubElement(channel, "description").text = "ProcessLama Sparkle appcast"

signed_items = 0
for item in items:
    dmg_artifact = next(
        (
            artifact
            for artifact in item.get("artifacts", [])
            if artifact.get("platform") == "macos" and artifact.get("format") == "dmg"
        ),
        None,
    )
    if dmg_artifact is None and item.get("file", "").endswith(".dmg"):
        dmg_artifact = {"file": item["file"]}
    if dmg_artifact is None:
        continue
    length = str(dmg_artifact.get("sizeBytes", 0))
    signature = str(dmg_artifact.get("sparkleSignature", ""))
    # Metadata created before hosted releases did not retain Sparkle signatures.
    # Keep those releases downloadable, but do not emit unverifiable appcast items.
    if require_signing and not signature:
        continue

    node = ET.SubElement(channel, "item")
    version = str(item["version"])
    build = str(item["build"])
    ET.SubElement(node, "title").text = f"{item.get('productName') or 'Mimameidr'} {version}"
    ET.SubElement(node, "pubDate").text = item.get("released", "")
    notes_path = str(item.get("notesPath") or "").lstrip("/")
    if notes_path:
        ET.SubElement(node, f"{{{ns}}}releaseNotesLink").text = urljoin(url_prefix, Path(notes_path).name)
    ET.SubElement(node, f"{{{ns}}}version").text = build
    ET.SubElement(node, f"{{{ns}}}shortVersionString").text = version
    minimum_system = str(dmg_artifact.get("minimumSystem") or item.get("minMacOS", "14.0"))
    ET.SubElement(node, f"{{{ns}}}minimumSystemVersion").text = minimum_system.removeprefix("macOS ")
    if item.get("channel") == "beta":
        ET.SubElement(node, f"{{{ns}}}channel").text = "beta"
    enclosure_attrs = {
        "url": dmg_artifact.get("downloadPath") or urljoin(url_prefix, dmg_artifact["file"]),
        "length": length,
        "type": "application/octet-stream",
    }
    if signature:
        enclosure_attrs[f"{{{ns}}}edSignature"] = signature
        signed_items += 1
    ET.SubElement(node, "enclosure", enclosure_attrs)

if require_signing and not signed_items:
    raise SystemExit("sparkle-appcast: no signed macOS release is available")

ET.ElementTree(rss).write(appcast_path, encoding="utf-8", xml_declaration=True)
PY
  echo "==> Generated $appcast_file" >&2
}
