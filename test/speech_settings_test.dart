import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaitalk/services/speech_settings.dart';
import 'package:thaitalk/theme.dart';
import 'package:thaitalk/widgets/speech_settings_panel.dart';

({String cipher, String mask}) encodeFixture(String key) {
  final bytes = utf8.encode(key);
  final mask = List<int>.generate(
    bytes.length,
    (index) => (index * 17 + 41) % 256,
  );
  return (
    cipher: base64Encode([
      for (var index = 0; index < bytes.length; index++)
        bytes[index] ^ mask[index],
    ]),
    mask: base64Encode(mask),
  );
}

void main() {
  test(
    'decodes the build-time XOR mask without storing configuration',
    () async {
      final fixture = encodeFixture('not-a-real-azure-key');
      final settings = SpeechSettings.fromEncoded(
        cipher: fixture.cipher,
        mask: fixture.mask,
      );
      await settings.load();
      expect(settings.apiKey, 'not-a-real-azure-key');
      expect(settings.region, 'southeastasia');
      expect(settings.isConfigured, isTrue);
      expect(settings.error, isNull);
    },
  );

  test('public constructor supports isolated speech-service tests', () {
    final settings = SpeechSettings(apiKey: ' test-key ', region: ' EastAsia ');
    expect(settings.apiKey, 'test-key');
    expect(settings.region, 'eastasia');
    expect(settings.isConfigured, isTrue);
  });

  test('absent build settings leave speech unconfigured', () {
    final settings = SpeechSettings.fromEncoded(cipher: '', mask: '');
    expect(settings.apiKey, isNull);
    expect(settings.region, 'southeastasia');
    expect(settings.isConfigured, isFalse);
  });

  test('malformed Base64, mismatched mask and malformed UTF-8 fail safely', () {
    for (final input in [
      (cipher: 'invalid!secret-marker', mask: 'also-invalid!'),
      (cipher: base64Encode([1, 2]), mask: base64Encode([1])),
      (cipher: base64Encode([0xff]), mask: base64Encode([0])),
      (cipher: base64Encode([32]), mask: base64Encode([0])),
      (cipher: base64Encode([1]), mask: ''),
    ]) {
      final settings = SpeechSettings.fromEncoded(
        cipher: input.cipher,
        mask: input.mask,
      );
      expect(settings.apiKey, isNull);
      expect(settings.isConfigured, isFalse);
      expect(settings.error, isNotNull);
      expect(settings.error, isNot(contains('secret-marker')));
      expect(settings.error, isNot(contains(input.cipher)));
    }
  });

  test(
    'invalid regions cannot become request hosts or retain decoded keys',
    () {
      final fixture = encodeFixture('not-a-real-azure-key');
      for (final region in [
        '',
        'https://example.com',
        'eastasia/../',
        'a.b',
        'a-b',
      ]) {
        final settings = SpeechSettings.fromEncoded(
          cipher: fixture.cipher,
          mask: fixture.mask,
          region: region,
        );
        expect(settings.apiKey, isNull);
        expect(settings.isConfigured, isFalse);
        expect(settings.region, 'southeastasia');
        expect(settings.error, isNotNull);
      }
    },
  );

  testWidgets('speech status has no key entry or credential display', (
    tester,
  ) async {
    final settings = SpeechSettings(apiKey: 'never-display-this-test-key');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: SpeechSettingsPanel(settings: settings)),
      ),
    );
    expect(find.text('Azure 發音評分已設定'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('never-display-this-test-key'), findsNothing);
  });
}
