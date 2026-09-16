import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/learning_item.dart';
import '../models/speaker_gender.dart';
import '../services/app_settings.dart';
import '../services/learning_store.dart';
import '../services/cloud_sync.dart';
import '../services/practice_session.dart';
import '../theme.dart';
import 'library_screen.dart';
import 'practice_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.items,
    required this.store,
    required this.cloud,
  });
  final List<LearningItem> items;
  final LearningStore store;
  final CloudSync cloud;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LearningItem> get _items => widget.items
      .map((item) => item.forGender(AppSettings.instance.gender))
      .toList(growable: false);

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  int _page = 0;
  String? _category;
  final _scroll = ScrollController();
  static const _labels = ['今日學習', '常用單字', '日常句子', '收藏複習', '學習進度'];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.style_outlined,
    Icons.chat_bubble_outline_rounded,
    Icons.bookmark_border_rounded,
    Icons.insights_rounded,
  ];
  void _navigate(int page, {String? category}) {
    setState(() {
      _page = page;
      _category = category;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _practice(List<LearningItem> items, {bool quiz = false}) {
    if (items.isEmpty) {
      showNotice(context, '先收藏幾個單字，開始你的複習吧。');
      return;
    }
    final session = samplePracticeItems(items);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PracticeScreen(items: session, store: widget.store, quiz: quiz),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.store,
      widget.cloud,
      AppSettings.instance,
    ]),
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      return Scaffold(
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                height: 72,
                backgroundColor: Colors.white,
                indicatorColor: peach,
                selectedIndex: _page,
                onDestinationSelected: _navigate,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (var i = 0; i < 5; i++)
                    NavigationDestination(
                      icon: Icon(_icons[i], size: 22),
                      label: ['今日', '單字', '句子', '收藏', '進度'][i],
                    ),
                ],
              ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _topbar(wide),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: EdgeInsets.all(wide ? 36 : 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1220),
                            child: switch (_page) {
                              0 => _dashboard(),
                              1 || 2 || 3 => LibraryScreen(
                                key: ValueKey('$_page/$_category'),
                                items: _items,
                                store: widget.store,
                                sentences: _page == 2,
                                savedOnly: _page == 3,
                                initialCategory: _category,
                                onPractice: _practice,
                              ),
                              _ => ProfileScreen(
                                items: _items,
                                store: widget.store,
                                cloud: widget.cloud,
                              ),
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _sidebar() => Container(
    width: 228,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 34, 20, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/brand/app-icon.png',
                  width: 42,
                  height: 42,
                ),
              ),
              const SizedBox(width: 11),
              const Text(
                'ThaiTalk',
                style: TextStyle(
                  fontSize: 25,
                  color: ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 12, 0, 42),
          child: Text(
            '讓泰語，走進你的日常。',
            style: TextStyle(fontSize: 11, color: muted, letterSpacing: 1),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 0, 14),
          child: Text(
            '我的學習',
            style: TextStyle(fontSize: 10, color: muted, letterSpacing: 2),
          ),
        ),
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _page == i ? peach : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _navigate(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _icons[i],
                        color: _page == i ? orange : muted,
                        size: 21,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        _labels[i],
                        style: TextStyle(
                          color: _page == i ? orange : ink,
                          fontSize: 14,
                          fontWeight: _page == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (i == 3 && widget.store.savedIds.isNotEmpty) ...[
                        const Spacer(),
                        Text(
                          '${widget.store.savedIds.length}',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: canvas,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.spa_outlined,
                color: Color(0xFF7D9475),
                size: 25,
              ),
              const SizedBox(height: 10),
              const Text(
                '每天一小步，\n離泰國更近一步。',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7D9475),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '你的泰語旅程，由此開始',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _navigate(4),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: sage,
                child: Icon(Icons.person_outline_rounded, color: ink, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cloud.isSignedIn ? '我的帳號' : '泰語探索者',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.cloud.isSignedIn ? '已登入 · 雲端同步' : '入門學習者',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _topbar(bool wide) => Container(
    height: wide ? 83 : 68,
    padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 20),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!wide) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/brand/app-icon.png',
              width: 30,
              height: 30,
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'ThaiTalk',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
        ] else ...[
          Text(
            _labels[_page],
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(width: 12),
          const Text('/', style: TextStyle(color: line)),
          const SizedBox(width: 12),
          const Text('每天進步一點點', style: TextStyle(color: muted, fontSize: 12)),
        ],
        const Spacer(),
        if (MediaQuery.sizeOf(context).width >= 440)
          const Tag(
            '繁體中文',
            background: canvas,
            color: muted,
            icon: Icons.language_rounded,
          ),
        SizedBox(width: wide ? 24 : 12),
        Icon(Icons.local_fire_department_outlined, size: 21, color: orange),
        const SizedBox(width: 5),
        Text(
          '${widget.store.streak}',
          style: const TextStyle(color: orange, fontWeight: FontWeight.w700),
        ),
        IconButton(
          key: const ValueKey('open-settings'),
          tooltip: '設定',
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined, size: 22),
        ),
        if (wide) ...[
          const SizedBox(width: 24),
          const SizedBox(height: 24, child: VerticalDivider()),
          const SizedBox(width: 14),
          const CircleAvatar(
            radius: 17,
            backgroundColor: sage,
            child: Text(
              'T',
              style: TextStyle(color: ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    ),
  );
  Widget _dashboard() {
    final compact = MediaQuery.sizeOf(context).width < 1250;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppSettings.instance.gender == SpeakerGender.male
                        ? 'สวัสดี ครับ  你好！'
                        : 'สวัสดี ค่ะ  你好！',
                    style: TextStyle(
                      fontFamily: 'NotoSerifThai',
                      fontFamilyFallback: const ['NotoSansTC'],
                      fontSize: compact ? 26 : 30,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '準備好開口說泰語了嗎？一起累積今天的小進步。',
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${DateTime.now().month} 月 ${DateTime.now().day} 日  ·  ${['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][DateTime.now().weekday - 1]}',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        if (compact) ...[
          _hero(),
          const SizedBox(height: 20),
          _stats(),
          const SizedBox(height: 30),
          _learningPaths(),
          const SizedBox(height: 28),
          _scenarios(),
          const SizedBox(height: 28),
          _dailyPanel(),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: [
                    _hero(),
                    const SizedBox(height: 22),
                    _stats(),
                    const SizedBox(height: 32),
                    _learningPaths(),
                    const SizedBox(height: 30),
                    _scenarios(),
                  ],
                ),
              ),
              const SizedBox(width: 26),
              Expanded(flex: 3, child: _dailyPanel()),
            ],
          ),
        const SizedBox(height: 32),
        const Center(
          child: Text(
            '用一點點練習，換一整個世界的交流。  ♡',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _hero() => LayoutBuilder(
    builder: (context, constraints) {
      final art = constraints.maxWidth > 570;
      return Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: peach,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            if (art)
              const Positioned(
                right: -12,
                top: -8,
                bottom: -8,
                width: 280,
                child: _HeroArt(),
              ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Tag(
                    'YOUR DAILY DOSE OF THAI',
                    background: Color(0xFFFFF7F0),
                    color: orange,
                    icon: Icons.wb_sunny_outlined,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '每天一點泰語，\n每次開口更有自信。',
                    style: TextStyle(
                      fontSize: art ? 29 : 26,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                      color: ink,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '從一句你好，到你的下一趟旅行。\n今天，就從 10 個小練習開始。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8F8175),
                      height: 1.9,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _practice(_items),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('開始今日練習'),
                        SizedBox(width: 18),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _stats() => Row(
    children: [
      Expanded(
        child: _stat(
          Icons.auto_stories_outlined,
          '${widget.store.learnedIds.length}',
          '已學會的內容',
          sage,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _stat(
          Icons.local_fire_department_outlined,
          '${widget.store.streak} 天',
          '連續學習',
          peach,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _stat(
          Icons.bolt_rounded,
          '${widget.store.totalXp}',
          '累積 XP',
          const Color(0xFFF6F0DD),
        ),
      ),
    ],
  );
  Widget _stat(IconData icon, String value, String label, Color color) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
    child: LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: color == peach ? orange : ink),
          ),
          const SizedBox(height: 11),
          Text(
            value,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    ),
  );
  Widget _learningPaths() => Column(
    children: [
      SectionHeading('找到你的學習節奏', subtitle: '聽、記、說，讓每個新單字真正成為你的。'),
      LayoutBuilder(
        builder: (context, c) {
          final cards = [
            _pathCard(
              '常用單字',
              '從生活裡最常用的單字開始',
              '300 個單字 · 8 個主題',
              Icons.style_outlined,
              sage,
              () => _navigate(1),
            ),
            _pathCard(
              '日常句子',
              '把泰語帶進真實生活情境',
              '100 個句子 · 8 個情境',
              Icons.forum_outlined,
              const Color(0xFFF7EFE2),
              () => _navigate(2),
            ),
          ];
          return c.maxWidth < 470
              ? Column(
                  children: [cards[0], const SizedBox(height: 14), cards[1]],
                )
              : Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[1]),
                  ],
                );
        },
      ),
    ],
  );
  Widget _pathCard(
    String title,
    String desc,
    String count,
    IconData icon,
    Color color,
    VoidCallback action,
  ) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: ink, size: 26),
                ),
                const Spacer(),
                const Icon(Icons.north_east_rounded, color: muted, size: 20),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(desc, style: const TextStyle(fontSize: 11, color: muted)),
            const SizedBox(height: 18),
            Text(
              count,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF78916E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _scenarios() => Column(
    children: [
      SectionHeading('下一站，泰國日常', action: '全部情境', onAction: () => _navigate(2)),
      LayoutBuilder(
        builder: (context, c) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final category in ['restaurant', 'taxi', 'shopping', 'hotel'])
              SizedBox(
                width:
                    (c.maxWidth - (c.maxWidth < 500 ? 12 : 36)) /
                    (c.maxWidth < 500 ? 2 : 4),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _navigate(2, category: category),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 21),
                      decoration: BoxDecoration(
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            categoryIcon(category),
                            color: Color(0xFF819579),
                            size: 27,
                          ),
                          const SizedBox(height: 13),
                          Text(
                            categoryName(category),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
  Widget _dailyPanel() => Column(
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.adjust_rounded, color: orange, size: 20),
                const SizedBox(width: 9),
                const Text(
                  '今日小目標',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '調整每日目標',
                  onPressed: () => _navigate(4),
                  icon: const Icon(Icons.tune_rounded, size: 18, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: SizedBox(
                width: 154,
                height: 154,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value:
                            (widget.store.todayCount / widget.store.dailyGoal)
                                .clamp(0, 1),
                        strokeWidth: 10,
                        backgroundColor: sage,
                        color: orange,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${widget.store.todayCount}',
                          style: const TextStyle(
                            fontSize: 39,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '/ ${widget.store.dailyGoal} 個練習',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                widget.store.todayCount >= widget.store.dailyGoal
                    ? '今天的目標達成了，做得好！'
                    : '一點一滴，就是進步。',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 17),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (var i = 0; i < 7; i++) _weekDay(i)],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      const SizedBox(height: 22),
      _dailyWord(),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: sage,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              color: Color(0xFF73886D),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '泰語小筆記',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    AppSettings.instance.gender == SpeakerGender.male
                        ? '男性說話時，在句尾加上「ครับ khrap」，就能讓語氣更有禮貌。'
                        : '女性陳述用「ค่ะ kha」，疑問通常用「คะ kha」。',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6D8067),
                      height: 1.9,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _weekDay(int i) {
    final now = DateTime.now();
    final date = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1)).add(Duration(days: i));
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final done = (widget.store.activity[key] ?? 0) > 0;
    return Column(
      children: [
        Text(
          ['一', '二', '三', '四', '五', '六', '日'][i],
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 10),
        Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: done ? orange : canvas,
            shape: BoxShape.circle,
            border: i == now.weekday - 1 ? Border.all(color: orange) : null,
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.remove_rounded,
            size: 13,
            color: done ? Colors.white : line,
          ),
        ),
      ],
    );
  }

  Widget _dailyWord() {
    final item = _items
        .where((i) => !i.isSentence)
        .toList()[DateTime.now().difference(DateTime(2026)).inDays.abs() % 300];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_twilight_rounded, size: 18, color: orange),
              SizedBox(width: 8),
              Text(
                '每日一詞',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              CopyThaiButton(item.thai),
            ],
          ),
          const SizedBox(height: 17),
          thai(item.thai, size: 30),
          Text(
            item.romanization,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(item.chinese, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 17),
          const Divider(),
          TextButton(
            onPressed: () => _practice([item]),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: orange,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('聽聽看，跟著說', style: TextStyle(fontSize: 12)),
                Icon(Icons.volume_up_outlined, size: 19),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroArt extends StatelessWidget {
  const _HeroArt();
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Positioned(
        right: -30,
        top: 30,
        child: Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF0D7C6).withValues(alpha: .7),
          ),
        ),
      ),
      Positioned(
        right: 24,
        bottom: 42,
        child: Transform.rotate(
          angle: .11,
          child: Container(
            width: 139,
            height: 166,
            decoration: BoxDecoration(
              color: const Color(0xFF9AAB8F),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(child: thai('ก', size: 98, color: Colors.white)),
          ),
        ),
      ),
      Positioned(
        left: 13,
        top: 40,
        child: Transform.rotate(
          angle: -.12,
          child: Container(
            width: 137,
            height: 165,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF5),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: ink.withValues(alpha: .07),
                  offset: const Offset(0, 8),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                thai('สวัสดี', size: 30),
                const SizedBox(height: 2),
                const Text(
                  'sa-wat-di',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 12),
                const Icon(Icons.graphic_eq_rounded, size: 25, color: orange),
              ],
            ),
          ),
        ),
      ),
      const Positioned(
        right: 46,
        top: 25,
        child: Icon(Icons.auto_awesome_rounded, size: 32, color: orange),
      ),
      Positioned(
        left: 18,
        bottom: 40,
        child: Transform.rotate(
          angle: -math.pi / 10,
          child: const Icon(
            Icons.eco_rounded,
            size: 57,
            color: Color(0xFF859A77),
          ),
        ),
      ),
      const Positioned(
        right: 3,
        top: 140,
        child: Icon(Icons.circle_outlined, size: 16, color: orange),
      ),
    ],
  );
}
