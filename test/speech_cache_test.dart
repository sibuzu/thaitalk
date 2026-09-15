import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/services/speech_cache.dart';

Uint8List testWav({int length = 48, int sample = 1}) {
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, length - 8, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 24000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, length - 44, Endian.little);
  bytes.fillRange(44, length, sample);
  return bytes;
}

void main() {
  late Directory directory;
  late SpeechCache cache;
  final firstKey = 'a' * 64;
  final secondKey = 'b' * 64;
  final thirdKey = 'c' * 64;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('thaitalk-speech-test-');
    cache = SpeechCache(directory: directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'WAV persists across cache instances and only digest is in filename',
    () async {
      final bytes = testWav();
      await cache.write(firstKey, bytes);
      final restarted = SpeechCache(directory: directory);
      expect(await restarted.read(firstKey), bytes);
      expect(
        (await directory.list().toList()).map(
          (entry) => entry.path.split('/').last,
        ),
        ['$firstKey.wav'],
      );
    },
  );

  test('missing, truncated and invalid WAV files return a miss', () async {
    expect(await cache.read(firstKey), isNull);
    final file = File('${directory.path}/$firstKey.wav');
    await file.writeAsBytes('RIFF'.codeUnits);
    expect(await cache.read(firstKey), isNull);
    expect(await file.exists(), isFalse);

    await file.writeAsBytes(Uint8List(48));
    expect(await cache.read(firstKey), isNull);
    await cache.write(firstKey, Uint8List(48));
    expect(await file.exists(), isFalse);
  });

  test('LRU eviction respects reads and total size cap', () async {
    cache = SpeechCache(directory: directory, maxBytes: 96);
    await cache.write(firstKey, testWav(sample: 1));
    await cache.write(secondKey, testWav(sample: 2));
    await File(
      '${directory.path}/$firstKey.wav',
    ).setLastModified(DateTime(2020));
    await File(
      '${directory.path}/$secondKey.wav',
    ).setLastModified(DateTime(2021));
    expect(await cache.read(firstKey), isNotNull);
    await cache.write(thirdKey, testWav(sample: 3));

    expect(await cache.read(secondKey), isNull);
    expect(await cache.read(firstKey), testWav(sample: 1));
    expect(await cache.read(thirdKey), testWav(sample: 3));
    final files = await directory.list().where((file) => file is File).toList();
    var total = 0;
    for (final file in files) {
      total += (await file.stat()).size;
    }
    expect(total, lessThanOrEqualTo(96));
  });

  test('oversized entries do not evict existing usable audio', () async {
    cache = SpeechCache(directory: directory, maxBytes: 48);
    await cache.write(firstKey, testWav());
    await cache.write(secondKey, testWav(length: 96));
    expect(await cache.read(firstKey), isNotNull);
    expect(await cache.read(secondKey), isNull);
  });

  test('clear removes cache files and temporary writes only', () async {
    await cache.write(firstKey, testWav());
    await cache.write(secondKey, testWav());
    await File(
      '${directory.path}/$thirdKey.123.4.tmp',
    ).writeAsString('partial');
    final unrelated = File('${directory.path}/unrelated.txt');
    await unrelated.writeAsString('keep');
    await cache.clear();
    expect(await cache.read(firstKey), isNull);
    expect(await cache.read(secondKey), isNull);
    expect(await unrelated.readAsString(), 'keep');
    expect((await directory.list().toList()).length, 1);
  });

  test('unavailable storage and unsafe keys never block playback', () async {
    final blocked = File('${directory.path}/not-a-directory');
    await blocked.writeAsString('file');
    final unavailable = SpeechCache(directory: Directory(blocked.path));
    await unavailable.write(firstKey, testWav());
    expect(await unavailable.read(firstKey), isNull);
    await unavailable.clear();

    await cache.write('../escape', testWav());
    expect(await cache.read('../escape'), isNull);
    expect((await directory.list().toList()).length, 1);
  });

  test(
    'concurrent instances write complete files without leftover temporaries',
    () async {
      final other = SpeechCache(directory: directory);
      final a = testWav(sample: 1);
      final b = testWav(sample: 2);
      await Future.wait([cache.write(firstKey, a), other.write(firstKey, b)]);
      expect(await cache.read(firstKey), b);
      expect((await directory.list().toList()).length, 1);
    },
  );
}
