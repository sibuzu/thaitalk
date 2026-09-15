import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persistent, bounded storage for synthesized WAV audio. Keys are SHA-256
/// digests of the speech request, so filenames never contain the spoken text.
class SpeechCache {
  SpeechCache({this.directory, this.maxBytes = 64 * 1024 * 1024});

  final Directory? directory;
  Directory? _resolvedDirectory;
  final int maxBytes;
  static final _keyPattern = RegExp(r'^[a-fA-F0-9]{64}$');
  static final _filePattern = RegExp(r'^[a-f0-9]{64}\.wav$');
  static final _temporaryPattern = RegExp(r'^[a-f0-9]{64}\.\d+\.\d+\.tmp$');
  static Future<void> _pending = Future<void>.value();
  static int _temporaryCounter = 0;

  Future<Directory> _resolveDirectory() async {
    _resolvedDirectory ??=
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}speech-cache',
        );
    return _resolvedDirectory!.create(recursive: true);
  }

  /// Serializing all cache operations also protects separate cache instances
  /// sharing the same directory from trim/write and clear/read races.
  static Future<void> _quietly(Future<void> Function() operation) {
    _pending = _pending.then((_) async {
      try {
        await operation();
      } on Object {
        // A full disk, unavailable directory or removed file is a cache miss.
        // Cache maintenance must never prevent learning or audio playback.
      }
    });
    return _pending;
  }

  Future<Uint8List?> read(String key) async {
    if (!_keyPattern.hasMatch(key) || maxBytes <= 0) return null;
    Uint8List? result;
    await _quietly(() async {
      final directory = await _resolveDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}${key.toLowerCase()}.wav',
      );
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return;
      }
      if (await file.length() > maxBytes) {
        await file.delete();
        return;
      }
      final bytes = await file.readAsBytes();
      if (!_isWav(bytes)) {
        await file.delete();
        return;
      }
      result = bytes;
      // Modification time records last use and survives application restarts.
      await file.setLastModified(DateTime.now());
    });
    return result;
  }

  Future<void> write(String key, Uint8List bytes) async {
    if (!_keyPattern.hasMatch(key) ||
        !_isWav(bytes) ||
        bytes.length > maxBytes) {
      return;
    }
    // The caller may reuse its buffer while this write waits for the queue.
    final copy = Uint8List.fromList(bytes);
    await _quietly(() async {
      final directory = await _resolveDirectory();
      final stem =
          '${directory.path}${Platform.pathSeparator}'
          '${key.toLowerCase()}';
      final temporary = File(
        '$stem.${DateTime.now().microsecondsSinceEpoch}.'
        '${_temporaryCounter++}.tmp',
      );
      try {
        await temporary.writeAsBytes(copy, flush: true);
        // Rename publishes the complete audio file atomically.
        await temporary.rename('$stem.wav');
        await _trim(directory);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
  }

  Future<void> _trim(Directory directory) async {
    final entries = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_filePattern.hasMatch(_name(entity))) continue;
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      entries.add((file: entity, stat: stat));
      total += stat.size;
    }
    entries.sort((a, b) {
      final age = a.stat.modified.compareTo(b.stat.modified);
      return age == 0 ? a.file.path.compareTo(b.file.path) : age;
    });
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.file.delete();
      total -= entry.stat.size;
    }
  }

  Future<void> clear() => _quietly(() async {
    final directory = await _resolveDirectory();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          (_filePattern.hasMatch(_name(entity)) ||
              _temporaryPattern.hasMatch(_name(entity)))) {
        await entity.delete();
      }
    }
  });

  static String _name(FileSystemEntity file) =>
      file.path.split(Platform.pathSeparator).last;

  static bool _isWav(Uint8List bytes) =>
      bytes.length >= 44 &&
      bytes[0] == 0x52 && // RIFF
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 && // WAVE
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;
}
