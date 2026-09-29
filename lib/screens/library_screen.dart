import 'package:flutter/material.dart';
import '../models/learning_item.dart';
import '../models/study_language.dart';
import '../services/learning_store.dart';
import '../services/app_settings.dart';
import '../services/speech_service.dart';
import '../theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.items,
    required this.store,
    required this.sentences,
    this.phrases = false,
    required this.savedOnly,
    required this.onPractice,
    this.initialCategory,
  });
  final List<LearningItem> items;
  final LearningStore store;
  final bool sentences, savedOnly;
  final bool phrases;
  final String? initialCategory;
  final void Function(List<LearningItem> items, {bool quiz}) onPractice;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  SpeechService? _speech;
  int _audioOperation = 0;
  String? _category;
  int? _level;
  bool _dueOnly = false;
  int? _playing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _category = _base.any((item) => item.category == widget.initialCategory)
        ? widget.initialCategory
        : null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _stopSpeech();
    super.dispose();
  }

  void _stopSpeech() {
    _audioOperation++;
    _speech?.dispose();
    _speech = null;
    _playing = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopSpeech();
      if (mounted) setState(() {});
    }
  }

  List<LearningItem> get _base => widget.items
      .where(
        (i) => widget.savedOnly
            ? widget.store.savedIds.contains(i.id)
            : widget.phrases
            ? i.isPhrase
            : i.isSentence == widget.sentences && !i.isPhrase,
      )
      .toList();
  List<LearningItem> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _base
        .where(
          (i) =>
              (_category == null || i.category == _category) &&
              (_level == null || i.level == _level) &&
              (!_dueOnly || widget.store.reviewDueIds.contains(i.id)) &&
              (q.isEmpty ||
                  '${i.thai} ${i.speechText} ${i.romanization} ${i.chinese}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
  }

  Future<void> _play(LearningItem item) async {
    if (_playing != null) return;
    final operation = ++_audioOperation;
    setState(() => _playing = item.id);
    try {
      await (_speech ??= SpeechService()).speak(
        item.speechText,
        provider: TtsProvider.local,
      );
    } catch (e) {
      if (mounted && operation == _audioOperation) {
        showNotice(context, e.toString());
      }
    } finally {
      if (mounted && operation == _audioOperation) {
        setState(() => _playing = null);
      }
    }
  }

  void _openPractice(List<LearningItem> items, {bool quiz = false}) {
    _stopSpeech();
    setState(() {});
    widget.onPractice(items, quiz: quiz);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    // Keep saved-topic choices stable when the final item in a topic is
    // removed, so the selected dropdown value remains valid.
    final categories = (widget.savedOnly ? widget.items : _base)
        .map((item) => item.category)
        .toSet();
    final noun = widget.savedOnly
        ? '收藏'
        : widget.phrases
        ? '片語'
        : widget.sentences
        ? '句子'
        : '單字';
    final selectedCount = AppSettings.instance.questionsPerRound;
    final roundSize = items.length < selectedCount
        ? items.length
        : selectedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.savedOnly
              ? '我的收藏'
              : widget.phrases
              ? '片語練習'
              : widget.sentences
              ? '句子練習'
              : '單字練習',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          widget.savedOnly
              ? '把想記住的內容，練習到熟悉。'
              : widget.phrases
              ? '每個片語約 3–5 音節，聽讀後試著錄音練習。'
              : '選個主題，開始一輪 $selectedCount 題練習。',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('library-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText:
                widget.items.firstOrNull?.language == StudyLanguage.japanese
                ? '搜尋日文、假名或中文…'
                : '搜尋泰文、拼音或中文…',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: muted,
            ),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜尋',
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('library-category'),
                initialValue: _category,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: ink),
                decoration: const InputDecoration(
                  labelText: '主題',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部主題')),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category,
                      child: Text(
                        categoryName(category),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int?>(
                key: const ValueKey('library-level'),
                initialValue: _level,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: ink),
                decoration: const InputDecoration(
                  labelText: '程度',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部程度')),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(
                      widget.items.firstOrNull?.language ==
                              StudyLanguage.japanese
                          ? 'N3'
                          : '入門 A1',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(
                      widget.items.firstOrNull?.language ==
                              StudyLanguage.japanese
                          ? 'N2'
                          : '基礎 A2',
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _level = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${items.length} 個$noun',
              key: const ValueKey('library-count'),
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            if (items.isNotEmpty)
              Text(
                '本輪隨機 $roundSize 題 · 每次重新排序',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            if (widget.savedOnly)
              FilterChip(
                label: const Text('到期複習', style: TextStyle(fontSize: 11)),
                selected: _dueOnly,
                onSelected: (value) => setState(() => _dueOnly = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('library-flashcards'),
                onPressed: items.isEmpty ? null : () => _openPractice(items),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 17,
                  ),
                ),
                icon: const Icon(Icons.style_outlined, size: 18),
                label: const Text('翻卡練習'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('library-quiz'),
                onPressed: items.isEmpty
                    ? null
                    : () => _openPractice(items, quiz: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 17,
                  ),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('開始測驗'),
              ),
            ),
          ],
        ),
        if (!widget.savedOnly && items.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '進入練習後，可朗讀、評分與複製泰文。',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
        if (items.isEmpty) ...[
          const SizedBox(height: 20),
          Panel(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  Icon(
                    widget.savedOnly
                        ? Icons.bookmark_border_rounded
                        : Icons.search_off_rounded,
                    size: 34,
                    color: const Color(0xFF9BAB94),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.savedOnly && _base.isEmpty ? '還沒有收藏內容' : '沒有符合條件的內容',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.savedOnly && _base.isEmpty
                        ? '在練習中點選書籤，建立自己的複習清單。'
                        : '試試其他關鍵字、主題或程度。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ] else if (widget.savedOnly) ...[
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 620
                  ? 1
                  : constraints.maxWidth < 1000
                  ? 2
                  : 3;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in items)
                    SizedBox(width: width, child: _item(item)),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _item(LearningItem item) => Panel(
    padding: const EdgeInsets.fromLTRB(21, 16, 15, 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Tag(categoryName(item.category), background: canvas, color: muted),
            const SizedBox(width: 6),
            if (widget.store.learnedIds.contains(item.id))
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF819579),
                size: 17,
              ),
            const Spacer(),
            IconButton(
              tooltip: widget.store.savedIds.contains(item.id) ? '取消收藏' : '收藏',
              onPressed: () => widget.store.toggleSaved(item.id),
              icon: Icon(
                widget.store.savedIds.contains(item.id)
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 21,
                color: widget.store.savedIds.contains(item.id) ? orange : muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        learningText(item, size: item.isSentence ? 25 : 30),
        const SizedBox(height: 10),
        Text(item.chinese, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 14),
        const Divider(),
        Row(
          children: [
            Text(
              item.language == StudyLanguage.japanese
                  ? item.levelLabel
                  : (item.level == 1 ? '入門 A1' : '基礎 A2'),
              style: const TextStyle(fontSize: 10, color: muted),
            ),
            const Spacer(),
            CopyThaiButton(item.thai),
            IconButton(
              tooltip: '朗讀',
              onPressed: _playing != null ? null : () => _play(item),
              icon: _playing == item.id
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.volume_up_outlined,
                      color: orange,
                      size: 20,
                    ),
            ),
            TextButton(
              onPressed: () => _openPractice([item]),
              child: const Row(
                children: [
                  Text('練習', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
