import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/speaker_gender.dart';

class LocalTtsException implements Exception {
  const LocalTtsException(this.message);
  final String message;
}

class _Cancelled implements Exception {}

/// Android system TTS. Only installed voices that do not require a network
/// are eligible; missing Thai data never falls back to a cloud voice.
class LocalTts {
  FlutterTts? _engine;
  Completer<int>? _cancel;
  Completer<int>? _playbackSignal;
  bool _disposed = false;
  int _generation = 0;
  static const missingVoice = '手機尚未安裝離線泰語語音。請到系統「文字轉語音」設定，安裝泰語語音資料後再試。';

  FlutterTts get _tts {
    if (_engine != null) return _engine!;
    final engine = FlutterTts();
    engine.setErrorHandler((_) => _signal(-1));
    engine.setCancelHandler(() => _signal(2));
    return _engine = engine;
  }

  void _signal(int value) {
    final signal = _playbackSignal;
    if (signal != null && !signal.isCompleted) signal.complete(value);
  }

  Future<dynamic> _step(
    Future<dynamic> work,
    Completer<int> cancel, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await Future.any([work, cancel.future]).timeout(timeout);
    if (_disposed || cancel.isCompleted) throw _Cancelled();
    return result;
  }

  static bool _offline(Map voice) {
    final network = voice['network_required'];
    return (network == false ||
            network == 0 ||
            network == '0' ||
            network == 'false') &&
        !(voice['features']?.toString().contains('notInstalled') ?? false);
  }

  Future<void> speak(
    String text, {
    bool slow = false,
    SpeakerGender gender = SpeakerGender.male,
  }) async {
    if (_disposed) throw const LocalTtsException('朗讀已結束，請重新開啟練習。');
    final generation = ++_generation;
    await _stopCurrent();
    if (_disposed || generation != _generation) return;
    final cancel = _cancel = Completer<int>();
    try {
      final engine = _tts;
      final raw = await _step(engine.getVoices, cancel);
      final voices = raw is List
          ? raw.whereType<Map>().where((voice) {
              final locale = voice['locale']
                  ?.toString()
                  .replaceAll('_', '-')
                  .toLowerCase();
              return (locale == 'th' || locale == 'th-th') &&
                  voice['name'] is String &&
                  _offline(voice);
            }).toList()
          : <Map>[];
      if (voices.isEmpty) throw const LocalTtsException(missingVoice);
      final defaultVoice = await _step(engine.getDefaultVoice, cancel);
      voices.sort(
        (a, b) => a['name'].toString().compareTo(b['name'].toString()),
      );
      // Some engines expose explicit gender metadata; Android's standard
      // Voice API does not. Never guess gender from a name or alter pitch.
      final genderVoices = voices.where((voice) {
        final value = voice['gender']?.toString().trim().toLowerCase();
        return value == gender.name;
      }).toList();
      final candidates = genderVoices.isEmpty ? voices : genderVoices;
      final voice = candidates.firstWhere(
        (v) => defaultVoice is Map && v['name'] == defaultVoice['name'],
        orElse: () => candidates.first,
      );
      if (await _step(engine.setLanguage('th-TH'), cancel) != 1 ||
          await _step(
                engine.setVoice({
                  'name': voice['name'] as String,
                  'locale': voice['locale'] as String,
                }),
                cancel,
              ) !=
              1) {
        throw const LocalTtsException(missingVoice);
      }
      // flutter_tts maps 0.5 to Android's normal 1.0 speech rate.
      await _step(engine.setSpeechRate(slow ? 0.375 : 0.5), cancel);
      await _step(engine.setPitch(1.0), cancel);
      await _step(engine.setVolume(1.0), cancel);
      await _step(engine.setQueueMode(0), cancel);
      await _step(engine.awaitSpeakCompletion(true), cancel);
      final signal = _playbackSignal = Completer<int>();
      final result = await _step(
        Future.any([engine.speak(text, focus: true), signal.future]),
        cancel,
        timeout: const Duration(minutes: 2),
      );
      if (result != 1 && result != 2) {
        throw const LocalTtsException('本機朗讀失敗，請確認系統泰語語音資料已安裝。');
      }
    } on _Cancelled {
      // Navigating away or starting a recording cancels pending synthesis.
    } on LocalTtsException {
      rethrow;
    } on TimeoutException {
      await stop();
      throw const LocalTtsException('本機語音引擎沒有回應，請檢查系統文字轉語音設定。');
    } on PlatformException {
      throw const LocalTtsException(missingVoice);
    } on MissingPluginException {
      throw const LocalTtsException('此版本未包含本機朗讀功能，請安裝更新後的 Android APK。');
    } finally {
      if (identical(_cancel, cancel)) {
        _cancel = null;
        _playbackSignal = null;
      }
    }
  }

  Future<void> _stopCurrent() async {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete(0);
    if (_engine == null) return;
    try {
      await _engine!.stop().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A missing/stopped TTS engine must not prevent recording or navigation.
    }
  }

  Future<void> stop() {
    _generation++;
    return _stopCurrent();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
  }
}
