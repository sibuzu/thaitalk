import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/speaker_gender.dart';

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
  final SharedPreferences? preferences;
  SharedPreferences? _resolvedPreferences;
  SpeakerGender _gender = SpeakerGender.male;
  TtsProvider _provider = TtsProvider.local;
  String? _error;
  bool _loaded = false;
  bool _isSaving = false;
  bool _disposed = false;
  Future<void> _pending = Future<void>.value();

  SpeakerGender get gender => _gender;
  TtsProvider get provider => _provider;
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
        _provider = provider;
      }
      _error = null;
      _loaded = true;
    } on Object {
      _error = '無法讀取設定，請重新選擇說話者與朗讀方式。';
    }
    _notify();
  }

  Future<void> setGender(SpeakerGender gender) => _save(gender: gender);
  Future<void> setTtsProvider(TtsProvider provider) =>
      _save(provider: provider);

  Future<void> _save({SpeakerGender? gender, TtsProvider? provider}) =>
      _enqueue(() async {
        await _readIfNeeded();
        final nextGender = gender ?? _gender;
        final nextProvider = provider ?? _provider;
        if (_loaded &&
            _error == null &&
            nextGender == _gender &&
            nextProvider == _provider) {
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
              'tts_provider': nextProvider.name,
            }),
          );
          if (!saved) throw StateError('Preference write failed.');
          _gender = nextGender;
          _provider = nextProvider;
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
