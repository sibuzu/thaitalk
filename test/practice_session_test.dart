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
}
