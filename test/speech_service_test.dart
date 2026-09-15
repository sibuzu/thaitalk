import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/services/speech_service.dart';

void main() {
  test('PCM recording is wrapped as valid mono 16kHz 16-bit WAV', () {
    final pcm = Uint8List.fromList([0, 0, 255, 127, 0, 128]);
    final wav = pcmToWav(pcm);
    final header = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.take(4)), 'RIFF');
    expect(header.getUint32(4, Endian.little), wav.length - 8);
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), pcm.length);
    expect(wav.sublist(44), pcm);
  });
  test('Assessment preserves service scores without invented defaults', () {
    final result = Assessment({
      'accuracy': 91.5,
      'fluency': 82,
      'completeness': 100,
      'pronunciationScore': 89,
      'recognizedText': 'สวัสดีครับ',
      'words': [],
    });
    expect(result.accuracy, 91.5);
    expect(result.overall, 89);
    expect(() => Assessment({'accuracy': 90}), throwsA(isA<TypeError>()));
  });
  test(
    'Azure flat and nested assessments preserve scores and missing word metadata',
    () {
      Map<String, dynamic> payload({bool nested = false}) {
        final scores = <String, dynamic>{
          'AccuracyScore': 91.5,
          'FluencyScore': 82,
          'CompletenessScore': 100,
          'PronScore': 89,
        };
        return {
          'RecognitionStatus': 'Success',
          'DisplayText': 'สวัสดีครับ',
          'NBest': [
            {
              if (nested) 'PronunciationAssessment': scores else ...scores,
              'Words': [
                {
                  'Word': 'สวัสดี',
                  if (nested)
                    'PronunciationAssessment': {'AccuracyScore': 91.5}
                  else
                    'AccuracyScore': 91.5,
                },
                {'Word': 'ครับ'},
              ],
            },
          ],
        };
      }

      for (final nested in [false, true]) {
        final result = Assessment.fromAzure(payload(nested: nested));
        expect(result.accuracy, 91.5);
        expect(result.overall, 89);
        expect(result.recognizedText, 'สวัสดีครับ');
        expect(result.words.first['accuracy'], 91.5);
        expect(result.words.first['errorType'], isNull);
        expect(result.words.last['accuracy'], isNull);
      }
      for (final invalidScore in [null, 101, -1, double.nan, '91']) {
        final value = payload();
        ((value['NBest'] as List).first as Map)['AccuracyScore'] = invalidScore;
        expect(
          () => Assessment.fromAzure(value),
          throwsA(isA<SpeechException>()),
        );
      }
      expect(
        () => Assessment.fromAzure({'RecognitionStatus': 'NoMatch'}),
        throwsA(isA<SpeechException>()),
      );
    },
  );
  test(
    'SSML escapes markup, rejects control characters, and defaults to male Thai',
    () {
      final ssml = buildSpeechSsml('สวัสดี <voice> & "ไทย"');
      expect(ssml, contains('th-TH-NiwatNeural'));
      expect(ssml, contains('&lt;voice&gt; &amp; &quot;ไทย&quot;'));
      for (final text in ['', ' ', 'ก' * 501, 'ไทย\u0000']) {
        expect(() => buildSpeechSsml(text), throwsA(isA<SpeechException>()));
      }
      expect(
        () => buildSpeechSsml('ไทย', voice: 'en-US-AriaNeural'),
        throwsA(isA<SpeechException>()),
      );
    },
  );
  test(
    'recordings validate exact format, chunk lengths and 30 second boundary',
    () {
      validateRecordingWav(pcmToWav(Uint8List(960000)));
      for (final pcmLength in [0, 320, 960002]) {
        expect(
          () => validateRecordingWav(pcmToWav(Uint8List(pcmLength))),
          throwsA(isA<SpeechException>()),
        );
      }
      for (final field in [(20, 3), (22, 2), (34, 8)]) {
        final wav = pcmToWav(Uint8List(8000));
        ByteData.sublistView(wav).setUint16(field.$1, field.$2, Endian.little);
        expect(
          () => validateRecordingWav(wav),
          throwsA(isA<SpeechException>()),
        );
      }
      final truncated = pcmToWav(Uint8List(8000));
      ByteData.sublistView(truncated).setUint32(40, 0xffffffff, Endian.little);
      expect(
        () => validateRecordingWav(truncated),
        throwsA(isA<SpeechException>()),
      );
    },
  );
}
