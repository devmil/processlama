#!/usr/bin/env python3
"""Reconcile retained ProcessLama releases and their assets on GitHub."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


USER_AGENT = "ProcessLama-release-reconciler/1"


class ApiError(RuntimeError):
    pass


class JsonApi:
    def __init__(self, base_url: str, token: str, scheme: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.scheme = scheme

    def request(self, method: str, path: str, payload: object | None = None) -> object | None:
        data = json.dumps(payload).encode() if payload is not None else None
        headers = {
            "Accept": "application/json",
            "Authorization": f"{self.scheme} {self.token}",
            "User-Agent": USER_AGENT,
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}/{path.lstrip('/')}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:2000]
            raise ApiError(f"{method} {path} returned {error.code}: {detail}") from error
        return json.loads(body) if body else None

    def optional(self, path: str) -> object | None:
        try:
            return self.request("GET", path)
        except ApiError as error:
            if " returned 404:" in str(error):
                return None
            raise


def releases_from_metadata(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 2:
        raise ValueError("release metadata has an unsupported schema")
    result: list[dict] = []
    for channel, track in (("stable", data), ("beta", data.get("beta") or {})):
        entries = [track.get("latest"), *(track.get("history") or [])]
        if len([entry for entry in entries if entry]) > 5:
            raise ValueError(f"{channel} metadata exceeds five-release retention")
        for entry in entries:
            if not entry:
                continue
            release = dict(entry)
            release["channel"] = channel
            release["tag"] = f"v{entry['version']}-{int(entry['build'])}"
            if not release.get("artifacts") and release.get("file"):
                release["artifacts"] = [
                    {
                        "file": release["file"],
                        "sizeBytes": release.get("sizeBytes", 0),
                        "sha256": release.get("sha256", ""),
                        "platform": "macos",
                        "format": "dmg",
                    }
                ]
            if not release.get("artifacts"):
                raise ValueError(f"{release['tag']} has no artifacts")
            result.append(release)
    if not result:
        raise ValueError("release metadata contains no releases")
    if len(result) > 10:
        raise ValueError("release metadata exceeds ten-release retention")
    return sorted(result, key=lambda release: int(release["build"]), reverse=True)


def release_payload(release: dict, *, github: bool) -> dict:
    notes = str(release.get("notesPath") or "").lstrip("/")
    body = f"Release notes: https://devmil.de/processlama/{notes}" if notes else "https://devmil.de/processlama/releases.html"
    payload = {
        "tag_name": release["tag"],
        "name": f"{release.get('productName') or 'ProcessLama'} {release['version']} (build {release['build']})",
        "body": body,
        "draft": False,
        "prerelease": release["channel"] != "stable",
    }
    if github:
        payload["target_commitish"] = "main"
    return payload


def expected_assets(release: dict) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for asset in release["artifacts"]:
        name = asset.get("file")
        if not isinstance(name, str) or not name:
            raise ValueError(f"{release['tag']} contains an invalid asset")
        if name in result:
            raise ValueError(f"{release['tag']} contains duplicate asset {name}")
        result[name] = asset
    return result


def verify_asset(path: Path, metadata: dict) -> None:
    if path.stat().st_size != int(metadata["sizeBytes"]):
        raise ValueError(f"{path.name} size does not match release metadata")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != metadata["sha256"]:
        raise ValueError(f"{path.name} checksum does not match release metadata")


def curl_upload(url: str, api: JsonApi, path: Path, *, multipart: bool) -> dict:
    command = [
        "curl", "--fail-with-body", "--silent", "--show-error", "--location",
        "--request", "POST", "--config", "-", "--header", f"User-Agent: {USER_AGENT}",
    ]
    if multipart:
        command.extend(["--form", f"attachment=@{path}"])
    else:
        command.extend(["--header", "Content-Type: application/octet-stream", "--upload-file", str(path)])
    command.append(url)
    result = subprocess.run(
        command,
        input=f'header = "Authorization: {api.scheme} {api.token}"\n',
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ApiError(result.stderr.strip() or f"upload failed for {path.name}")
    return json.loads(result.stdout)


def all_releases(api: JsonApi, repository: str) -> list[dict]:
    result: list[dict] = []
    page = 1
    while True:
        limit = 100 if api.base_url == "https://api.github.com" else 50
        query = f"per_page={limit}&page={page}" if limit == 100 else f"limit={limit}&page={page}"
        batch = api.request("GET", f"repos/{repository}/releases?{query}")
        if not isinstance(batch, list):
            raise ApiError("release API returned an invalid release list")
        result.extend(item for item in batch if isinstance(item, dict))
        if len(batch) < limit:
            return result
        page += 1


def local_directory(
    root: Path, release: dict, current_tag: str, legacy_root: Path | None
) -> Path | None:
    tagged = root / release["tag"]
    if tagged.is_dir():
        return tagged
    if release["tag"] == current_tag and all((root / name).is_file() for name in expected_assets(release)):
        return root
    if legacy_root and all((legacy_root / name).is_file() for name in expected_assets(release)):
        return legacy_root
    return None


class StripRedirectAuthorization(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        if redirected is not None:
            redirected.remove_header("Authorization")
        return redirected


def download_verified(url: str, metadata: dict, destination: Path | None = None, token: str = "") -> None:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/octet-stream"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    opener = urllib.request.build_opener(StripRedirectAuthorization())
    for attempt in range(5):
        try:
            digest, size = hashlib.sha256(), 0
            with opener.open(urllib.request.Request(url, headers=headers), timeout=120) as response:
                output = destination.open("wb") if destination else None
                try:
                    while block := response.read(1024 * 1024):
                        size += len(block)
                        if size > int(metadata["sizeBytes"]):
                            raise ValueError("remote asset size exceeds release metadata")
                        digest.update(block)
                        if output:
                            output.write(block)
                finally:
                    if output:
                        output.close()
            if size != int(metadata["sizeBytes"]) or digest.hexdigest() != metadata["sha256"]:
                raise ValueError("remote asset checksum or size differs from release metadata")
            return
        except urllib.error.HTTPError as error:
            if error.code not in (404, 429, 500, 502, 503, 504) or attempt == 4:
                raise ApiError(f"asset readback returned HTTP {error.code}") from None
            time.sleep(2 ** attempt)


def verify_remote_asset(api: JsonApi, repository: str, asset: dict, metadata: dict) -> None:
    download_verified(f"{api.base_url}/repos/{repository}/releases/assets/{asset['id']}", metadata, token=api.token)


def download_retained_asset(metadata: dict, destination: Path) -> None:
    # Existing public releases remain the source of historical bytes when restoring retained releases.
    url = str(metadata.get("downloadPath", ""))
    if not url.startswith("https://github.com/devmil/processlama/releases/download/"):
        raise ValueError("missing local retained asset or approved public source")
    download_verified(url, metadata, destination)


def reconcile_github(
    releases: list[dict], api: JsonApi, repository: str, artifact_root: Path,
    legacy_artifact_root: Path | None,
) -> None:
    retained = {release["tag"] for release in releases}
    current_tag = releases[0]["tag"]
    with tempfile.TemporaryDirectory(prefix="processlama-release-") as temporary:
        for release in releases:
            tag = release["tag"]
            remote = api.optional(f"repos/{repository}/releases/tags/{urllib.parse.quote(tag)}")
            if remote is None:
                remote = api.request("POST", f"repos/{repository}/releases", {**release_payload(release, github=True), "draft": True})
            if not isinstance(remote, dict) or not isinstance(remote.get("id"), int):
                raise ApiError(f"GitHub returned an invalid release for {tag}")
            assets = remote.get("assets") or api.request("GET", f"repos/{repository}/releases/{remote['id']}/assets") or []
            by_name = {item.get("name"): item for item in assets if isinstance(item, dict)}
            directory = local_directory(artifact_root, release, current_tag, legacy_artifact_root)
            expected = expected_assets(release)
            unexpected = set(by_name) - set(expected)
            if unexpected:
                raise ValueError(f"unexpected hosted assets for {tag}")
            for name, metadata in expected.items():
                existing = by_name.get(name)
                if isinstance(existing, dict) and existing.get("size") == int(metadata["sizeBytes"]):
                    verify_remote_asset(api, repository, existing, metadata)
                    continue
                if not remote.get("draft", False):
                    raise ValueError(f"published release {tag} has missing or changed immutable assets")
                source = directory / name if directory else Path(temporary) / name
                if not directory:
                    download_retained_asset(metadata, source)
                verify_asset(source, metadata)
                if isinstance(existing, dict):
                    api.request("DELETE", f"repos/{repository}/releases/assets/{existing['id']}")
                upload_url = str(remote.get("upload_url", "")).split("{", 1)[0]
                if not upload_url:
                    raise ApiError("release has no asset upload URL")
                uploaded = curl_upload(f"{upload_url}?{urllib.parse.urlencode({'name': name})}", api, source, multipart=False)
                verify_remote_asset(api, repository, uploaded, metadata)
            api.request("PATCH", f"repos/{repository}/releases/{remote['id']}", release_payload(release, github=True))
        # Only prune after every retained release has passed checksum readback.
        for remote in all_releases(api, repository):
            if remote.get("tag_name") not in retained and isinstance(remote.get("id"), int):
                api.request("DELETE", f"repos/{repository}/releases/{remote['id']}")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    root.add_argument("--metadata", type=Path, required=True)
    root.add_argument("--artifact-root", type=Path, required=True)
    root.add_argument("--legacy-artifact-root", type=Path)
    commands = root.add_subparsers(dest="command", required=True)
    github = commands.add_parser("github")
    github.add_argument("--repository", required=True)
    github.add_argument("--token-env", required=True)
    return root


def main() -> None:
    args = parser().parse_args()
    token = os.environ.get(args.token_env, "")
    if not token:
        raise SystemExit(f"environment variable {args.token_env} is empty")
    reconcile_github(releases_from_metadata(args.metadata),
                     JsonApi("https://api.github.com", token, "Bearer"),
                     args.repository, args.artifact_root, args.legacy_artifact_root)


if __name__ == "__main__":
    main()
