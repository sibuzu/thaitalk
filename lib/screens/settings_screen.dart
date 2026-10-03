import 'dart:async';

import 'package:flutter/material.dart';

import '../models/speaker_gender.dart';
import '../models/study_language.dart';
import '../services/app_settings.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.settings});
  final AppSettings? settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _notice;
  AppSettings get _settings => widget.settings ?? AppSettings.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _settings.load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _change(Future<void> Function() save) async {
    setState(() => _notice = null);
    try {
      await save();
      if (mounted) setState(() => _notice = '已儲存設定。');
    } on Object {
      // The settings service exposes a safe message and keeps the old choice.
      if (mounted) setState(() => _notice = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final busy = _loading || _settings.isSaving;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('學習語言', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (
                      var row = 0;
                      row < StudyLanguage.values.length;
                      row += 2
                    ) ...[
                      if (row > 0) const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final language
                              in StudyLanguage.values.skip(row).take(2)) ...[
                            if (language != StudyLanguage.values[row])
                              const SizedBox(width: 10),
                            _choice(
                              key: 'settings-language-${language.name}',
                              label: '${language.flag} ${language.displayName}',
                              selected: _settings.language == language,
                              enabled: !busy,
                              onTap: () => _change(
                                () => _settings.setLanguage(language),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      '各語言的教材與學習紀錄分開保存。',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('說話者', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _choice(
                          key: 'settings-gender-male',
                          label: '男',
                          selected: _settings.gender == SpeakerGender.male,
                          enabled: !busy,
                          onTap: () => _change(
                            () => _settings.setGender(SpeakerGender.male),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _choice(
                          key: 'settings-gender-female',
                          label: '女',
                          selected: _settings.gender == SpeakerGender.female,
                          enabled: !busy,
                          onTap: () => _change(
                            () => _settings.setGender(SpeakerGender.female),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _settings.language == StudyLanguage.thai
                          ? '切換例句的自稱、禮貌用語與 Azure 聲音。'
                          : '切換${_settings.language.chineseName}朗讀使用的男聲或女聲。',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: thai(
                            _settings.language.greeting(_settings.gender),
                            size: 24,
                          ),
                        ),
                        const Text(
                          '你好',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('每輪題數', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final count
                            in AppSettings.questionCountOptions) ...[
                          if (count != AppSettings.questionCountOptions.first)
                            const SizedBox(width: 6),
                          _choice(
                            key: 'settings-questions-$count',
                            label: '$count',
                            selected: _settings.questionsPerRound == count,
                            enabled: !busy,
                            onTap: () => _change(
                              () => _settings.setQuestionsPerRound(count),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '單字、片語、句子與今日練習都使用此題數；內容不足時使用全部。',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _settings.error ??
                    (_loading
                        ? '載入設定中…'
                        : busy
                        ? '儲存中…'
                        : _notice ?? '選擇後自動儲存，下次開啟仍會保留。'),
                key: const ValueKey('settings-status'),
                style: TextStyle(
                  fontSize: 12,
                  color: _settings.error == null ? muted : orange,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _choice({
    required String key,
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) => Expanded(
    child: ChoiceChip(
      key: ValueKey(key),
      label: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: enabled
          ? (value) {
              if (value) onTap();
            }
          : null,
      selectedColor: ink,
      labelStyle: TextStyle(color: selected ? Colors.white : ink),
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? ink : line),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
