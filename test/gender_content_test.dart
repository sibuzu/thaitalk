import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/models/speaker_gender.dart';

void main() {
  late List<LearningItem> items;

  setUpAll(() {
    items = LearningItem.parseCurriculum(
      File('thai_practice_dataset.json').readAsStringSync(),
    );
  });

  LearningItem item(int id) => items.singleWhere((item) => item.id == id);
  String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

  test(
    'both genders preserve IDs, meanings, native text and reversible selection',
    () {
      for (final source in items) {
        final female = source.forGender(SpeakerGender.female);
        final male = female.forGender(SpeakerGender.male);
        expect(
          identical(male, source),
          isTrue,
          reason: 'Round trip ${source.id}',
        );
        expect(female.id, source.id);
        expect(female.category, source.category);
        expect(female.level, source.level);
        expect(female.isSentence, source.isSentence);
        expect(female.chinese, source.chinese);
        expect(female.exampleChinese, source.exampleChinese);
        for (final selected in [male, female]) {
          expect(compact(selected.thai), compact(selected.speechText));
          if (source.id <= 300) {
            expect(selected.exampleThai, isNotNull);
            expect(selected.exampleRomanization, isNotEmpty);
            expect(
              selected.exampleRomanization,
              isNot(matches(RegExp(r'[ก-๙]'))),
            );
            expect(selected.exampleNativeThai, isNotNull);
            expect(
              compact(selected.exampleThai!),
              compact(selected.exampleNativeThai!),
              reason: 'Example display/native mismatch ${source.id}',
            );
          }
        }
        expect(female.forGender(SpeakerGender.female).thai, female.thai);
        expect(
          female.forGender(SpeakerGender.female).exampleThai,
          female.exampleThai,
        );
      }
    },
  );

  test(
    'all 100 female scenarios use reviewed pronouns and appropriate particles',
    () {
      final scenarios = items.where((item) => item.isSentence).toList();
      expect(scenarios, hasLength(100));
      final questionMarker = RegExp(r'ไหม|อะไร|ไหน|เท่าไร|กี่');
      for (final source in scenarios) {
        final female = source.forGender(SpeakerGender.female);
        expect(source.speechText, endsWith('ครับ'));
        expect(female.speechText, isNot(contains('ครับ')));
        expect(female.speechText, isNot(contains('ผม')));
        expect(female.thai, contains(' '));
        if (questionMarker.hasMatch(source.speechText) ||
            source.speechText.endsWith('นะครับ')) {
          expect(
            female.speechText,
            endsWith('คะ'),
            reason: 'Question/นะ ${source.id}',
          );
          expect(female.romanization, endsWith('khá'));
        } else {
          expect(
            female.speechText,
            endsWith('ค่ะ'),
            reason: 'Statement/request ${source.id}',
          );
          expect(female.romanization, endsWith('khâ'));
        }
        if (source.thai.split(' ').contains('ผม')) {
          expect(female.thai.split(' '), contains('ฉัน'));
          expect(female.romanization.split(' '), contains('chan'));
          expect(female.romanization.split(' '), isNot(contains('phom')));
        }
      }
    },
  );

  test('example romanization follows gender', () {
    expect(item(9).exampleRomanization, 'phom sabai di');
    expect(
      item(9).forGender(SpeakerGender.female).exampleRomanization,
      'chan sabai di',
    );
    expect(
      item(1).forGender(SpeakerGender.female).exampleRomanization,
      'sawatdi khâ',
    );
  });

  test('question, softened request and ordinary request remain distinct', () {
    expect(
      item(1003).forGender(SpeakerGender.female).speechText,
      'คุณชื่ออะไรคะ',
    );
    expect(
      item(1032).forGender(SpeakerGender.female).speechText,
      'ห้องของฉันอยู่ชั้นไหนคะ',
    );
    // The Thai utterance requests a menu; Chinese punctuation is not grammar.
    expect(
      item(1013).forGender(SpeakerGender.female).speechText,
      'ขอดูเมนูหน่อยค่ะ',
    );
    expect(
      item(1019).forGender(SpeakerGender.female).speechText,
      'ไม่ใส่พริกนะคะ',
    );
    expect(
      item(1089).forGender(SpeakerGender.female).speechText,
      'ถึงบ้านแล้วบอกฉันด้วยนะคะ',
    );
    expect(
      item(1090).forGender(SpeakerGender.female).speechText,
      'แล้วเจอกันอีกนะคะ',
    );
    expect(
      item(1100).forGender(SpeakerGender.female).speechText,
      'กรุณาติดต่อสถานทูตให้ฉันค่ะ',
    );
  });

  test(
    '500 dictionary headwords retain meaning while 68 speaker examples adapt',
    () {
      final vocabulary = items
          .where((item) => !item.isSentence && !item.isPhrase)
          .toList();
      expect(vocabulary, hasLength(500));
      var changedExamples = 0;
      for (final source in vocabulary) {
        final female = source.forGender(SpeakerGender.female);
        expect(female.thai, source.thai);
        expect(female.nativeThai, source.nativeThai);
        expect(female.romanization, source.romanization);
        expect(female.chinese, source.chinese);
        if (female.exampleThai != source.exampleThai) changedExamples++;
        if (source.id != 14) {
          expect(
            female.exampleNativeThai,
            isNot(contains('ผม')),
            reason: 'Pronoun ${source.id}',
          );
        }
        if (source.id != 19) {
          expect(
            female.exampleNativeThai,
            isNot(contains('ครับ')),
            reason: 'Particle ${source.id}',
          );
        }
      }
      expect(changedExamples, 68);
      expect(
        item(1).forGender(SpeakerGender.female).exampleNativeThai,
        'สวัสดีค่ะ',
      );
      expect(
        item(9).forGender(SpeakerGender.female).exampleNativeThai,
        'ฉันสบายดี',
      );
      expect(
        item(201).forGender(SpeakerGender.female).exampleNativeThai,
        'นี่คือหนังสือเดินทางของฉัน',
      );
      expect(
        item(2).forGender(SpeakerGender.female).exampleNativeThai,
        'ขอบคุณมาก',
      );
    },
  );

  test('gender-specific lexical entries keep their teaching examples', () {
    const examples = {
      14: 'ผมชื่อเจ',
      19: 'ขอบคุณครับ',
      20: 'ขอบคุณค่ะ',
      21: 'ไปไหนคะ',
    };
    for (final entry in examples.entries) {
      final source = item(entry.key);
      for (final gender in SpeakerGender.values) {
        final selected = source.forGender(gender);
        expect(selected.exampleNativeThai, entry.value);
        expect(selected.thai, source.thai);
        expect(selected.chinese, source.chinese);
      }
    }
  });

  test(
    'unreviewed fixtures and hair meaning are never guessed from substrings',
    () {
      const hair = LearningItem(
        id: 9001,
        thai: 'ผม',
        romanization: 'phom',
        chinese: '頭髮',
        category: 'greeting',
        level: 1,
        isSentence: false,
        exampleThai: 'ผม ของ ฉัน ยาว',
        exampleNativeThai: 'ผมของฉันยาว',
        exampleChinese: '我的頭髮很長',
      );
      const literalParticle = LearningItem(
        id: 9002,
        thai: 'ครับ',
        romanization: 'khrap',
        chinese: '男性禮貌語尾',
        category: 'greeting',
        level: 1,
        isSentence: false,
        exampleThai: 'คำ ว่า ครับ',
        exampleChinese: 'ครับ 這個詞',
      );
      for (final fixture in [hair, literalParticle]) {
        for (final gender in SpeakerGender.values) {
          expect(identical(fixture.forGender(gender), fixture), isTrue);
        }
      }
    },
  );

  test(
    'display-only explicit variants never retain stale male native speech',
    () {
      const source = LearningItem(
        id: 9003,
        thai: 'สวัสดี ครับ',
        nativeThai: 'สวัสดีครับ',
        romanization: 'sawatdi khrap',
        chinese: '你好',
        category: 'greeting',
        level: 1,
        isSentence: true,
        femaleVariant: {'thai': 'สวัสดี ค่ะ', 'romanization': 'sawatdi khâ'},
      );
      final female = source.forGender(SpeakerGender.female);
      expect(female.speechText, 'สวัสดี ค่ะ');
      expect(female.romanization, 'sawatdi khâ');
      expect(female.forGender(SpeakerGender.male).speechText, 'สวัสดีครับ');
    },
  );
}
