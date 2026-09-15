import 'dart:convert';

import 'package:flutter/services.dart';

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
    this.exampleNativeThai,
  });

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
  final String? exampleNativeThai;

  String get speechText => nativeThai ?? thai;

  factory LearningItem.fromJson(
    Map<String, dynamic> json, {
    required bool isSentence,
  }) {
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
      exampleNativeThai: json['example_thai_native'] as String?,
    );
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
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Curriculum contains duplicate item IDs.');
    }
    return List<LearningItem>.unmodifiable(items);
  }

  static Future<List<LearningItem>> loadCurriculum() async {
    return parseCurriculum(
      await rootBundle.loadString('assets/data/thai_practice_dataset_400.json'),
    );
  }
}

Future<List<LearningItem>> loadCurriculum() => LearningItem.loadCurriculum();
