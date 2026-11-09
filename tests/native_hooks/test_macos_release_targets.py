"""Exercise parsed workflow target setup before universal macOS packaging."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('workflow_parser', ROOT / 'scripts/check_workflows.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class MacosReleaseTargetsTest(unittest.TestCase):
    def test_both_rust_targets_are_installed_before_app_build_and_slices_checked(self):
        workflow = module.validate((ROOT / '.github/workflows/release.yml').read_text(encoding='utf-8'))
        prepare = workflow['jobs']['prepare']['steps']
        probe = next(i for i, step in enumerate(prepare) if step.get('name') == 'Verify native universal architecture checker')
        mutate = next(i for i, step in enumerate(prepare) if step.get('name') == 'Prepare, verify, and push release commit')
        self.assertLess(probe, mutate)
        subprocess.run(['bash', '-n'], input=prepare[probe]['run'], text=True, encoding='utf-8', check=True)
        steps = workflow['jobs']['macos']['steps']
        setup = next(i for i, step in enumerate(steps) if step.get('name') == 'Install macOS application Rust targets')
        build = next(i for i, step in enumerate(steps) if step.get('name') == 'Build, sign, notarize, and sign the update')
        self.assertLess(setup, build)
        commands = [line.strip() for line in steps[build]['run'].splitlines() if line.strip().startswith('lipo ') and ' -verify_arch ' in line]
        self.assertEqual(len(commands), 2)
        self.assertLess(steps[build]['run'].index('lipo build/macos/'), steps[build]['run'].index('./scripts/notarize-release.sh'))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for tool in ['rustup', 'lipo']:
                executable = root / tool
                executable.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
if pathlib.Path(sys.argv[0]).name == 'lipo':
 if len(sys.argv) != 5 or sys.argv[1].startswith('-') or sys.argv[2:] != ['-verify_arch','arm64','x86_64']:
  sys.exit(2)
with pathlib.Path(os.environ['MAC_TARGET_CALLS']).open('a') as log:
 log.write(json.dumps([pathlib.Path(sys.argv[0]).name,*sys.argv[1:]])+'\\n')
''', encoding='utf-8')
                executable.chmod(0o755)
            calls = root / 'calls'
            env = {**os.environ, 'PATH': str(root)+os.pathsep+os.environ['PATH'], 'MAC_TARGET_CALLS': str(calls)}
            old_order = subprocess.run(['lipo', '-verify_arch', 'arm64', 'x86_64', 'fixture'], env=env)
            self.assertNotEqual(old_order.returncode, 0, 'fixture must reject the original invalid argument order')
            subprocess.run(['bash', '-eu', '-c', steps[setup]['run']], env=env, check=True)
            subprocess.run(['bash', '-eu', '-c', '\n'.join(commands)], env=env, check=True)
            actual = [json.loads(line) for line in calls.read_text(encoding='utf-8').splitlines()]
            self.assertEqual(actual[0], ['rustup', 'target', 'add', 'aarch64-apple-darwin', 'x86_64-apple-darwin'])
            self.assertEqual([call[2:] for call in actual[1:]], [['-verify_arch','arm64','x86_64']]*2)
            self.assertTrue(actual[1][1].endswith('/Contents/MacOS/processlama'))
            self.assertTrue(actual[2][1].endswith('/processlama_core.framework/processlama_core'))
