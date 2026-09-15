import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/services/learning_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late LearningStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 9, 15, 12);
    store = await LearningStore.load(clock: () => now);
  });

  tearDown(() async {
    await store.flush();
    store.dispose();
  });

  test('new learners start with no synthetic activity', () {
    expect(store.totalXp, 0);
    expect(store.todayCount, 0);
    expect(store.streak, 0);
    expect(store.activity, isEmpty);
    expect(store.learnedIds, isEmpty);
    expect(store.reviewDueIds, isEmpty);
  });

  test(
    'study, saved items, daily goal and best score survive reload',
    () async {
      store.toggleSaved(1);
      store.markReviewed(1, remembered: true);
      store.recordQuizAnswer(2, correct: false);
      store.recordPronunciation(1001, 84.5);
      store.recordPronunciation(1001, 72);
      store.setDailyGoal(20);
      await store.flush();

      final restored = await LearningStore.load(clock: () => now);
      expect(restored.savedIds, {1});
      expect(restored.learnedIds, {1, 1001});
      expect(restored.bestScores[1001], 84.5);
      expect(restored.todayCount, 4);
      expect(restored.totalXp, 53);
      expect(restored.dailyGoal, 20);
      expect(restored.streak, 1);
      restored.dispose();
    },
  );

  test('successful reviews advance only once when due', () {
    store.markReviewed(1, remembered: true);
    final firstDue = now.add(const Duration(days: 1));
    expect(store.nextReviewAt(1), firstDue);
    expect(store.reviewDueIds, isEmpty);

    now = now.add(const Duration(hours: 1));
    store.markReviewed(1, remembered: true);
    expect(store.nextReviewAt(1), firstDue);

    now = firstDue;
    expect(store.reviewDueIds, {1});
    store.markReviewed(1, remembered: true);
    expect(store.nextReviewAt(1), now.add(const Duration(days: 3)));
    expect(store.reviewDueIds, isEmpty);
  });

  test('forgotten answers retry in ten minutes and reset the interval', () {
    store.markReviewed(1, remembered: true);
    now = now.add(const Duration(days: 1));
    store.markReviewed(1, remembered: false);
    expect(store.nextReviewAt(1), now.add(const Duration(minutes: 10)));
    expect(store.reviewDueIds, isEmpty);
    now = now.add(const Duration(minutes: 10));
    expect(store.reviewDueIds, {1});
    store.markReviewed(1, remembered: true);
    expect(store.nextReviewAt(1), now.add(const Duration(days: 1)));
  });

  test('correcting a mistake early still gets a full first interval', () {
    store.recordQuizAnswer(1, correct: false);
    store.recordQuizAnswer(1, correct: true);
    expect(store.nextReviewAt(1), now.add(const Duration(days: 1)));
  });

  test('streak spans calendar days and breaks after a missed day', () {
    store.markReviewed(1, remembered: true);
    now = DateTime(2026, 9, 16, 1);
    expect(store.todayCount, 0);
    expect(store.streak, 1);
    store.recordQuizAnswer(2, correct: true);
    expect(store.streak, 2);
    now = DateTime(2026, 9, 17, 1);
    expect(store.streak, 2);
    now = DateTime(2026, 9, 18, 1);
    expect(store.streak, 0);
  });

  test('cloud merges add device counters without double-counting', () async {
    store.markReviewed(1, remembered: true);
    final remote = <String, dynamic>{
      'version': 1,
      'updated_at': now.millisecondsSinceEpoch,
      'activity': {
        '2026-09-15': {
          'second-device': {'count': 2, 'xp': 30},
        },
      },
      'learned': [2],
      'best_scores': {'2': 92.0},
    };
    await store.importProgress(remote);
    await store.importProgress(remote);
    expect(store.todayCount, 3);
    expect(store.totalXp, 40);
    expect(store.learnedIds, {1, 2});
    expect(store.bestScores[2], 92);
  });

  test(
    'newer unsaved state survives merging an older saved snapshot',
    () async {
      store.toggleSaved(1);
      final older = store.exportProgress();
      now = now.add(const Duration(seconds: 1));
      store.toggleSaved(1);
      await store.importProgress(older);
      expect(store.savedIds, isEmpty);
    },
  );

  test(
    'accounts have separate local histories and guest migration is once',
    () async {
      store.markReviewed(1, remembered: true);
      store.toggleSaved(1);
      await store.useAccount('account-a', migrateGuest: true);
      expect(store.learnedIds, {1});
      expect(store.totalXp, 10);

      await store.useAccount(null);
      expect(store.learnedIds, isEmpty);
      expect(store.totalXp, 0);

      await store.useAccount('account-b', migrateGuest: true);
      expect(store.learnedIds, isEmpty);
      store.markReviewed(2, remembered: true);

      await store.useAccount('account-a');
      expect(store.learnedIds, {1});
      expect(store.savedIds, {1});
      expect(store.totalXp, 10);
    },
  );

  test('invalid scores and goals cannot corrupt progress', () {
    expect(() => store.recordPronunciation(1, double.nan), throwsArgumentError);
    expect(() => store.recordPronunciation(1, 101), throwsArgumentError);
    expect(() => store.recordPronunciation(1, -1), throwsArgumentError);
    expect(() => store.setDailyGoal(0), throwsArgumentError);
    expect(() => store.setDailyGoal(101), throwsArgumentError);
    expect(store.totalXp, 0);
  });

  test('new guest work adds to previously migrated account activity', () async {
    store.markReviewed(1, remembered: true);
    await store.useAccount('account-a', migrateGuest: true);
    store.markReviewed(2, remembered: true);
    expect(store.todayCount, 2);

    await store.useAccount(null);
    store.markReviewed(3, remembered: true);
    await store.useAccount('account-a', migrateGuest: true);
    expect(store.todayCount, 3);
    expect(store.totalXp, 30);
    expect(store.learnedIds, {1, 2, 3});
  });
}
