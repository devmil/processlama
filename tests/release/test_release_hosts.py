import hashlib
import io
import urllib.error
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "release_hosts", ROOT / "scripts" / "reconcile-release-hosts.py"
)
release_hosts = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(release_hosts)


class ReleaseHostsTest(unittest.TestCase):
    def test_reads_both_tracks_and_marks_beta_prerelease(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "releases.json"
            path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 2,
                        "latest": self.entry("1.0.0", 10),
                        "history": [],
                        "beta": {
                            "latest": self.entry("1.1.0-beta.1", 11),
                            "history": [],
                        },
                    }
                )
            )
            releases = release_hosts.releases_from_metadata(path)

        self.assertEqual([item["tag"] for item in releases], ["v1.1.0-beta.1-11", "v1.0.0-10"])
        self.assertTrue(release_hosts.release_payload(releases[0], github=True)["prerelease"])
        self.assertFalse(release_hosts.release_payload(releases[1], github=False)["prerelease"])

    def test_verifies_release_asset_checksum_and_size(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "artifact"
            path.write_bytes(b"release")
            metadata = {
                "sizeBytes": 7,
                "sha256": hashlib.sha256(b"release").hexdigest(),
            }
            release_hosts.verify_asset(path, metadata)
            with self.assertRaisesRegex(ValueError, "checksum"):
                release_hosts.verify_asset(path, {**metadata, "sha256": "0" * 64})

    def test_migrates_legacy_dmg_metadata_for_first_hosted_release(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "releases.json"
            path.write_text(json.dumps({
                "schemaVersion": 2,
                "latest": None,
                "history": [],
                "beta": {
                    "latest": {
                        "version": "1.0.0-beta.9",
                        "build": 9,
                        "file": "ProcessLama-1.0.0-beta.9-9.dmg",
                        "sizeBytes": 42,
                        "sha256": "a" * 64,
                    },
                    "history": [],
                },
            }))
            releases = release_hosts.releases_from_metadata(path)

        self.assertEqual(
            releases[0]["artifacts"][0]["file"],
            "ProcessLama-1.0.0-beta.9-9.dmg",
        )

    def test_github_keeps_matching_asset_without_fetching_source(self):
        release = {
            **self.entry("1.0.0-beta.10", 12),
            "channel": "beta",
            "tag": "v1.0.0-beta.10-12",
        }
        remote = {
            "id": 7,
            "tag_name": release["tag"],
            "assets": [{"id": 9, "name": "ProcessLama.dmg", "size": 1}],
        }

        class GithubApi:
            base_url = "https://api.github.com"

            def optional(self, path):
                return remote

            def request(self, method, path, payload=None):
                if method == "PATCH":
                    return remote
                if method == "GET" and path.startswith("repos/devmil/processlama/releases?"):
                    return [remote]
                raise AssertionError(f"unexpected request: {method} {path}")

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(
                release_hosts,
                "download_retained_asset",
                side_effect=AssertionError("matching assets must not be downloaded"),
            ), mock.patch.object(release_hosts, "verify_remote_asset") as verify:
                release_hosts.reconcile_github(
                    [release],
                    GithubApi(),
                    "devmil/processlama",
                    Path(directory),
                    None,
                )

                verify.assert_called_once()

    def test_readback_retries_temporary_404_then_verifies_bytes(self):
        data = b"release"
        metadata = {"sizeBytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        opener = mock.Mock()
        opener.open.side_effect = [
            urllib.error.HTTPError("https://example.test/asset", 404, "not visible", {}, None),
            io.BytesIO(data),
        ]
        with mock.patch.object(release_hosts.urllib.request, "build_opener", return_value=opener), mock.patch.object(release_hosts.time, "sleep") as sleep:
            release_hosts.download_verified("https://example.test/asset", metadata)
        self.assertEqual(opener.open.call_count, 2)
        sleep.assert_called_once_with(1)

    def test_checksum_mismatch_is_fatal_without_retry(self):
        opener = mock.Mock()
        opener.open.return_value = io.BytesIO(b"changed")
        with mock.patch.object(release_hosts.urllib.request, "build_opener", return_value=opener), mock.patch.object(release_hosts.time, "sleep") as sleep:
            with self.assertRaisesRegex(ValueError, "checksum"):
                release_hosts.download_verified("https://example.test/asset", {"sizeBytes": 7, "sha256": "0" * 64})
        sleep.assert_not_called()

    def test_published_assets_are_never_replaced(self):
        release = {**self.entry("1.0.0", 12), "channel": "stable", "tag": "v1.0.0-12"}
        remote = {"id": 7, "draft": False, "assets": [{"id": 9, "name": "ProcessLama.dmg", "size": 2}]}
        api = mock.Mock()
        api.optional.return_value = remote
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, "immutable"):
            release_hosts.reconcile_github([release], api, "devmil/processlama", Path(directory), None)
        api.request.assert_not_called()

    def test_redirect_drops_bearer_token(self):
        request = release_hosts.urllib.request.Request("https://api.github.com/asset", headers={"Authorization": "Bearer test-only"})
        redirected = release_hosts.StripRedirectAuthorization().redirect_request(request, None, 302, "redirect", {}, "https://example.test/signed")
        self.assertFalse(redirected.has_header("Authorization"))

    @staticmethod
    def entry(version, build):
        return {
            "version": version,
            "build": build,
            "notesPath": f"/download/ProcessLama-{version}-{build}.html",
            "artifacts": [
                {
                    "file": "ProcessLama.dmg",
                    "sizeBytes": 1,
                    "sha256": "0" * 64,
                }
            ],
        }


if __name__ == "__main__":
    unittest.main()
