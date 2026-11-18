import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/services/hive_service.dart';
import '../core/services/master_cache_service.dart';
import '../core/services/sync_service.dart';
import '../models/milk_reception_model.dart';

/// Controlador MVC que coordina el estado de red, caché maestro y cola de sincronización Hive.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.hiveService,
    SyncService? syncService,
    MasterCacheService? masterCacheService,
    this.connectivity,
  })  : _syncService = syncService ?? SyncService(hiveService: hiveService),
        _masterCacheService =
            masterCacheService ?? MasterCacheService(hiveService: hiveService);

  final HiveService hiveService;
  final SyncService _syncService;
  final MasterCacheService _masterCacheService;
  final Connectivity? connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingCount = 0;
  int _lastSyncCount = 0;
  DateTime? _lastSyncAt;
  String? _errorMessage;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  int get lastSyncCount => _lastSyncCount;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get errorMessage => _errorMessage;

  Future<void> initialize({bool startConnectivityWatch = true}) async {
    await refreshPendingCount();
    if (!startConnectivityWatch) {
      return;
    }

    final Connectivity conn = connectivity ?? Connectivity();
    _connectivitySub?.cancel();
    conn.checkConnectivity().then(_handleConnectivityChanged).catchError((_) {});
    _connectivitySub = conn.onConnectivityChanged.listen(
      _handleConnectivityChanged,
      onError: (_) {},
    );
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final bool nextOnline =
        results.any((ConnectivityResult r) => r != ConnectivityResult.none);
    final bool reconnected = !_isOnline && nextOnline;
    _isOnline = nextOnline;
    notifyListeners();

    if (reconnected) {
      syncNow(refreshMasters: true);
    }
  }

  Future<void> refreshPendingCount() async {
    final int nextCount = (await hiveService.getPendingReceptions()).length;
    if (nextCount != _pendingCount) {
      _pendingCount = nextCount;
      notifyListeners();
    }
  }

  Future<MilkReceptionModel> registerReception(
    MilkReceptionModel reception,
  ) async {
    _errorMessage = null;
    final MilkReceptionModel saved =
        await _syncService.registerReceptionOfflineFirst(
      reception,
      tryImmediateSync: _isOnline,
    );
    await refreshPendingCount();
    return saved;
  }

  Future<SyncExecutionResult> syncNow({bool refreshMasters = false}) async {
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    if (refreshMasters) {
      await _masterCacheService.refreshAll();
    }

    final SyncExecutionResult result =
        await _syncService.syncPendingReceptions();
    _isSyncing = false;
    _pendingCount = result.remainingPendingCount;
    if (result.syncedCount > 0) {
      _lastSyncCount = result.syncedCount;
      _lastSyncAt = DateTime.now().toUtc();
    }
    _errorMessage = result.error;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
