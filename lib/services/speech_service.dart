import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

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
      throw SpeechException('沒有辨識到清楚的泰語，請靠近麥克風再試一次。');
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

class SpeechService {
  SpeechService({
    http.Client? client,
    SpeechCache? diskCache,
    SpeechSettings? settings,
  }) : _client = client ?? http.Client(),
       _diskCache = diskCache ?? SpeechCache(),
       _settings = settings ?? SpeechSettings.instance;

  AudioPlayer? _audioPlayer;
  AudioRecorder? _audioRecorder;
  AudioPlayer get _player => _audioPlayer ??= AudioPlayer();
  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();
  final http.Client _client;
  final Map<String, Uint8List> _cache = {};
  final SpeechCache _diskCache;
  final SpeechSettings _settings;
  final List<int> _pcm = [];
  final Set<Completer<void>> _requests = {};
  StreamSubscription<Uint8List>? _subscription;
  bool _disposed = false;
  static const _maxPcmBytes = 16000 * 2 * 30;
  static const _setupMessage = '此安裝版本尚未設定語音服務，請使用已設定的 APK。';

  void _ensureActive() {
    if (_disposed) throw SpeechException('練習已結束，請重新開啟後再試一次。');
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
    }
  }

  SpeechException _azureError(int status) => switch (status) {
    401 || 403 => SpeechException('此安裝版本的 Azure 語音設定無法使用，請更新已設定的 APK。'),
    429 => SpeechException('Azure 語音額度或請求次數已達上限，請稍候再試或檢查你的 Azure 額度。'),
    400 => SpeechException('Azure 無法處理這段語音或文字，請重新錄音後再試一次。'),
    _ => SpeechException('Azure 語音服務暫時無法使用，請稍後重試。'),
  };

  Future<void> speak(String text, {bool slow = false, bool male = true}) async {
    _ensureActive();
    await _player.stop();
    final bytes = await loadSpeechAudio(text, slow: slow, male: male);
    if (!_disposed) {
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
    }
  }

  /// Cached speech remains available without a key, a network, or an account.
  Future<Uint8List> loadSpeechAudio(
    String text, {
    bool slow = false,
    bool male = true,
  }) async {
    _ensureActive();
    final voice = male ? 'th-TH-NiwatNeural' : 'th-TH-PremwadeeNeural';
    final ssml = buildSpeechSsml(text, voice: voice, slow: slow);
    // Version 1 preserves the WAV cache created by earlier app versions.
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'locale': 'th-TH',
              'text': text,
              'voice': voice,
              'slow': slow,
            }),
          ),
        )
        .toString();
    var bytes = _cache[key] ?? await _diskCache.read(key);
    _ensureActive();
    if (bytes == null) {
      final credentials = await _credentials();
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
      if (pcm.isEmpty || pcm.length.isOdd) {
        throw SpeechException('Azure 沒有回傳可播放的語音，請再試一次。');
      }
      bytes = pcmToWav(pcm);
      await _diskCache.write(key, bytes);
    }
    if (_cache.length >= 40) _cache.remove(_cache.keys.first);
    _cache[key] = bytes;
    return bytes;
  }

  Future<void> startRecording() async {
    await _credentials();
    await _player.stop();
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
        {'language': 'th-TH', 'format': 'detailed'},
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
    for (final request in _requests) {
      if (!request.isCompleted) request.complete();
    }
    _subscription?.cancel();
    _audioRecorder?.dispose();
    _audioPlayer?.dispose();
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
    throw SpeechException('請提供 1 至 500 個字元的泰文內容。');
  }
  return text;
}

String buildSpeechSsml(
  String text, {
  String voice = 'th-TH-NiwatNeural',
  bool slow = false,
}) {
  final plainText = _validateText(text);
  if (!const ['th-TH-NiwatNeural', 'th-TH-PremwadeeNeural'].contains(voice)) {
    throw SpeechException('請選擇支援的泰語聲音。');
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
  return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="th-TH">'
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
