import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/services/practice_session.dart';

void main() {
  final pool = List.generate(
    30,
    (index) => LearningItem(
      id: index + 1,
      thai: 'คำ ${index + 1}',
      romanization: 'kham',
      chinese: '單字 ${index + 1}',
      category: 'greeting',
      level: 1,
      isSentence: false,
    ),
  );

  test('each launch samples ten unique eligible items in random order', () {
    final first = samplePracticeItems(pool, random: Random(1));
    final second = samplePracticeItems(pool, random: Random(2));
    final ids = first.map((item) => item.id).toList();
    expect(first, hasLength(10));
    expect(ids.toSet(), hasLength(10));
    expect(first.every(pool.contains), isTrue);
    expect(ids.any((id) => id > 10), isTrue);
    expect(ids, isNot(orderedEquals([...ids]..sort())));
    expect(second.map((item) => item.id), isNot(orderedEquals(ids)));
    expect(second.map((item) => item.id).toSet(), isNot(unorderedEquals(ids)));
    expect(
      pool.map((item) => item.id),
      orderedEquals(List.generate(30, (i) => i + 1)),
    );
  });

  test('small filtered pools use every available item without repeats', () {
    final filtered = pool.skip(20).take(6).toList();
    final selected = samplePracticeItems(filtered, random: Random(1));
    expect(selected, unorderedEquals(filtered));
    expect(selected, isNot(orderedEquals(filtered)));
    expect(samplePracticeItems([pool.first]), [pool.first]);
    expect(samplePracticeItems([]), isEmpty);
  });

  test('configured round sizes are capped by the available pool', () {
    for (final count in [10, 20, 30, 50]) {
      final selected = samplePracticeItems(
        pool,
        random: Random(1),
        count: count,
      );
      expect(selected, hasLength(count < pool.length ? count : pool.length));
      expect(
        selected.map((item) => item.id).toSet(),
        hasLength(selected.length),
      );
    }
  });

  test(
    'next round uses new cards first and fills short pools without repeats',
    () {
      final first = samplePracticeItems(pool, random: Random(1));
      final firstIds = first.map((item) => item.id).toSet();
      final next = samplePracticeItems(
        pool,
        random: Random(2),
        excludeIds: firstIds,
      );
      expect(next, hasLength(10));
      expect(
        next.map((item) => item.id).toSet().intersection(firstIds),
        isEmpty,
      );

      final shortPool = pool.take(12).toList();
      final shortFirst = samplePracticeItems(shortPool, random: Random(1));
      final shortIds = shortFirst.map((item) => item.id).toSet();
      final shortNext = samplePracticeItems(
        shortPool,
        random: Random(2),
        excludeIds: shortIds,
      );
      expect(shortNext.map((item) => item.id).toSet(), hasLength(10));
      expect(
        shortNext.map((item) => item.id).toSet().difference(shortIds),
        hasLength(2),
      );
    },
  );
}
