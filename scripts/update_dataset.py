#!/usr/bin/env python3
"""Publish root curriculum to the APK asset and SHA-256 sidecar, or --check."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = 'thai_practice_dataset.json'


def update(root=ROOT, check=False):
    source = root / NAME
    bundle = root / 'assets/data' / NAME
    checksum = root / (NAME + '.sha256')
    original = source.read_bytes()
    content = original.replace(b'\r\n', b'\n')
    data = json.loads(content)
    entries = data['vocabulary'] + data['sentences']
    ids = [entry['id'] for entry in entries]
    if not entries or len(ids) != len(set(ids)):
        raise ValueError('Dataset must contain entries with unique IDs.')
    digest = hashlib.sha256(content).hexdigest()
    expected = f'{digest}  {NAME}\n'
    if check:
        if original != content or bundle.read_bytes() != content or checksum.read_text() != expected:
            raise ValueError('Run python3 scripts/update_dataset.py to sync the asset and checksum.')
    else:
        source.write_bytes(content)
        bundle.write_bytes(content)
        checksum.write_text(expected, encoding='ascii')
    return digest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    print(update(check=parser.parse_args().check))
