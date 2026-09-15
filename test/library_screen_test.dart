import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/screens/library_screen.dart';
import 'package:thaitalk/services/learning_store.dart';
import 'package:thaitalk/theme.dart';

void main() {
  final words = List.generate(
    15,
    (index) => LearningItem(
      id: index + 1,
      thai: 'คำ ${index + 1}',
      nativeThai: 'คำ${index + 1}',
      romanization: 'word${index + 1}',
      chinese: '單字${index + 1}',
      category: index < 10 ? 'food' : 'greeting',
      level: index < 10 ? 1 : 2,
      isSentence: false,
    ),
  );
  const sentence = LearningItem(
    id: 1001,
    thai: 'ผม ไป ครับ',
    nativeThai: 'ผมไปครับ',
    romanization: 'phom pai khrap',
    chinese: '我走了',
    category: 'greeting',
    level: 1,
    isSentence: true,
  );
  late LearningStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    store.dispose();
  });

  Future<void> showLibrary(
    WidgetTester tester, {
    bool sentences = false,
    bool savedOnly = false,
    String? category,
    required void Function(List<LearningItem>, {bool quiz}) onPractice,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => LibraryScreen(
                items: [...words, sentence],
                store: store,
                sentences: sentences,
                savedOnly: savedOnly,
                initialCategory: category,
                onPractice: onPractice,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('word launchers pass the complete pool and show no item cards', (
    tester,
  ) async {
    store = await LearningStore.load();
    List<LearningItem>? launched;
    var quizMode = false;
    await showLibrary(
      tester,
      onPractice: (items, {quiz = false}) {
        launched = items;
        quizMode = quiz;
      },
    );
    expect(find.text('單字練習'), findsOneWidget);
    expect(find.text('15 個單字'), findsOneWidget);
    expect(find.text(words.first.thai), findsNothing);
    expect(find.text(words.first.chinese), findsNothing);
    expect(find.byTooltip('男聲朗讀'), findsNothing);
    expect(find.byTooltip('複製泰文'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('library-flashcards')));
    expect(launched, words);
    expect(quizMode, isFalse);
    await tester.tap(find.byKey(const ValueKey('library-quiz')));
    expect(launched, words);
    expect(quizMode, isTrue);
  });

  testWidgets('search narrows the pool without revealing a word card', (
    tester,
  ) async {
    store = await LearningStore.load();
    List<LearningItem>? launched;
    await showLibrary(
      tester,
      onPractice: (items, {quiz = false}) => launched = items,
    );
    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      words.last.speechText,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 個單字'), findsOneWidget);
    expect(find.text(words.last.thai), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-quiz')));
    expect(launched, [words.last]);
  });

  testWidgets('sentence selection launches sentences with no sentence cards', (
    tester,
  ) async {
    store = await LearningStore.load();
    List<LearningItem>? launched;
    await showLibrary(
      tester,
      sentences: true,
      onPractice: (items, {quiz = false}) => launched = items,
    );
    expect(find.text('句子練習'), findsOneWidget);
    expect(find.text('1 個句子'), findsOneWidget);
    expect(find.text(sentence.thai), findsNothing);
    expect(find.byTooltip('男聲朗讀'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('library-flashcards')));
    expect(launched, [sentence]);
  });

  testWidgets('initial topic and selected level both filter launched items', (
    tester,
  ) async {
    store = await LearningStore.load();
    List<LearningItem>? launched;
    await showLibrary(
      tester,
      category: 'greeting',
      onPractice: (items, {quiz = false}) => launched = items,
    );
    expect(find.text('5 個單字'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('library-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('入門 A1').last);
    await tester.pumpAndSettle();
    expect(find.text('沒有符合條件的內容'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('library-quiz')),
    );
    expect(button.onPressed, isNull);
    expect(launched, isNull);
  });

  testWidgets('saved cards remain usable after removing the selected topic', (
    tester,
  ) async {
    store = await LearningStore.load();
    store.toggleSaved(words.first.id);
    await showLibrary(
      tester,
      savedOnly: true,
      category: 'food',
      onPractice: (items, {quiz = false}) {},
    );
    expect(find.text(words.first.thai), findsOneWidget);
    expect(find.byTooltip('複製泰文'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('取消收藏'));
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(store.savedIds, isEmpty);
    expect(find.text('還沒有收藏內容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Finish fake-async preference writes before leaving this widget test.
    await store.flush();
    await tester.pumpWidget(const SizedBox());
  });
}
