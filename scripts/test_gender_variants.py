import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import apply_gender_variants as variants


class GenderCoverageTests(unittest.TestCase):
    def test_words_without_examples_do_not_need_example_review(self):
        source = variants.SOURCE.read_text(encoding='utf-8')
        data = json.loads(source)
        self.assertTrue(any('example_thai' not in item for item in data['vocabulary']))
        self.assertEqual(variants.rendered_curriculum(), source)

    def test_new_example_still_requires_explicit_review(self):
        data = json.loads(variants.SOURCE.read_text(encoding='utf-8'))
        word = next(item for item in data['vocabulary'] if 'example_thai' not in item)
        word['example_thai'] = 'ตัวอย่าง'
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'thai.json'
            source.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
            with patch.object(variants, 'SOURCE', source):
                with self.assertRaisesRegex(ValueError, 'review coverage'):
                    variants.rendered_curriculum()


if __name__ == '__main__':
    unittest.main()
