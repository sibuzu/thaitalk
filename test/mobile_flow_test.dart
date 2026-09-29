import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/main.dart';
import 'package:thaitalk/services/curriculum_repository.dart';
import 'package:thaitalk/screens/practice_screen.dart';
import 'package:thaitalk/services/cloud_sync.dart';
import 'package:thaitalk/services/learning_store.dart';

void main() {
  testWidgets(
    '320px phone launches word, phrase and sentence rounds and copies Thai',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = await LearningStore.load();
      final cloud = await CloudSync.initialize(store);
      final items = (await tester.runAsync(() async {
        // Actual glyph widths catch layout problems hidden by test fonts.
        await (FontLoader('NotoSansTC')
              ..addFont(rootBundle.load('assets/fonts/NotoSansTC.subset.ttf')))
            .load();
        await (FontLoader(
          'NotoSerifThai',
        )..addFont(rootBundle.load('assets/fonts/NotoSerifThai.ttf'))).load();
        return CurriculumRepository.instance.load();
      }))!;
      final sentence = items
          .where((item) => item.isSentence)
          .reduce((a, b) => a.thai.length > b.thai.length ? a : b);
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      Future<void> copyAndDismissNotice() async {
        await tester.tap(find.byTooltip('複製泰文'));
        await tester.pumpAndSettle();
        expect(find.text('已複製泰文'), findsOneWidget);
        final closeTooltip = MaterialLocalizations.of(
          tester.element(find.byType(SnackBar)),
        ).closeButtonTooltip;
        await tester.tap(find.byTooltip(closeTooltip));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        ThaiTalkApp(items: items, store: store, cloud: cloud),
      );
      await tester.pumpAndSettle();
      expect(find.text('開始今日練習'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.text('單字練習'), findsOneWidget);
      expect(find.byTooltip('複製泰文'), findsNothing);
      expect(tester.takeException(), isNull);
      final flashcards = find.byKey(const ValueKey('library-flashcards'));
      await tester.ensureVisible(flashcards);
      await tester.tap(flashcards);
      await tester.pumpAndSettle();
      final round = tester.widget<PracticeScreen>(find.byType(PracticeScreen));
      expect(round.items, hasLength(10));
      expect(round.items.map((item) => item.id).toSet(), hasLength(10));
      expect(round.items.every((item) => !item.isSentence), isTrue);
      final word = round.items.first;
      expect(find.text(word.thai), findsOneWidget);
      expect(find.text(word.chinese), findsOneWidget);
      expect(
        tester.widget<Text>(find.text(word.thai)).style?.fontFamily,
        'NotoSerifThai',
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('practice-next')));
      await tester.pumpAndSettle();
      expect(find.text(round.items[1].thai), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('practice-previous')));
      await tester.pumpAndSettle();
      expect(find.text(word.thai), findsOneWidget);
      expect(
        store.todayCount,
        0,
        reason: 'Browsing must not count as an answer.',
      );
      await copyAndDismissNotice();
      expect(clipboardText, word.thai);
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('句子練習'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('片語練習'), findsOneWidget);
      await tester.ensureVisible(flashcards);
      await tester.tap(flashcards);
      await tester.pumpAndSettle();
      final phraseRound = tester.widget<PracticeScreen>(
        find.byType(PracticeScreen),
      );
      expect(phraseRound.items, hasLength(10));
      expect(phraseRound.items.every((item) => item.isPhrase), isTrue);
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('句子練習'), findsOneWidget);
      expect(find.byTooltip('複製泰文'), findsNothing);
      final search = find.byKey(const ValueKey('library-search'));
      await tester.enterText(search, sentence.speechText);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      expect(find.text(sentence.thai), findsNothing);
      await tester.ensureVisible(flashcards);
      await tester.tap(flashcards);
      await tester.pumpAndSettle();
      final filteredRound = tester.widget<PracticeScreen>(
        find.byType(PracticeScreen),
      );
      expect(filteredRound.items.map((item) => item.id), [sentence.id]);
      expect(find.text(sentence.thai), findsOneWidget);
      expect(find.text(sentence.chinese), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Longest sentence fits.');
      await copyAndDismissNotice();
      expect(clipboardText, sentence.thai);
      expect(clipboardText, contains(' '));
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('清除搜尋'));
      await tester.pumpAndSettle();
      final quiz = find.byKey(const ValueKey('library-quiz'));
      await tester.ensureVisible(quiz);
      await tester.runAsync(() async {
        await tester.tap(quiz);
        await tester.pump();
        await CurriculumRepository.instance.load();
      });
      await tester.pumpAndSettle();
      final quizRound = tester.widget<PracticeScreen>(
        find.byType(PracticeScreen),
      );
      expect(quizRound.quiz, isTrue);
      expect(quizRound.items, hasLength(10));
      expect(quizRound.items.every((item) => item.isSentence), isTrue);
      expect(quizRound.items.map((item) => item.id).toSet(), hasLength(10));
      expect(tester.takeException(), isNull);

      await store.flush();
      await tester.pumpWidget(const SizedBox());
      cloud.dispose();
      store.dispose();
    },
  );
}
