"""Exercise the generated RPM lifecycle scripts without changing host services."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LinuxRpmScriptsTest(unittest.TestCase):
    def test_install_upgrade_and_removal_preserve_the_service_lifecycle(self):
        source = (ROOT / 'scripts/package-linux.sh').read_text(encoding='utf-8')
        template = re.search(r'      cat >"\$rpm_root/SPECS/processlama.spec" <<EOF\n.*?\nEOF', source, re.S).group()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'SPECS').mkdir()
            commands = root / 'commands'
            tools = root / 'bin'
            tools.mkdir()
            systemctl = tools / 'systemctl'
            systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$RPM_TEST_COMMANDS"\n', encoding='utf-8')
            systemctl.chmod(0o755)
            environment = {**os.environ, 'rpm_root': str(root), 'rpm_version': '1.0.0', 'rpm_release': '1',
                           'RPM_TEST_COMMANDS': str(commands), 'PATH': str(tools) + os.pathsep + os.environ['PATH']}
            subprocess.run(['bash', '-eu', '-c', template], env=environment, check=True)
            spec = (root / 'SPECS/processlama.spec').read_text(encoding='utf-8')
            for section, argument, expected in [
                ('post', '1', ['daemon-reload', 'enable --now processlama-network.service', 'try-restart processlama-network.service']),
                ('preun', '1', []),
                ('preun', '0', ['disable --now processlama-network.service']),
                ('postun', '1', ['daemon-reload', 'try-restart processlama-network.service']),
                ('postun', '0', ['daemon-reload']),
            ]:
                with self.subTest(section=section, argument=argument):
                    script = re.search(rf'^%{section}\n(.*?)(?=^%|\Z)', spec, re.M | re.S).group(1)
                    commands.write_text('', encoding='utf-8')
                    subprocess.run(['sh', '-eu', '-c', script, 'rpm-script', argument], env=environment, check=True)
                    self.assertEqual(commands.read_text(encoding='utf-8').splitlines(), expected)
