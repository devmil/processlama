#!/usr/bin/env python3
"""Signs AppImage updates for the in-app updater.

The app installs an AppImage update only when `updateSignature` in
releases.json is an Ed25519 signature, by the Sparkle key whose public half
the app embeds, over `message(...)`. The message binds the build, the
architecture, the size and the SHA-256 of the exact file, and starts with a
ProcessLama prefix so it can never pass for a Sparkle archive signature.
The Rust side (`infra-platform/src/updates.rs`) builds the same bytes.

  update_signature.py message --artifact FILE --build N --arch x86_64
  update_signature.py sign --artifact FILE --build N --arch x86_64 \\
      --seed-env SPARKLE_PRIVATE_KEY_BASE64 [--openssl openssl]
  update_signature.py verify --artifact FILE --build N --arch x86_64 \\
      --signature BASE64 --public-key BASE64 [--openssl openssl]
"""

import argparse
import base64
import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PREFIX = "ProcessLama AppImage update v1"
# DER prefixes that wrap a raw 32-byte Ed25519 seed or public key.
PRIVATE_DER = bytes.fromhex("302e020100300506032b657004220420")
PUBLIC_DER = bytes.fromhex("302a300506032b6570032100")


def message(build: int, arch: str, size: int, sha256: str) -> bytes:
    if build <= 0 or size <= 0 or not arch or len(sha256) != 64:
        raise ValueError("invalid update identity")
    return f"{PREFIX}\nbuild={build}\narch={arch}\nsize={size}\nsha256={sha256}\n".encode()


def artifact_message(path: Path, build: int, arch: str) -> bytes:
    payload = path.read_bytes()
    return message(build, arch, len(payload), hashlib.sha256(payload).hexdigest())


def _decode32(value: str, what: str) -> bytes:
    try:
        raw = base64.b64decode("".join(value.split()), validate=True)
    except ValueError:
        raw = b""
    if len(raw) != 32:
        raise SystemExit(f"update_signature: {what} must be 32 bytes of base64")
    return raw


def sign(data: bytes, seed: bytes, openssl: str) -> str:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        key = root / "key.der"
        key.write_bytes(PRIVATE_DER + seed)
        os.chmod(key, 0o600)
        (root / "message").write_bytes(data)
        signature = subprocess.run(
            [openssl, "pkeyutl", "-sign", "-rawin", "-keyform", "DER", "-inkey", str(key), "-in", str(root / "message")],
            check=True, capture_output=True,
        ).stdout
    if len(signature) != 64:
        raise SystemExit("update_signature: OpenSSL returned an invalid signature")
    return base64.b64encode(signature).decode()


def verify(data: bytes, signature: str, public_key: bytes, openssl: str) -> bool:
    try:
        raw = base64.b64decode(signature, validate=True)
    except ValueError:
        return False
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "key.der").write_bytes(PUBLIC_DER + public_key)
        (root / "message").write_bytes(data)
        (root / "signature").write_bytes(raw)
        result = subprocess.run(
            [openssl, "pkeyutl", "-verify", "-pubin", "-rawin", "-keyform", "DER", "-inkey", str(root / "key.der"),
             "-in", str(root / "message"), "-sigfile", str(root / "signature")],
            capture_output=True,
        )
    return result.returncode == 0


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("message", "sign", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--artifact", required=True)
        command.add_argument("--build", required=True, type=int)
        command.add_argument("--arch", required=True)
        if name != "message":
            command.add_argument("--openssl", default="openssl")
        if name == "sign":
            command.add_argument("--seed-env", required=True)
        if name == "verify":
            command.add_argument("--signature", required=True)
            command.add_argument("--public-key", required=True)
    args = parser.parse_args()
    data = artifact_message(Path(args.artifact), args.build, args.arch)
    if args.command == "message":
        sys.stdout.buffer.write(data)
    elif args.command == "sign":
        seed = _decode32(os.environ.get(args.seed_env, ""), args.seed_env)
        print(sign(data, seed, args.openssl))
    elif not verify(data, args.signature, _decode32(args.public_key, "--public-key"), args.openssl):
        raise SystemExit("update_signature: the signature does not match")


if __name__ == "__main__":
    main()
