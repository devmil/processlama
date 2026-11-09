import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseSecretsTest(unittest.TestCase):
    def test_decode_permissions_and_failure_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'credential'
            for value, expected in [
                (base64.b64encode(b'private\x00bytes').decode(), b'private\x00bytes'),
                ('cHJp dmF0ZQ==\n', b'private'),
                ('bad%%%base64', None), ('', None), ('   ', None),
            ]:
                with self.subTest(value=value):
                    output.write_bytes(b'stale')
                    result = subprocess.run(
                        ['bash', '-c', 'source scripts/lib/release-secrets.sh; processlama_secret_file TEST_SECRET "$1"', '-', str(output)],
                        cwd=ROOT, env={**os.environ, 'TEST_SECRET': value},
                        capture_output=True, text=True, encoding='utf-8')
                    if expected is None:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(output.exists())
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(output.read_bytes(), expected)
                        if os.name != 'nt':
                            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                    self.assertNotIn('stale', result.stdout + result.stderr)
                    self.assertEqual(result.stdout, '')
