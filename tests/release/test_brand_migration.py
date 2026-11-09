import functools
import http.server
import json
from pathlib import Path
import plistlib
import threading
import unittest
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class BrandMigrationTest(unittest.TestCase):
    def test_linux_packaging_links_match_the_live_website_slug(self):
        metainfo = ET.fromstring((ROOT / "linux/packaging/de.devmil.processlama.metainfo.xml").read_bytes())
        homepage = metainfo.find("url[@type='homepage']").text
        self.assertEqual("https://devmil.de/processlama/", homepage)
        self.assertIn(f'Documentation={homepage}', (ROOT / "linux/packaging/processlama-network.service").read_text())
        self.assertIn(f'<link rel="canonical" href="{homepage}">', (ROOT / "website/index.html").read_text())

    def test_processlama_platform_and_storage_identity(self):
        info = plistlib.loads((ROOT / "macos/Runner/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "ProcessLama")
        self.assertEqual(info["SUFeedURL"], "https://devmil.de/processlama/download/appcast.xml")
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = de.devmil.processlama", (ROOT / "macos/Runner/Configs/AppInfo.xcconfig").read_text())
        self.assertIn("PRODUCT_NAME = processlama", (ROOT / "macos/Runner/Configs/AppInfo.xcconfig").read_text())
        for path in ["linux/CMakeLists.txt", "windows/CMakeLists.txt"]:
            self.assertIn('set(BINARY_NAME "processlama")', (ROOT / path).read_text())
        wix = ET.fromstring((ROOT / "packaging/windows/processlama.wxs").read_bytes())
        self.assertNotEqual("{D82A73FC-CB5E-4F95-AA5F-49BEFC5A3143}", wix.find("{http://wixtoolset.org/schemas/v4/wxs}Package").get("UpgradeCode"))
        for identity in ["INSTALLFOLDER", "ApplicationProgramsFolder"]:
            self.assertEqual("ProcessLama", wix.find(f".//*[@Id='{identity}']").get("Name"))
        resource = (ROOT / "windows/runner/Runner.rc").read_text()
        self.assertIn('VALUE "ProductName", "ProcessLama"', resource)
        self.assertIn('VALUE "OriginalFilename", "processlama.exe"', resource)
        snapshot = (ROOT / "lib/repositories/impl/file_snapshot_repository.dart").read_text()
        self.assertIn(".processlama-snapshot.json", snapshot)
        self.assertIn("source: 'ProcessLama'", snapshot)

    def test_current_site_serves_real_feeds_and_resources(self):
        handler = functools.partial(QuietHandler, directory=str(ROOT))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f"http://127.0.0.1:{server.server_port}/website"
            for path in ["index.html", "releases.html", "_data/releases.json", "download/appcast.xml", "assets/icons/favicon-16.png", "site.webmanifest"]:
                with urllib.request.urlopen(f"{base}/{path}") as response:
                    data = response.read()
                if path.endswith("appcast.xml"):
                    self.assertEqual(ET.fromstring(data).tag, "rss")
                if path.endswith("releases.json"):
                    self.assertEqual(json.loads(data)["schemaVersion"], 2)
                if path == "index.html":
                    self.assertIn(b'https://devmil.de/processlama/', data)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
