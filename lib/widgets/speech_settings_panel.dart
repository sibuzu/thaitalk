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
                  '朗讀與發音練習',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Tag(
            configuration.isConfigured ? 'Azure 發音評分已設定' : 'Azure 發音評分尚未設定',
            icon: configuration.isConfigured
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            background: configuration.isConfigured ? sage : peach,
          ),
          const SizedBox(height: 14),
          const Text(
            '卡片提供 Local TTS 與 Azure TTS 播放按鈕。本機朗讀不快取；Azure 朗讀會快取。'
            'Azure 朗讀與錄音發音評分需要服務設定；本機朗讀需安裝對應語言的離線語音資料。',
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
