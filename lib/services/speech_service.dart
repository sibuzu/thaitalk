import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../models/speaker_gender.dart';
import '../models/study_language.dart';
import 'app_settings.dart';
import 'local_tts.dart';
import 'speech_cache.dart';
import 'speech_settings.dart';

class SpeechException implements Exception {
  SpeechException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Assessment {
  Assessment(Map<String, dynamic> json)
    : accuracy = (json['accuracy'] as num).toDouble(),
      fluency = (json['fluency'] as num).toDouble(),
      completeness = (json['completeness'] as num).toDouble(),
      overall = (json['pronunciationScore'] as num).toDouble(),
      recognizedText = json['recognizedText'] as String? ?? '',
      words = (json['words'] as List? ?? []).cast<Map<String, dynamic>>();

  factory Assessment.fromAzure(Map<String, dynamic> result) {
    if (const [
      'NoMatch',
      'InitialSilenceTimeout',
      'BabbleTimeout',
    ].contains(result['RecognitionStatus'])) {
      throw SpeechException('沒有辨識到清楚的語音，請靠近麥克風再試一次。');
    }
    final alternatives = result['NBest'];
    if (result['RecognitionStatus'] != 'Success' ||
        alternatives is! List ||
        alternatives.isEmpty ||
        alternatives.first is! Map) {
      throw SpeechException('Azure 沒有回傳發音評分，請再試一次。');
    }
    final best = alternatives.first as Map;
    // REST uses flat scores; SDK-compatible responses can nest the same data.
    final details = best['PronunciationAssessment'] is Map
        ? best['PronunciationAssessment'] as Map
        : best;
    final accuracy = _score(details['AccuracyScore']);
    final fluency = _score(details['FluencyScore']);
    final completeness = _score(details['CompletenessScore']);
    final overall = _score(details['PronScore']);
    if ([accuracy, fluency, completeness, overall].contains(null)) {
      throw SpeechException('Azure 回傳的評分不完整，請重新朗讀後再試一次。');
    }
    final words = <Map<String, dynamic>>[];
    if (best['Words'] is List) {
      for (final word in best['Words'] as List) {
        if (word is! Map || word['Word'] is! String) continue;
        final wordDetails = word['PronunciationAssessment'] is Map
            ? word['PronunciationAssessment'] as Map
            : word;
        words.add({
          'word': word['Word'],
          'accuracy': _score(wordDetails['AccuracyScore']),
          'errorType': wordDetails['ErrorType'] is String
              ? wordDetails['ErrorType']
              : null,
        });
      }
    }
    return Assessment({
      'accuracy': accuracy,
      'fluency': fluency,
      'completeness': completeness,
      'pronunciationScore': overall,
      'recognizedText': best['Display'] is String
          ? best['Display']
          : result['DisplayText'] is String
          ? result['DisplayText']
          : '',
      'words': words,
    });
  }

  static double? _score(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 100
      ? value.toDouble()
      : null;

  final double accuracy, fluency, completeness, overall;
  final String recognizedText;
  final List<Map<String, dynamic>> words;
}

/// Lazily creates the Android audio player only when Azure audio is played.
/// Kept separate from requests so playback and cancellation can be tested.
class SpeechAudioOutput {
  AudioPlayer? _player;
  StreamSubscription<void>? _completed;
  Completer<void>? _playback;
  bool _playbackFailed = false;
  bool _disposed = false;
  int _generation = 0;

  void _finish() {
    final playback = _playback;
    if (playback != null && !playback.isCompleted) playback.complete();
  }

  Future<void> play(Uint8List bytes) async {
    if (_disposed) return;
    final generation = ++_generation;
    await _stopCurrent();
    if (_disposed || generation != _generation) return;
    final playback = _playback = Completer<void>();
    _playbackFailed = false;
    try {
      final player = _player ??= AudioPlayer();
      _completed ??= player.onPlayerComplete.listen(
        (_) => _finish(),
        onError: (Object _) {
          _playbackFailed = true;
          _finish();
        },
      );
      await player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      if (_disposed || generation != _generation) {
        await _stopCurrent();
        return;
      }
      await playback.future.timeout(const Duration(minutes: 3));
      if (_playbackFailed) throw SpeechException('Azure 語音播放失敗，請再試一次。');
    } catch (_) {
      if (_disposed || generation != _generation) return;
      await _stopCurrent();
      throw SpeechException('Azure 語音播放失敗，請再試一次。');
    } finally {
      if (identical(_playback, playback)) _playback = null;
    }
  }

  Future<void> _stopCurrent() async {
    _finish();
    try {
      await _player?.stop().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A stopped player must not prevent recording or switching providers.
    }
  }

  Future<void> stop() {
    _generation++;
    return _stopCurrent();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _completed?.cancel();
    try {
      await _player?.dispose();
    } catch (_) {
      // Native teardown is best effort when a route or app is closing.
    }
  }
}

class SpeechService {
  SpeechService({
    http.Client? client,
    SpeechSettings? settings,
    AppSettings? preferences,
    SpeechCache? diskCache,
    SpeechAudioOutput? audioOutput,
  }) : _client = client ?? http.Client(),
       _settings = settings ?? SpeechSettings.instance,
       _preferences = preferences ?? AppSettings.instance,
       _diskCache = diskCache ?? SpeechCache(),
       _audioOutput = audioOutput ?? SpeechAudioOutput() {
    _lastProvider = _preferences.provider;
    _lastGender = _preferences.gender;
    _lastLanguage = _preferences.language;
    _preferences.addListener(_onPreferencesChanged);
  }

  LocalTts? _localTts;
  LocalTts get _tts => _localTts ??= LocalTts();
  AudioRecorder? _audioRecorder;
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();
  final http.Client _client;
  final SpeechSettings _settings;
  final AppSettings _preferences;
  final SpeechCache _diskCache;
  final SpeechAudioOutput _audioOutput;
  final Map<String, Uint8List> _cache = {};
  late TtsProvider _lastProvider;
  late SpeakerGender _lastGender;
  late StudyLanguage _lastLanguage;
  int _speechGeneration = 0;
  Future<void> _stopping = Future<void>.value();
  final List<int> _pcm = [];
  final Set<Completer<void>> _requests = {};
  final Set<Completer<void>> _ttsRequests = {};
  StreamSubscription<Uint8List>? _subscription;
  bool _disposed = false;
  static const _maxPcmBytes = 16000 * 2 * 30;
  static const _setupMessage = '此安裝版本尚未設定 Azure 語音服務，請使用已設定的 APK。';

  void _ensureActive() {
    if (_disposed) throw SpeechException('練習已結束，請重新開啟後再試一次。');
  }

  void _ensureTtsActive(int generation) {
    _ensureActive();
    if (generation != _speechGeneration) throw SpeechException('朗讀已取消。');
  }

  Future<({String apiKey, String region})> _credentials() async {
    _ensureActive();
    await _settings.load();
    _ensureActive();
    final key = _settings.apiKey?.trim();
    final region = _settings.region.trim().toLowerCase();
    if (!_settings.isConfigured || key == null || key.isEmpty) {
      throw SpeechException(_setupMessage);
    }
    if (key.length > 512 ||
        key.contains(RegExp(r'[\r\n]')) ||
        !RegExp(r'^[a-z0-9]{2,40}$').hasMatch(region)) {
      throw SpeechException('此安裝版本的語音設定不正確，請使用已設定的 APK。');
    }
    return (apiKey: key, region: region);
  }

  Future<Uint8List> _request(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
    bool audio = false,
  }) async {
    _ensureActive();
    final abort = Completer<void>();
    _requests.add(abort);
    if (audio) _ttsRequests.add(abort);
    try {
      return await (() async {
        final request =
            http.AbortableRequest('POST', uri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll(headers)
              ..bodyBytes = body;
        final response = await _client.send(request);
        if (response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          throw _azureError(response.statusCode);
        }
        final type = response.headers['content-type']?.toLowerCase() ?? '';
        if (audio &&
            !(type.startsWith('audio/') ||
                type.startsWith('application/octet-stream'))) {
          await response.stream.listen(null).cancel();
          throw SpeechException('Azure 沒有回傳可播放的語音，請再試一次。');
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          await response.stream.listen(null).cancel();
          throw SpeechException('Azure 回傳的資料過大，請縮短內容後再試一次。');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw SpeechException('Azure 回傳的資料過大，請縮短內容後再試一次。');
          }
          bytes.add(chunk);
        }
        _ensureActive();
        return bytes.takeBytes();
      })().timeout(const Duration(seconds: 40));
    } on SpeechException {
      rethrow;
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw SpeechException('Azure 語音服務回應逾時，請再試一次。');
    } catch (_) {
      // Never expose response bodies, request headers, or credential errors.
      throw SpeechException('無法連線到 Azure 語音服務，請確認網路後再試一次。');
    } finally {
      _requests.remove(abort);
      _ttsRequests.remove(abort);
    }
  }

  SpeechException _azureError(int status) => switch (status) {
    401 || 403 => SpeechException('此安裝版本的 Azure 語音設定無法使用，請更新已設定的 APK。'),
    429 => SpeechException('Azure 語音額度或請求次數已達上限，請稍候再試或檢查你的 Azure 額度。'),
    400 => SpeechException('Azure 無法處理這段語音或文字，請重新錄音後再試一次。'),
    _ => SpeechException('Azure 語音服務暫時無法使用，請稍後重試。'),
  };

  void _onPreferencesChanged() {
    if (_disposed ||
        (_lastProvider == _preferences.provider &&
            _lastGender == _preferences.gender &&
            _lastLanguage == _preferences.language)) {
      return;
    }
    _lastProvider = _preferences.provider;
    _lastGender = _preferences.gender;
    _lastLanguage = _preferences.language;
    unawaited(stop());
  }

  Future<void> _stopEngines() {
    // Finish pending stop operations before allowing another engine to start.
    _stopping = _stopping.then((_) async {
      await Future.wait([
        if (_localTts != null) _localTts!.stop(),
        _audioOutput.stop(),
      ]);
    });
    return _stopping;
  }

  /// Stops playback and pending TTS, without cancelling an assessment upload.
  Future<void> stop() {
    _speechGeneration++;
    for (final request in _ttsRequests) {
      if (!request.isCompleted) request.complete();
    }
    return _stopEngines();
  }

  Future<void> speak(
    String text, {
    bool slow = false,
    TtsProvider? provider,
  }) async {
    _ensureActive();
    final nativeText = _validateText(text);
    await _preferences.load();
    if (_disposed) return;
    await stop();
    if (_disposed) return;
    final generation = ++_speechGeneration;
    final selectedProvider = provider ?? _preferences.provider;
    final gender = _preferences.gender;
    try {
      if (selectedProvider == TtsProvider.local) {
        await _tts.speak(
          nativeText,
          slow: slow,
          gender: gender,
          language: _preferences.language,
        );
      } else {
        final bytes = await loadSpeechAudio(
          nativeText,
          slow: slow,
          male: gender == SpeakerGender.male,
        );
        if (_disposed || generation != _speechGeneration) return;
        await _audioOutput.play(bytes);
      }
    } on LocalTtsException catch (error) {
      if (_disposed || generation != _speechGeneration) return;
      throw SpeechException(error.message);
    } catch (_) {
      if (_disposed || generation != _speechGeneration) return;
      rethrow;
    }
  }

  /// Loads Azure audio only, regardless of the selected playback provider.
  /// Existing WAV files remain usable without credentials or a network.
  /// Omitting [male] uses the current speaker setting.
  Future<Uint8List> loadSpeechAudio(
    String text, {
    bool slow = false,
    bool? male,
  }) async {
    _ensureActive();
    await _preferences.load();
    _ensureActive();
    final generation = _speechGeneration;
    final isMale = male ?? _preferences.gender == SpeakerGender.male;
    final language = _preferences.language;
    final voice = language.azureVoice(
      isMale ? SpeakerGender.male : SpeakerGender.female,
    );
    final ssml = buildSpeechSsml(text, voice: voice, slow: slow);
    // Version 1 preserves the WAV cache created by earlier app versions.
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'locale': language.speechLocale,
              'text': text,
              'voice': voice,
              'slow': slow,
            }),
          ),
        )
        .toString();
    var bytes = _cache[key] ?? await _diskCache.read(key);
    _ensureTtsActive(generation);
    if (bytes == null) {
      final credentials = await _credentials();
      _ensureTtsActive(generation);
      final pcm = await _request(
        Uri.https(
          '${credentials.region}.tts.speech.microsoft.com',
          '/cognitiveservices/v1',
        ),
        headers: {
          'Ocp-Apim-Subscription-Key': credentials.apiKey,
          'Content-Type': 'application/ssml+xml; charset=utf-8',
          'X-Microsoft-OutputFormat': 'raw-16khz-16bit-mono-pcm',
          'User-Agent': 'ThaiTalk',
        },
        body: utf8.encode(ssml),
        maxBytes: 4_000_000,
        audio: true,
      );
      _ensureTtsActive(generation);
      if (pcm.isEmpty || pcm.length.isOdd) {
        throw SpeechException('Azure 沒有回傳可播放的語音，請再試一次。');
      }
      bytes = pcmToWav(pcm);
      await _diskCache.write(key, bytes);
    }
    _ensureTtsActive(generation);
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[key] = bytes;
    return bytes;
  }

  Future<void> startRecording() async {
    await _credentials();
    await stop();
    if (!await _recorder.hasPermission()) {
      throw SpeechException('請允許麥克風權限，才能開始朗讀練習。');
    }
    _ensureActive();
    _pcm.clear();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _ensureActive();
    _subscription = stream.listen((data) {
      final remaining = _maxPcmBytes - _pcm.length;
      if (remaining > 0) _pcm.addAll(data.take(remaining));
    });
  }

  Future<Assessment> stopAndAssess(String reference) async {
    _ensureActive();
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    if (_pcm.length < 6400) throw SpeechException('錄音太短了，請完整朗讀後再送出。');
    final wav = pcmToWav(Uint8List.fromList(_pcm));
    _pcm.clear();
    return assessAudio(wav, reference);
  }

  /// Uploads only the current recording directly to the user's Azure resource.
  /// Recordings and assessment results never enter the synthesized audio cache.
  Future<Assessment> assessAudio(Uint8List wav, String reference) async {
    await _preferences.load();
    final text = _validateText(reference);
    validateRecordingWav(wav);
    final credentials = await _credentials();
    final parameters = base64Encode(
      utf8.encode(
        jsonEncode({
          'ReferenceText': text,
          'GradingSystem': 'HundredMark',
          'Granularity': 'Word',
          'Dimension': 'Comprehensive',
          'EnableMiscue': true,
        }),
      ),
    );
    final response = await _request(
      Uri.https(
        '${credentials.region}.stt.speech.microsoft.com',
        '/speech/recognition/conversation/cognitiveservices/v1',
        {'language': _preferences.language.speechLocale, 'format': 'detailed'},
      ),
      headers: {
        'Ocp-Apim-Subscription-Key': credentials.apiKey,
        'Content-Type': 'audio/wav; codecs=audio/pcm; samplerate=16000',
        'Pronunciation-Assessment': parameters,
        'Accept': 'application/json',
      },
      body: wav,
      maxBytes: 1_000_000,
    );
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response));
    } catch (_) {
      throw SpeechException('Azure 回傳的評分格式不正確，請再試一次。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw SpeechException('Azure 回傳的評分格式不正確，請再試一次。');
    }
    return Assessment.fromAzure(decoded);
  }

  Future<void> cancelRecording() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.cancel();
    _pcm.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _speechGeneration++;
    _preferences.removeListener(_onPreferencesChanged);
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
    _subscription?.cancel();
    _audioRecorder?.dispose();
    _localTts?.dispose();
    unawaited(_audioOutput.dispose());
    _client.close();
    _pcm.clear();
    _cache.clear();
  }
}

String _validateText(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > 500 ||
      RegExp(
        '[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\ufffe\\uffff]',
      ).hasMatch(text)) {
    throw SpeechException('請提供 1 至 500 個字元的學習內容。');
  }
  return text;
}

String buildSpeechSsml(
  String text, {
  String voice = 'th-TH-NiwatNeural',
  bool slow = false,
}) {
  final plainText = _validateText(text);
  final language = StudyLanguage.values
      .where(
        (language) => SpeakerGender.values.any(
          (gender) => language.azureVoice(gender) == voice,
        ),
      )
      .firstOrNull;
  if (language == null) {
    throw SpeechException('請選擇支援的朗讀聲音。');
  }
  final escaped = plainText.replaceAllMapped(
    RegExp('[&<>"\']'),
    (match) => {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&apos;',
    }[match[0]]!,
  );
  final locale = language.speechLocale;
  return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="$locale">'
      '<voice name="$voice"><prosody rate="${slow ? '-25%' : '0%'}">'
      '$escaped</prosody></voice></speak>';
}

void validateRecordingWav(Uint8List audio) {
  Never invalid() =>
      throw SpeechException('請使用 0.15 至 30 秒、16 kHz 單聲道的 WAV 錄音。');
  if (audio.length < 44 || audio.length > 964096) invalid();
  final data = ByteData.sublistView(audio);
  String tag(int offset) =>
      String.fromCharCodes(audio.sublist(offset, offset + 4));
  if (tag(0) != 'RIFF' ||
      tag(8) != 'WAVE' ||
      data.getUint32(4, Endian.little) + 8 != audio.length) {
    invalid();
  }
  var offset = 12;
  var formatFound = false;
  int? dataBytes;
  while (offset + 8 <= audio.length) {
    final chunk = tag(offset);
    final length = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + length > audio.length) invalid();
    if (chunk == 'fmt ') {
      if (formatFound ||
          length < 16 ||
          data.getUint16(start, Endian.little) != 1 ||
          data.getUint16(start + 2, Endian.little) != 1 ||
          data.getUint32(start + 4, Endian.little) != 16000 ||
          data.getUint32(start + 8, Endian.little) != 32000 ||
          data.getUint16(start + 12, Endian.little) != 2 ||
          data.getUint16(start + 14, Endian.little) != 16) {
        invalid();
      }
      formatFound = true;
    }
    if (chunk == 'data') {
      if (dataBytes != null || length.isOdd) invalid();
      dataBytes = length;
    }
    offset = start + length + length % 2;
  }
  if (offset != audio.length ||
      !formatFound ||
      dataBytes == null ||
      dataBytes < 4800 ||
      dataBytes > 960000) {
    invalid();
  }
}

Uint8List pcmToWav(Uint8List pcm) {
  final bytes = ByteData(44 + pcm.length);
  void textAt(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  textAt(0, 'RIFF');
  bytes.setUint32(4, 36 + pcm.length, Endian.little);
  textAt(8, 'WAVE');
  textAt(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 16000, Endian.little);
  bytes.setUint32(28, 32000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  textAt(36, 'data');
  bytes.setUint32(40, pcm.length, Endian.little);
  bytes.buffer.asUint8List().setRange(44, 44 + pcm.length, pcm);
  return bytes.buffer.asUint8List();
}
