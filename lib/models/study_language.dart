enum StudyLanguage { thai, japanese }

extension StudyLanguageDetails on StudyLanguage {
  String get displayName => switch (this) {
    StudyLanguage.thai => 'ภาษาไทย',
    StudyLanguage.japanese => '日本語',
  };

  String get flag => switch (this) {
    StudyLanguage.thai => '🇹🇭',
    StudyLanguage.japanese => '🇯🇵',
  };

  String get speechLocale => switch (this) {
    StudyLanguage.thai => 'th-TH',
    StudyLanguage.japanese => 'ja-JP',
  };

  String get datasetFilename => switch (this) {
    StudyLanguage.thai => 'thai_practice_dataset.json',
    StudyLanguage.japanese => 'japanese_practice_dataset.json',
  };
}
