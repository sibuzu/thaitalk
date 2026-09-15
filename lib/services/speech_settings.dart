import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Read-only speech configuration supplied when the Android APK is built.
/// Encoding avoids embedding the literal key; it is not a security boundary
/// against someone who can inspect the application binary.
class SpeechSettings extends ChangeNotifier {
  SpeechSettings._({required this.apiKey, required this.region, this.error});

  factory SpeechSettings({String? apiKey, String region = defaultRegion}) {
    final normalizedRegion = region.trim().toLowerCase();
    if (!_regionPattern.hasMatch(normalizedRegion)) {
      return SpeechSettings._(
        apiKey: null,
        region: defaultRegion,
        error: '此版本的語音區域設定無效，請安裝設定完整的 APK。',
      );
    }
    final normalizedKey = apiKey?.trim();
    return SpeechSettings._(
      apiKey: normalizedKey?.isNotEmpty == true ? normalizedKey : null,
      region: normalizedRegion,
    );
  }

  factory SpeechSettings.fromEnvironment() => SpeechSettings.fromEncoded(
    cipher: const String.fromEnvironment('AZURE_KEY_CIPHER'),
    mask: const String.fromEnvironment('AZURE_KEY_MASK'),
    region: const String.fromEnvironment(
      'AZURE_REGION',
      defaultValue: defaultRegion,
    ),
  );

  /// Decodes the build script's two equally sized Base64 byte arrays. Errors
  /// never include supplied values, decoded key bytes, or platform exceptions.
  factory SpeechSettings.fromEncoded({
    required String cipher,
    required String mask,
    String region = defaultRegion,
  }) {
    if (cipher.isEmpty && mask.isEmpty) {
      return SpeechSettings(apiKey: null, region: region);
    }
    try {
      final encryptedBytes = base64Decode(cipher);
      final maskBytes = base64Decode(mask);
      if (encryptedBytes.isEmpty || encryptedBytes.length != maskBytes.length) {
        throw const FormatException();
      }
      final key = utf8.decode([
        for (var index = 0; index < encryptedBytes.length; index++)
          encryptedBytes[index] ^ maskBytes[index],
      ]).trim();
      if (key.isEmpty) throw const FormatException();
      return SpeechSettings(apiKey: key, region: region);
    } on Object {
      return SpeechSettings._(
        apiKey: null,
        region: defaultRegion,
        error: '此版本的語音設定無法讀取，請安裝設定完整的 APK。',
      );
    }
  }

  static final instance = SpeechSettings.fromEnvironment();
  static const defaultRegion = 'southeastasia';
  static final _regionPattern = RegExp(r'^[a-z0-9]+$');

  final String? apiKey;
  final String region;
  final String? error;
  bool get isConfigured => apiKey?.isNotEmpty == true;

  /// Retained for initialization callers; build configuration is synchronous.
  Future<void> load() async {}
}
