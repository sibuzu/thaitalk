#!/usr/bin/env python3
"""Subset bundled Chinese/Korean glyphs; retain full Thai and source fonts.

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


def required_codepoints():
    # Latin/romanization and punctuation remain available for dynamic text.
    points = set(range(0x20, 0x250))
    points.update(range(0x2000, 0x2070))
    points.update(range(0x3000, 0x3040))
    points.update(range(0xFF00, 0xFFF0))
    paths = sorted((ROOT / 'lib').rglob('*.dart'))
    paths.extend(sorted((ROOT / 'assets/data').glob('*_practice_dataset.json')))
    for path in paths:
        points.update(map(ord, path.read_text(encoding='utf-8')))
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    points = required_codepoints()
    for family in ['NotoSansTC', 'NotoSansKR']:
        source_path = ROOT / f'assets/fonts/{family}.ttf'
        output_path = ROOT / f'assets/fonts/{family}.subset.ttf'
        # Korean only needs Hangul, Latin and punctuation; CJK ideographs use TC.
        selected = points if family == 'NotoSansTC' else {
            p for p in points if p < 0x250 or 0x1100 <= p <= 0x11ff
            or 0x2000 <= p <= 0x206f or 0x3130 <= p <= 0x318f
            or 0xac00 <= p <= 0xd7af
        }
        with TTFont(source_path, recalcTimestamp=False) as source:
            required = selected & source.getBestCmap().keys()
            if not args.check:
                subset_font(source, required, output_path)
        with TTFont(output_path) as result:
            missing = required - result.getBestCmap().keys()
            if missing:
                raise SystemExit(f'Regenerate {family}: missing ' + ', '.join(f'U+{code:04X}' for code in sorted(missing)))
            if 'fvar' not in result:
                raise SystemExit('Font weight variations must be retained.')
        print(f'{family}: {source_path.stat().st_size:,} -> {output_path.stat().st_size:,} bytes; {len(required)} required codepoints covered.')


def subset_font(source, required, output):
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=required)
    subsetter.subset(source)
    source.save(output)


if __name__ == '__main__':
    main()
