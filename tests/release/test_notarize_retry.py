import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NotarizeRetryTest(unittest.TestCase):
    def test_staple_retries_transient_failure_and_keeps_permanent_failure_fatal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dmg = root / 'fixture.dmg'
            dmg.write_bytes(b'fixture')
            for tool in ['xcrun', 'spctl']:
                executable = root / tool
                executable.write_text('''#!/usr/bin/env python3
import os,sys,pathlib
root=pathlib.Path(os.environ['NOTARY_TEST_ROOT'])
with (root/'calls').open('a') as log: log.write(' '.join(sys.argv[1:])+'\\n')
if sys.argv[1:3]==['stapler','staple']:
 p=root/'attempts'
 n=int(p.read_text())+1 if p.exists() else 1
 p.write_text(str(n))
 sys.exit(1 if n <= int(os.environ['NOTARY_FAILURES']) else 0)
''', encoding='utf-8')
                executable.chmod(0o755)
            for failures, expected in [(2, 3), (10, 5)]:
                with self.subTest(failures=failures):
                    for name in ['attempts', 'calls']:
                        (root / name).unlink(missing_ok=True)
                    result = subprocess.run(['bash', str(ROOT / 'scripts/notarize-release.sh'), str(dmg)],
                        env={**os.environ, 'PATH': str(root)+os.pathsep+os.environ['PATH'],
                             'NOTARY_PROFILE': 'fixture', 'NOTARY_TEST_ROOT': str(root),
                             'NOTARY_FAILURES': str(failures), 'PROCESSLAMA_STAPLE_RETRY_SECONDS': '0'},
                        text=True, encoding='utf-8', capture_output=True)
                    self.assertEqual(int((root/'attempts').read_text()), expected)
                    self.assertEqual(result.returncode == 0, failures == 2, result.stderr)
                    self.assertEqual('stapler validate' in (root/'calls').read_text(), failures == 2)
