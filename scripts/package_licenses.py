#!/usr/bin/env python3
"""Stage application and component license notices alongside release payloads."""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]


def stage(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'LICENSE', destination / 'LICENSE')
    shutil.copytree(ROOT / 'LICENSES', destination / 'LICENSES', dirs_exist_ok=True)


if __name__ == '__main__':
    stage(sys.argv[1])
