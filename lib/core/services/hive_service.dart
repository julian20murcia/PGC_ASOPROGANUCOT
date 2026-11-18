import 'package:hive_flutter/hive_flutter.dart';

import '../../models/user_model.dart';
import '../constants/app_constants.dart';

/// Servicio central de persistencia local Offline-First sobre Hive.
class HiveService {
  HiveService({this.enablePersistence = true});

  final bool enablePersistence;
  bool _initialized = false;

  Box<dynamic>? _usersBox;
  Box<dynamic>? _sessionBox;

  // Respaldo en memoria para entornos de prueba sin filesystem.
  final Map<String, Map<String, dynamic>> _memoryUsers =
      <String, Map<String, dynamic>>{};
  final Map<String, dynamic> _memorySession = <String, dynamic>{};

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    if (enablePersistence) {
      await Hive.initFlutter('asoproganucot_db');
      _usersBox = await Hive.openBox<dynamic>(AppConstants.usersBox);
      _sessionBox = await Hive.openBox<dynamic>(AppConstants.sessionBox);
    }
    _initialized = true;
  }

  Future<void> cacheUsers(List<UserModel> users) async {
    await init();
    if (_usersBox != null) {
      await _usersBox!.clear();
      for (final UserModel user in users) {
        await _usersBox!.put(user.uid, user.toMap());
      }
      return;
    }
    _memoryUsers.clear();
    for (final UserModel user in users) {
      _memoryUsers[user.uid] = user.toMap();
    }
  }

  Future<void> upsertUser(UserModel user) async {
    await init();
    if (_usersBox != null) {
      await _usersBox!.put(user.uid, user.toMap());
      return;
    }
    _memoryUsers[user.uid] = user.toMap();
  }

  Future<List<UserModel>> getCachedUsers() async {
    await init();
    final Iterable<dynamic> rawValues =
        _usersBox != null ? _usersBox!.values : _memoryUsers.values;
    final List<UserModel> result = rawValues
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> raw) => UserModel.fromMap(
            Map<String, dynamic>.from(raw),
          ),
        )
        .toList();
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
}
