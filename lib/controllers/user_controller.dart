import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/services/firebase_user_service.dart';
import '../models/user_model.dart';

enum UserSortColumn {
  nombreCompleto,
  documento,
  rol,
  activo,
  correo,
  fechaCreacion,
}

/// Controlador MVC para la gestión administrativa de usuarios (RF-01, RF-02, RF-03).
class UserController extends ChangeNotifier {
  UserController({
    FirebaseUserService? userService,
    Connectivity? connectivity,
  })  : _userService = userService ?? FirebaseUserService(),
        _connectivity = connectivity ?? Connectivity();

  final FirebaseUserService _userService;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  List<UserModel> _users = <UserModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isFromOfflineCache = false;
  bool _isOnline = true;
  String? _errorMessage;
  String? _feedbackMessage;

  String _searchQuery = '';
  String _roleFilter = 'ALL';
  String _statusFilter = 'ALL';
  UserSortColumn _sortColumn = UserSortColumn.nombreCompleto;
  bool _sortAscending = true;
  int _currentPage = 1;
  int _itemsPerPage = 7;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isFromOfflineCache => _isFromOfflineCache;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;

  String get searchQuery => _searchQuery;
  String get roleFilter => _roleFilter;
  String get statusFilter => _statusFilter;
  UserSortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;

  List<UserModel> get allUsers => List<UserModel>.unmodifiable(_users);

  int get totalCount => _users.length;
  int get activeCount => _users.where((UserModel u) => u.activo).length;
  int get adminCount => _users.where((UserModel u) => u.isAdmin).length;
  int get operarioCount => _users.where((UserModel u) => u.isOperario).length;
  int get productorCount => _users.where((UserModel u) => u.isProductor).length;

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _roleFilter != 'ALL' ||
      _statusFilter != 'ALL';

  List<UserModel> get filteredUsers {
    final String query = _searchQuery.trim().toLowerCase();
    final List<UserModel> filtered = _users.where((UserModel user) {
      final bool matchesQuery = query.isEmpty ||
          user.nombreCompleto.toLowerCase().contains(query) ||
          user.documento.toLowerCase().contains(query) ||
          user.correo.toLowerCase().contains(query) ||
          user.telefono.toLowerCase().contains(query);

      final bool matchesRole =
          _roleFilter == 'ALL' || user.rol == _roleFilter;

      final bool matchesStatus = _statusFilter == 'ALL' ||
          (_statusFilter == 'ACTIVE' && user.activo) ||
          (_statusFilter == 'INACTIVE' && !user.activo);

      return matchesQuery && matchesRole && matchesStatus;
    }).toList();

    filtered.sort((UserModel a, UserModel b) {
      int comparison = 0;
      switch (_sortColumn) {
        case UserSortColumn.nombreCompleto:
          comparison = a.nombreCompleto
              .toLowerCase()
              .compareTo(b.nombreCompleto.toLowerCase());
          break;
        case UserSortColumn.documento:
          comparison = a.documento.compareTo(b.documento);
          break;
        case UserSortColumn.rol:
          comparison = _roleRank(a.rol).compareTo(_roleRank(b.rol));
          break;
        case UserSortColumn.activo:
          comparison = (a.activo ? 0 : 1).compareTo(b.activo ? 0 : 1);
          break;
        case UserSortColumn.correo:
          comparison = a.correo.toLowerCase().compareTo(b.correo.toLowerCase());
          break;
        case UserSortColumn.fechaCreacion:
          comparison = a.fechaCreacion.compareTo(b.fechaCreacion);
          break;
      }
      if (comparison == 0) {
        comparison = a.nombreCompleto
            .toLowerCase()
            .compareTo(b.nombreCompleto.toLowerCase());
      }
      return _sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  int get totalPages {
    final int count = filteredUsers.length;
    if (count == 0) {
      return 1;
    }
    return (count / _itemsPerPage).ceil();
  }

  List<UserModel> get paginatedUsers {
    final List<UserModel> list = filteredUsers;
    final int safePage = _currentPage.clamp(1, totalPages);
    final int start = (safePage - 1) * _itemsPerPage;
    if (start >= list.length) {
      return const <UserModel>[];
    }
    final int end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  int _roleRank(String rol) {
    switch (rol) {
      case AppConstants.roleAdmin:
        return 1;
      case AppConstants.roleOperario:
        return 2;
      case AppConstants.roleProductor:
        return 3;
      default:
        return 9;
    }
  }

  void startConnectivityMonitor() {
    _connectivitySub?.cancel();
    _connectivity.checkConnectivity().then(_updateConnectivityState).catchError((_) {});
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _updateConnectivityState,
      onError: (_) {},
    );
  }

  void _updateConnectivityState(List<ConnectivityResult> results) {
    final bool nextOnline =
        results.any((ConnectivityResult r) => r != ConnectivityResult.none);
    if (nextOnline != _isOnline) {
      _isOnline = nextOnline;
      notifyListeners();
    }
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ({List<UserModel> users, bool fromCache}) result =
          await _userService.listUsers();
      _users = result.users;
      _isFromOfflineCache = result.fromCache;
      _currentPage = _currentPage.clamp(1, totalPages);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUser({
    required String nombreCompleto,
    required String documento,
    required String correo,
    required String telefono,
    required String rol,
    required String password,
    required bool activo,
    required String actorUid,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final UserModel created = await _userService.createUser(
        nombreCompleto: nombreCompleto,
        documento: documento,
        correo: correo,
        telefono: telefono,
        rol: rol,
        password: password,
        activo: activo,
        actorUid: actorUid,
      );
      _users = <UserModel>[created, ..._users];
      _feedbackMessage =
          'Usuario "${created.nombreCompleto}" creado correctamente.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on UserServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible crear el usuario: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateUser({
    required UserModel previousUser,
    required String nombreCompleto,
    required String documento,
    required String telefono,
    required String rol,
    required bool activo,
    required String actorUid,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final UserModel updated = await _userService.updateUser(
        previousUser: previousUser,
        nombreCompleto: nombreCompleto,
        documento: documento,
        telefono: telefono,
        rol: rol,
        activo: activo,
        actorUid: actorUid,
      );
      _users = _users
          .map((UserModel u) => u.uid == updated.uid ? updated : u)
          .toList();
      _feedbackMessage = 'Usuario "${updated.nombreCompleto}" actualizado.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on UserServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible actualizar el usuario: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleUserStatus({
    required UserModel user,
    required String actorUid,
  }) async {
    _errorMessage = null;
    _feedbackMessage = null;
    try {
      final UserModel updated = await _userService.toggleUserStatus(
        user: user,
        newStatus: !user.activo,
        actorUid: actorUid,
      );
      _users = _users
          .map((UserModel u) => u.uid == updated.uid ? updated : u)
          .toList();
      _feedbackMessage = updated.activo
          ? 'Usuario "${updated.nombreCompleto}" activado.'
          : 'Usuario "${updated.nombreCompleto}" suspendido.';
      notifyListeners();
      return true;
    } on UserServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible cambiar el estado: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    _errorMessage = null;
    _feedbackMessage = null;
    try {
      await _userService.sendPasswordReset(email);
      _feedbackMessage =
          'Se envió el enlace de restablecimiento de contraseña a $email.';
      notifyListeners();
      return true;
    } on UserServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible enviar el correo de recuperación: $e';
      notifyListeners();
      return false;
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    _currentPage = 1;
    notifyListeners();
  }

  void setRoleFilter(String value) {
    _roleFilter = value;
    _currentPage = 1;
    notifyListeners();
  }

  void setStatusFilter(String value) {
    _statusFilter = value;
    _currentPage = 1;
    notifyListeners();
  }

  void setItemsPerPage(int value) {
    _itemsPerPage = value;
    _currentPage = 1;
    notifyListeners();
  }

  void setPage(int page) {
    _currentPage = page.clamp(1, totalPages);
    notifyListeners();
  }

  void toggleSort(UserSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    _currentPage = 1;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _roleFilter = 'ALL';
    _statusFilter = 'ALL';
    _currentPage = 1;
    notifyListeners();
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
