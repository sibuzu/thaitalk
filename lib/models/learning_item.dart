import 'dart:convert';

import 'package:flutter/services.dart';

import 'speaker_gender.dart';

/// One item from the bundled, offline Thai curriculum.
class LearningItem {
  const LearningItem({
    required this.id,
    required this.thai,
    required this.romanization,
    required this.chinese,
    required this.category,
    required this.level,
    required this.isSentence,
    this.nativeThai,
    this.exampleThai,
    this.exampleChinese,
    this.exampleRomanization,
    this.exampleNativeThai,
    Map<String, String> femaleVariant = const {},
    // Keep the constructor parameter public and the stored variant private.
    // ignore: prefer_initializing_formals
  }) : _femaleVariant = femaleVariant,
       _canonical = null;

  LearningItem._withGender(LearningItem source)
    : id = source.id,
      thai = source._femaleVariant['thai'] ?? source.thai,
      romanization =
          source._femaleVariant['romanization'] ?? source.romanization,
      chinese = source._femaleVariant['chinese'] ?? source.chinese,
      category = source.category,
      level = source.level,
      isSentence = source.isSentence,
      nativeThai =
          source._femaleVariant['thai_native'] ??
          (source._femaleVariant.containsKey('thai')
              ? null
              : source.nativeThai),
      exampleThai = source._femaleVariant['example_thai'] ?? source.exampleThai,
      exampleRomanization =
          source._femaleVariant['example_romanization'] ??
          source.exampleRomanization,
      exampleChinese =
          source._femaleVariant['example_chinese'] ?? source.exampleChinese,
      exampleNativeThai =
          source._femaleVariant['example_thai_native'] ??
          (source._femaleVariant.containsKey('example_thai')
              ? null
              : source.exampleNativeThai),
      _femaleVariant = source._femaleVariant,
      _canonical = source;

  final int id;
  final String thai;
  final String romanization;
  final String chinese;
  final String category;
  final int level;
  final bool isSentence;
  final String? nativeThai;
  final String? exampleThai;
  final String? exampleChinese;
  final String? exampleRomanization;
  final String? exampleNativeThai;

  final Map<String, String> _femaleVariant;
  final LearningItem? _canonical;

  String get speechText => nativeThai ?? thai;

  /// Uses reviewed curriculum variants, never guesses grammar from substrings.
  /// Dictionary headwords and their meanings remain the same in either mode.
  /// Switching an adapted item back to male restores its canonical source.
  LearningItem forGender(SpeakerGender gender) {
    final source = _canonical ?? this;
    if (gender == SpeakerGender.male || source._femaleVariant.isEmpty) {
      return source;
    }
    return LearningItem._withGender(source);
  }

  factory LearningItem.fromJson(
    Map<String, dynamic> json, {
    required bool isSentence,
  }) {
    if (json['id'] is! int ||
        (json['id'] as int) <= 0 ||
        !const [1, 2].contains(json['level'])) {
      throw const FormatException('Invalid curriculum ID or level.');
    }
    for (final field in ['thai', 'romanization', 'chinese', 'category']) {
      _validateText(json[field]);
    }
    for (final field in [
      'thai_native',
      'example_thai',
      'example_thai_native',
      'example_chinese',
      'example_romanization',
    ]) {
      if (json[field] != null) _validateText(json[field]);
    }
    final female = json['female'];
    if (female != null) {
      if (female is! Map) {
        throw const FormatException('Invalid gender variant.');
      }
      for (final value in female.values) {
        _validateText(value);
      }
    }
    return LearningItem(
      id: (json['id'] as num).toInt(),
      thai: json['thai'] as String,
      romanization: json['romanization'] as String,
      chinese: json['chinese'] as String,
      category: json['category'] as String,
      level: (json['level'] as num).toInt(),
      isSentence: isSentence,
      nativeThai: json['thai_native'] as String?,
      exampleThai: json['example_thai'] as String?,
      exampleChinese: json['example_chinese'] as String?,
      exampleRomanization: json['example_romanization'] as String?,
      exampleNativeThai: json['example_thai_native'] as String?,
      femaleVariant: Map<String, String>.unmodifiable(
        Map<String, String>.from(json['female'] as Map? ?? const {}),
      ),
    );
  }

  static void _validateText(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 2000) {
      throw const FormatException('Invalid curriculum text.');
    }
  }

  String get categoryLabel => categoryLabels[category] ?? category;
  String get levelLabel => level == 1 ? '入門' : '基礎';

  static const categoryLabels = <String, String>{
    'greeting': '打招呼',
    'food': '飲食',
    'numbers': '數字',
    'shopping': '購物',
    'time': '時間',
    'transport': '交通',
    'travel': '旅行',
    'verbs': '常用動詞',
    'airport': '機場',
    'dating': '交朋友',
    'emergency': '緊急求助',
    'hotel': '住宿',
    'restaurant': '餐廳',
    'taxi': '搭計程車',
  };

  static List<LearningItem> parseCurriculum(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    final items = <LearningItem>[
      for (final value in data['vocabulary'] as List<dynamic>)
        LearningItem.fromJson(
          Map<String, dynamic>.from(value as Map),
          isSentence: false,
        ),
      for (final value in data['sentences'] as List<dynamic>)
        LearningItem.fromJson(
          Map<String, dynamic>.from(value as Map),
          isSentence: true,
        ),
    ];
    if (items.isEmpty || items.length > 10000) {
      throw const FormatException('Invalid curriculum size.');
    }
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Curriculum contains duplicate item IDs.');
    }
    String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
    for (final source in items) {
      for (final gender in SpeakerGender.values) {
        final item = source.forGender(gender);
        if (compact(item.thai) != compact(item.speechText) ||
            (item.exampleNativeThai != null &&
                (item.exampleThai == null ||
                    compact(item.exampleThai!) !=
                        compact(item.exampleNativeThai!)))) {
          throw const FormatException('Display and speech text differ.');
        }
      }
    }
    return List<LearningItem>.unmodifiable(items);
  }

  static Future<List<LearningItem>> loadCurriculum() async {
    return parseCurriculum(
      await rootBundle.loadString('assets/data/thai_practice_dataset.json'),
    );
  }
}

Future<List<LearningItem>> loadCurriculum() => LearningItem.loadCurriculum();
