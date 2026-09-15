import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thaitalk/services/speech_cache.dart';
import 'package:thaitalk/services/speech_service.dart';
import 'package:thaitalk/services/speech_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Direct Azure WAV persists across restarts and works offline without configuration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thaitalk-tts-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final pcm = Uint8List(3200);
      final wav = pcmToWav(pcm);
      var requests = 0;
      final requestedVoices = <String>[];
      final first = SpeechService(
        settings: SpeechSettings(apiKey: 'test-key', region: 'southeastasia'),
        diskCache: SpeechCache(directory: directory),
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'southeastasia.tts.speech.microsoft.com');
          requestedVoices.add(
            RegExp('voice name="([^"]+)"').firstMatch(request.body)!.group(1)!,
          );
          return http.Response.bytes(
            pcm,
            200,
            headers: {'content-type': 'audio/basic'},
          );
        }),
      );
      expect(await first.loadSpeechAudio('สวัสดีครับ'), wav);
      expect(await first.loadSpeechAudio('สวัสดีครับ'), wav);
      expect(requests, 1);
      await first.loadSpeechAudio('สวัสดีครับ', slow: true);
      await first.loadSpeechAudio('สวัสดีครับ', male: false);
      expect(requests, 3);
      expect(requestedVoices, [
        'th-TH-NiwatNeural',
        'th-TH-NiwatNeural',
        'th-TH-PremwadeeNeural',
      ]);
      first.dispose();
      final reopened = SpeechService(
        settings: SpeechSettings(),
        diskCache: SpeechCache(directory: directory),
        client: MockClient((_) async {
          requests++;
          throw const SocketException('offline');
        }),
      );
      expect(await reopened.loadSpeechAudio('สวัสดีครับ'), wav);
      expect(await reopened.loadSpeechAudio('สวัสดีครับ', slow: true), wav);
      expect(await reopened.loadSpeechAudio('สวัสดีครับ', male: false), wav);
      expect(requests, 3);
      await expectLater(
        reopened.loadSpeechAudio('ขอบคุณครับ'),
        throwsA(
          isA<SpeechException>().having(
            (error) => error.message,
            'setup guidance',
            contains('APK'),
          ),
        ),
      );
      expect(requests, 3);
      reopened.dispose();
    },
  );
}
