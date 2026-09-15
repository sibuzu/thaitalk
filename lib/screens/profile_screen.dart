import 'package:flutter/material.dart';
import '../models/learning_item.dart';
import '../services/learning_store.dart';
import '../services/cloud_sync.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.items,
    required this.store,
    required this.cloud,
  });
  final List<LearningItem> items;
  final LearningStore store;
  final CloudSync cloud;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false, _signup = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _auth() async {
    if (!_email.text.contains('@') || _password.text.length < 8) {
      setState(() => _message = '請輸入有效的 Email，密碼至少 8 個字元。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signup) {
        final active = await widget.cloud.signUp(
          _email.text.trim(),
          _password.text,
        );
        if (mounted) {
          setState(() => _message = active ? '帳號建立成功。' : '已寄出驗證信，請到信箱完成驗證後登入。');
        }
      } else {
        await widget.cloud.signIn(_email.text.trim(), _password.text);
      }
      _password.clear();
    } catch (_) {
      if (mounted) setState(() => _message = '登入或註冊失敗，請確認資料、信箱驗證及網路連線。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final cloud = widget.cloud;
    final categories = widget.items.map((i) => i.category).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Tag('YOUR LEARNING JOURNEY'),
        const SizedBox(height: 15),
        Text('每一點努力，都算數。', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          '看看走過的路，為下一個小目標做好準備。',
          style: TextStyle(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final stat in [
                (
                  Icons.auto_stories_outlined,
                  '${store.learnedIds.length} / 400',
                  '已學會內容',
                ),
                (
                  Icons.local_fire_department_outlined,
                  '${store.streak} 天',
                  '連續學習',
                ),
                (Icons.bolt_rounded, '${store.totalXp} XP', '學習經驗'),
                (
                  Icons.mic_none_rounded,
                  store.bestScores.isEmpty
                      ? '—'
                      : '${(store.bestScores.values.reduce((a, b) => a + b) / store.bestScores.length).round()} 分',
                  '平均最佳發音',
                ),
              ])
                SizedBox(
                  width:
                      (c.maxWidth - (c.maxWidth < 650 ? 16 : 48)) /
                      (c.maxWidth < 650 ? 2 : 4),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(stat.$1, color: orange),
                        const SizedBox(height: 14),
                        Text(
                          stat.$2,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stat.$3,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                '為每天，留一點泰語時間',
                subtitle: '依照自己的步調設定目標，完成一次練習就前進一步。',
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final goal in [5, 10, 20, 30])
                    ChoiceChip(
                      selected: store.dailyGoal == goal,
                      label: Text(
                        '$goal 個練習 / 天',
                        style: TextStyle(
                          fontSize: 12,
                          color: store.dailyGoal == goal ? Colors.white : ink,
                        ),
                      ),
                      selectedColor: ink,
                      showCheckmark: false,
                      onSelected: (_) => store.setDailyGoal(goal),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('主題學習進度'),
              for (final category in categories) ...[
                _categoryProgress(category),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_outlined, color: orange),
                  const SizedBox(width: 10),
                  Text(
                    '你的學習，隨身同行',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!cloud.isConfigured) ...[
                const Text('學習進度已自動儲存在這台裝置。', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 7),
                const Text(
                  '此版本尚未啟用帳號同步，你可以繼續使用所有本機學習功能。',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ] else if (cloud.isSignedIn) ...[
                Text(
                  cloud.email ?? '已登入',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 10),
                Text(
                  cloud.isSyncing
                      ? '正在同步學習進度…'
                      : cloud.lastSyncedAt != null
                      ? '最近同步：${cloud.lastSyncedAt!.toLocal().toString().substring(0, 16)}'
                      : '登入後自動同步學習進度',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: cloud.isSyncing ? null : () => cloud.sync(),
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('立即同步'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await cloud.signOut();
                        } catch (_) {
                          if (context.mounted) {
                            showNotice(context, '登出失敗，請稍後重試。');
                          }
                        }
                      },
                      child: const Text('登出'),
                    ),
                  ],
                ),
              ] else ...[
                const Text(
                  '登入即可在不同裝置接續練習。',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _busy ? null : _auth(),
                        decoration: const InputDecoration(
                          labelText: '密碼（至少 8 個字元）',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _busy ? null : _auth,
                            child: Text(
                              _busy
                                  ? '處理中…'
                                  : _signup
                                  ? '建立帳號'
                                  : '登入',
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _signup = !_signup;
                                    _message = null;
                                  }),
                            child: Text(_signup ? '已有帳號？登入' : '還沒有帳號？註冊'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 12, color: orange),
                ),
              ],
              if (cloud.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  cloud.error!,
                  style: const TextStyle(fontSize: 12, color: orange),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Panel(
          color: sage,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.record_voice_over_outlined, color: ink),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '男聲朗讀 · 自信開口',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '所有情境句子採用男性說話者用語，搭配泰語男聲 Niwat。錄音只在你送出評分時傳送至語音服務，不會儲存在學習紀錄中。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6D8067),
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Center(
          child: Text(
            'ThaiTalk 1.1.0  ·  Made for your next สวัสดี',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontFamilyFallback: ['NotoSerifThai'],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryProgress(String category) {
    final items = widget.items.where((i) => i.category == category).toList();
    final learned = items
        .where((i) => widget.store.learnedIds.contains(i.id))
        .length;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: canvas,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            categoryIcon(category),
            size: 18,
            color: Color(0xFF819579),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    categoryName(category),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '$learned / ${items.length}',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: learned / items.length,
                  color: const Color(0xFF8DA180),
                  backgroundColor: sage,
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
