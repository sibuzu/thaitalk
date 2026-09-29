import 'dart:math';

import '../models/learning_item.dart';

/// Pick up to [count] items without replacement, in random presentation order.
/// Prefer items outside the previous round when starting another one.
List<LearningItem> samplePracticeItems(
  Iterable<LearningItem> pool, {
  Random? random,
  Set<int> excludeIds = const {},
  int count = 10,
}) {
  if (count < 1) throw ArgumentError.value(count, 'count');
  final fresh = <LearningItem>[];
  final repeated = <LearningItem>[];
  for (final item in pool) {
    (excludeIds.contains(item.id) ? repeated : fresh).add(item);
  }
  fresh.shuffle(random);
  repeated.shuffle(random);
  return List<LearningItem>.unmodifiable([...fresh, ...repeated].take(count));
}
