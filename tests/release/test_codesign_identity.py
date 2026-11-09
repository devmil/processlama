import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('codesign_identity', ROOT / 'scripts/lib/codesign_identity.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class CodesignIdentityTest(unittest.TestCase):
    def test_requires_one_exact_valid_identity(self):
        identity = 'Developer ID Application: Release Fixture (TEST)'
        text = f'  1) {"1" * 40} "{identity}"\n  2) {"2" * 40} "Other identity"\n     2 valid identities found'
        self.assertEqual(module.resolve(text, identity), '1' * 40)
        self.assertEqual(module.resolve(text, '2' * 40), '2' * 40)
        for request in ['missing', 'Developer ID Application']:
            with self.subTest(request=request), self.assertRaises(ValueError):
                module.resolve(text, request)
        with self.assertRaises(ValueError):
            module.resolve(text + f'\n 3) {"3" * 40} "{identity}"', identity)
