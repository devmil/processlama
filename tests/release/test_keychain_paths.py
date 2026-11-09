import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('keychain_paths', ROOT / 'scripts/lib/keychain_paths.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class KeychainPathsTest(unittest.TestCase):
    def test_quoted_spaces_duplicates_and_invalid_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            keychain = Path(directory) / 'login keychain-db'
            other = Path(directory) / 'other.keychain-db'
            keychain.touch()
            other.touch()
            text = f'    "{keychain}"\n "{keychain}"\n"{other}"\n"/missing"\n"unterminated\ntwo words\n'
            self.assertEqual(module.normalize(text), [str(keychain), str(other)])

    def test_no_usable_original_is_fatal(self):
        with self.assertRaisesRegex(ValueError, 'no usable'):
            module.normalize('   "/nonexistent"\n')
