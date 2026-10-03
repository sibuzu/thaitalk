import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/study_language.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/services/app_settings.dart';
import 'package:thaitalk/services/speech_cache.dart';
import 'package:thaitalk/services/speech_service.dart';
import 'package:thaitalk/services/speech_settings.dart';

Map<String, dynamic> azureAssessment() => {
  'RecognitionStatus': 'Success',
  'NBest': [
    {
      'Display': 'สวัสดีครับ',
      'AccuracyScore': 89.5,
      'FluencyScore': 78,
      'CompletenessScore': 100,
      'PronScore': 84.7,
      'Words': [
        {'Word': 'สวัสดี', 'AccuracyScore': 90, 'ErrorType': 'None'},
        {'Word': 'ครับ', 'AccuracyScore': 57, 'ErrorType': 'Mispronunciation'},
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in [StudyLanguage.korean, StudyLanguage.vietnamese]) {
    test(
      '${language.name} uses its locale and both Azure voices with separate caches',
      () async {
        final preferences = AppSettings();
        await preferences.setLanguage(language);
        final requests = <http.Request>[];
        final speech = SpeechService(
          preferences: preferences,
          settings: SpeechSettings(apiKey: 'test-key'),
          diskCache: SpeechCache(maxBytes: 0),
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.host.contains('.tts.')) {
              return http.Response.bytes(
                [0, 0, 1, 0],
                200,
                headers: {'content-type': 'audio/basic'},
              );
            }
            return http.Response(
              jsonEncode(azureAssessment()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(() {
          speech.dispose();
          preferences.dispose();
        });
        final text = language.greeting(SpeakerGender.male);
        await speech.loadSpeechAudio(text);
        await speech.loadSpeechAudio(text);
        await preferences.setGender(SpeakerGender.female);
        await speech.loadSpeechAudio(text);
        expect(requests, hasLength(2));
        for (final gender in SpeakerGender.values) {
          final body = utf8.decode(requests[gender.index].bodyBytes);
          expect(body, contains(language.azureVoice(gender)));
          expect(body, contains('xml:lang="${language.speechLocale}"'));
          expect(body, contains(text));
        }
        await speech.assessAudio(pcmToWav(Uint8List(8000)), text);
        expect(
          requests.last.url.queryParameters['language'],
          language.speechLocale,
        );
        final assessment = jsonDecode(
          utf8.decode(
            base64Decode(requests.last.headers['Pronunciation-Assessment']!),
          ),
        );
        expect(assessment['ReferenceText'], text);
      },
    );
  }
  SpeechService service(MockClient client, {SpeechSettings? settings}) {
    final value = SpeechService(
      client: client,
      diskCache: SpeechCache(maxBytes: 0),
      preferences: AppSettings(),
      settings:
          settings ??
          SpeechSettings(apiKey: 'test-key', region: 'southeastasia'),
    );
    addTearDown(value.dispose);
    return value;
  }

  test(
    'uncached audio and assessment require an APK configured for Azure',
    () async {
      var requests = 0;
      final speech = service(
        MockClient((_) async {
          requests++;
          throw StateError('No request should be sent');
        }),
        settings: SpeechSettings(),
      );
      final unavailable = throwsA(
        isA<SpeechException>().having(
          (error) => error.message,
          'actionable error',
          contains('已設定的 APK'),
        ),
      );
      await expectLater(speech.loadSpeechAudio('สวัสดีครับ'), unavailable);
      await expectLater(
        speech.assessAudio(pcmToWav(Uint8List(8000)), 'สวัสดีครับ'),
        unavailable,
      );
      expect(requests, 0);
    },
  );

  test(
    'TTS calls Azure directly with safe SSML, male voice and correct audio format',
    () async {
      final pcm = Uint8List.fromList(List<int>.filled(8000, 17));
      final speech = service(
        MockClient((request) async {
          expect(
            request.url.toString(),
            'https://southeastasia.tts.speech.microsoft.com/cognitiveservices/v1',
          );
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(request.headers['Ocp-Apim-Subscription-Key'], 'test-key');
          expect(
            request.headers['X-Microsoft-OutputFormat'],
            'raw-16khz-16bit-mono-pcm',
          );
          expect(request.headers.containsKey('Authorization'), isFalse);
          final body = utf8.decode(request.bodyBytes);
          expect(body, contains('th-TH-NiwatNeural'));
          expect(body, contains('rate="-25%"'));
          expect(body, contains('สวัสดี &lt;audio&gt; &amp; &quot;ไทย&quot;'));
          expect(body, isNot(contains('test-key')));
          return http.Response.bytes(
            pcm,
            200,
            headers: {'content-type': 'audio/basic'},
          );
        }),
      );
      final wav = await speech.loadSpeechAudio(
        'สวัสดี <audio> & "ไทย"',
        slow: true,
      );
      validateRecordingWav(wav);
      expect(wav.sublist(44), pcm);
    },
  );

  test(
    'assessment sends native Thai reference, actual WAV and comprehensive settings directly',
    () async {
      final wav = pcmToWav(Uint8List(8000));
      final speech = service(
        MockClient((request) async {
          expect(request.url.host, 'southeastasia.stt.speech.microsoft.com');
          expect(request.url.queryParameters, {
            'language': 'th-TH',
            'format': 'detailed',
          });
          expect(request.headers['Content-Type'], contains('audio/wav'));
          expect(request.headers['Ocp-Apim-Subscription-Key'], 'test-key');
          expect(request.bodyBytes, wav);
          final parameters = jsonDecode(
            utf8.decode(
              base64Decode(request.headers['Pronunciation-Assessment']!),
            ),
          );
          expect(parameters, {
            'ReferenceText': 'สวัสดีครับ',
            'GradingSystem': 'HundredMark',
            'Granularity': 'Word',
            'Dimension': 'Comprehensive',
            'EnableMiscue': true,
          });
          return http.Response(
            jsonEncode(azureAssessment()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final result = await speech.assessAudio(wav, 'สวัสดีครับ');
      expect(result.accuracy, 89.5);
      expect(result.fluency, 78);
      expect(result.completeness, 100);
      expect(result.overall, 84.7);
      expect(result.recognizedText, 'สวัสดีครับ');
      expect(result.words.last['errorType'], 'Mispronunciation');
    },
  );

  test(
    'upstream status, invalid responses and connection errors never leak credentials',
    () async {
      for (final status in [400, 401, 403, 429, 500]) {
        final speech = service(
          MockClient(
            (_) async => http.Response('private key test-key response', status),
          ),
        );
        await expectLater(
          speech.loadSpeechAudio('สวัสดีครับ'),
          throwsA(
            isA<SpeechException>().having(
              (error) => error.message,
              'no secrets',
              isNot(contains('test-key')),
            ),
          ),
        );
      }
      final offline = service(
        MockClient((_) async => throw const SocketException('secret test-key')),
      );
      await expectLater(
        offline.loadSpeechAudio('สวัสดีครับ'),
        throwsA(
          isA<SpeechException>().having(
            (error) => error.message,
            'safe network error',
            contains('確認網路'),
          ),
        ),
      );
      for (final invalid in [
        http.Response(
          'not audio',
          200,
          headers: {'content-type': 'application/json'},
        ),
        http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/basic'},
        ),
        http.Response.bytes([], 200, headers: {'content-type': 'audio/basic'}),
      ]) {
        final speech = service(MockClient((_) async => invalid));
        await expectLater(
          speech.loadSpeechAudio('สวัสดีครับ'),
          throwsA(isA<SpeechException>()),
        );
      }
    },
  );

  test(
    'bad recording format and invalid region are rejected before a network call',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        throw StateError('No request should be sent');
      });
      final speech = service(client);
      final invalid = pcmToWav(Uint8List(8000));
      ByteData.sublistView(invalid).setUint32(24, 48000, Endian.little);
      await expectLater(
        speech.assessAudio(invalid, 'สวัสดีครับ'),
        throwsA(isA<SpeechException>()),
      );
      final badSettings = service(
        client,
        settings: SpeechSettings(
          apiKey: 'test-key',
          region: 'evil.example/path',
        ),
      );
      await expectLater(
        badSettings.loadSpeechAudio('สวัสดีครับ'),
        throwsA(isA<SpeechException>()),
      );
      expect(requests, 0);
    },
  );

  test('invalid assessment JSON and silence never invent a score', () async {
    final wav = pcmToWav(Uint8List(8000));
    for (final response in [
      'not JSON',
      '[]',
      jsonEncode({'RecognitionStatus': 'InitialSilenceTimeout'}),
    ]) {
      final speech = service(
        MockClient((_) async => http.Response(response, 200)),
      );
      await expectLater(
        speech.assessAudio(wav, 'สวัสดีครับ'),
        throwsA(isA<SpeechException>()),
      );
    }
  });
}
