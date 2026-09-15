import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline-first study progress. Counters are kept per installation so cloud
/// merges do not double-count activities or discard work from another device.
class LearningStore extends ChangeNotifier {
  LearningStore._(this._preferences, this._deviceId, this._clock);

  static const _prefix = 'thaitalk.progress.v1';
  final SharedPreferences _preferences;
  final String _deviceId;
  final DateTime Function() _clock;
  String _counterSource = '';
  String? _accountId;
  final Map<int, _SavedState> _saved = {};
  final Set<int> _learned = {};
  final Map<int, _ReviewState> _reviews = {};
  final Map<int, double> _bestScores = {};
  final Map<String, Map<String, _ActivityCounter>> _counters = {};
  int _dailyGoal = 10;
  int _goalUpdatedAt = 0;
  int _updatedAt = 0;
  Future<void> _pendingWrite = Future<void>.value();
  String? _persistenceError;

  static Future<LearningStore> load({DateTime Function()? clock}) async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString('thaitalk.device_id');
    if (deviceId == null) {
      deviceId =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${Random.secure().nextInt(0x100000000).toRadixString(36)}';
      await preferences.setString('thaitalk.device_id', deviceId);
    }
    final store = LearningStore._(preferences, deviceId, clock ?? DateTime.now);
    await store._loadCounterSource();
    store._restore(preferences.getString(store._storageKey));
    return store;
  }

  String get _storageKey => '$_prefix.${_accountId ?? 'guest'}';
  String? get accountId => _accountId;
  String? get persistenceError => _persistenceError;
  Set<int> get savedIds => Set<int>.unmodifiable(
    _saved.entries
        .where((entry) => entry.value.saved)
        .map((entry) => entry.key),
  );
  Set<int> get learnedIds => Set<int>.unmodifiable(_learned);
  Set<int> get reviewDueIds {
    final now = _clock().toUtc();
    return Set<int>.unmodifiable(
      _reviews.entries
          .where((entry) => !entry.value.dueAt.isAfter(now))
          .map((entry) => entry.key),
    );
  }

  Map<int, double> get bestScores => Map<int, double>.unmodifiable(_bestScores);
  Map<String, int> get activity => Map<String, int>.unmodifiable({
    for (final entry in _counters.entries)
      entry.key: entry.value.values.fold<int>(
        0,
        (sum, value) => sum + value.count,
      ),
  });
  int get totalXp => _counters.values.fold<int>(
    0,
    (sum, devices) =>
        sum + devices.values.fold<int>(0, (sum, value) => sum + value.xp),
  );
  int get dailyGoal => _dailyGoal;
  int get todayCount => activity[_dayKey(_clock())] ?? 0;
  int get streak {
    final counts = activity;
    final now = _clock();
    var day = DateTime(now.year, now.month, now.day);
    if ((counts[_dayKey(day)] ?? 0) == 0) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var count = 0;
    while ((counts[_dayKey(day)] ?? 0) > 0) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  DateTime? nextReviewAt(int id) => _reviews[id]?.dueAt.toLocal();

  void toggleSaved(int id) {
    _requireId(id);
    _saved[id] = _SavedState(!(_saved[id]?.saved ?? false), _timestamp());
    _changed();
  }

  void markReviewed(int id, {required bool remembered}) {
    _requireId(id);
    _scheduleReview(id, remembered);
    _recordActivity(remembered ? 10 : 3);
    _changed();
  }

  void recordQuizAnswer(int id, {required bool correct}) {
    _requireId(id);
    _scheduleReview(id, correct);
    _recordActivity(correct ? 15 : 3);
    _changed();
  }

  void recordPronunciation(int id, double score) {
    _requireId(id);
    if (!score.isFinite || score < 0 || score > 100) {
      throw ArgumentError.value(score, 'score', 'Must be between 0 and 100.');
    }
    _bestScores[id] = max(_bestScores[id] ?? 0, score);
    _scheduleReview(id, score >= 70);
    _recordActivity(score >= 70 ? 20 : 5);
    _changed();
  }

  void setDailyGoal(int goal) {
    if (goal < 1 || goal > 100) {
      throw ArgumentError.value(goal, 'goal', 'Must be between 1 and 100.');
    }
    _dailyGoal = goal;
    _goalUpdatedAt = _timestamp();
    _changed();
  }

  void _scheduleReview(int id, bool remembered) {
    final now = _clock().toUtc();
    final previous = _reviews[id];
    // Practising the same item repeatedly before its due date does not skip
    // ahead through the spaced-repetition intervals.
    final advance =
        previous == null || previous.stage == 0 || !previous.dueAt.isAfter(now);
    final stage = remembered
        ? (advance ? min((previous?.stage ?? 0) + 1, 6) : previous.stage)
        : 0;
    const days = [0, 1, 3, 7, 14, 30, 60];
    final dueAt = remembered
        ? (advance ? now.add(Duration(days: days[stage])) : previous.dueAt)
        : now.add(const Duration(minutes: 10));
    if (remembered) _learned.add(id);
    _reviews[id] = _ReviewState(stage, dueAt, _timestamp());
  }

  void _recordActivity(int xp) {
    final devices = _counters.putIfAbsent(_dayKey(_clock()), () => {});
    final counter = devices.putIfAbsent(
      _counterSource,
      () => _ActivityCounter(0, 0),
    );
    counter.count++;
    counter.xp += xp;
  }

  int _timestamp() =>
      max(_clock().toUtc().millisecondsSinceEpoch, _updatedAt + 1);
  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  static void _requireId(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'Must be positive.');
  }

  void _changed() {
    _updatedAt = _timestamp();
    _persist();
    notifyListeners();
  }

  void _persist() {
    final key = _storageKey;
    final snapshot = jsonEncode(exportProgress());
    _pendingWrite = _pendingWrite
        .then((_) async {
          final saved = await _preferences.setString(key, snapshot);
          if (!saved) throw StateError('Could not save learning progress.');
          _persistenceError = null;
        })
        .catchError((Object error) {
          _persistenceError = '學習紀錄尚未儲存，請確認裝置儲存空間。';
          debugPrint('Learning progress persistence failed: $error');
        });
  }

  /// Wait until all local writes are complete (useful before account changes).
  Future<void> flush() => _pendingWrite;

  Future<void> _loadCounterSource() async {
    final key = '$_storageKey.counter_source';
    final existing = _preferences.getString(key);
    if (existing != null) {
      _counterSource = existing;
      return;
    }
    _counterSource =
        '$_deviceId-'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${Random.secure().nextInt(0x100000000).toRadixString(36)}';
    await _preferences.setString(key, _counterSource);
  }

  Map<String, dynamic> exportProgress() => {
    'version': 1,
    'updated_at': _updatedAt,
    'saved': {
      for (final entry in _saved.entries) '${entry.key}': entry.value.toJson(),
    },
    'learned': _learned.toList()..sort(),
    'reviews': {
      for (final entry in _reviews.entries)
        '${entry.key}': entry.value.toJson(),
    },
    'best_scores': {
      for (final entry in _bestScores.entries) '${entry.key}': entry.value,
    },
    'activity': {
      for (final day in _counters.entries)
        day.key: {
          for (final device in day.value.entries)
            device.key: {'count': device.value.count, 'xp': device.value.xp},
        },
    },
    'daily_goal': _dailyGoal,
    'goal_updated_at': _goalUpdatedAt,
  };

  /// Merge cloud state. Saved-item deletions carry timestamps; per-device
  /// activity counters use maxima, making repeated imports idempotent.
  Future<void> importProgress(Map<String, dynamic> data) async {
    _merge(data);
    _changed();
    await flush();
  }

  void _merge(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unsupported progress data version.');
    }
    for (final entry in _map(data['saved']).entries) {
      final id = int.tryParse(entry.key);
      final value = _map(entry.value);
      if (id == null || id <= 0 || value['saved'] is! bool) continue;
      final at = _int(value['at']);
      if (at > (_saved[id]?.updatedAt ?? -1)) {
        _saved[id] = _SavedState(value['saved'] as bool, at);
      }
    }
    final learned = data['learned'];
    if (learned is List) {
      _learned.addAll(learned.whereType<int>().where((id) => id > 0));
    }
    for (final entry in _map(data['reviews']).entries) {
      final id = int.tryParse(entry.key);
      final value = _map(entry.value);
      final due = DateTime.tryParse(value['due']?.toString() ?? '');
      if (id == null || id <= 0 || due == null) continue;
      final at = _int(value['at']);
      if (at > (_reviews[id]?.updatedAt ?? -1)) {
        _reviews[id] = _ReviewState(
          _int(value['stage']).clamp(0, 6),
          due.toUtc(),
          at,
        );
      }
    }
    for (final entry in _map(data['best_scores']).entries) {
      final id = int.tryParse(entry.key);
      final score = entry.value;
      if (id == null || id <= 0 || score is! num || !score.isFinite) continue;
      _bestScores[id] = max(
        _bestScores[id] ?? 0,
        score.toDouble().clamp(0, 100),
      );
    }
    for (final day in _map(data['activity']).entries) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day.key)) continue;
      final devices = _counters.putIfAbsent(day.key, () => {});
      for (final device in _map(day.value).entries) {
        final raw = _map(device.value);
        final old = devices[device.key];
        devices[device.key] = _ActivityCounter(
          max(old?.count ?? 0, max(0, _int(raw['count']))),
          max(old?.xp ?? 0, max(0, _int(raw['xp']))),
        );
      }
    }
    final goalAt = _int(data['goal_updated_at']);
    if (goalAt >= _goalUpdatedAt) {
      _dailyGoal = _int(data['daily_goal'], fallback: 10).clamp(1, 100);
      _goalUpdatedAt = goalAt;
    }
    _updatedAt = max(_updatedAt, _int(data['updated_at']));
  }

  void _restore(String? source) {
    if (source == null) return;
    try {
      _merge(Map<String, dynamic>.from(jsonDecode(source) as Map));
    } on Object catch (error) {
      _persistenceError = '部分學習紀錄無法讀取。';
      debugPrint('Learning progress could not be restored: $error');
    }
  }

  /// Accounts have isolated local snapshots. Guest work is migrated only when
  /// explicitly requested and then removed from the guest snapshot.
  Future<void> useAccount(String? userId, {bool migrateGuest = false}) async {
    if (_accountId == userId) return;
    await flush();
    final guest = _accountId == null && userId != null && migrateGuest
        ? exportProgress()
        : null;
    _accountId = userId;
    await _loadCounterSource();
    _saved.clear();
    _learned.clear();
    _reviews.clear();
    _bestScores.clear();
    _counters.clear();
    _dailyGoal = 10;
    _goalUpdatedAt = 0;
    _updatedAt = 0;
    _restore(_preferences.getString(_storageKey));
    if (guest != null) {
      _merge(guest);
      await _preferences.remove('$_prefix.guest');
      await _preferences.remove('$_prefix.guest.counter_source');
    }
    _changed();
    await flush();
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static int _int(Object? value, {int fallback = 0}) =>
      value is num && value.isFinite ? value.toInt() : fallback;
}

class _SavedState {
  const _SavedState(this.saved, this.updatedAt);
  final bool saved;
  final int updatedAt;
  Map<String, dynamic> toJson() => {'saved': saved, 'at': updatedAt};
}

class _ReviewState {
  const _ReviewState(this.stage, this.dueAt, this.updatedAt);
  final int stage;
  final DateTime dueAt;
  final int updatedAt;
  Map<String, dynamic> toJson() => {
    'stage': stage,
    'due': dueAt.toUtc().toIso8601String(),
    'at': updatedAt,
  };
}

class _ActivityCounter {
  _ActivityCounter(this.count, this.xp);
  int count;
  int xp;
}
