import importlib.util
import json
import re
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "website_release", ROOT / "scripts" / "lib" / "website_release.py"
)
website_release = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(website_release)
WEBSITE = ROOT / "website"
STYLES = (WEBSITE / "styles.css").read_text(encoding="utf-8")


class WebsiteReleaseTest(unittest.TestCase):
    def test_publish_records_hosted_url_signature_and_retains_five(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            artifact = root / "ProcessLama-2.0.0-20.dmg"
            artifact.write_bytes(b"dmg")
            history = [self.entry(index) for index in range(19, 13, -1)]
            data.write_text(json.dumps({
                "schemaVersion": 2,
                "latest": self.entry(19),
                "history": history,
                "beta": {"latest": None, "history": []},
            }))
            website_release.publish(Namespace(
                data=str(data), version="2.0.0", build="20", channel="stable",
                artifact=str(artifact), platform="macos", format="dmg",
                architectures="Apple Silicon", minimum_system="macOS 14.0",
                notes_path="/download/notes.html",
                download_url="https://github.example/releases/ProcessLama-2.0.0-20.dmg",
                sparkle_signature="signed-value",
            ))
            result = json.loads(data.read_text())

        self.assertEqual(len(result["history"]), 4)
        stored = result["latest"]["artifacts"][0]
        self.assertEqual(stored["sparkleSignature"], "signed-value")
        self.assertTrue(stored["downloadPath"].startswith("https://github.example/"))

    def test_render_shows_all_platform_logos_and_windows_formats(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            output = root / "releases.html"
            entry = self.entry(20)
            entry["artifacts"] = [
                {"file": "ProcessLama.msi", "platform": "windows", "format": "msi"},
                {"file": "ProcessLama.dmg", "platform": "macos", "format": "dmg"},
                {"file": "ProcessLama.rpm", "platform": "linux", "format": "rpm"},
            ]
            data.write_text(json.dumps({
                "schemaVersion": 2,
                "latest": entry,
                "history": [],
                "beta": {"latest": None, "history": []},
            }))

            website_release.render(Namespace(data=str(data), output=str(output)))
            document = output.read_text()

        for mark in ("windows", "apple", "linux", "fedora"):
            self.assertIn(f'<span class="os-icon os-{mark}"></span>', document)
            self.assertIn(f".os-{mark} {{", STYLES)
            self.assertTrue((WEBSITE / "assets" / "platform" / f"{mark}.svg").is_file())
        self.assertIn("Download Windows installer", document)
        self.assertIn("sudo dnf install ./ProcessLama.rpm", document)

    def test_reworked_assets_get_new_urls_on_both_pages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            output = root / "releases.html"
            data.write_text(json.dumps({"latest": None, "beta": {"latest": None}}))
            (root / "index.html").write_text('<link href="styles.css"><script src="site.js"></script>')
            (root / "styles.css").write_text("body { color: black; }")
            (root / "site.js").write_text("/* previous site */")
            website_release.render(Namespace(data=str(data), output=str(output)))
            previous = re.search(r'src="(site.js[^"]+)"', output.read_text()).group(1)
            (root / "site.js").write_text("/* reworked About dialog */")
            website_release.render(Namespace(data=str(data), output=str(output)))
            current = re.search(r'src="(site.js[^"]+)"', output.read_text()).group(1)
            self.assertNotEqual(previous, current)
            self.assertIn(f'src="{current}"', (root / "index.html").read_text())
            self.assertIn('href="styles.css?v=', output.read_text())

    def test_recoloured_artwork_gets_new_urls_in_pages_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "assets/icons").mkdir(parents=True)
            (root / "assets/brand").mkdir(parents=True)
            (root / "assets/icons/icon-192.png").write_bytes(b"blue icon")
            (root / "assets/brand/processlama-feature-graphic.png").write_bytes(b"blue card")
            (root / "site.webmanifest").write_text('{"icons": [{ "src": "assets/icons/icon-192.png", "sizes": "192x192" }]}')
            (root / "index.html").write_text(
                '<link rel="manifest" href="site.webmanifest">'
                '<meta property="og:image" content="https://devmil.de/processlama/assets/brand/processlama-feature-graphic.png">'
            )
            website_release.version_site(root)
            before = (root / "index.html").read_text()
            manifest_before = (root / "site.webmanifest").read_text()
            self.assertIn('"src": "assets/icons/icon-192.png?v=', manifest_before)
            self.assertIn('content="https://devmil.de/processlama/assets/brand/processlama-feature-graphic.png?v=', before)
            (root / "assets/icons/icon-192.png").write_bytes(b"green icon")
            (root / "assets/brand/processlama-feature-graphic.png").write_bytes(b"green card")
            website_release.version_site(root)
            after = (root / "index.html").read_text()
            self.assertNotEqual(manifest_before, (root / "site.webmanifest").read_text())
            manifest_url = lambda page: re.search(r'href="(site\.webmanifest[^"]*)"', page).group(1)
            card_url = lambda page: re.search(r'content="([^"]*feature-graphic[^"]*)"', page).group(1)
            self.assertNotEqual(manifest_url(before), manifest_url(after))
            self.assertNotEqual(card_url(before), card_url(after))

    def test_published_pages_name_current_asset_digests(self):
        for path, text in website_release.versioned_site(WEBSITE).items():
            self.assertEqual(
                path.read_text(encoding="utf-8"), text,
                f"{path.name} names stale asset digests; run python3 scripts/lib/website_release.py render "
                "--data website/_data/releases.json --output website/releases.html",
            )

    def test_render_leads_with_the_channel_that_has_a_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            output = root / "releases.html"
            entry = self.entry(21)
            entry["channel"] = "beta"
            data.write_text(json.dumps({
                "schemaVersion": 2,
                "latest": None,
                "history": [],
                "beta": {"latest": entry, "history": []},
            }))

            website_release.render(Namespace(data=str(data), output=str(output)))
            document = output.read_text()

        self.assertLess(document.index("ProcessLama 1.0.21"), document.index("No build published yet."))
        self.assertNotIn("release-history", document)

    def test_render_lists_the_network_service_after_the_app_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            output = root / "releases.html"
            entry = self.entry(20)
            entry["artifacts"] = [
                {"file": "processlama-network-service-1.0.0-20-linux-aarch64.rpm", "platform": "linux-network", "format": "rpm", "architectures": "aarch64"},
                {"file": "ProcessLama.rpm", "platform": "linux", "format": "rpm"},
                {"file": "processlama-network-service-1.0.0-20-linux-x86_64.deb", "platform": "linux-network", "format": "deb", "architectures": "x86_64"},
                {"file": "processlama-network-service-1.0.0-20-linux-x86_64.tar.gz", "platform": "linux-network", "format": "tar", "architectures": "x86_64"},
            ]
            data.write_text(json.dumps({
                "schemaVersion": 2,
                "latest": entry,
                "history": [],
                "beta": {"latest": None, "history": []},
            }))

            website_release.render(Namespace(data=str(data), output=str(output)))
            document = output.read_text()

        heading = "Network service for remote Linux hosts"
        self.assertIn(f">{heading}</h3>", document)
        self.assertIn('data-de="Netzwerkdienst für entfernte Linux-Hosts"', document)
        self.assertLess(document.index('data-platform="linux"'), document.index('data-platform="linux-network"'))
        self.assertIn("sudo dnf install ./processlama-network-service-1.0.0-20-linux-aarch64.rpm", document)
        self.assertIn("Fedora · aarch64", document)
        self.assertIn(
            "tar -xzf processlama-network-service-1.0.0-20-linux-x86_64.tar.gz"
            " &amp;&amp; sudo ./processlama-network-service-1.0.0-20-linux-x86_64/install.sh",
            document,
        )

    def test_landing_page_offers_every_published_format(self):
        landing = (WEBSITE / "index.html").read_text(encoding="utf-8")
        for kind in website_release.FORMAT_LABELS:
            self.assertIn(f'data-format="{kind}"', landing)

    def test_every_page_links_the_legal_pages_for_its_language(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = root / "releases.json"
            data.write_text(json.dumps({"latest": None, "beta": {"latest": None}}))
            output = root / "releases.html"
            website_release.render(Namespace(data=str(data), output=str(output)))
            rendered = output.read_text()
            notes = root / "notes.md"
            notes.write_text("## [9.9.9] - 2026-10-10\n### Fixed\n- A thing.\n")
            notes_page = root / "notes.html"
            website_release.notes(Namespace(notes=str(notes), version="9.9.9", output=str(notes_page)))
            notes_html = notes_page.read_text()
        for document in (rendered, (WEBSITE / "index.html").read_text(encoding="utf-8")):
            self.assertIn('href="imprint.html" data-de="Impressum" data-de-href="de/imprint.html"', document)
            self.assertIn('href="privacy.html" data-de="Datenschutz" data-de-href="de/privacy.html"', document)
        for name in ("imprint.html", "privacy.html", "de/imprint.html", "de/privacy.html"):
            page = (WEBSITE / name).read_text(encoding="utf-8")
            self.assertIn('<a href="imprint.html"', page, name)
            self.assertIn('<a href="privacy.html"', page, name)
        for page in [notes_html, *(path.read_text(encoding="utf-8") for path in (WEBSITE / "download").glob("*.html"))]:
            self.assertIn('<a href="../imprint.html">Imprint</a>', page)
            self.assertIn('<a href="../privacy.html">Privacy</a>', page)

    def test_legal_pages_switch_to_their_counterpart(self):
        for name in ("imprint.html", "privacy.html"):
            english = (WEBSITE / name).read_text(encoding="utf-8")
            german = (WEBSITE / "de" / name).read_text(encoding="utf-8")
            self.assertIn('<html lang="en">', english)
            self.assertIn('<html lang="de">', german)
            self.assertIn(f'<a href="de/{name}" lang="de" hreflang="de" data-lang="de">DE</a>', english)
            self.assertIn(f'<a href="{name}" lang="en" hreflang="en" data-lang="en" aria-current="true">EN</a>', english)
            self.assertIn(f'<a href="../{name}" lang="en" hreflang="en" data-lang="en">EN</a>', german)
            self.assertIn(f'<a href="{name}" lang="de" hreflang="de" data-lang="de" aria-current="true">DE</a>', german)
            for page in (english, german):
                self.assertIn('class="contact-email" data-user="info" data-domain="devmil" data-tld="de"', page)

    def test_main_pages_carry_german_copy_and_the_switch(self):
        for name in ("index.html", "releases.html"):
            page = (WEBSITE / name).read_text(encoding="utf-8")
            self.assertIn('<button type="button" lang="de" data-lang="de" aria-pressed="false">DE</button>', page)
            self.assertGreater(page.count(" data-de="), 10, name)
        script = (WEBSITE / "site.js").read_text(encoding="utf-8")
        self.assertIn('const LANGUAGE_KEY = "preferred-language";', script)

    def test_sitemap_lists_every_page(self):
        sitemap = (WEBSITE / "sitemap.xml").read_text(encoding="utf-8")
        for name in website_release.PAGES:
            location = website_release.SITE_URL + ("" if name == "index.html" else name)
            self.assertIn(f"<loc>{location}</loc>", sitemap)

    def test_published_files_never_contain_the_contact_address(self):
        address = "info" + "@" + "devmil" + "." + "de"
        suffixes = {".html", ".js", ".css", ".json", ".xml", ".webmanifest", ".map", ".txt", ".svg"}
        for path in WEBSITE.rglob("*"):
            if path.is_file() and path.suffix in suffixes:
                text = path.read_text(encoding="utf-8", errors="replace").lower()
                self.assertNotIn(address, text, path)
                self.assertNotIn("mailto:" + "info", text, path)

    def test_pages_load_nothing_from_other_hosts(self):
        resource = re.compile(r'<(?:script|img|iframe|source)\b[^>]*\bsrc="([^"]+)"|<link\b(?=[^>]*\brel="(?:stylesheet|icon|preload|manifest|apple-touch-icon|modulepreload)")[^>]*\bhref="([^"]+)"')
        for name in website_release.PAGES:
            page = (WEBSITE / name).read_text(encoding="utf-8")
            for match in resource.finditer(page):
                url = match.group(1) or match.group(2)
                self.assertFalse(re.match(r"^(?:https?:)?//", url) and not url.startswith(website_release.SITE_URL), f"{name}: {url}")
        self.assertNotRegex((WEBSITE / "styles.css").read_text(encoding="utf-8"), r"url\(\s*[\"']?(?:https?:)?//")

    @staticmethod
    def entry(build):
        return {
            "productName": "ProcessLama", "version": f"1.0.{build}", "build": build, "channel": "stable",
            "artifacts": [{"file": f"old-{build}.dmg", "platform": "macos", "format": "dmg"}],
        }


if __name__ == "__main__":
    unittest.main()
