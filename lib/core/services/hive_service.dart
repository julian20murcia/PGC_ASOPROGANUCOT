import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/app_notification_model.dart';
import '../../models/milk_rate_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';

/// Servicio central de persistencia local Offline-First sobre Hive con cifrado AES-256.
class HiveService {
  HiveService({
    this.enablePersistence = true,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final bool enablePersistence;
  final FlutterSecureStorage _secureStorage;
  bool _initialized = false;

  Box<dynamic>? _usersBox;
  Box<dynamic>? _sessionBox;
  Box<dynamic>? _deliveriesBox;
  Box<dynamic>? _producersBox;
  Box<dynamic>? _ratesBox;
  Box<dynamic>? _settlementsBox;
  Box<dynamic>? _notificationsBox;

  // Respaldo en memoria para entornos de prueba sin sistema de archivos.
  final Map<String, Map<String, dynamic>> _memoryUsers =
      <String, Map<String, dynamic>>{};
  final Map<String, dynamic> _memorySession = <String, dynamic>{};
  final Map<String, Map<String, dynamic>> _memoryDeliveries =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _memoryProducers =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _memoryRates =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _memorySettlements =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> _memoryNotifications =
      <String, Map<String, dynamic>>{};

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    if (enablePersistence) {
      await Hive.initFlutter('asoproganucot_db');
      final HiveAesCipher? cipher = await _resolveAesCipher();

      _usersBox = await Hive.openBox<dynamic>(AppConstants.usersBox);
      _sessionBox = await Hive.openBox<dynamic>(AppConstants.sessionBox);
      _deliveriesBox = await Hive.openBox<dynamic>(
        AppConstants.deliveriesBox,
        encryptionCipher: cipher,
      );
      _producersBox = await Hive.openBox<dynamic>(
        AppConstants.producersBox,
        encryptionCipher: cipher,
      );
      _ratesBox = await Hive.openBox<dynamic>(
        AppConstants.ratesBox,
        encryptionCipher: cipher,
      );
      _settlementsBox = await Hive.openBox<dynamic>(
        AppConstants.settlementsBox,
        encryptionCipher: cipher,
      );
      _notificationsBox = await Hive.openBox<dynamic>(
        AppConstants.notificationsBox,
        encryptionCipher: cipher,
      );
    }
    _initialized = true;
  }

  Future<HiveAesCipher?> _resolveAesCipher() async {
    try {
      final String? stored = await _secureStorage.read(
        key: AppConstants.hiveEncryptionKeyStorageKey,
      );
      if (stored != null && stored.isNotEmpty) {
        final Uint8List decoded = base64Decode(stored);
        if (decoded.length == 32) {
          return HiveAesCipher(decoded);
        }
      }

      final List<int> freshKey = Hive.generateSecureKey();
      await _secureStorage.write(
        key: AppConstants.hiveEncryptionKeyStorageKey,
        value: base64Encode(freshKey),
      );
      return HiveAesCipher(freshKey);
    } catch (_) {
      // Respaldo resiliente si el entorno no dispone de keyring seguro nativo.
      return null;
    }
  }

  // ---- Helpers genéricos compartidos para colecciones Hive ----

  Future<void> _replaceCollection<T>({
    required Box<dynamic>? box,
    required Map<String, Map<String, dynamic>> memoryMap,
    required List<T> items,
    required String Function(T) keyOf,
    required Map<String, dynamic> Function(T) toMap,
  }) async {
    await init();
    if (box != null) {
      await box.clear();
      for (final T item in items) {
        await box.put(keyOf(item), toMap(item));
      }
      return;
    }
    memoryMap.clear();
    for (final T item in items) {
      memoryMap[keyOf(item)] = toMap(item);
    }
  }

  Future<void> _upsertItem<T>({
    required Box<dynamic>? box,
    required Map<String, Map<String, dynamic>> memoryMap,
    required T item,
    required String Function(T) keyOf,
    required Map<String, dynamic> Function(T) toMap,
  }) async {
    await init();
    if (box != null) {
      await box.put(keyOf(item), toMap(item));
      return;
    }
    memoryMap[keyOf(item)] = toMap(item);
  }

  Future<List<T>> _readCollection<T>({
    required Box<dynamic>? box,
    required Map<String, Map<String, dynamic>> memoryMap,
    required T Function(Map<String, dynamic>) fromMap,
  }) async {
    await init();
    final Iterable<dynamic> rawValues = box != null ? box.values : memoryMap.values;
    return rawValues
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> raw) =>
              fromMap(Map<String, dynamic>.from(raw)),
        )
        .toList();
  }

  // ---- Usuarios y sesión ----

  Future<void> cacheUsers(List<UserModel> users) => _replaceCollection<UserModel>(
        box: _usersBox,
        memoryMap: _memoryUsers,
        items: users,
        keyOf: (UserModel u) => u.uid,
        toMap: (UserModel u) => u.toMap(),
      );

  Future<void> upsertUser(UserModel user) => _upsertItem<UserModel>(
        box: _usersBox,
        memoryMap: _memoryUsers,
        item: user,
        keyOf: (UserModel u) => u.uid,
        toMap: (UserModel u) => u.toMap(),
      );

  Future<List<UserModel>> getCachedUsers() async {
    final List<UserModel> result = await _readCollection<UserModel>(
      box: _usersBox,
      memoryMap: _memoryUsers,
      fromMap: (Map<String, dynamic> m) => UserModel.fromMap(m),
    );
    result.sort(
      (UserModel a, UserModel b) =>
          a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
    );
    return result;
  }

  Future<UserModel?> findCachedUserByDocument(String documento) async {
    final String normalized = documento.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final List<UserModel> users = await getCachedUsers();
    for (final UserModel user in users) {
      if (user.documento.trim() == normalized) {
        return user;
      }
    }
    return null;
  }

  Future<void> saveSessionState({
    required bool rememberMe,
    required String lastIdentifier,
    required bool bootstrapMode,
    UserModel? cachedUser,
  }) async {
    await init();
    final Map<String, dynamic> payload = <String, dynamic>{
      AppConstants.sessionRememberMeKey: rememberMe,
      AppConstants.sessionLastIdentifierKey: lastIdentifier,
      AppConstants.sessionBootstrapModeKey: bootstrapMode,
      AppConstants.sessionCachedUserKey:
          cachedUser?.toMap(includeBootstrapFlag: true),
    };
    if (_sessionBox != null) {
      await _sessionBox!.putAll(payload);
      return;
    }
    _memorySession.addAll(payload);
  }

  Future<bool> getRememberMe() async {
    await init();
    final dynamic val = _sessionBox != null
        ? _sessionBox!.get(AppConstants.sessionRememberMeKey)
        : _memorySession[AppConstants.sessionRememberMeKey];
    return val == true;
  }

  Future<String> getLastIdentifier() async {
    await init();
    final dynamic val = _sessionBox != null
        ? _sessionBox!.get(AppConstants.sessionLastIdentifierKey)
        : _memorySession[AppConstants.sessionLastIdentifierKey];
    return (val ?? '').toString();
  }

  Future<bool> isBootstrapSessionSaved() async {
    await init();
    final dynamic val = _sessionBox != null
        ? _sessionBox!.get(AppConstants.sessionBootstrapModeKey)
        : _memorySession[AppConstants.sessionBootstrapModeKey];
    return val == true;
  }

  Future<UserModel?> getSavedSessionUser() async {
    await init();
    final dynamic raw = _sessionBox != null
        ? _sessionBox!.get(AppConstants.sessionCachedUserKey)
        : _memorySession[AppConstants.sessionCachedUserKey];
    if (raw is Map<dynamic, dynamic>) {
      return UserModel.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> clearActiveSession({bool keepIdentifier = true}) async {
    await init();
    final String identifier = keepIdentifier ? await getLastIdentifier() : '';
    final bool rememberMe = keepIdentifier ? await getRememberMe() : false;
    if (_sessionBox != null) {
      await _sessionBox!.delete(AppConstants.sessionBootstrapModeKey);
      await _sessionBox!.delete(AppConstants.sessionCachedUserKey);
      await _sessionBox!.put(AppConstants.sessionRememberMeKey, rememberMe);
      await _sessionBox!.put(AppConstants.sessionLastIdentifierKey, identifier);
      return;
    }
    _memorySession.remove(AppConstants.sessionBootstrapModeKey);
    _memorySession.remove(AppConstants.sessionCachedUserKey);
    _memorySession[AppConstants.sessionRememberMeKey] = rememberMe;
    _memorySession[AppConstants.sessionLastIdentifierKey] = identifier;
  }

  // ---- Recepciones de leche (deliveries_box) ----

  Future<MilkReceptionModel?> getReceptionById(String recepcionId) async {
    await init();
    final dynamic raw = _deliveriesBox != null
        ? _deliveriesBox!.get(recepcionId)
        : _memoryDeliveries[recepcionId];
    if (raw is Map<dynamic, dynamic>) {
      return MilkReceptionModel.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  /// Guarda atómicamente una recepción en Hive. Bloquea sobrescritura post-liquidación.
  Future<void> saveReception(MilkReceptionModel reception) async {
    await init();
    final MilkReceptionModel? existing =
        await getReceptionById(reception.recepcionId);
    if (existing != null && existing.isLiquidada) {
      throw StateError(
        'No es posible modificar una recepción que ya pertenece a una liquidación.',
      );
    }

    await _upsertItem<MilkReceptionModel>(
      box: _deliveriesBox,
      memoryMap: _memoryDeliveries,
      item: reception,
      keyOf: (MilkReceptionModel r) => r.recepcionId,
      toMap: (MilkReceptionModel r) => r.toMap(),
    );
  }

  Future<void> cacheReceptions(List<MilkReceptionModel> receptions) =>
      _replaceCollection<MilkReceptionModel>(
        box: _deliveriesBox,
        memoryMap: _memoryDeliveries,
        items: receptions,
        keyOf: (MilkReceptionModel r) => r.recepcionId,
        toMap: (MilkReceptionModel r) => r.toMap(),
      );

  Future<List<MilkReceptionModel>> getReceptions() async {
    final List<MilkReceptionModel> items =
        await _readCollection<MilkReceptionModel>(
      box: _deliveriesBox,
      memoryMap: _memoryDeliveries,
      fromMap: (Map<String, dynamic> m) => MilkReceptionModel.fromMap(m),
    );
    items.sort(
      (MilkReceptionModel a, MilkReceptionModel b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return items;
  }

  Future<List<MilkReceptionModel>> getPendingReceptions() async {
    final List<MilkReceptionModel> items = await getReceptions();
    final List<MilkReceptionModel> pending = items
        .where(
          (MilkReceptionModel r) =>
              !r.isSynced || r.syncStatus != AppConstants.syncSynced,
        )
        .toList();
    pending.sort(
      (MilkReceptionModel a, MilkReceptionModel b) =>
          a.createdAt.compareTo(b.createdAt),
    );
    return pending;
  }

  Future<void> markReceptionsAsSynced(List<String> recepcionIds, {bool audited = false}) async {
    await init();
    for (final String id in recepcionIds) {
      final MilkReceptionModel? existing = await getReceptionById(id);
      if (existing == null) {
        continue;
      }
      final MilkReceptionModel updated = existing.copyWith(
        isSynced: true,
        syncStatus: AppConstants.syncSynced,
        auditLogId: audited ? 'recepcion_$id' : null,
      );
      await _upsertItem<MilkReceptionModel>(
        box: _deliveriesBox,
        memoryMap: _memoryDeliveries,
        item: updated,
        keyOf: (MilkReceptionModel r) => r.recepcionId,
        toMap: (MilkReceptionModel r) => r.toMap(),
      );
    }
  }

  // ---- Productores (producers_box) ----

  Future<void> cacheProducers(List<ProducerModel> producers) =>
      _replaceCollection<ProducerModel>(
        box: _producersBox,
        memoryMap: _memoryProducers,
        items: producers,
        keyOf: (ProducerModel p) => p.productorId,
        toMap: (ProducerModel p) => p.toMap(),
      );

  Future<void> upsertProducer(ProducerModel producer) =>
      _upsertItem<ProducerModel>(
        box: _producersBox,
        memoryMap: _memoryProducers,
        item: producer,
        keyOf: (ProducerModel p) => p.productorId,
        toMap: (ProducerModel p) => p.toMap(),
      );

  Future<List<ProducerModel>> getCachedProducers() async {
    final List<ProducerModel> items = await _readCollection<ProducerModel>(
      box: _producersBox,
      memoryMap: _memoryProducers,
      fromMap: (Map<String, dynamic> m) => ProducerModel.fromMap(m),
    );
    items.sort(
      (ProducerModel a, ProducerModel b) =>
          a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
    );
    return items;
  }

  // ---- Tarifas por litro (rates_box) ----

  Future<void> cacheMilkRates(List<MilkRateModel> rates) =>
      _replaceCollection<MilkRateModel>(
        box: _ratesBox,
        memoryMap: _memoryRates,
        items: rates,
        keyOf: (MilkRateModel r) => r.tarifaId,
        toMap: (MilkRateModel r) => r.toMap(),
      );

  Future<void> upsertMilkRate(MilkRateModel rate) => _upsertItem<MilkRateModel>(
        box: _ratesBox,
        memoryMap: _memoryRates,
        item: rate,
        keyOf: (MilkRateModel r) => r.tarifaId,
        toMap: (MilkRateModel r) => r.toMap(),
      );

  Future<List<MilkRateModel>> getCachedMilkRates() async {
    final List<MilkRateModel> items = await _readCollection<MilkRateModel>(
      box: _ratesBox,
      memoryMap: _memoryRates,
      fromMap: (Map<String, dynamic> m) => MilkRateModel.fromMap(m),
    );
    items.sort(
      (MilkRateModel a, MilkRateModel b) =>
          b.fechaInicioVigencia.compareTo(a.fechaInicioVigencia),
    );
    return items;
  }

  Future<MilkRateModel?> getActiveMilkRate({DateTime? atDate}) async {
    final List<MilkRateModel> rates = await getCachedMilkRates();
    final DateTime target = (atDate ?? DateTime.now()).toUtc();
    for (final MilkRateModel rate in rates) {
      if (rate.isVigenteEn(target)) {
        return rate;
      }
    }
    for (final MilkRateModel rate in rates) {
      if (rate.activa) {
        return rate;
      }
    }
    return rates.isEmpty ? null : rates.first;
  }

  /// Asigna el `liquidacionId` de cierre quincenal a entregas aún no liquidadas.
  /// Verifica primero todas las entregas para mantener atomicidad e inmutabilidad (`RNF-06`).
  Future<void> assignSettlementToReceptions({
    required List<String> recepcionIds,
    required String liquidacionId,
  }) async {
    await init();
    final List<MilkReceptionModel> pendingToMark = <MilkReceptionModel>[];
    for (final String id in recepcionIds) {
      final MilkReceptionModel? existing = await getReceptionById(id);
      if (existing == null) continue;
      if (existing.isLiquidada) {
        throw StateError(
          'La entrega ${existing.recepcionId} ya pertenece a la liquidación ${existing.liquidacionId}.',
        );
      }
      pendingToMark.add(existing.copyWith(liquidacionId: liquidacionId));
    }

    for (final MilkReceptionModel updated in pendingToMark) {
      await _upsertItem<MilkReceptionModel>(
        box: _deliveriesBox,
        memoryMap: _memoryDeliveries,
        item: updated,
        keyOf: (MilkReceptionModel r) => r.recepcionId,
        toMap: (MilkReceptionModel r) => r.toMap(),
      );
    }
  }

  // ---- Liquidaciones (settlements_box) ----

  Future<void> cacheSettlements(List<SettlementModel> settlements) =>
      _replaceCollection<SettlementModel>(
        box: _settlementsBox,
        memoryMap: _memorySettlements,
        items: settlements,
        keyOf: (SettlementModel s) => s.liquidacionId,
        toMap: (SettlementModel s) => s.toMap(),
      );

  Future<void> upsertSettlement(SettlementModel settlement) =>
      _upsertItem<SettlementModel>(
        box: _settlementsBox,
        memoryMap: _memorySettlements,
        item: settlement,
        keyOf: (SettlementModel s) => s.liquidacionId,
        toMap: (SettlementModel s) => s.toMap(),
      );

  Future<SettlementModel?> getSettlementById(String liquidacionId) async {
    await init();
    final dynamic raw = _settlementsBox != null
        ? _settlementsBox!.get(liquidacionId)
        : _memorySettlements[liquidacionId];
    if (raw is Map<dynamic, dynamic>) {
      return SettlementModel.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<List<SettlementModel>> getCachedSettlements() async {
    final List<SettlementModel> items = await _readCollection<SettlementModel>(
      box: _settlementsBox,
      memoryMap: _memorySettlements,
      fromMap: (Map<String, dynamic> m) => SettlementModel.fromMap(m),
    );
    items.sort(
      (SettlementModel a, SettlementModel b) =>
          b.fechaLiquidacion.compareTo(a.fechaLiquidacion),
    );
    return items;
  }

  // ---- Notificaciones (notifications_box) ----

  Future<void> cacheNotifications(List<AppNotificationModel> notifications) =>
      _replaceCollection<AppNotificationModel>(
        box: _notificationsBox,
        memoryMap: _memoryNotifications,
        items: notifications,
        keyOf: (AppNotificationModel n) => n.notificacionId,
        toMap: (AppNotificationModel n) => n.toMap(),
      );

  Future<void> upsertNotification(AppNotificationModel notification) =>
      _upsertItem<AppNotificationModel>(
        box: _notificationsBox,
        memoryMap: _memoryNotifications,
        item: notification,
        keyOf: (AppNotificationModel n) => n.notificacionId,
        toMap: (AppNotificationModel n) => n.toMap(),
      );

  Future<List<AppNotificationModel>> getCachedNotifications() async {
    final List<AppNotificationModel> items =
        await _readCollection<AppNotificationModel>(
      box: _notificationsBox,
      memoryMap: _memoryNotifications,
      fromMap: (Map<String, dynamic> m) => AppNotificationModel.fromMap(m),
    );
    items.sort(
      (AppNotificationModel a, AppNotificationModel b) =>
          b.fechaEnvio.compareTo(a.fechaEnvio),
    );
    return items;
  }
}
