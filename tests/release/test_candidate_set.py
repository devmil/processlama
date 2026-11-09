import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('candidate_set', ROOT / 'scripts/check_release_artifacts.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class CandidateSetTest(unittest.TestCase):
    def test_complete_candidate_and_rejects_missing_empty_or_other_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = module.required_files('1.0.0-beta.35', '42')
            self.assertEqual(len(expected), 14)
            for name in expected:
                (root / name).write_bytes(b'candidate fixture')
            module.validate(root, '1.0.0-beta.35', '42')
            artifact = root / 'ProcessLama-1.0.0-beta.35-42-windows-x86_64.msi'
            artifact.unlink()
            with self.assertRaisesRegex(ValueError, 'missing'):
                module.validate(root, '1.0.0-beta.35', '42')
            artifact.touch()
            with self.assertRaisesRegex(ValueError, 'empty'):
                module.validate(root, '1.0.0-beta.35', '42')
            artifact.write_bytes(b'fixture')
            artifact.rename(root / artifact.name.replace('-42-', '-43-'))
            with self.assertRaisesRegex(ValueError, 'unexpected'):
                module.validate(root, '1.0.0-beta.35', '42')
