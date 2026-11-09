#!/usr/bin/env python3
"""Require the complete desktop and standalone network-service candidate set."""
import argparse
from pathlib import Path
import re


def required_files(version, build):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-(?:beta|rc)\.\d+)?', version) or not re.fullmatch(r'[1-9]\d*', str(build)):
        raise ValueError('invalid candidate identity')
    base = f'ProcessLama-{version}-{build}'
    files = {base + '.dmg', base + '.dmg.sparkle-signature'}
    files.update(base + '-linux-x86_64.' + suffix for suffix in ('AppImage', 'deb', 'rpm', 'tar.gz'))
    files.update(base + '-windows-x86_64.' + suffix for suffix in ('msi', 'zip'))
    files.update(f'processlama-network-service-{version}-{build}-linux-{arch}.{suffix}'
                 for arch in ('x86_64', 'aarch64') for suffix in ('deb', 'rpm', 'tar.gz'))
    return files


def validate(directory, version, build):
    expected = required_files(version, build)
    actual = {path.name for path in Path(directory).iterdir()}
    if actual != expected:
        raise ValueError(f'candidate set differs: missing {sorted(expected - actual)}, unexpected {sorted(actual - expected)}')
    if any(not (Path(directory) / name).is_file() or (Path(directory) / name).stat().st_size == 0 for name in expected):
        raise ValueError('candidate contains an empty or non-file artifact')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    validate(args.directory, args.version, args.build)
