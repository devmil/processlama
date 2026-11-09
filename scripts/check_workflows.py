#!/usr/bin/env python3
"""Validate workflow YAML without accepting duplicate mapping keys."""
from pathlib import Path
import sys
import yaml


class WorkflowLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        seen = set()
        for key, _ in node.value:
            if key.tag == 'tag:yaml.org,2002:merge':
                continue
            value = self.construct_object(key, deep=deep)
            if value in seen:
                raise ValueError('duplicate workflow mapping key')
            seen.add(value)
        return super().construct_mapping(node, deep=deep)


def validate(text):
    document = yaml.load(text, Loader=WorkflowLoader)
    if not isinstance(document, dict) or not isinstance(document.get('jobs'), dict) or not document['jobs']:
        raise ValueError('workflow must contain a nonempty jobs mapping')
    for job in document['jobs'].values():
        if not isinstance(job, dict) or ('steps' in job and not isinstance(job['steps'], list)):
            raise ValueError('invalid workflow job')
    return document


def main():
    failed = False
    for path in sorted(Path('.github/workflows').glob('*.yml')):
        try:
            validate(path.read_text(encoding='utf-8'))
        except (ValueError, yaml.YAMLError, TypeError):
            print(f'{path}: invalid workflow structure or duplicate mapping key', file=sys.stderr)
            failed = True
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
