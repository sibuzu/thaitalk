import 'dart:math';

import '../models/learning_item.dart';

/// Pick up to ten items without replacement, in random presentation order.
/// Call once when opening practice so previous/next keep the session stable.
List<LearningItem> samplePracticeItems(
  Iterable<LearningItem> pool, {
  Random? random,
}) {
  final shuffled = pool.toList()..shuffle(random);
  return List<LearningItem>.unmodifiable(shuffled.take(10));
}
