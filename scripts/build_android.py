#!/usr/bin/env python3
"""Build Android with an encoded Azure key without putting secrets in source.

XOR plus base64 is reversible obfuscation, not protection from APK inspection.
Both the cipher and mask must be in the APK for the app to call Azure directly.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def read_dotenv(path: Path) -> dict[str, str]:
    """Read simple KEY=value settings; never execute a shell or echo values."""
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('export '):
            line = line[7:].strip()
        if '=' not in line:
            continue
        name, value = line.split('=', 1)
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in '\"\'':
            value = value[1:-1]
        values[name.strip()] = value
    return values


def encode_defines(key: str, region: str) -> dict[str, str]:
    key = key.strip()
    region = region.strip().lower()
    if not key or any(c.isspace() for c in key) or len(key) > 512:
        raise ValueError('Set a valid AZURE_APIKEY in .env or the environment.')
    if not re.fullmatch(r'[a-z0-9]+', region):
        raise ValueError('AZURE_REGION must be an Azure region identifier.')
    data = key.encode('utf-8')
    mask = secrets.token_bytes(len(data))
    cipher = bytes(a ^ b for a, b in zip(data, mask))
    return {
        'AZURE_KEY_CIPHER': base64.b64encode(cipher).decode('ascii'),
        'AZURE_KEY_MASK': base64.b64encode(mask).decode('ascii'),
        'AZURE_REGION': region,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description='Build ThaiTalk Android with encoded Azure credentials.')
    parser.add_argument('--flutter', default=os.environ.get('FLUTTER_BIN', 'flutter'))
    parser.add_argument('--mode', choices=('debug', 'release'), default='release')
    packaging = parser.add_mutually_exclusive_group()
    packaging.add_argument('--split-per-abi', dest='split_per_abi', action='store_true', help='One smaller APK per CPU architecture (default).')
    packaging.add_argument('--universal', dest='split_per_abi', action='store_false', help='One larger APK containing all selected CPU architectures.')
    parser.set_defaults(split_per_abi=True)
    parser.add_argument('--target-platform', choices=('android-arm', 'android-arm64', 'android-x64'), help='Optionally build only this CPU architecture.')
    parser.add_argument('--verify-speech', action='store_true', help='Assess AZURE_TEST_WAV with AZURE_TEST_REFERENCE before building (no Azure TTS).')
    args = parser.parse_args()
    values = read_dotenv(ROOT / '.env')
    key = os.environ.get('AZURE_APIKEY', values.get('AZURE_APIKEY', ''))
    region = os.environ.get('AZURE_REGION', values.get('AZURE_REGION', ''))
    if not region:
        endpoint = os.environ.get('AZURE_URL', values.get('AZURE_URL', ''))
        match = re.fullmatch(r'https://([a-z0-9]+)\.api\.cognitive\.microsoft\.com/?', endpoint)
        region = match.group(1) if match else 'southeastasia'
    try:
        defines = encode_defines(key, region)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    # This private, temporary file contains only encoded material and is
    # deleted on success or failure. No Azure key is passed as a command arg.
    def terminate(_signum, _frame):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, terminate)
    if args.verify_speech:
        defines['RUN_LIVE_AZURE'] = 'true'
    with tempfile.TemporaryDirectory(prefix='thaitalk-build-') as directory:
        config = Path(directory) / 'speech-defines.json'
        config.write_text(json.dumps(defines), encoding='utf-8')
        config.chmod(0o600)
        command = [args.flutter, 'build', 'apk', f'--{args.mode}', f'--dart-define-from-file={config}']
        if args.split_per_abi:
            command.append('--split-per-abi')
        if args.target_platform:
            command.append(f'--target-platform={args.target_platform}')
        # The compiler only receives cipher+mask, never the original key env.
        environment = os.environ.copy()
        environment.pop('AZURE_APIKEY', None)
        print('Building Android with encoded Azure configuration; key is not printed.', flush=True)
        try:
            if args.verify_speech:
                verification = subprocess.run([args.flutter, 'test', 'test/live_azure_test.dart', f'--dart-define-from-file={config}'], cwd=ROOT, env=environment, check=False)
                if verification.returncode:
                    return verification.returncode
            return subprocess.run(command, cwd=ROOT, env=environment, check=False).returncode
        except OSError:
            print('Could not launch Flutter. Set --flutter to your Flutter executable.', file=sys.stderr)
            return 2


if __name__ == '__main__':
    raise SystemExit(main())
