import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/learning_item.dart';
import '../models/study_language.dart';

class _Curriculum {
  _Curriculum(this.bytes, this.language)
    : digest = sha256.convert(bytes).toString(),
      items = LearningItem.parseCurriculum(
        utf8.decode(bytes),
        language: language,
      );

  final Uint8List bytes;
  final StudyLanguage language;
  final String digest;
  final List<LearningItem> items;
}

/// The APK is the offline seed. A verified download replaces only the copy in
/// private app storage, using an atomic rename so interruption preserves it.
class CurriculumRepository {
  CurriculumRepository({
    this.language = StudyLanguage.thai,
    this.directory,
    this.clientFactory,
    this.bundleLoader,
    this.checkTimeout = const Duration(seconds: 3),
    this.downloadTimeout = const Duration(seconds: 5),
  });

  static final instance = CurriculumRepository();
  static final japaneseInstance = CurriculumRepository(
    language: StudyLanguage.japanese,
  );
  final StudyLanguage language;
  static const filename = 'thai_practice_dataset.json';
  String get activeFilename => language.datasetFilename;
  static final datasetUrl = Uri.parse(
    'https://raw.githubusercontent.com/sibuzu/thaitalk/main/$filename',
  );
  static final checksumUrl = Uri.parse('$datasetUrl.sha256');
  Uri get activeDatasetUrl => language == StudyLanguage.thai
      ? datasetUrl
      : Uri.parse(
          'https://raw.githubusercontent.com/sibuzu/thaitalk/main/$activeFilename',
        );
  Uri get activeChecksumUrl => language == StudyLanguage.thai
      ? checksumUrl
      : Uri.parse('$activeDatasetUrl.sha256');
  static const maxBytes = 5 * 1024 * 1024;
  final Directory? directory;
  final http.Client Function()? clientFactory;
  final Future<Uint8List> Function()? bundleLoader;
  final Duration checkTimeout;
  final Duration downloadTimeout;
  _Curriculum? _active;
  Future<_Curriculum>? _loading;
  Future<List<LearningItem>>? _startup;

  Future<File> _localFile() async {
    final folder = directory ?? await getApplicationSupportDirectory();
    return File('${folder.path}${Platform.pathSeparator}$activeFilename');
  }

  Future<_Curriculum> _load() async {
    try {
      final file = await _localFile();
      if (await file.length() <= maxBytes) {
        return _active = _Curriculum(await file.readAsBytes(), language);
      }
    } on Object {
      // Missing, corrupt or inaccessible storage falls back to bundled data.
    }
    final loader = bundleLoader;
    final Uint8List bytes;
    if (loader != null) {
      bytes = await loader();
    } else {
      final data = await rootBundle.load('assets/data/$activeFilename');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    return _active = _Curriculum(bytes, language);
  }

  Future<_Curriculum> _current() async =>
      _active ?? await (_loading ??= _load());

  /// All screens (including quiz distractors) share the same accepted version.
  Future<List<LearningItem>> load() async => (await _current()).items;

  /// One bounded check per application start. Network errors never block use of
  /// valid local data, and equal checksums avoid downloading the JSON again.
  Future<List<LearningItem>> loadAtStartup() => _startup ??= _update();

  Future<Uint8List> _download(
    http.Client client,
    Uri url,
    int limit,
    Duration timeout,
  ) => (() async {
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers['Cache-Control'] = 'no-cache';
    final response = await client.send(request);
    if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
      throw const FormatException('Invalid curriculum response.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('Curriculum response too large.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  })().timeout(timeout);

  Future<List<LearningItem>> _update() async {
    final current = await _current();
    http.Client? client;
    File? temporary;
    try {
      client = clientFactory?.call() ?? http.Client();
      final checksum = utf8
          .decode(await _download(client, activeChecksumUrl, 256, checkTimeout))
          .trim();
      final match = RegExp(
        '^([a-fA-F0-9]{64})(?:\\s+\\*?${RegExp.escape(activeFilename)})?\$',
      ).firstMatch(checksum);
      if (match == null) throw const FormatException('Invalid SHA-256 file.');
      final expected = match.group(1)!.toLowerCase();
      if (expected == current.digest) return current.items;
      final bytes = await _download(
        client,
        activeDatasetUrl,
        maxBytes,
        downloadTimeout,
      );
      if (sha256.convert(bytes).toString() != expected) {
        throw const FormatException('Curriculum checksum mismatch.');
      }
      final next = _Curriculum(bytes, language);
      final target = await _localFile();
      await target.parent.create(recursive: true);
      temporary = File('${target.path}.download');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
      _active = next;
      return next.items;
    } on Object {
      // Keep the old version on offline/404/timeout/hash/schema/storage errors.
      return current.items;
    } finally {
      client?.close();
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } on Object {
        // A stale partial download is never used as the active dataset.
      }
    }
  }
}
