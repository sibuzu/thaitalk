#!/usr/bin/env python3
"""Subset bundled Chinese glyphs; retain full Thai font and source Chinese font.

Requires fonttools (development only). Regenerate after changing UI/curriculum:
  python3 scripts/subset_fonts.py
Validate coverage without modifying files:
  python3 scripts/subset_fonts.py --check
"""
import argparse
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/fonts/NotoSansTC.ttf'
OUTPUT = ROOT / 'assets/fonts/NotoSansTC.subset.ttf'


def required_codepoints():
    # Latin/romanization and punctuation remain available for dynamic text.
    points = set(range(0x20, 0x250))
    points.update(range(0x2000, 0x2070))
    points.update(range(0x3000, 0x3040))
    points.update(range(0xFF00, 0xFFF0))
    paths = sorted((ROOT / 'lib').rglob('*.dart'))
    paths.append(ROOT / 'assets/data/thai_practice_dataset_400.json')
    for path in paths:
        points.update(map(ord, path.read_text(encoding='utf-8')))
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    with TTFont(SOURCE, recalcTimestamp=False) as source:
        required = required_codepoints() & source.getBestCmap().keys()
        if not args.check:
            options = subset.Options()
            options.name_IDs = ['*']
            options.name_legacy = True
            options.name_languages = ['*']
            subsetter = subset.Subsetter(options=options)
            subsetter.populate(unicodes=required)
            subsetter.subset(source)
            source.save(OUTPUT)
    with TTFont(OUTPUT) as result:
        missing = required - result.getBestCmap().keys()
        if missing:
            raise SystemExit('Regenerate font: missing ' + ', '.join(f'U+{code:04X}' for code in sorted(missing)))
        if 'fvar' not in result:
            raise SystemExit('Font weight variations must be retained.')
    print(f'Chinese font: {SOURCE.stat().st_size:,} -> {OUTPUT.stat().st_size:,} bytes; {len(required)} required codepoints covered.')


if __name__ == '__main__':
    main()
