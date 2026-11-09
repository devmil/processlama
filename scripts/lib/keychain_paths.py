#!/usr/bin/env python3
"""Normalize security list-keychains output without splitting paths with spaces."""
from pathlib import Path
import shlex
import sys


def normalize(text):
    result = []
    for line in text.splitlines():
        try:
            values = shlex.split(line)
        except ValueError:
            continue
        if len(values) != 1:
            continue
        path = values[0]
        if Path(path).is_file() and path not in result:
            result.append(path)
    if not result:
        raise ValueError('no usable original keychains')
    return result


if __name__ == '__main__':
    try:
        print('\n'.join(normalize(sys.stdin.read())))
    except ValueError:
        sys.exit('release: no usable original keychain search list')
