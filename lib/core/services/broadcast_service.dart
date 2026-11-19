import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_notification_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import '../security/permissions.dart';

class BroadcastException implements Exception {
  BroadcastException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reglas de contenido de un comunicado (compartidas con la UI y los tests).
class BroadcastRules {
  BroadcastRules._();

  static const int titleMax = 80;
  static const int titleMin = 3;
  static const int messageMax = 500;
  static const int messageMin = 5;

  static String? validateTitle(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return 'Escribe un título';
    if (s.length < titleMin) return 'Mínimo $titleMin caracteres';
    if (s.length > titleMax) return 'Máximo $titleMax caracteres';
    if (RegExp(r'(.)\1{4,}').hasMatch(s)) return 'Revisa caracteres repetidos';
    return null;
  }

  static String? validateMessage(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return 'Escribe el mensaje';
    if (s.length < messageMin) return 'Mínimo $messageMin caracteres';
    if (s.length > messageMax) return 'Máximo $messageMax caracteres';
    if (RegExp(r'(.)\1{5,}').hasMatch(s)) return 'Revisa caracteres repetidos';
    return null;
  }
}

/// Persistencia de comunicados. Separada para poder probar sin Firebase.
abstract class BroadcastBackend {
  Future<List<AppNotificationModel>> fetchBroadcasts();
  Future<void> commitSend(AppNotificationModel notification, AuditLogModel log);
  Future<void> commitDelete(AppNotificationModel notification, AuditLogModel log);
}

/// Escribe en `notificaciones` con el mismo formato que
/// `NotificationService.sendInstitutionalBroadcast` y su registro en
/// `auditoria_logs` en el mismo lote (todo o nada).
class FirestoreBroadcastBackend implements BroadcastBackend {
  FirestoreBroadcastBackend({this.firestore});

  final FirebaseFirestore? firestore;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<AppNotificationModel>> fetchBroadcasts() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.notificationsCollection)
        .where('tipo', isEqualTo: 'COMUNICADO')
        .get();
    return snap.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            AppNotificationModel.fromMap(d.data(), documentId: d.id))
        .toList();
  }

  @override
  Future<void> commitSend(AppNotificationModel notification, AuditLogModel log) async {
    final WriteBatch batch = _db.batch();
    batch.set(
      _db.collection(AppConstants.notificationsCollection).doc(notification.notificacionId),
      notification.toMap(),
      SetOptions(merge: true),
    );
    batch.set(
      _db.collection(AppConstants.auditLogsCollection).doc(log.logId),
      <String, dynamic>{...log.toMap(), 'timestamp': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  @override
  Future<void> commitDelete(AppNotificationModel notification, AuditLogModel log) async {
    final WriteBatch batch = _db.batch();
    batch.delete(_db.collection(AppConstants.notificationsCollection).doc(notification.notificacionId));
    batch.set(
      _db.collection(AppConstants.auditLogsCollection).doc(log.logId),
      <String, dynamic>{...log.toMap(), 'timestamp': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }
}

/// Servicio del módulo de Comunicados.
class BroadcastService {
  BroadcastService({BroadcastBackend? backend}) : _backendOverride = backend;

  static const Uuid _uuid = Uuid();
  final BroadcastBackend? _backendOverride;
  BroadcastBackend? _lazyBackend;

  BroadcastBackend get _backend => _backendOverride ?? (_lazyBackend ??= FirestoreBroadcastBackend());

  /// Comunicados enviados, del más reciente al más antiguo.
  Future<List<AppNotificationModel>> listSent() async {
    try {
      final List<AppNotificationModel> list = await _backend.fetchBroadcasts();
      list.sort((AppNotificationModel a, AppNotificationModel b) => b.fechaEnvio.compareTo(a.fechaEnvio));
      return list;
    } catch (_) {
      throw BroadcastException('No fue posible cargar el historial de comunicados. Verifica tu conexión.');
    }
  }

  Future<AppNotificationModel> send({
    required UserModel actor,
    required String titulo,
    required String mensaje,
    String? destinoProductorId,
    String? destinoNombre,
  }) async {
    if (!actor.can(Permissions.comunicados, PermAction.crear)) {
      throw BroadcastException('No tienes permiso para enviar comunicados.');
    }
    final String cleanTitle = titulo.trim().replaceAll(RegExp(r'\s+'), ' ');
    final String cleanBody = mensaje.trim();
    final String? titleError = BroadcastRules.validateTitle(cleanTitle);
    if (titleError != null) throw BroadcastException('Título: $titleError.');
    final String? bodyError = BroadcastRules.validateMessage(cleanBody);
    if (bodyError != null) throw BroadcastException('Mensaje: $bodyError.');
    final String? target =
        (destinoProductorId == null || destinoProductorId.trim().isEmpty) ? null : destinoProductorId.trim();

    final DateTime nowUtc = DateTime.now().toUtc();
    final AppNotificationModel notification = AppNotificationModel(
      notificacionId: _uuid.v4(),
      titulo: cleanTitle,
      mensaje: cleanBody,
      tipo: 'COMUNICADO',
      destinoProductorId: target,
      fechaEnvio: nowUtc,
      leida: false,
    );
    final AuditLogModel log = AuditLogModel(
      logId: _uuid.v4(),
      entidadAfectada: AppConstants.notificationsCollection,
      registroId: notification.notificacionId,
      accion: 'CREAR',
      valorNuevo: <String, dynamic>{
        'titulo': cleanTitle,
        'tipo': 'COMUNICADO',
        'destinoProductorId': target ?? 'GENERAL',
        if (destinoNombre != null && destinoNombre.isNotEmpty) 'destinoNombre': destinoNombre,
        'actorNombre': actor.nombreCompleto,
      },
      motivo: target == null ? 'Comunicado institucional general' : 'Aviso institucional dirigido',
      usuarioUid: actor.uid,
      timestamp: nowUtc,
    );
    try {
      await _backend.commitSend(notification, log);
    } catch (_) {
      throw BroadcastException(
        'No fue posible enviar el comunicado. Verifica tu conexión e intenta de nuevo.',
      );
    }
    return notification;
  }

  Future<void> delete({required UserModel actor, required AppNotificationModel notification}) async {
    if (!actor.can(Permissions.comunicados, PermAction.eliminar)) {
      throw BroadcastException('No tienes permiso para eliminar comunicados.');
    }
    final AuditLogModel log = AuditLogModel(
      logId: _uuid.v4(),
      entidadAfectada: AppConstants.notificationsCollection,
      registroId: notification.notificacionId,
      accion: 'ELIMINAR',
      valorAnterior: <String, dynamic>{
        'titulo': notification.titulo,
        'mensaje': notification.mensaje.length > 200
            ? '${notification.mensaje.substring(0, 200)}…'
            : notification.mensaje,
        'tipo': notification.tipo,
        'destinoProductorId': notification.destinoProductorId ?? 'GENERAL',
        'fechaEnvio': notification.fechaEnvio.toUtc().toIso8601String(),
      },
      motivo: 'Comunicado eliminado del historial',
      usuarioUid: actor.uid,
      timestamp: DateTime.now().toUtc(),
    );
    try {
      await _backend.commitDelete(notification, log);
    } catch (_) {
      throw BroadcastException('No fue posible eliminar el comunicado. Verifica tu conexión.');
    }
  }
}
