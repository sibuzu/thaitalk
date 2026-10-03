import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/main.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/models/study_language.dart';
import 'package:thaitalk/screens/home_screen.dart';
import 'package:thaitalk/screens/practice_screen.dart';
import 'package:thaitalk/services/app_settings.dart';
import 'package:thaitalk/services/cloud_sync.dart';
import 'package:thaitalk/services/curriculum_repository.dart';
import 'package:thaitalk/services/learning_store.dart';
import 'package:thaitalk/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final language in [StudyLanguage.korean, StudyLanguage.vietnamese]) {
    test('${language.name} has a complete, valid offline curriculum', () async {
      final items = await LearningItem.loadCurriculum(language: language);
      expect(items, hasLength(800));
      expect(items.where((i) => !i.isPhrase && !i.isSentence), hasLength(500));
      expect(items.where((i) => i.isPhrase), hasLength(200));
      expect(items.where((i) => i.isSentence), hasLength(100));
      expect(items.map((i) => i.id).toSet(), hasLength(800));
      expect(items.every((i) => i.language == language), isTrue);
      expect(items.every((i) => i.speechText == i.thai), isTrue);
      expect(items.every((i) => !i.showsFurigana), isTrue);
      expect(items.every((i) => i.romanization.isEmpty), isTrue);
      expect(
        items.every((i) => i.forGender(SpeakerGender.female) == i),
        isTrue,
      );
      expect(items.every((i) => i.categoryLabel != i.category), isTrue);
      expect(
        await File(language.datasetFilename).readAsBytes(),
        await File('assets/data/${language.datasetFilename}').readAsBytes(),
      );
      final data = jsonDecode(
        await File(language.datasetFilename).readAsString(),
      );
      data['vocabulary'][0][language.name] = '';
      expect(
        () =>
            LearningItem.parseCurriculum(jsonEncode(data), language: language),
        throwsFormatException,
      );
    });
  }

  test(
    'all four languages persist separate progress for identical IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings();
      for (final language in StudyLanguage.values) {
        final store = await LearningStore.load(language: language);
        expect(store.savedIds, isEmpty);
        expect(store.bestScores, isEmpty);
        expect(store.todayCount, 0);
        store.toggleSaved(language.index + 1);
        store.markReviewed(1, remembered: language.index.isEven);
        store.recordPronunciation(1001, 70 + language.index.toDouble());
        store.setDailyGoal(10 + language.index);
        await store.flush();
        store.dispose();
        await settings.setLanguage(language);
        final restored = AppSettings();
        await restored.load();
        expect(restored.language, language);
        restored.dispose();
      }
      for (final language in StudyLanguage.values) {
        final store = await LearningStore.load(language: language);
        expect(store.savedIds, {language.index + 1});
        expect(store.bestScores[1001], 70 + language.index);
        expect(store.learnedIds.contains(1), language.index.isEven);
        expect(store.todayCount, 2);
        expect(store.dailyGoal, 10 + language.index);
        store.dispose();
      }
      settings.dispose();
    },
  );

  testWidgets('phone switches all languages, searches, copies and quizzes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings.instance;
    await settings.load();
    await settings.setLanguage(StudyLanguage.thai);
    final curricula = <StudyLanguage, List<LearningItem>>{};
    final stores = <StudyLanguage, LearningStore>{};
    await tester.runAsync(() async {
      for (final family in ['NotoSansTC', 'NotoSerifThai', 'NotoSansKR']) {
        final suffix = family == 'NotoSerifThai' ? '' : '.subset';
        await (FontLoader(
          family,
        )..addFont(rootBundle.load('assets/fonts/$family$suffix.ttf'))).load();
      }
      for (final language in StudyLanguage.values) {
        curricula[language] = await CurriculumRepository.forLanguage(
          language,
        ).load();
      }
    });
    for (final language in StudyLanguage.values) {
      stores[language] = await LearningStore.load(language: language);
    }
    final cloud = await CloudSync.initialize(stores[StudyLanguage.thai]!);
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      ThaiTalkApp(
        items: curricula[StudyLanguage.thai]!,
        store: stores[StudyLanguage.thai]!,
        curricula: curricula,
        stores: stores,
        cloud: cloud,
      ),
    );
    await tester.pumpAndSettle();

    for (final language in [
      StudyLanguage.korean,
      StudyLanguage.vietnamese,
      StudyLanguage.japanese,
      StudyLanguage.thai,
    ]) {
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('settings-language-${language.name}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
      expect(home.language, language);
      expect(home.store, same(stores[language]));
      expect(home.items, same(curricula[language]));
      expect(
        find.text('${language.greeting(settings.gender)}  你好！'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Exercise the wide hero and sidebar as well as the narrow phone layout.
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpAndSettle();
      expect(
        find.text('YOUR DAILY DOSE OF ${language.name.toUpperCase()}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.text(language.searchHint), findsOneWidget);
      final item = curricula[language]!.first;
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        item.thai,
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-flashcards')));
      await tester.pumpAndSettle();
      final practice = tester.widget<PracticeScreen>(
        find.byType(PracticeScreen),
      );
      expect(practice.items.every((i) => i.language == language), isTrue);
      await tester.tap(find.byTooltip('複製${language.textLabel}'));
      await tester.pumpAndSettle();
      expect(practice.items.map((i) => i.thai), contains(copied));
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(NavigationBar)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library-quiz')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PracticeScreen>(find.byType(PracticeScreen)).quiz,
        isTrue,
      );
      final meanings = curricula[language]!.map((i) => i.chinese).toSet();
      for (var index = 0; index < 4; index++) {
        final choice = tester.widget<OutlinedButton>(
          find.byKey(ValueKey('quiz-choice-$index')),
        );
        final row = choice.child! as Row;
        final text = (row.children.last as Expanded).child as Text;
        expect(meanings, contains(text.data));
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    cloud.dispose();
    for (final store in stores.values) {
      await store.flush();
      store.dispose();
    }
  });

  testWidgets(
    'Korean and Vietnamese cards preserve native script without duplicate readings',
    (tester) async {
      final korean = LearningItem.parseCurriculum(
        File('korean_practice_dataset.json').readAsStringSync(),
        language: StudyLanguage.korean,
      ).first;
      final vietnamese = LearningItem.parseCurriculum(
        File('vietnamese_practice_dataset.json').readAsStringSync(),
        language: StudyLanguage.vietnamese,
      ).first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [learningText(korean), learningText(vietnamese)],
            ),
          ),
        ),
      );
      expect(find.text('안녕하세요'), findsOneWidget);
      expect(find.text('xin chào'), findsOneWidget);
      expect(find.byType(Text), findsNWidgets(2));
      expect(
        tester.widget<Text>(find.text('안녕하세요')).style!.fontFamily,
        'NotoSansKR',
      );
    },
  );
}
