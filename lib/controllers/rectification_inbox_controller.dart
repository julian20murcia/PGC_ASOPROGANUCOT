import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/security/permissions.dart';
import '../core/services/rectification_inbox_service.dart';
import '../models/user_model.dart';

/// Bandeja de escritorio con las solicitudes de rectificación de datos que
/// los productores envían desde la app móvil.
class RectificationInboxController extends ChangeNotifier {
  RectificationInboxController({RectificationInboxService? service}) : _serviceOverride = service;

  final RectificationInboxService? _serviceOverride;
  RectificationInboxService? _service;
  StreamSubscription<List<RectificationRequest>>? _sub;
  String? _boundUid;
  String? _staffUid;
  bool _firstSnapshot = true;
  final StreamController<RectificationRequest> _arrivals = StreamController<RectificationRequest>.broadcast();

  List<RectificationRequest> _items = const <RectificationRequest>[];
  String? errorMessage;

  List<RectificationRequest> get items => _items;
  List<RectificationRequest> get pending => _items.where((RectificationRequest r) => !r.atendida).toList();
  int get pendingCount => _items.where((RectificationRequest r) => !r.atendida).length;
  bool get isActive => _sub != null;

  /// Solicitudes nuevas que llegan mientras la sesión está abierta.
  Stream<RectificationRequest> get arrivals => _arrivals.stream;

  /// Quién ve la bandeja: administradores y personal que puede editar productores.
  static bool canAttend(UserModel user) =>
      user.isAdmin || (user.isOperario && user.can(Permissions.productores, PermAction.editar));

  /// Empieza a escuchar para [user]. Sin Firebase inicializado (pruebas) no hace nada.
  void bind(UserModel user) {
    if (!canAttend(user)) {
      unbind();
      return;
    }
    if (_boundUid == user.uid && _sub != null) return;
    if (_serviceOverride == null && Firebase.apps.isEmpty) return;
    unbind();
    _boundUid = user.uid;
    _staffUid = user.uid;
    _firstSnapshot = true;
    _service = _serviceOverride ?? RectificationInboxService();
    _sub = _service!.watch().listen(_onData, onError: (Object _) {
      errorMessage = 'No fue posible cargar las solicitudes de rectificación.';
      notifyListeners();
    });
  }

  void _onData(List<RectificationRequest> next) {
    if (!_firstSnapshot) {
      final Set<String> known = _items.map((RectificationRequest r) => r.id).toSet();
      for (final RectificationRequest r in next) {
        if (!known.contains(r.id) && !r.atendida) _arrivals.add(r);
      }
    }
    _firstSnapshot = false;
    _items = next;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> markAttended(RectificationRequest request) async {
    final RectificationInboxService? service = _service;
    final String? uid = _staffUid;
    if (service == null || uid == null) return false;
    try {
      await service.markAttended(request.id, staffUid: uid);
      return true;
    } catch (_) {
      errorMessage = 'No se pudo marcar la solicitud como atendida. Verifica tu conexión.';
      notifyListeners();
      return false;
    }
  }

  void unbind() {
    _sub?.cancel();
    _sub = null;
    _boundUid = null;
    _staffUid = null;
    _service = null;
    if (_items.isNotEmpty) {
      _items = const <RectificationRequest>[];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _arrivals.close();
    super.dispose();
  }
}
