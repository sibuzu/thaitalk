import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/speaker_gender.dart';
import '../models/study_language.dart';

enum TtsProvider { local, azure }

class AppSettingsException implements Exception {
  const AppSettingsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Device preferences for learning examples and speech. No credentials are
/// stored here. A new choice becomes active only after it is persisted.
class AppSettings extends ChangeNotifier {
  AppSettings({this.preferences});

  static final instance = AppSettings();
  static const storageKey = 'thaitalk.app_settings.v1';
  static const questionCountOptions = [10, 20, 30, 50];
  final SharedPreferences? preferences;
  SharedPreferences? _resolvedPreferences;
  SpeakerGender _gender = SpeakerGender.male;
  StudyLanguage _language = StudyLanguage.thai;
  TtsProvider _provider = TtsProvider.local;
  int _questionsPerRound = 10;
  String? _error;
  bool _loaded = false;
  bool _isSaving = false;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  SpeakerGender get gender => _gender;
  StudyLanguage get language => _language;
  TtsProvider get provider => _provider;
  int get questionsPerRound => _questionsPerRound;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<SharedPreferences> _storage() async => _resolvedPreferences ??=
      preferences ?? await SharedPreferences.getInstance();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> load() => _enqueue(_readIfNeeded);

  Future<void> _readIfNeeded() async {
    if (_loaded) return;
    try {
      final source = (await _storage()).getString(storageKey);
      if (source != null) {
        final decoded = jsonDecode(source);
        if (decoded is! Map || decoded['version'] != 1) {
          throw const FormatException();
        }
        final gender = SpeakerGender.values.byName(decoded['gender'] as String);
        final provider = TtsProvider.values.byName(
          decoded['tts_provider'] as String,
        );
        _gender = gender;
        _language = StudyLanguage.values.byName(
          (decoded['language'] as String?) ?? 'thai',
        );
        _provider = provider;
        final count = decoded['questions_per_round'];
        _questionsPerRound = questionCountOptions.contains(count)
            ? count as int
            : 10;
      }
      _error = null;
      _loaded = true;
    } on Object {
      _error = '無法讀取設定，請重新選擇說話者與朗讀方式。';
    }
    _notify();
  }

  Future<void> setGender(SpeakerGender gender) => _save(gender: gender);
  Future<void> setLanguage(StudyLanguage language) => _save(language: language);
  Future<void> setTtsProvider(TtsProvider provider) =>
      _save(provider: provider);
  Future<void> setQuestionsPerRound(int count) {
    if (!questionCountOptions.contains(count)) {
      throw ArgumentError.value(count, 'count', 'Choose 10, 20, 30 or 50.');
    }
    return _save(questionsPerRound: count);
  }

  Future<void> _save({
    SpeakerGender? gender,
    StudyLanguage? language,
    TtsProvider? provider,
    int? questionsPerRound,
  }) => _enqueue(() async {
    await _readIfNeeded();
    final nextGender = gender ?? _gender;
    final nextLanguage = language ?? _language;
    final nextProvider = provider ?? _provider;
    final nextCount = questionsPerRound ?? _questionsPerRound;
    if (_loaded &&
        _error == null &&
        nextGender == _gender &&
        nextLanguage == _language &&
        nextProvider == _provider &&
        nextCount == _questionsPerRound) {
      return;
    }
    _isSaving = true;
    _error = null;
    _notify();
    SharedPreferences? storage;
    String? previousSnapshot;
    var capturedSnapshot = false;
    try {
      storage = await _storage();
      previousSnapshot = storage.getString(storageKey);
      capturedSnapshot = true;
      final saved = await storage.setString(
        storageKey,
        jsonEncode({
          'version': 1,
          'gender': nextGender.name,
          'language': nextLanguage.name,
          'tts_provider': nextProvider.name,
          'questions_per_round': nextCount,
        }),
      );
      if (!saved) throw StateError('Preference write failed.');
      _gender = nextGender;
      _language = nextLanguage;
      _provider = nextProvider;
      _questionsPerRound = nextCount;
      _loaded = true;
    } on Object {
      // SharedPreferences updates its process-local cache before the
      // platform confirms a write. Restore that cache as well, so another
      // settings instance cannot read an unpersisted choice as saved.
      if (capturedSnapshot && storage != null) {
        try {
          if (previousSnapshot == null) {
            await storage.remove(storageKey);
          } else {
            await storage.setString(storageKey, previousSnapshot);
          }
        } on Object {
          // The cache is updated before this best-effort rollback reaches
          // the same failing platform backend. Keep the visible error.
        }
      }
      _error = '設定尚未儲存，已保留原本選擇。請稍後再試。';
      throw AppSettingsException(_error!);
    } finally {
      _isSaving = false;
      _notify();
    }
  });

  /// Wait for previously requested preference writes to finish.
  Future<void> flush() => _pending;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
