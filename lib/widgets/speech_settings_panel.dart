import 'package:flutter/material.dart';

import '../services/speech_settings.dart';
import '../theme.dart';

/// Optional read-only speech status. There are no credential-entry controls.
class SpeechSettingsPanel extends StatelessWidget {
  const SpeechSettingsPanel({super.key, this.settings});
  final SpeechSettings? settings;

  @override
  Widget build(BuildContext context) {
    final configuration = settings ?? SpeechSettings.instance;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over_outlined, color: orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '泰語朗讀與發音練習',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Tag(
            configuration.isConfigured ? '語音功能已就緒' : '語音功能尚未設定',
            icon: configuration.isConfigured
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            background: configuration.isConfigured ? sage : peach,
          ),
          const SizedBox(height: 14),
          const Text(
            '泰語男聲朗讀，支援正常與慢速播放。第一次朗讀與每次發音評分需要網路；'
            '已快取的同一句朗讀可離線播放。',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          if (configuration.error != null) ...[
            const SizedBox(height: 12),
            Text(
              configuration.error!,
              style: const TextStyle(fontSize: 13, color: orange),
            ),
          ],
        ],
      ),
    );
  }
}
