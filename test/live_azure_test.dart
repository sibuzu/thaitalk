import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/services/speech_cache.dart';
import 'package:thaitalk/services/speech_service.dart';
import 'package:thaitalk/services/speech_settings.dart';

void main() {
  test(
    'encoded APK configuration directly synthesizes and assesses male Thai',
    () async {
      final settings = SpeechSettings.fromEnvironment();
      // Never put the key itself into a test expectation or diagnostics.
      expect(settings.isConfigured, isTrue);
      final directory = await Directory.systemTemp.createTemp('thaitalk-live-');
      final service = SpeechService(
        settings: settings,
        diskCache: SpeechCache(directory: directory),
      );
      try {
        const phrase = 'สวัสดีครับ';
        final wav = await service.loadSpeechAudio(phrase);
        expect(wav.length, greaterThan(44));
        final result = await service.assessAudio(wav, phrase);
        expect(result.overall, inInclusiveRange(0, 100));
        expect(result.accuracy, inInclusiveRange(0, 100));
        expect(result.fluency, inInclusiveRange(0, 100));
        expect(result.completeness, inInclusiveRange(0, 100));
        expect(result.recognizedText, isNotEmpty);
      } finally {
        service.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_AZURE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
