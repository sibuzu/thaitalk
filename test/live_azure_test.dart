import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/services/speech_service.dart';
import 'package:thaitalk/services/speech_settings.dart';

void main() {
  test(
    'encoded APK configuration assesses a supplied Thai recording',
    () async {
      final settings = SpeechSettings.fromEnvironment();
      // Never put the key itself into a test expectation or diagnostics.
      expect(settings.isConfigured, isTrue);
      final path = Platform.environment['AZURE_TEST_WAV'];
      final phrase = Platform.environment['AZURE_TEST_REFERENCE'];
      if (path == null || phrase == null || phrase.trim().isEmpty) {
        fail(
          'Set AZURE_TEST_WAV to a 16 kHz mono PCM WAV and AZURE_TEST_REFERENCE to its Thai transcript.',
        );
      }
      final service = SpeechService(settings: settings);
      try {
        final wav = await File(path).readAsBytes();
        expect(wav.length, greaterThan(44));
        final result = await service.assessAudio(wav, phrase);
        expect(result.overall, inInclusiveRange(0, 100));
        expect(result.accuracy, inInclusiveRange(0, 100));
        expect(result.fluency, inInclusiveRange(0, 100));
        expect(result.completeness, inInclusiveRange(0, 100));
        expect(result.recognizedText, isNotEmpty);
      } finally {
        service.dispose();
      }
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_AZURE'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
