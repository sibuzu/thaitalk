import 'speaker_gender.dart';

enum StudyLanguage { thai, japanese, korean, vietnamese }

extension StudyLanguageDetails on StudyLanguage {
  String get displayName => switch (this) {
    StudyLanguage.thai => 'ภาษาไทย',
    StudyLanguage.japanese => '日本語',
    StudyLanguage.korean => '한국어',
    StudyLanguage.vietnamese => 'Tiếng Việt',
  };

  String get flag => switch (this) {
    StudyLanguage.thai => '🇹🇭',
    StudyLanguage.japanese => '🇯🇵',
    StudyLanguage.korean => '🇰🇷',
    StudyLanguage.vietnamese => '🇻🇳',
  };

  String get speechLocale => switch (this) {
    StudyLanguage.thai => 'th-TH',
    StudyLanguage.japanese => 'ja-JP',
    StudyLanguage.korean => 'ko-KR',
    StudyLanguage.vietnamese => 'vi-VN',
  };

  String get datasetFilename => '${name}_practice_dataset.json';

  String get chineseName => switch (this) {
    StudyLanguage.thai => '泰語',
    StudyLanguage.japanese => '日語',
    StudyLanguage.korean => '韓語',
    StudyLanguage.vietnamese => '越南語',
  };

  String get textLabel => switch (this) {
    StudyLanguage.thai => '泰文',
    StudyLanguage.japanese => '日文',
    StudyLanguage.korean => '韓文',
    StudyLanguage.vietnamese => '越南文',
  };

  String? get readingField => switch (this) {
    StudyLanguage.thai => 'romanization',
    StudyLanguage.japanese => 'reading',
    StudyLanguage.korean || StudyLanguage.vietnamese => null,
  };

  String get fontFamily => this == StudyLanguage.thai
      ? 'NotoSerifThai'
      : this == StudyLanguage.korean
      ? 'NotoSansKR'
      : 'NotoSansTC';

  String greeting(SpeakerGender gender) => switch (this) {
    StudyLanguage.thai =>
      gender == SpeakerGender.male ? 'สวัสดี ครับ' : 'สวัสดี ค่ะ',
    StudyLanguage.japanese => 'こんにちは',
    StudyLanguage.korean => '안녕하세요',
    StudyLanguage.vietnamese => 'Xin chào',
  };

  String get heroCharacter => switch (this) {
    StudyLanguage.thai => 'ก',
    StudyLanguage.japanese => 'あ',
    StudyLanguage.korean => '한',
    StudyLanguage.vietnamese => 'ă',
  };

  String get searchHint => switch (this) {
    StudyLanguage.thai => '搜尋泰文、拼音或中文…',
    StudyLanguage.japanese => '搜尋日文、假名或中文…',
    StudyLanguage.korean => '搜尋韓文或中文…',
    StudyLanguage.vietnamese => '搜尋越南文或中文…',
  };

  String levelLabel(int level) => this == StudyLanguage.japanese
      ? (level == 1 ? 'N3' : 'N2')
      : (level == 1 ? '入門' : '基礎');

  String filterLevelLabel(int level) => this == StudyLanguage.thai
      ? (level == 1 ? '入門 A1' : '基礎 A2')
      : levelLabel(level);

  String learningTip(SpeakerGender gender) => switch (this) {
    StudyLanguage.thai =>
      gender == SpeakerGender.male
          ? '男性說話時，在句尾加上「ครับ khrap」，就能讓語氣更有禮貌。'
          : '女性陳述用「ค่ะ kha」，疑問通常用「คะ kha」。',
    StudyLanguage.japanese => '遇到漢字時先看上方假名，再聽發音跟讀；片假名詞彙直接練習朗讀。',
    StudyLanguage.korean => '先看韓文字母組成的音節，再聽發音跟讀。和不熟的人交談時，練習使用「요」結尾的禮貌說法。',
    StudyLanguage.vietnamese => '越南文的聲調符號會影響詞義；跟讀時留意母音與聲調。稱呼會隨年齡和關係改變。',
  };

  String azureVoice(SpeakerGender gender) => switch ((this, gender)) {
    (StudyLanguage.thai, SpeakerGender.male) => 'th-TH-NiwatNeural',
    (StudyLanguage.thai, SpeakerGender.female) => 'th-TH-PremwadeeNeural',
    (StudyLanguage.japanese, SpeakerGender.male) => 'ja-JP-KeitaNeural',
    (StudyLanguage.japanese, SpeakerGender.female) => 'ja-JP-NanamiNeural',
    (StudyLanguage.korean, SpeakerGender.male) => 'ko-KR-InJoonNeural',
    (StudyLanguage.korean, SpeakerGender.female) => 'ko-KR-SunHiNeural',
    (StudyLanguage.vietnamese, SpeakerGender.male) => 'vi-VN-NamMinhNeural',
    (StudyLanguage.vietnamese, SpeakerGender.female) => 'vi-VN-HoaiMyNeural',
  };
}
