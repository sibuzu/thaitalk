import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/services/app_settings.dart';

class ControlledPreferences implements SharedPreferences {
  String? stored;
  String? persisted;
  bool failWrites = false;
  Completer<void>? writeGate;

  @override
  String? getString(String key) => stored;

  @override
  Future<bool> setString(String key, String value) async {
    // Match SharedPreferences: process-local cache changes before disk writes.
    stored = value;
    await writeGate?.future;
    if (failWrites) return false;
    persisted = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    stored = null;
    if (failWrites) return false;
    persisted = null;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new settings default to male speaker and local TTS', () async {
    final settings = AppSettings();
    await settings.load();
    expect(settings.gender, SpeakerGender.male);
    expect(settings.provider, TtsProvider.local);
    expect(settings.error, isNull);
    settings.dispose();
  });

  test('gender and provider persist together across instances', () async {
    final settings = AppSettings();
    await settings.load();
    await settings.setGender(SpeakerGender.female);
    await settings.setTtsProvider(TtsProvider.azure);
    await settings.flush();

    final restarted = AppSettings();
    await restarted.load();
    expect(restarted.gender, SpeakerGender.female);
    expect(restarted.provider, TtsProvider.azure);
    final stored = (await SharedPreferences.getInstance()).getString(
      AppSettings.storageKey,
    )!;
    expect(jsonDecode(stored), {
      'version': 1,
      'gender': 'female',
      'tts_provider': 'azure',
    });
    settings.dispose();
    restarted.dispose();
  });

  test('queued changes preserve both settings without lost updates', () async {
    final settings = AppSettings();
    await Future.wait([
      settings.setGender(SpeakerGender.female),
      settings.setTtsProvider(TtsProvider.azure),
      settings.setGender(SpeakerGender.male),
    ]);
    final restarted = AppSettings();
    await restarted.load();
    expect(restarted.gender, SpeakerGender.male);
    expect(restarted.provider, TtsProvider.azure);
    settings.dispose();
    restarted.dispose();
  });

  test('a choice is published only once persistence succeeds', () async {
    final storage = ControlledPreferences()..writeGate = Completer<void>();
    final settings = AppSettings(preferences: storage);
    await settings.load();
    final saving = settings.setGender(SpeakerGender.female);
    await Future<void>.delayed(Duration.zero);
    expect(settings.isSaving, isTrue);
    expect(settings.gender, SpeakerGender.male);
    storage.writeGate!.complete();
    await saving;
    expect(settings.gender, SpeakerGender.female);
    expect(settings.isSaving, isFalse);
    settings.dispose();
  });

  test(
    'failed persistence keeps old choice and allows a later retry',
    () async {
      final storage = ControlledPreferences();
      final settings = AppSettings(preferences: storage);
      await settings.setGender(SpeakerGender.female);
      final previousSnapshot = storage.persisted;
      storage.failWrites = true;
      await expectLater(
        settings.setTtsProvider(TtsProvider.azure),
        throwsA(isA<AppSettingsException>()),
      );
      expect(settings.gender, SpeakerGender.female);
      expect(settings.provider, TtsProvider.local);
      expect(settings.error, contains('尚未儲存'));
      expect(settings.isSaving, isFalse);
      expect(storage.persisted, previousSnapshot);
      expect(storage.stored, previousSnapshot);
      final reloaded = AppSettings(preferences: storage);
      await reloaded.load();
      expect(reloaded.gender, SpeakerGender.female);
      expect(reloaded.provider, TtsProvider.local);
      reloaded.dispose();

      storage.failWrites = false;
      await settings.setTtsProvider(TtsProvider.azure);
      expect(settings.provider, TtsProvider.azure);
      expect(settings.error, isNull);
      settings.dispose();
    },
  );

  test('corrupt preferences use defaults and can be replaced', () async {
    final storage = ControlledPreferences()..stored = '{invalid';
    final settings = AppSettings(preferences: storage);
    await settings.load();
    expect(settings.gender, SpeakerGender.male);
    expect(settings.provider, TtsProvider.local);
    expect(settings.error, isNotNull);
    await settings.setGender(SpeakerGender.female);
    expect(settings.gender, SpeakerGender.female);
    expect(settings.error, isNull);
    settings.dispose();
  });

  test('failed first save removes the unsaved cached snapshot', () async {
    final storage = ControlledPreferences()..failWrites = true;
    final settings = AppSettings(preferences: storage);
    await expectLater(
      settings.setGender(SpeakerGender.female),
      throwsA(isA<AppSettingsException>()),
    );
    expect(storage.stored, isNull);
    expect(storage.persisted, isNull);
    final reloaded = AppSettings(preferences: storage);
    await reloaded.load();
    expect(reloaded.gender, SpeakerGender.male);
    expect(reloaded.provider, TtsProvider.local);
    settings.dispose();
    reloaded.dispose();
  });
}
