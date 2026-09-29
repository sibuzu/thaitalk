import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/models/study_language.dart';
import 'package:thaitalk/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the bundled curriculum has 500 words, 200 phrases and 100 sentences',
    () async {
      final items = await LearningItem.loadCurriculum();
      expect(items.length, 800);
      expect(
        items.where((item) => !item.isSentence && !item.isPhrase).length,
        500,
      );
      expect(items.where((item) => item.isPhrase).length, 200);
      expect(items.where((item) => item.isSentence).length, 100);
      expect(items.map((item) => item.id).toSet().length, 800);
      expect(
        items
            .where((item) => item.isPhrase)
            .every(
              (item) =>
                  item.romanization.split(' ').length >= 3 &&
                  item.romanization.split(' ').length <= 5,
            ),
        isTrue,
      );
      expect(
        items.every((item) => item.thai.isNotEmpty && item.chinese.isNotEmpty),
        isTrue,
      );
    },
  );

  test('source and bundled curriculum remain identical', () async {
    expect(
      await File('assets/data/thai_practice_dataset.json').readAsString(),
      await File('thai_practice_dataset.json').readAsString(),
    );
  });

  test('Japanese curriculum counts and katakana reading rules', () async {
    final items = await LearningItem.loadCurriculum(
      language: StudyLanguage.japanese,
    );
    expect(items.length, 800);
    expect(
      items.where((item) => !item.isSentence && !item.isPhrase).length,
      500,
    );
    expect(items.where((item) => item.isPhrase).length, 200);
    expect(items.where((item) => item.isSentence).length, 100);
    expect(
      items.every((item) => item.language == StudyLanguage.japanese),
      isTrue,
    );
    expect(items.map((item) => item.id).toSet().length, 800);
    expect(
      items.where((item) => item.thai == 'アイスクリーム').single.showsFurigana,
      isFalse,
    );
    expect(
      items.where((item) => item.thai == 'メニュー').single.showsFurigana,
      isFalse,
    );
    const katakana = LearningItem(
      id: 1,
      thai: 'コーヒー',
      romanization: 'こーひー',
      chinese: '咖啡',
      category: 'food',
      level: 1,
      isSentence: false,
      language: StudyLanguage.japanese,
    );
    const kanji = LearningItem(
      id: 2,
      thai: '食事',
      romanization: 'しょくじ',
      chinese: '用餐',
      category: 'food',
      level: 1,
      isSentence: false,
      language: StudyLanguage.japanese,
    );
    expect(katakana.showsFurigana, isFalse);
    expect(kanji.showsFurigana, isTrue);
  });

  testWidgets('katakana card omits furigana while kanji card shows it', (
    tester,
  ) async {
    const katakana = LearningItem(
      id: 1,
      thai: 'コーヒー',
      romanization: 'こーひー',
      chinese: '咖啡',
      category: 'food',
      level: 1,
      isSentence: false,
      language: StudyLanguage.japanese,
    );
    const kanji = LearningItem(
      id: 2,
      thai: '食事',
      romanization: 'しょくじ',
      chinese: '用餐',
      category: 'food',
      level: 1,
      isSentence: false,
      language: StudyLanguage.japanese,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [learningText(katakana), learningText(kanji)]),
        ),
      ),
    );
    expect(find.text('コーヒー'), findsOneWidget);
    expect(find.text('こーひー'), findsNothing);
    expect(find.text('食事'), findsOneWidget);
    expect(find.text('しょくじ'), findsOneWidget);
  });

  test('male sentences are spaced for reading and native for speech', () async {
    final items = await LearningItem.loadCurriculum();
    for (final item in items) {
      expect(
        item.thai.replaceAll(RegExp(r'\s+'), ''),
        item.speechText.replaceAll(RegExp(r'\s+'), ''),
        reason: 'Display and speech text differ for item ${item.id}',
      );
      if (!item.isSentence) continue;
      expect(
        item.nativeThai,
        isNotNull,
        reason: 'Missing native sentence ${item.id}',
      );
      expect(item.thai, contains(' '), reason: 'Unspaced sentence ${item.id}');
      expect(item.speechText, isNot(contains('ฉัน')));
      expect(item.speechText, isNot(contains('ค่ะ')));
      expect(item.speechText, isNot(contains('คะ')));
      expect(item.speechText.trim(), endsWith('ครับ'));
    }
  });

  test('older model constructors fall back to display text for speech', () {
    const item = LearningItem(
      id: 1,
      thai: 'สวัสดี',
      romanization: 'sawatdi',
      chinese: '你好',
      category: 'greeting',
      level: 1,
      isSentence: false,
    );
    expect(item.speechText, 'สวัสดี');
    expect(item.categoryLabel, '打招呼');
  });
}
