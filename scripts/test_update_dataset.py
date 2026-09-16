import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from update_dataset import NAME, update


class DatasetPublishTests(unittest.TestCase):
    def test_repository_dataset_and_checksum_match(self):
        self.assertEqual(len(update(check=True)), 64)

    def test_publishing_and_stale_checksum_detection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'assets/data').mkdir(parents=True)
            source = root / NAME
            source.write_bytes((json.dumps({'vocabulary': [{'id': 1}], 'sentences': []}) + '\r\n').encode())
            digest = update(root)
            self.assertNotIn(b'\r\n', source.read_bytes())
            self.assertEqual(digest, hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(update(root, check=True), digest)
            source.write_text(json.dumps({'vocabulary': [{'id': 2}], 'sentences': []}))
            with self.assertRaises(ValueError):
                update(root, check=True)
            update(root)
            self.assertEqual((root / 'assets/data' / NAME).read_bytes(), source.read_bytes())

    def test_duplicate_ids_cannot_be_published(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / NAME).write_text(json.dumps({'vocabulary': [{'id': 1}], 'sentences': [{'id': 1}]}))
            with self.assertRaises(ValueError):
                update(root)
            self.assertFalse((root / (NAME + '.sha256')).exists())
