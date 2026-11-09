#!/usr/bin/env python3
"""Resolve one exact codesign identity inside the disposable release keychain."""
import os
import re
import sys


def resolve(text, requested):
    matches = set()
    for line in text.splitlines():
        match = re.fullmatch(r'\s*\d+\)\s+([0-9a-fA-F]{40})\s+"(.*)"\s*', line)
        if match and (match[2] == requested or match[1].upper() == requested.upper()):
            matches.add(match[1].upper())
    if len(matches) != 1:
        raise ValueError('release: signing identity must match exactly one valid fingerprint')
    return matches.pop()


if __name__ == '__main__':
    try:
        print(resolve(sys.stdin.read(), os.environ['MACOS_CODESIGN_IDENTITY']))
    except (ValueError, KeyError):
        sys.exit('release: signing identity must match exactly one valid fingerprint')
