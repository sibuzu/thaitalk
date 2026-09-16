import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/screens/practice_screen.dart';
import 'package:thaitalk/services/learning_store.dart';
import 'package:thaitalk/services/curriculum_repository.dart';
import 'package:thaitalk/theme.dart';

const practiceItems = [
  LearningItem(
    id: 9001,
    thai: 'สวัสดี ครับ',
    romanization: 'sà-wàt-dii khráp',
    chinese: '你好（男性用語）',
    category: 'greeting',
    level: 1,
    isSentence: false,
    exampleThai: 'สวัสดี ครับ คุณ สบายดี ไหม',
    exampleChinese: '你好，你好嗎？',
    exampleRomanization: 'sawatdi khrap khun sabai di mai',
  ),
  LearningItem(
    id: 9002,
    thai: 'ขอบคุณ ครับ',
    romanization: 'khàawp-khun khráp',
    chinese: '謝謝（男性用語）',
    category: 'greeting',
    level: 1,
    isSentence: false,
  ),
];

const longSentence = LearningItem(
  id: 9003,
  thai: 'ผม อยาก จอง ห้อง สำหรับ สอง คน คืนนี้ ครับ',
  romanization: 'phǒm yàak jaawng hâwng sǎm-ràp sǎawng khon khuen-níi khráp',
  chinese: '我想預訂今晚兩個人的房間。',
  category: 'hotel',
  level: 2,
  isSentence: true,
);

Future<LearningStore> pumpPractice(
  WidgetTester tester, {
  bool quiz = false,
  List<LearningItem> items = practiceItems,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LearningStore.load();
  Future<void> build() async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: PracticeScreen(items: items, store: store, quiz: quiz),
      ),
    );
    if (quiz) await CurriculumRepository.instance.load();
  }

  // The screen's large curriculum asset uses an isolate for JSON loading.
  if (quiz) {
    await tester.runAsync(build);
  } else {
    await build();
  }
  await tester.pumpAndSettle();
  return store;
}

Finder get previous => find.byKey(const ValueKey('practice-previous'));
Finder get next => find.byKey(const ValueKey('practice-next'));
Finder get choices => find.byWidgetPredicate(
  (widget) =>
      widget is OutlinedButton &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('quiz-choice-'),
);

List<String> choiceMeanings(WidgetTester tester) =>
    tester.widgetList<OutlinedButton>(choices).map((button) {
      final row = button.child! as Row;
      return ((row.children[2] as Expanded).child as Text).data!;
    }).toList();

void main() {
  testWidgets(
    'flashcards show Chinese immediately; arrows preserve review state',
    (tester) async {
      final store = await pumpPractice(tester);
      expect(find.text(practiceItems.first.chinese), findsOneWidget);
      expect(find.text('顯示中文意思'), findsNothing);
      expect(find.text('你好，你好嗎？'), findsNothing);
      expect(find.byTooltip('查看例句'), findsOneWidget);
      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      expect(store.todayCount, 0);

      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text(practiceItems[1].chinese), findsOneWidget);
      expect(store.todayCount, 0);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(find.text(practiceItems.first.chinese), findsOneWidget);

      await tester.tap(find.text('記住了'));
      await tester.pumpAndSettle();
      expect(store.learnedIds, contains(9001));
      expect(store.todayCount, 1);
      expect(find.text('第 2 / 2 題'), findsOneWidget);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '記住了'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '還要練習'))
            .onPressed,
        isNull,
      );
      final xpAfterFirst = store.totalXp;
      await tester.tap(find.text('記住了'));
      await tester.pumpAndSettle();
      expect(store.todayCount, 1);
      expect(store.totalXp, xpAfterFirst);

      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.text('還要練習'));
      await tester.pumpAndSettle();
      expect(store.learnedIds, isNot(contains(9002)));
      expect(store.todayCount, 2);
      expect(find.text('已複習 2 / 2 張 · 記住了 1 張'), findsOneWidget);
      await tester.tap(find.text('返回卡片'));
      await tester.pumpAndSettle();
      expect(find.text(practiceItems[1].chinese), findsOneWidget);
      expect(store.todayCount, 2);
      await store.flush();
    },
  );

  testWidgets(
    'quiz choices and answers survive backward navigation without extra XP',
    (tester) async {
      final store = await pumpPractice(tester, quiz: true);
      final initialChoices = choiceMeanings(tester);
      expect(initialChoices.toSet(), hasLength(4));
      expect(initialChoices, contains(practiceItems.first.chinese));
      expect(find.byKey(const ValueKey('flashcard-meaning')), findsNothing);
      expect(find.byKey(const ValueKey('quiz-feedback')), findsNothing);

      await tester.tap(find.text(practiceItems.first.chinese));
      await tester.pumpAndSettle();
      expect(store.todayCount, 1);
      expect(find.text('答對了'), findsOneWidget);
      final xpAfterFirst = store.totalXp;
      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(choiceMeanings(tester), initialChoices);
      expect(find.text('答對了'), findsOneWidget);
      expect(
        tester
            .widgetList<OutlinedButton>(choices)
            .every((button) => button.onPressed == null),
        isTrue,
      );
      await tester.tap(find.text(practiceItems.first.chinese));
      await tester.pumpAndSettle();
      expect(store.todayCount, 1);
      expect(store.totalXp, xpAfterFirst);

      await tester.tap(next);
      await tester.pumpAndSettle();
      await tester.tap(find.text(practiceItems[1].chinese));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('答對 2 / 2 題 · 正確率 100%'), findsOneWidget);
      expect(store.todayCount, 2);
      await store.flush();
    },
  );

  testWidgets(
    'wrong single-item quiz answer reveals correct meaning and score',
    (tester) async {
      final store = await pumpPractice(
        tester,
        quiz: true,
        items: [practiceItems.first],
      );
      final meanings = choiceMeanings(tester);
      expect(meanings.toSet(), hasLength(4));
      final wrong = meanings.firstWhere(
        (meaning) => meaning != practiceItems.first.chinese,
      );
      await tester.tap(find.text(wrong));
      await tester.pumpAndSettle();
      expect(find.text('正確：${practiceItems.first.chinese}'), findsOneWidget);
      expect(store.learnedIds, isEmpty);
      expect(store.nextReviewAt(9001), isNotNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('答對 0 / 1 題 · 正確率 0%'), findsOneWidget);
      expect(store.todayCount, 1);
      await store.flush();
    },
  );

  testWidgets('skipping cards does not claim or record completed reviews', (
    tester,
  ) async {
    final store = await pumpPractice(tester, items: [practiceItems.first]);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('已複習 0 / 1 張 · 記住了 0 張'), findsOneWidget);
    expect(store.todayCount, 0);
    expect(store.learnedIds, isEmpty);
    await store.flush();
  });

  testWidgets(
    'example sheet has Thai, Chinese, copy and TTS without practice controls',
    (tester) async {
      final store = await pumpPractice(tester);
      await tester.tap(find.byTooltip('查看例句'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('example-sheet'));
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(practiceItems.first.exampleThai!),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(practiceItems.first.exampleChinese!),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byTooltip('複製泰文')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byTooltip('Local TTS 播放')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byIcon(Icons.mic_none_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byTooltip('朗讀練習')),
        findsNothing,
      );
      expect(
        find.text(practiceItems.first.exampleRomanization!),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byTooltip('Azure TTS 播放')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('關閉例句'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      final controls = ['查看例句', 'Local TTS 播放', 'Azure TTS 播放', '朗讀練習'];
      for (var i = 1; i < controls.length; i++) {
        final previous = tester.getCenter(find.byTooltip(controls[i - 1]));
        final current = tester.getCenter(find.byTooltip(controls[i]));
        expect(current.dx, greaterThan(previous.dx));
        expect(current.dy, previous.dy);
      }
      expect(find.byTooltip('慢速朗讀'), findsNothing);
      expect(store.todayCount, 0);
      await store.flush();
    },
  );

  for (final quiz in [false, true]) {
    testWidgets(
      'long Thai ${quiz ? 'quiz' : 'flashcard'} and icons fit one narrow phone',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
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
        final store = await pumpPractice(
          tester,
          quiz: quiz,
          items: [longSentence],
        );
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('查看例句'), findsNothing);
        final card = find.byKey(const ValueKey('practice-card'));
        final cardRect = tester.getRect(card);
        for (final tooltip in [
          'Local TTS 播放',
          'Azure TTS 播放',
          '朗讀練習',
          '複製泰文',
        ]) {
          final control = find.byTooltip(tooltip);
          expect(find.descendant(of: card, matching: control), findsOneWidget);
          final rect = tester.getRect(control);
          expect(cardRect.contains(rect.center), isTrue);
          expect(rect.bottom, lessThanOrEqualTo(740));
        }
        expect(tester.getCenter(previous).dx, lessThan(cardRect.center.dx));
        expect(tester.getCenter(next).dx, greaterThan(cardRect.center.dx));
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.maxScrollExtent, 0);
        expect(find.text('男聲朗讀'), findsNothing);
        expect(find.text('聽一聽，再開口說'), findsNothing);
        if (!quiz) expect(find.text(longSentence.chinese), findsOneWidget);
        await tester.tap(find.byTooltip('複製泰文'));
        await tester.pumpAndSettle();
        expect(copied, longSentence.thai);
        if (quiz) {
          ScaffoldMessenger.of(
            tester.element(find.byType(PracticeScreen)),
          ).hideCurrentSnackBar();
          await tester.pumpAndSettle();
          await tester.tap(find.text(longSentence.chinese));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('quiz-feedback')), findsOneWidget);
          expect(scroll.position.maxScrollExtent, 0);
        }
        await store.flush();
      },
    );
  }
}
