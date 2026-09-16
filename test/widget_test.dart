import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/main.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/services/cloud_sync.dart';
import 'package:thaitalk/services/learning_store.dart';

void main() {
  testWidgets(
    'New learner sees real empty progress and can change daily goal',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LearningStore.load();
      final cloud = await CloudSync.initialize(store);
      final items = (await tester.runAsync(loadCurriculum))!;
      await tester.pumpWidget(
        ThaiTalkApp(items: items, store: store, cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(find.text('สวัสดี ครับ  你好！'), findsOneWidget);
      expect(find.text('開始今日練習'), findsOneWidget);
      expect(store.totalXp, 0);
      expect(store.learnedIds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(NavigationDestination).last);
      await tester.pumpAndSettle();
      expect(find.text('每一點努力，都算數。'), findsOneWidget);
      await tester.ensureVisible(find.text('20 個練習 / 天'));
      await tester.tap(find.text('20 個練習 / 天'));
      await tester.pumpAndSettle();
      expect(store.dailyGoal, 20);
      await store.flush();
      expect((await LearningStore.load()).dailyGoal, 20);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      cloud.dispose();
      store.dispose();
    },
  );
  testWidgets(
    'updated curriculum can change counts without breaking daily word',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LearningStore.load();
      final cloud = await CloudSync.initialize(store);
      final all = (await tester.runAsync(loadCurriculum))!;
      final small = [
        all.firstWhere((item) => !item.isSentence),
        all.firstWhere((item) => item.isSentence),
      ];
      await tester.pumpWidget(
        ThaiTalkApp(items: small, store: store, cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 個單字 · 1 個主題'), findsOneWidget);
      expect(find.text('1 個句子 · 1 個情境'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      cloud.dispose();
      store.dispose();
    },
  );
}
