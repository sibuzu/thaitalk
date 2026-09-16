import base64
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_android


class BuildConfigurationTests(unittest.TestCase):
    def test_encoded_values_round_trip_without_plaintext_key(self):
        key = 'test-key-for-build-only'
        result = build_android.encode_defines(key, 'southeastasia')
        cipher = base64.b64decode(result['AZURE_KEY_CIPHER'])
        mask = base64.b64decode(result['AZURE_KEY_MASK'])
        self.assertEqual(bytes(a ^ b for a, b in zip(cipher, mask)).decode(), key)
        self.assertNotIn(key, str(result))
        self.assertNotEqual(result, build_android.encode_defines(key, 'southeastasia'))

    def test_invalid_key_or_region_is_rejected_without_echoing_key(self):
        with self.assertRaises(ValueError) as caught:
            build_android.encode_defines('private key invalid', 'southeastasia')
        self.assertNotIn('private key invalid', str(caught.exception))
        with self.assertRaises(ValueError):
            build_android.encode_defines('test-key', 'example.com/redirect')

    def test_dotenv_quoted_value_is_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / '.env'
            path.write_text('# sample\nexport AZURE_APIKEY="test-key"\nAZURE_REGION=southeastasia\n')
            self.assertEqual(build_android.read_dotenv(path)['AZURE_APIKEY'], 'test-key')

    def test_build_uses_private_temporary_file_and_cleans_on_failure(self):
        config_path = None
        def fake_run(command, **kwargs):
            nonlocal config_path
            config_path = Path(next(arg.split('=', 1)[1] for arg in command if arg.startswith('--dart-define-from-file=')))
            self.assertEqual(config_path.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('test-build-key', config_path.read_text())
            self.assertNotIn('test-build-key', ' '.join(command))
            self.assertNotIn('AZURE_APIKEY', kwargs['env'])
            self.assertIn('--release', command)
            self.assertIn('--split-per-abi', command)
            return type('Result', (), {'returncode': 1})()
        with patch.dict('os.environ', {'AZURE_APIKEY':'test-build-key', 'AZURE_REGION':'southeastasia'}), patch('sys.argv', ['build_android.py']), patch('build_android.subprocess.run', side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(build_android.main(), 1)
        self.assertIsNotNone(config_path)
        self.assertFalse(config_path.exists())

    def test_explicit_architecture_and_universal_overrides(self):
        for options, expected, unexpected in [
            (['--target-platform', 'android-arm64'], ['--release', '--split-per-abi', '--target-platform=android-arm64'], ['--debug']),
            (['--mode', 'debug', '--universal'], ['--debug'], ['--release', '--split-per-abi']),
        ]:
            with self.subTest(options=options):
                commands = []
                def fake_run(command, **kwargs):
                    commands.append(command)
                    return type('Result', (), {'returncode': 0})()
                with patch.dict('os.environ', {'AZURE_APIKEY': 'test-build-key', 'AZURE_REGION': 'southeastasia'}), patch('sys.argv', ['build_android.py', *options]), patch('build_android.subprocess.run', side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(build_android.main(), 0)
                self.assertEqual(len(commands), 1)
                for option in expected:
                    self.assertIn(option, commands[0])
                for option in unexpected:
                    self.assertNotIn(option, commands[0])


if __name__ == '__main__':
    unittest.main()
