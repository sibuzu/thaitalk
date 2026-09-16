#!/usr/bin/env python3
"""Apply reviewed female utterances without changing the canonical male data.

Edit gender_variants.json to review a complete utterance pair. This script does
not infer pronouns, interrogatives, politeness particles, or vocabulary meaning.
Source-text checks force a new review when a relevant canonical utterance changes.
Run with --check for a read-only reproducibility check of both curriculum copies.
"""

import argparse
import json
from pathlib import Path

from example_romanization import add_example_romanization

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'thai_practice_dataset_400.json'
BUNDLE = ROOT / 'assets/data/thai_practice_dataset_400.json'
MANIFEST = ROOT / 'scripts/gender_variants.json'


def without_spaces(text):
    return ''.join(text.split())


def rendered_curriculum():
    data = json.loads(SOURCE.read_text(encoding='utf-8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    if manifest['schema_version'] != 1:
        raise ValueError('Unsupported gender variant manifest version.')
    if len(data['vocabulary']) != 300 or len(data['sentences']) != 100:
        raise ValueError('Review coverage expects 300 vocabulary items and 100 sentences.')
    items = {item['id']: item for item in data['vocabulary'] + data['sentences']}
    if len(items) != 400:
        raise ValueError('Curriculum IDs must be unique.')
    for item in items.values():
        item.pop('female', None)
        item.pop('example_romanization', None)
    seen = set()
    vocabulary_ids = {item['id'] for item in data['vocabulary']}
    sentence_ids = {item['id'] for item in data['sentences']}
    for entry in manifest['entries']:
        item_id = entry['id']
        if item_id in seen or item_id not in items:
            raise ValueError(f'Duplicate or missing variant item {item_id}.')
        seen.add(item_id)
        item = items[item_id]
        is_sentence = item_id in sentence_ids
        if entry['kind'] != ('sentence' if is_sentence else 'vocabulary'):
            raise ValueError(f'Wrong variant kind for item {item_id}.')
        keys = (
            {'thai', 'thai_native', 'romanization', 'chinese'}
            if is_sentence
            else {'example_thai', 'example_thai_native', 'example_chinese'}
        )
        if set(entry['source']) != keys or set(entry['female']) != keys:
            raise ValueError(f'Incomplete or unexpected text fields for item {item_id}.')
        for key, expected in entry['source'].items():
            if item[key] != expected:
                raise ValueError(f'Source changed: item {item_id}, {key}; review its female variant.')
        female = entry['female']
        if not all(isinstance(value, str) and value for value in female.values()):
            raise ValueError(f'Empty variant text for item {item_id}.')
        display_key = 'thai' if is_sentence else 'example_thai'
        native_key = 'thai_native' if is_sentence else 'example_thai_native'
        if without_spaces(female[display_key]) != without_spaces(female[native_key]):
            raise ValueError(f'Display/native mismatch for item {item_id}.')
        if entry['source'] == female:
            raise ValueError(f'Unnecessary identical variant for item {item_id}.')
        item['female'] = female
    neutral = set(manifest['unchanged_vocabulary_examples'])
    if neutral & seen or (seen & vocabulary_ids) | neutral != vocabulary_ids:
        raise ValueError('Vocabulary example review coverage is incomplete or overlaps.')
    if not sentence_ids <= seen:
        raise ValueError('Every scenario sentence needs a reviewed female variant.')
    if not set(manifest['lexical_example_exceptions']) <= neutral:
        raise ValueError('Lexical gender examples must retain their taught word.')
    add_example_romanization(data)
    return json.dumps(data, ensure_ascii=False, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify without writing files.')
    args = parser.parse_args()
    rendered = rendered_curriculum()
    if args.check:
        for path in (SOURCE, BUNDLE):
            if path.read_text(encoding='utf-8') != rendered:
                raise SystemExit(f'Gender variants need regeneration: {path.relative_to(ROOT)}')
        print('Both curriculum copies match all reviewed gender variants.')
    else:
        SOURCE.write_text(rendered, encoding='utf-8')
        BUNDLE.write_text(rendered, encoding='utf-8')
        print('Applied 68 example and 100 scenario variants to both curriculum copies.')


if __name__ == '__main__':
    main()
