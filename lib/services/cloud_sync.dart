import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'learning_store.dart';

/// Optional email/password accounts and conflict-safe progress synchronization.
/// No connection is attempted unless both compile-time settings are supplied.
class CloudSync extends ChangeNotifier {
  CloudSync._(this._store, this._client);

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final LearningStore _store;
  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _syncTimer;
  Future<void> _accountReady = Future<void>.value();
  bool _isSyncing = false;
  bool _applyingRemote = false;
  bool _syncAgain = false;
  bool _migrateGuestOnSignIn = false;
  bool _disposed = false;
  String? _error;
  DateTime? _lastSyncedAt;

  bool get isConfigured => _client != null;
  bool get isSignedIn => _client?.auth.currentUser != null;
  String? get email => _client?.auth.currentUser?.email;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get error => _error;

  static Future<CloudSync> initialize(LearningStore store) async {
    SupabaseClient? client;
    String? startupError;
    if (_url.isNotEmpty && _anonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: _url, publishableKey: _anonKey);
        client = Supabase.instance.client;
      } on Object {
        startupError = '帳號服務暫時無法連線，學習紀錄會繼續儲存在此裝置。';
      }
    }
    final service = CloudSync._(store, client).._error = startupError;
    if (client != null) {
      store.addListener(service._onProgressChanged);
      service._authSubscription = client.auth.onAuthStateChange.listen(
        (state) {
          service._queueAccount(
            state.session?.user.id,
            migrateGuest: service._migrateGuestOnSignIn,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          service._error = '帳號連線中斷，請稍後重試同步。';
          service._notify();
        },
      );
      service._queueAccount(client.auth.currentUser?.id);
      await service._accountReady;
    }
    return service;
  }

  Future<void> signIn(String email, String password) async {
    final client = _requireClient();
    _error = null;
    _migrateGuestOnSignIn = true;
    try {
      final result = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _queueAccount(result.user?.id, migrateGuest: true);
      await _accountReady;
      await sync();
    } on AuthException catch (exception) {
      _error = exception.message;
      _notify();
      rethrow;
    } finally {
      _migrateGuestOnSignIn = false;
    }
  }

  /// Returns false when Supabase requires the user to confirm their email.
  Future<bool> signUp(String email, String password) async {
    final client = _requireClient();
    _error = null;
    _migrateGuestOnSignIn = true;
    try {
      final result = await client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (result.session == null) return false;
      _queueAccount(result.user?.id, migrateGuest: true);
      await _accountReady;
      await sync();
      return true;
    } on AuthException catch (exception) {
      _error = exception.message;
      _notify();
      rethrow;
    } finally {
      _migrateGuestOnSignIn = false;
    }
  }

  Future<void> signOut() async {
    final client = _requireClient();
    await _store.flush();
    // Each account keeps its own local snapshot even when the network is down.
    await client.auth.signOut(scope: SignOutScope.local);
    _queueAccount(null);
    await _accountReady;
  }

  void _queueAccount(String? userId, {bool migrateGuest = false}) {
    _accountReady = _accountReady
        .then((_) async {
          if (_disposed) return;
          if (_store.accountId == userId) return;
          _applyingRemote = true;
          try {
            await _store.useAccount(userId, migrateGuest: migrateGuest);
          } finally {
            _applyingRemote = false;
          }
          _lastSyncedAt = null;
          _notify();
          if (userId != null) _scheduleSync();
        })
        .catchError((Object error) {
          _error = '無法切換學習帳號，請重新登入。';
          _notify();
        });
  }

  void _onProgressChanged() {
    if (!_applyingRemote && isSignedIn) _scheduleSync();
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  /// Uses an atomic compare-and-set RPC so concurrent devices cannot overwrite
  /// one another. Local progress remains available when synchronization fails.
  Future<void> sync() async {
    if (_disposed || _client == null || !isSignedIn) return;
    await _accountReady;
    if (_isSyncing) {
      _syncAgain = true;
      return;
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null || _store.accountId != userId) return;
    _syncTimer?.cancel();
    _isSyncing = true;
    _error = null;
    _notify();
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await _client
            .from('learning_progress')
            .select('data, revision')
            .eq('user_id', userId)
            .maybeSingle();
        if (_disposed ||
            _store.accountId != userId ||
            _client.auth.currentUser?.id != userId) {
          return;
        }
        if (remote != null) {
          _applyingRemote = true;
          try {
            await _store.importProgress(
              Map<String, dynamic>.from(remote['data'] as Map),
            );
          } finally {
            _applyingRemote = false;
          }
        }
        if (_disposed ||
            _store.accountId != userId ||
            _client.auth.currentUser?.id != userId) {
          return;
        }
        final saved = await _client.rpc(
          'save_learning_progress',
          params: {
            'progress_data': _store.exportProgress(),
            'expected_revision': remote?['revision'] ?? 0,
          },
        );
        if (saved == true) {
          _lastSyncedAt = DateTime.now();
          return;
        }
      }
      _error = '其他裝置正在同步，請稍後再試。';
    } on Object {
      _error = '同步尚未完成。紀錄已保留在此裝置，連線恢復後可重試。';
    } finally {
      _isSyncing = false;
      _notify();
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        _scheduleSync();
      }
    }
  }

  SupabaseClient _requireClient() {
    if (_client == null) throw StateError('Supabase is not configured.');
    return _client;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    _store.removeListener(_onProgressChanged);
    super.dispose();
  }
}
