import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:thaitalk/services/curriculum_repository.dart';
import 'package:thaitalk/models/study_language.dart';

void main() {
  late Directory directory;
  late Uint8List bundled;
  late Uint8List updated;
  late List<Uri> requests;
  late http.Response Function(http.Request) response;

  String checksum(List<int> bytes) => sha256.convert(bytes).toString();
  File localFile() =>
      File('${directory.path}/${CurriculumRepository.filename}');
  Uint8List encode(Object value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
  Map<String, dynamic> data() =>
      jsonDecode(utf8.decode(bundled)) as Map<String, dynamic>;

  CurriculumRepository repository({Duration? timeout}) => CurriculumRepository(
    directory: directory,
    bundleLoader: () async => bundled,
    checkTimeout: timeout ?? const Duration(seconds: 1),
    downloadTimeout: timeout ?? const Duration(seconds: 1),
    clientFactory: () => MockClient((request) async {
      requests.add(request.url);
      return response(request);
    }),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'thaitalk-curriculum-test-',
    );
    bundled = await File('thai_practice_dataset.json').readAsBytes();
    final changed = data();
    final vocabulary = changed['vocabulary'] as List;
    vocabulary.add({...vocabulary.first as Map, 'id': 9999, 'chinese': '更新教材'});
    updated = encode(changed);
    requests = [];
    response = (request) => request.url == CurriculumRepository.checksumUrl
        ? http.Response(
            '${checksum(updated)}  thai_practice_dataset.json\n',
            200,
          )
        : http.Response.bytes(updated, 200);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('same checksum checks once per start and skips JSON download', () async {
    response = (_) => http.Response(checksum(bundled), 200);
    final repo = repository();
    expect(await repo.loadAtStartup(), hasLength(800));
    await repo.loadAtStartup();
    await repo.load();
    expect(requests, [CurriculumRepository.checksumUrl]);
    expect(await localFile().exists(), isFalse);
  });

  test('Japanese update uses its own GitHub URL and storage file', () async {
    final japanese = await File('japanese_practice_dataset.json').readAsBytes();
    final changed = jsonDecode(utf8.decode(japanese)) as Map<String, dynamic>;
    (changed['vocabulary'] as List).add({
      ...(changed['vocabulary'] as List).first as Map,
      'id': 9999,
      'chinese': '更新日語教材',
    });
    final incoming = encode(changed);
    final repo = CurriculumRepository(
      language: StudyLanguage.japanese,
      directory: directory,
      bundleLoader: () async => japanese,
      clientFactory: () => MockClient((request) async {
        requests.add(request.url);
        return request.url.path.endsWith('.sha256')
            ? http.Response(
                '${checksum(incoming)}  japanese_practice_dataset.json\n',
                200,
              )
            : http.Response.bytes(incoming, 200);
      }),
    );
    expect(
      (await repo.loadAtStartup()).lastWhere((item) => item.id == 9999).chinese,
      '更新日語教材',
    );
    expect(requests, [repo.activeChecksumUrl, repo.activeDatasetUrl]);
    expect(
      await File('${directory.path}/japanese_practice_dataset.json').exists(),
      isTrue,
    );
    expect(await localFile().exists(), isFalse);
  });

  for (final language in [StudyLanguage.korean, StudyLanguage.vietnamese]) {
    test(
      '${language.name} updates and restarts without touching other languages',
      () async {
        final bytes = await File(language.datasetFilename).readAsBytes();
        final changed = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        changed['vocabulary'][0]['chinese'] = '更新${language.chineseName}教材';
        final incoming = encode(changed);
        final repo = CurriculumRepository(
          language: language,
          directory: directory,
          bundleLoader: () async => bytes,
          clientFactory: () => MockClient((request) async {
            requests.add(request.url);
            expect(
              request.url.path,
              endsWith(
                language.datasetFilename +
                    (request.url.path.endsWith('.sha256') ? '.sha256' : ''),
              ),
            );
            return request.url.path.endsWith('.sha256')
                ? http.Response(
                    '${checksum(incoming)}  ${language.datasetFilename}\n',
                    200,
                  )
                : http.Response.bytes(incoming, 200);
          }),
        );
        expect(
          (await repo.loadAtStartup()).first.chinese,
          '更新${language.chineseName}教材',
        );
        expect(requests, [repo.activeChecksumUrl, repo.activeDatasetUrl]);
        expect(await directory.list().length, 1);
        final restarted = CurriculumRepository(
          language: language,
          directory: directory,
          bundleLoader: () async =>
              throw StateError('Must load the installed update'),
          clientFactory: () =>
              MockClient((_) async => http.Response('offline', 503)),
        );
        expect(
          (await restarted.loadAtStartup()).first.chinese,
          '更新${language.chineseName}教材',
        );
        expect(
          await File(
            '${directory.path}/${language.datasetFilename}',
          ).readAsBytes(),
          incoming,
        );
        expect(await localFile().exists(), isFalse);
      },
    );
  }

  test(
    'verified update replaces local JSON and all readers use new items',
    () async {
      final repo = repository();
      expect(await repo.load(), hasLength(800));
      expect(requests, isEmpty);
      final items = await repo.loadAtStartup();
      expect(items, hasLength(801));
      expect(items.lastWhere((item) => item.id == 9999).chinese, '更新教材');
      expect(await repo.load(), same(items));
      expect(await localFile().readAsBytes(), updated);
      expect(await directory.list().length, 1);
      expect(requests, [
        CurriculumRepository.checksumUrl,
        CurriculumRepository.datasetUrl,
      ]);
      requests.clear();
      expect(await repository().loadAtStartup(), hasLength(801));
      expect(requests, [CurriculumRepository.checksumUrl]);
    },
  );

  test('offline startup retains installed update', () async {
    await localFile().writeAsBytes(updated);
    response = (_) => throw const SocketException('offline');
    expect(await repository().loadAtStartup(), hasLength(801));
    expect(await localFile().readAsBytes(), updated);
  });

  test('corrupt local file falls back to bundled data offline', () async {
    await localFile().writeAsString('truncated');
    response = (_) => http.Response('unavailable', 503);
    expect(await repository().loadAtStartup(), hasLength(800));
  });

  for (final failure in [
    'bad checksum',
    'mismatch',
    'invalid JSON',
    'duplicate IDs',
    'empty',
    'fractional ID',
    'empty text',
    'bad gender',
    'speech mismatch',
    '404',
  ]) {
    test('$failure never replaces the existing dataset', () async {
      await localFile().writeAsBytes(bundled);
      var incoming = updated;
      final changed = data();
      switch (failure) {
        case 'invalid JSON':
          incoming = encode('not a curriculum');
        case 'duplicate IDs':
          (changed['vocabulary'] as List).add(
            (changed['vocabulary'] as List).first,
          );
          incoming = encode(changed);
        case 'empty':
          incoming = encode({'vocabulary': [], 'sentences': []});
        case 'fractional ID':
          changed['vocabulary'][0]['id'] = 1.5;
          incoming = encode(changed);
        case 'empty text':
          changed['vocabulary'][0]['thai'] = '';
          incoming = encode(changed);
        case 'bad gender':
          changed['vocabulary'][0]['female'] = {'example_thai': 123};
          incoming = encode(changed);
        case 'speech mismatch':
          changed['vocabulary'][0]['thai_native'] = 'คน';
          incoming = encode(changed);
      }
      response = (request) {
        if (request.url == CurriculumRepository.checksumUrl) {
          return http.Response(
            failure == 'bad checksum' ? 'invalid' : checksum(incoming),
            200,
          );
        }
        return switch (failure) {
          'mismatch' => http.Response.bytes(bundled, 200),
          '404' => http.Response('not found', 404),
          _ => http.Response.bytes(incoming, 200),
        };
      };
      expect(await repository().loadAtStartup(), hasLength(800));
      expect(await localFile().readAsBytes(), bundled);
      expect(await directory.list().length, 1);
    });
  }

  for (final advertised in [true, false]) {
    test(
      'oversized ${advertised ? 'content length' : 'stream'} preserves data',
      () async {
        await localFile().writeAsBytes(bundled);
        final repo = CurriculumRepository(
          directory: directory,
          bundleLoader: () async => bundled,
          clientFactory: () => MockClient.streaming((request, _) async {
            if (request.url == CurriculumRepository.checksumUrl) {
              return http.StreamedResponse(
                Stream.value(utf8.encode(checksum(updated))),
                200,
              );
            }
            return http.StreamedResponse(
              Stream.value(
                advertised
                    ? updated
                    : Uint8List(CurriculumRepository.maxBytes + 1),
              ),
              200,
              contentLength: advertised
                  ? CurriculumRepository.maxBytes + 1
                  : null,
            );
          }),
        );
        expect(await repo.loadAtStartup(), hasLength(800));
        expect(await localFile().readAsBytes(), bundled);
      },
    );
  }

  test('checksum 404 keeps bundled curriculum', () async {
    response = (_) => http.Response('not found', 404);
    expect(await repository().loadAtStartup(), hasLength(800));
    expect(requests, hasLength(1));
  });

  for (final delayChecksum in [true, false]) {
    test(
      '${delayChecksum ? 'checksum' : 'download'} timeout cannot publish late data',
      () async {
        final pending = Completer<http.Response>();
        final repo = CurriculumRepository(
          directory: directory,
          bundleLoader: () async => bundled,
          checkTimeout: const Duration(milliseconds: 10),
          downloadTimeout: const Duration(milliseconds: 10),
          clientFactory: () => MockClient((request) async {
            if (!delayChecksum &&
                request.url == CurriculumRepository.checksumUrl) {
              return http.Response(checksum(updated), 200);
            }
            return pending.future;
          }),
        );
        expect(await repo.loadAtStartup(), hasLength(800));
        pending.complete(
          delayChecksum
              ? http.Response(checksum(updated), 200)
              : http.Response.bytes(updated, 200),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(await repo.load(), hasLength(800));
        expect(await localFile().exists(), isFalse);
      },
    );
  }

  test(
    'failed disk replacement keeps previous in-memory and stored version',
    () async {
      await localFile().writeAsBytes(bundled);
      await Directory('${localFile().path}.download').create();
      expect(await repository().loadAtStartup(), hasLength(800));
      expect(await localFile().readAsBytes(), bundled);
    },
  );
}
