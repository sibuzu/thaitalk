import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/models/study_language.dart';
import 'package:thaitalk/services/app_settings.dart';
import 'package:thaitalk/services/speech_cache.dart';
import 'package:thaitalk/services/speech_service.dart';
import 'package:thaitalk/services/speech_settings.dart';

class _CacheProbe extends SpeechCache {
  int reads = 0;
  int writes = 0;
  final values = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    values[key] = bytes;
  }
}

class _AudioProbe extends SpeechAudioOutput {
  final played = <Uint8List>[];
  int stops = 0;
  Completer<void>? pending;
  Completer<void>? started;
  bool holdPlayback = false;

  @override
  Future<void> play(Uint8List bytes) async {
    played.add(bytes);
    if (holdPlayback) pending = Completer<void>();
    started?.complete();
    await pending?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<void> dispose() => stop();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<Map<String, Object>> voices;
  late SpeechService service;
  late AppSettings preferences;
  late _CacheProbe cache;
  late _AudioProbe audio;
  Future<Object?> Function(MethodCall)? override;
  const offline = {
    'name': 'thai-local',
    'locale': 'th-TH',
    'network_required': '0',
    'features': '',
  };
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = AppSettings();
    cache = _CacheProbe();
    audio = _AudioProbe();
    calls = [];
    voices = [
      {'name': 'thai-network', 'locale': 'th-TH', 'network_required': '1'},
      {
        'name': 'thai-missing',
        'locale': 'th-TH',
        'network_required': '0',
        'features': 'notInstalled',
      },
      offline,
    ];
    override = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (override != null) return override!(call);
      if (call.method == 'getVoices') return voices;
      if (call.method == 'getDefaultVoice') return voices.first;
      return 1;
    });
    service = SpeechService(
      preferences: preferences,
      diskCache: cache,
      audioOutput: audio,
      settings: SpeechSettings(),
      client: MockClient(
        (_) async => throw StateError('Local TTS must never call HTTP'),
      ),
    );
  });
  tearDown(() {
    service.dispose();
    preferences.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final language in [StudyLanguage.korean, StudyLanguage.vietnamese]) {
    test(
      '${language.name} local voices select the right language and gender',
      () async {
        voices.addAll([
          for (final gender in SpeakerGender.values)
            {
              'name': '${language.name}-${gender.name}',
              'locale': language.speechLocale.replaceAll('-', '_'),
              'network_required': '0',
              'gender': gender.name,
            },
          {
            'name': '${language.name}-cloud',
            'locale': language.speechLocale,
            'network_required': '1',
          },
        ]);
        await preferences.setLanguage(language);
        for (final gender in SpeakerGender.values) {
          await preferences.setGender(gender);
          await service.speak(language.greeting(gender));
        }
        expect(
          calls.where((c) => c.method == 'setLanguage').map((c) => c.arguments),
          [language.speechLocale, language.speechLocale],
        );
        expect(
          calls
              .where((c) => c.method == 'setVoice')
              .map((c) => c.arguments['name']),
          ['${language.name}-male', '${language.name}-female'],
        );
        expect(cache.reads, 0);
        expect(cache.writes, 0);
        voices = [offline];
        await expectLater(
          service.speak(language.greeting(SpeakerGender.male)),
          throwsA(
            isA<SpeechException>().having(
              (e) => e.message,
              'correct installation guidance',
              contains('安裝離線${language.chineseName}'),
            ),
          ),
        );
      },
    );
  }

  test(
    'normal and slow Thai use installed offline voice with no Azure key or HTTP',
    () async {
      await service.speak('คน');
      await service.speak('มีคนเยอะมาก', slow: true);
      expect(cache.reads, 0);
      expect(cache.writes, 0);
      expect(audio.played, isEmpty);
      expect(
        calls.where((c) => c.method == 'setVoice').map((c) => c.arguments),
        [
          {'name': 'thai-local', 'locale': 'th-TH'},
          {'name': 'thai-local', 'locale': 'th-TH'},
        ],
      );
      expect(
        calls.where((c) => c.method == 'setSpeechRate').map((c) => c.arguments),
        [0.5, 0.375],
      );
      expect(
        calls
            .where((c) => c.method == 'speak')
            .map((c) => c.arguments is Map ? c.arguments['text'] : c.arguments),
        ['คน', 'มีคนเยอะมาก'],
      );
      expect(
        calls
            .where((c) => c.method == 'awaitSpeakCompletion')
            .every((c) => c.arguments == true),
        isTrue,
      );
    },
  );

  test(
    'network, missing, unknown-status and non-Thai voices are rejected',
    () async {
      voices = [
        {'name': 'cloud', 'locale': 'th-TH', 'network_required': '1'},
        {'name': 'unknown', 'locale': 'th-TH'},
        {
          'name': 'not-installed',
          'locale': 'th-TH',
          'network_required': '0',
          'features': 'notInstalled',
        },
        {'name': 'english', 'locale': 'en-US', 'network_required': '0'},
      ];
      await expectLater(
        service.speak('คน'),
        throwsA(
          isA<SpeechException>().having(
            (e) => e.message,
            'installation guidance',
            contains('安裝離線泰語'),
          ),
        ),
      );
      expect(calls.any((c) => c.method == 'speak'), isFalse);
      // Retrying after installing a voice re-queries the system.
      voices.add(offline);
      await service.speak('คน');
      expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    },
  );

  test('explicit play buttons override the old stored provider', () async {
    service.dispose();
    var requests = 0;
    service = SpeechService(
      preferences: preferences,
      settings: SpeechSettings(apiKey: 'test-key'),
      diskCache: cache,
      audioOutput: audio,
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(
          [0, 0, 1, 0],
          200,
          headers: {'content-type': 'audio/basic'},
        );
      }),
    );
    await preferences.setTtsProvider(TtsProvider.azure);
    await service.speak('คน', provider: TtsProvider.local);
    expect(requests, 0);
    expect(cache.reads, 0);
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    await preferences.setTtsProvider(TtsProvider.local);
    await service.speak('คน', provider: TtsProvider.azure);
    await service.speak('คน', provider: TtsProvider.azure);
    expect(requests, 1);
    expect(audio.played, hasLength(2));
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
  });

  test('empty and invalid input never starts local synthesis', () async {
    for (final text in ['', ' ', 'ก' * 501, 'ไทย\u0000']) {
      await expectLater(service.speak(text), throwsA(isA<SpeechException>()));
    }
    expect(calls, isEmpty);
  });

  test('dispose during voice discovery prevents delayed speech', () async {
    final pending = Completer<Object?>();
    final started = Completer<void>();
    override = (call) async {
      if (call.method == 'getVoices') {
        started.complete();
        return pending.future;
      }
      return 1;
    };
    final speaking = service.speak('คน');
    await started.future;
    service.dispose();
    await speaking;
    pending.complete([offline]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'speak'), isFalse);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
  });

  test('dispose unblocks an unfinished utterance and stops playback', () async {
    final pending = Completer<Object?>();
    final started = Completer<void>();
    override = (call) async {
      if (call.method == 'getVoices') return [offline];
      if (call.method == 'getDefaultVoice') return offline;
      if (call.method == 'speak') {
        started.complete();
        return pending.future;
      }
      return 1;
    };
    final speaking = service.speak('คน');
    await started.future;
    service.dispose();
    await speaking;
    pending.complete(1);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
  });

  test('engine failure is reported without cloud fallback', () async {
    override = (call) async {
      if (call.method == 'getVoices') return [offline];
      if (call.method == 'getDefaultVoice') return offline;
      return call.method == 'speak' ? 0 : 1;
    };
    await expectLater(
      service.speak('คน'),
      throwsA(
        isA<SpeechException>().having(
          (e) => e.message,
          'local error',
          contains('本機朗讀失敗'),
        ),
      ),
    );
  });
  test('asynchronous engine errors unblock the pending speak future', () async {
    final pending = Completer<Object?>();
    final started = Completer<void>();
    override = (call) async {
      if (call.method == 'getVoices') return [offline];
      if (call.method == 'getDefaultVoice') return offline;
      if (call.method == 'speak') {
        started.complete();
        return pending.future;
      }
      return 1;
    };
    final speaking = service.speak('คน');
    final expectation = expectLater(speaking, throwsA(isA<SpeechException>()));
    await started.future;
    // Native flutter_tts reports synthesis errors through this event rather
    // than completing its outstanding awaitSpeakCompletion method result.
    await messenger.handlePlatformMessage(
      'flutter_tts',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('speak.onError', 'engine failure'),
      ),
      (_) {},
    );
    await expectation;
    pending.complete(0);
  });

  test(
    'local voices honor explicit gender metadata without changing pitch',
    () async {
      voices = [
        {...offline, 'name': 'voice-a', 'gender': 'female'},
        {...offline, 'name': 'voice-b', 'gender': 'male'},
      ];
      await service.speak('ผม');
      await preferences.setGender(SpeakerGender.female);
      await service.speak('ฉัน');
      expect(
        calls
            .where((c) => c.method == 'setVoice')
            .map((c) => c.arguments['name']),
        ['voice-b', 'voice-a'],
      );
      expect(
        calls.where((c) => c.method == 'setPitch').map((c) => c.arguments),
        [1.0, 1.0],
      );
      expect(cache.reads, 0);
      expect(cache.writes, 0);
    },
  );

  test(
    'opaque voice names never imply gender; default offline voice wins',
    () async {
      voices = [
        {...offline, 'name': 'th-female-default'},
        {...offline, 'name': 'th-male-other'},
      ];
      await service.speak('ผม');
      await preferences.setGender(SpeakerGender.female);
      await service.speak('ฉัน');
      expect(
        calls
            .where((c) => c.method == 'setVoice')
            .map((c) => c.arguments['name']),
        ['th-female-default', 'th-female-default'],
      );
    },
  );

  test('switching to Azure cancels pending local voice discovery', () async {
    final pending = Completer<Object?>();
    final started = Completer<void>();
    override = (call) async {
      if (call.method == 'getVoices') {
        started.complete();
        return pending.future;
      }
      return 1;
    };
    final speaking = service.speak('คน');
    await started.future;
    await preferences.setTtsProvider(TtsProvider.azure);
    await speaking;
    pending.complete([offline]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'speak'), isFalse);
    expect(calls.any((c) => c.method == 'stop'), isTrue);
    expect(audio.played, isEmpty);
    expect(cache.reads, 0);
  });

  test(
    'Azure uses current gender and speed; local bypasses every cache layer',
    () async {
      service.dispose();
      final requests = <http.Request>[];
      service = SpeechService(
        preferences: preferences,
        settings: SpeechSettings(apiKey: 'test-key'),
        diskCache: cache,
        audioOutput: audio,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(
            [0, 0, 1, 0],
            200,
            headers: {'content-type': 'audio/basic'},
          );
        }),
      );
      await preferences.setTtsProvider(TtsProvider.azure);
      await service.speak('คน');
      await service.speak('คน');
      await preferences.setGender(SpeakerGender.female);
      await service.speak('คน');
      await service.speak('คน', slow: true);
      expect(requests, hasLength(3));
      expect(requests[0].body, contains('th-TH-NiwatNeural'));
      expect(requests[1].body, contains('th-TH-PremwadeeNeural'));
      expect(requests[2].body, contains('rate="-25%"'));
      expect(audio.played, hasLength(4));
      expect(calls.any((c) => c.method == 'speak'), isFalse);
      final reads = cache.reads;
      final writes = cache.writes;
      await preferences.setTtsProvider(TtsProvider.local);
      await service.speak('คน');
      expect(calls.where((c) => c.method == 'speak'), hasLength(1));
      expect(cache.reads, reads);
      expect(cache.writes, writes);
      expect(requests, hasLength(3));
      expect(audio.played, hasLength(4));
    },
  );

  test(
    'changing provider prevents a delayed Azure response from playing',
    () async {
      service.dispose();
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      service = SpeechService(
        preferences: preferences,
        settings: SpeechSettings(apiKey: 'test-key'),
        diskCache: cache,
        audioOutput: audio,
        client: MockClient((_) async {
          started.complete();
          return pending.future;
        }),
      );
      await preferences.setTtsProvider(TtsProvider.azure);
      final speaking = service.speak('คน');
      await started.future;
      await preferences.setTtsProvider(TtsProvider.local);
      await service.speak('คน');
      pending.complete(
        http.Response.bytes(
          [0, 0],
          200,
          headers: {'content-type': 'audio/basic'},
        ),
      );
      await speaking;
      expect(audio.played, isEmpty);
      expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    },
  );

  test('Azure errors do not fall back to local synthesis', () async {
    service.dispose();
    service = SpeechService(
      preferences: preferences,
      settings: SpeechSettings(apiKey: 'test-key'),
      diskCache: cache,
      audioOutput: audio,
      client: MockClient((_) async => http.Response('unavailable', 500)),
    );
    await preferences.setTtsProvider(TtsProvider.azure);
    await expectLater(service.speak('คน'), throwsA(isA<SpeechException>()));
    expect(calls.any((c) => c.method == 'speak'), isFalse);
    expect(audio.played, isEmpty);
  });

  test(
    'switching provider stops active Azure playback and unblocks speak',
    () async {
      service.dispose();
      audio = _AudioProbe()..holdPlayback = true;
      final started = audio.started = Completer<void>();
      service = SpeechService(
        preferences: preferences,
        settings: SpeechSettings(apiKey: 'test-key'),
        diskCache: cache,
        audioOutput: audio,
        client: MockClient(
          (_) async => http.Response.bytes(
            [0, 0],
            200,
            headers: {'content-type': 'audio/basic'},
          ),
        ),
      );
      await preferences.setTtsProvider(TtsProvider.azure);
      final speaking = service.speak('คน');
      await started.future;
      final stopsBeforeChange = audio.stops;
      await preferences.setTtsProvider(TtsProvider.local);
      await speaking;
      expect(audio.stops, greaterThan(stopsBeforeChange));
      expect(audio.pending!.isCompleted, isTrue);
    },
  );
}
