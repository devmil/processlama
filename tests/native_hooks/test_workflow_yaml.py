import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('workflows', ROOT / 'scripts/check_workflows.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class WorkflowYamlTest(unittest.TestCase):
    def test_nested_duplicate_keys_are_rejected(self):
        for text in [
            'jobs: {}\njobs: {}',
            'jobs:\n  test: {}\n  test: {}',
            'jobs:\n  test:\n    env:\n      A: first\n      A: second',
            'jobs:\n  test:\n    steps:\n      - run: first\n        run: second',
        ]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                module.validate(text)

    def test_invalid_shapes_are_rejected(self):
        for text in ['[]', 'jobs: []', 'jobs: {}', 'jobs: {test: []}']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                module.validate(text)

    def test_merge_and_all_current_workflows(self):
        module.validate('base: &base {A: value}\njobs:\n  test:\n    env: {<<: *base, B: other}')
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            with self.subTest(path=path):
                module.validate(path.read_text(encoding='utf-8'))
