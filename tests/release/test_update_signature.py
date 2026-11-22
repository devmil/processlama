import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "update_signature", ROOT / "scripts" / "lib" / "update_signature.py"
)
update_signature = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(update_signature)

# The same vector as infra-platform/src/appimage.rs: seed 0x00..0x1f over a
# 14-byte AppImage `appimage-bytes`, build 47, x86_64.
TEST_SEED = bytes(range(32))
TEST_KEY = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="
TEST_SIGNATURE = "a4nkL0vctU64mqhOEPSLMwRE8N3h/6JmnIUSPf7QnqRn4JPTkYUqNQOk5IstUwcP0P9tXVgaxUmueMAQ46/NBQ=="


OPENSSL = update_signature.find_openssl()


class UpdateSignatureTest(unittest.TestCase):
    def artifact(self, directory: str, payload: bytes = b"appimage-bytes") -> Path:
        path = Path(directory) / "ProcessLama.AppImage"
        path.write_bytes(payload)
        return path

    def test_message_binds_build_arch_size_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            message = update_signature.artifact_message(self.artifact(directory), 47, "x86_64")
        self.assertEqual(message.split(b"\n")[:4],
                         [b"ProcessLama AppImage update v1", b"build=47", b"arch=x86_64", b"size=14"])
        self.assertTrue(message.endswith(b"\n"))

    @unittest.skipUnless(OPENSSL, "OpenSSL 3 is required")
    def test_sign_matches_the_rust_vector_and_verifies(self):
        with tempfile.TemporaryDirectory() as directory:
            message = update_signature.artifact_message(self.artifact(directory), 47, "x86_64")
            signature = update_signature.sign(message, TEST_SEED, OPENSSL)
            key = update_signature._decode32(TEST_KEY, "key")
            self.assertEqual(signature, TEST_SIGNATURE)
            self.assertTrue(update_signature.verify(message, signature, key, OPENSSL))
            other = update_signature.artifact_message(self.artifact(directory, b"appimage-bytez"), 47, "x86_64")
            self.assertFalse(update_signature.verify(other, signature, key, OPENSSL))


if __name__ == "__main__":
    unittest.main()
