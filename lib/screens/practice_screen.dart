import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/learning_item.dart';
import '../models/study_language.dart';
import '../services/learning_store.dart';
import '../services/app_settings.dart';
import '../services/curriculum_repository.dart';
import '../services/practice_session.dart';
import '../services/speech_service.dart';
import '../theme.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.items,
    this.eligibleItems,
    required this.store,
    this.quiz = false,
  });

  final List<LearningItem> items;
  final List<LearningItem>? eligibleItems;
  final LearningStore store;
  final bool quiz;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with WidgetsBindingObserver {
  final _random = Random();
  final _answers = <int, String>{};
  final _reviews = <int, bool>{};
  final _choiceSets = <int, List<String>>{};
  final _assessments = <int, Assessment>{};
  late List<LearningItem> _items;
  List<LearningItem> _pool = [];
  SpeechService? _speech;
  Timer? _timer;
  int _index = 0;
  int _seconds = 0;
  int _operation = 0;
  bool _loadingChoices = false;
  bool _busy = false;
  bool _recording = false;
  String? _error;

  bool get _finished => _index >= _items.length;
  bool get _locked => _busy || _recording;
  LearningItem get _item => _items[_index];
  String? get _selected => _answers[_item.id];
  List<String> get _choices => _choiceSets[_item.id] ?? const [];
  Assessment? get _assessment => _assessments[_item.id];
  int get _correct =>
      _items.where((item) => _answers[item.id] == item.chinese).length;
  int get _remembered => _reviews.values.where((value) => value).length;
  SpeechService get _voice => _speech ??= SpeechService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The launcher supplies a random selection and order. Navigation must keep
    // that order, and each card keeps its answer even when revisited.
    _items = widget.items
        .map((item) => item.forGender(AppSettings.instance.gender))
        .toList();
    _pool = List.of(_items);
    if (widget.quiz && _items.isNotEmpty) {
      _loadingChoices = true;
      unawaited(_loadChoices());
    }
  }

  Future<void> _loadChoices() async {
    try {
      final curriculum =
          await (_items.first.language == StudyLanguage.japanese
                  ? CurriculumRepository.japaneseInstance
                  : CurriculumRepository.instance)
              .load();
      if (!mounted) return;
      _pool = [
        ..._items,
        ...curriculum.map(
          (item) => item.forGender(AppSettings.instance.gender),
        ),
      ];
    } catch (_) {
      // A selection containing four meanings can still supply distractors.
    }
    if (!mounted) return;
    setState(() {
      _loadingChoices = false;
      _makeChoices();
    });
  }

  void _makeChoices() {
    if (_finished || _loadingChoices || _choiceSets.containsKey(_item.id)) {
      return;
    }
    final distractors =
        _pool
            .where(
              (item) =>
                  item.isSentence == _item.isSentence &&
                  item.isPhrase == _item.isPhrase,
            )
            .map((item) => item.chinese)
            .where((meaning) => meaning != _item.chinese)
            .toSet()
            .toList()
          ..shuffle(_random);
    _choiceSets[_item.id] = [_item.chinese, ...distractors.take(3)]
      ..shuffle(_random);
    if (_choices.length < 4) {
      _error = '題庫讀取不完整，請返回後重新開啟測驗。';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      final interrupted = _locked;
      _releaseMedia();
      if (mounted) {
        setState(() {
          if (interrupted) _error = '練習已暫停，返回後可重新錄音或播放。';
        });
      }
    }
  }

  void _releaseMedia() {
    _operation++;
    _timer?.cancel();
    _timer = null;
    _speech?.dispose();
    _speech = null;
    _busy = false;
    _recording = false;
    _seconds = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseMedia();
    super.dispose();
  }

  String _message(Object error) =>
      error is SpeechException ? error.message : '語音功能暫時無法使用，請確認麥克風與網路後重試。';

  Future<void> _speak({String? text, required TtsProvider provider}) async {
    if (_locked || _finished) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _voice.speak(text ?? _item.speechText, provider: provider);
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording() async {
    if (_locked || _finished) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _seconds = 0;
    });
    try {
      await _voice.startRecording();
      if (!mounted || operation != _operation) return;
      setState(() {
        _recording = true;
        _busy = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        setState(() => _seconds++);
        if (_seconds >= 30) unawaited(_finishRecording());
      });
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _finishRecording() async {
    if (!_recording || _busy) return;
    final operation = ++_operation;
    final item = _item;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final result = await _voice.stopAndAssess(item.speechText);
      if (!mounted || operation != _operation) return;
      widget.store.recordPronunciation(item.id, result.overall);
      setState(() => _assessments[item.id] = result);
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording || _busy) return;
    final operation = ++_operation;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      await _voice.cancelRecording();
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  void _answer(String choice) {
    if (_locked || _selected != null) return;
    widget.store.recordQuizAnswer(_item.id, correct: choice == _item.chinese);
    setState(() => _answers[_item.id] = choice);
  }

  void _review(bool remembered) {
    if (_locked || _reviews.containsKey(_item.id)) return;
    widget.store.markReviewed(_item.id, remembered: remembered);
    _reviews[_item.id] = remembered;
    _goTo(_index + 1);
  }

  void _goTo(int index) {
    if (index < 0 || index > _items.length) return;
    // Chevrons also let the learner leave a playing/recording card safely.
    _releaseMedia();
    setState(() {
      _index = index;
      _error = null;
      if (widget.quiz) _makeChoices();
    });
  }

  void _restart() {
    _releaseMedia();
    final previousIds = _items.map((item) => item.id).toSet();
    final next = samplePracticeItems(
      widget.eligibleItems ?? widget.items,
      random: _random,
      excludeIds: previousIds,
      count: AppSettings.instance.questionsPerRound,
    );
    setState(() {
      _items = next
          .map((item) => item.forGender(AppSettings.instance.gender))
          .toList();
      _index = 0;
      _answers.clear();
      _reviews.clear();
      _choiceSets.clear();
      _assessments.clear();
      _error = null;
      if (widget.quiz) _makeChoices();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      title: Text(widget.quiz ? '選擇測驗' : '單字卡練習'),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: '結束練習',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_finished) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: _completion(),
                );
              }
              // Normal phones use one viewport. Very short windows or large
              // accessibility text can scroll instead of clipping controls.
              final minHeight =
                  520.0 * MediaQuery.textScalerOf(context).scale(1);
              final height = max(constraints.maxHeight, minHeight);
              return SingleChildScrollView(
                physics: height <= constraints.maxHeight
                    ? const NeverScrollableScrollPhysics()
                    : null,
                child: SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: _practice(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _practice() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            '第 ${_index + 1} / ${_items.length} 題',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            widget.quiz ? '答對 $_correct 題' : '已複習 ${_reviews.length} 張',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: (_index + 1) / _items.length,
        minHeight: 4,
        borderRadius: BorderRadius.circular(8),
        backgroundColor: line,
        color: orange,
      ),
      const SizedBox(height: 12),
      Expanded(child: _card()),
    ],
  );

  Widget _card() => Panel(
    key: const ValueKey('practice-card'),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_item.categoryLabel} · ${_item.levelLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ),
            CopyThaiButton(_item.thai),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chevron(previous: true),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            learningText(
                              _item,
                              size: _item.isSentence ? 28 : 38,
                              align: TextAlign.center,
                            ),
                            if (!widget.quiz) ...[
                              const SizedBox(height: 16),
                              Text(
                                _item.chinese,
                                key: const ValueKey('flashcard-meaning'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _chevron(previous: false),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _speechControls(),
        if (_error != null) _errorFeedback(),
        if (_assessment != null && !_recording) _assessmentButton(),
        const SizedBox(height: 8),
        if (widget.quiz) _quizChoices() else _flashcardActions(),
      ],
    ),
  );

  Widget _chevron({required bool previous}) => SizedBox(
    width: 36,
    child: Center(
      child: IconButton(
        key: ValueKey(previous ? 'practice-previous' : 'practice-next'),
        tooltip: previous
            ? '上一張'
            : _index == _items.length - 1
            ? '查看結果'
            : '下一張',
        onPressed: previous && _index == 0
            ? null
            : () => _goTo(_index + (previous ? -1 : 1)),
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 48),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(
          previous ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
          size: 30,
        ),
      ),
    ),
  );

  Widget _speechControls() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (!widget.quiz && !_item.isSentence && _item.exampleThai != null)
        IconButton(
          tooltip: '查看例句',
          onPressed: _locked ? null : _showExample,
          icon: const Icon(Icons.article_outlined),
        ),
      IconButton(
        tooltip: 'Local TTS 播放',
        onPressed: _locked ? null : () => _speak(provider: TtsProvider.local),
        icon: const Icon(Icons.volume_up_outlined),
      ),
      IconButton(
        tooltip: 'Azure TTS 播放',
        onPressed: _locked ? null : () => _speak(provider: TtsProvider.azure),
        color: orange,
        icon: const Icon(Icons.volume_up_outlined),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        tooltip: _busy
            ? '語音處理中'
            : _recording
            ? '完成錄音'
            : '朗讀練習',
        onPressed: _busy
            ? null
            : _recording
            ? _finishRecording
            : _startRecording,
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded),
      ),
      if (_recording) ...[
        const SizedBox(width: 8),
        Text('$_seconds / 30', style: const TextStyle(fontSize: 12)),
        IconButton(
          tooltip: '取消錄音',
          onPressed: _cancelRecording,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    ],
  );

  Widget _flashcardActions() {
    final reviewed = _reviews.containsKey(_item.id);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _locked || reviewed ? null : () => _review(false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            child: const Text('還要練習'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _locked || reviewed ? null : () => _review(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            child: const Text('記住了'),
          ),
        ),
      ],
    );
  }

  Widget _quizChoices() {
    if (_loadingChoices) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_choices.length != 4) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _selected == _item.chinese ? '答對了' : '正確：${_item.chinese}',
                key: const ValueKey('quiz-feedback'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _choice(_choices[row * 2], row * 2)),
                const SizedBox(width: 8),
                Expanded(child: _choice(_choices[row * 2 + 1], row * 2 + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _choice(String choice, int index) {
    final answered = _selected != null;
    final correct = answered && choice == _item.chinese;
    final wrong = answered && choice == _selected && !correct;
    return OutlinedButton(
      key: ValueKey('quiz-choice-$index'),
      onPressed: answered || _locked ? null : () => _answer(choice),
      style: OutlinedButton.styleFrom(
        backgroundColor: correct
            ? sage
            : wrong
            ? peach
            : Colors.white,
        foregroundColor: ink,
        disabledForegroundColor: ink,
        side: BorderSide(
          color: correct
              ? ink
              : wrong
              ? orange
              : line,
        ),
        minimumSize: const Size(0, 64),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: correct || wrong
                ? Icon(
                    correct ? Icons.check_rounded : Icons.close_rounded,
                    color: correct ? ink : orange,
                    size: 18,
                  )
                : Text(
                    String.fromCharCode(65 + index),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(choice, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _errorFeedback() => InkWell(
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: orange, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: orange, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _assessmentButton() => TextButton.icon(
    onPressed: () => _showSheet(_scorePanel(_assessment!)),
    icon: const Icon(Icons.analytics_outlined, size: 18),
    label: Text('發音 ${_assessment!.overall.toStringAsFixed(0)} / 100'),
  );

  Future<void> _showExample() async {
    final item = _item;
    var playing = false;
    await _showSheet(
      StatefulBuilder(
        builder: (sheetContext, updateSheet) => Column(
          key: const ValueKey('example-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('例句')),
                CopyThaiButton(item.exampleThai!),
              ],
            ),
            thai(item.exampleThai!, size: 25),
            if (item.exampleRomanization != null) ...[
              const SizedBox(height: 8),
              Text(
                item.exampleRomanization!,
                key: const ValueKey('example-romanization'),
                style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
              ),
            ],
            if (item.exampleChinese != null) ...[
              const SizedBox(height: 12),
              Text(item.exampleChinese!),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final provider in TtsProvider.values)
                  IconButton(
                    color: provider == TtsProvider.azure ? orange : null,
                    tooltip: provider == TtsProvider.local
                        ? 'Local TTS 播放'
                        : 'Azure TTS 播放',
                    onPressed: playing
                        ? null
                        : () async {
                            updateSheet(() => playing = true);
                            await _speak(
                              text: item.exampleNativeThai ?? item.exampleThai!,
                              provider: provider,
                            );
                            if (!sheetContext.mounted) return;
                            updateSheet(() => playing = false);
                            if (_error != null) {
                              showNotice(sheetContext, _error!);
                            }
                          },
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                IconButton(
                  tooltip: '關閉例句',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _releaseMedia();
    setState(() {});
  }

  Future<void> _showSheet(Widget child) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _scorePanel(Assessment result) {
    final errors = result.words.where((word) {
      final type = word['errorType']?.toString();
      return type != null && type != 'None' && type != 'none';
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '發音回饋',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        _scoreBar('整體發音', result.overall),
        _scoreBar('準確度', result.accuracy),
        _scoreBar('流暢度', result.fluency),
        _scoreBar('完整度', result.completeness),
        if (result.recognizedText.isNotEmpty) ...[
          const Text('辨識到的內容', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
          thai(result.recognizedText, size: 20),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('可以再練習的地方', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final word in errors.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${word['word'] ?? ''} · ${_errorLabel(word['errorType']?.toString())}',
                style: const TextStyle(
                  fontFamily: 'NotoSerifThai',
                  color: muted,
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _errorLabel(String? type) => switch (type) {
    'Mispronunciation' => '留意這個字的發音',
    'Omission' => '試著完整讀出這個字',
    'Insertion' => '這裡多讀了一個字',
    'UnexpectedBreak' => '這裡的停頓可以短一點',
    'MissingBreak' => '這裡可以稍微停頓',
    _ => '聽完示範後再讀一次',
  };

  Widget _scoreBar(String label, double score) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(
              score.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: (score / 100).clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
          backgroundColor: line,
          color: score >= 70 ? ink : orange,
        ),
      ],
    ),
  );

  Widget _completion() {
    if (_items.isEmpty) {
      return const Panel(child: Text('目前沒有可以練習的內容'));
    }
    final count = _items.length;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const CircleAvatar(
            radius: 32,
            backgroundColor: sage,
            child: Icon(Icons.check_rounded, color: ink, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            widget.quiz ? '測驗結果' : '練習紀錄',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Text(
            widget.quiz
                ? '答對 $_correct / $count 題 · 正確率 ${(_correct / count * 100).round()}%'
                : '已複習 ${_reviews.length} / $count 張 · 記住了 $_remembered 張',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
          if (widget.quiz && _answers.length < count) ...[
            const SizedBox(height: 8),
            Text(
              '尚有 ${count - _answers.length} 題未作答',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('完成練習'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _goTo(_items.length - 1),
            child: const Text('返回卡片'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _restart, child: const Text('再練習一次')),
        ],
      ),
    );
  }
}
