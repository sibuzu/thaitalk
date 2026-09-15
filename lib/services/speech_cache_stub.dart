import 'dart:typed_data';

/// Native platforms keep speech on disk. Web playback remains available when
/// persistent browser storage is not configured.
class SpeechCache {
  SpeechCache({Object? directory, int maxBytes = 64 * 1024 * 1024});

  Future<Uint8List?> read(String key) async => null;
  Future<void> write(String key, Uint8List bytes) async {}
  Future<void> clear() async {}
}
