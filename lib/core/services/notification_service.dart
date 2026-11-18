import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_notification_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import 'hive_service.dart';

class NotificationServiceException implements Exception {
  NotificationServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fuente remota abstracta para `notificaciones` y `auditoria_logs`.
abstract class RemoteNotificationDataSource {
  Future<List<AppNotificationModel>> fetchNotifications({
    String? productorId,
    String? userUid,
  });
  Future<void> upsertNotification(AppNotificationModel notification);
  Future<void> markNotificationRead(String notificacionId);
  Future<void> appendAuditLog(AuditLogModel log);
}

class FirestoreNotificationDataSource implements RemoteNotificationDataSource {
  FirestoreNotificationDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<AppNotificationModel>> fetchNotifications({
    String? productorId,
    String? userUid,
  }) async {
    final CollectionReference<Map<String, dynamic>> col =
        _db.collection(AppConstants.notificationsCollection);

    if (productorId == null && userUid == null) {
      final QuerySnapshot<Map<String, dynamic>> snap = await col.get();
      return snap.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                AppNotificationModel.fromMap(doc.data(), documentId: doc.id),
          )
          .toList();
    }

    // Consultar comunicados generales (`null`) y avisos dirigidos al productor/UID
    // respetando reglas estrictas de aislamiento en `firestore.rules`.
    final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries =
        <Future<QuerySnapshot<Map<String, dynamic>>>>[
      col.where('destinoProductorId', isNull: true).get(),
      if (productorId != null && productorId.trim().isNotEmpty)
        col.where('destinoProductorId', isEqualTo: productorId.trim()).get(),
      if (userUid != null &&
          userUid.trim().isNotEmpty &&
          userUid.trim() != productorId?.trim())
        col.where('destinoProductorId', isEqualTo: userUid.trim()).get(),
    ];

    final List<QuerySnapshot<Map<String, dynamic>>> snapshots =
        await Future.wait<QuerySnapshot<Map<String, dynamic>>>(queries);
    final Map<String, AppNotificationModel> byId =
        <String, AppNotificationModel>{};
    for (final QuerySnapshot<Map<String, dynamic>> snap in snapshots) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs) {
        final AppNotificationModel model =
            AppNotificationModel.fromMap(doc.data(), documentId: doc.id);
        byId[model.notificacionId] = model;
      }
    }
    return byId.values.toList();
  }

  @override
  Future<void> upsertNotification(AppNotificationModel notification) async {
    await _db
        .collection(AppConstants.notificationsCollection)
        .doc(notification.notificacionId)
        .set(notification.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> markNotificationRead(String notificacionId) async {
    await _db
        .collection(AppConstants.notificationsCollection)
        .doc(notificacionId)
        .update(<String, dynamic>{'leida': true});
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    try {
      await _db
          .collection(AppConstants.auditLogsCollection)
          .doc(log.logId)
          .set(log.toMap());
    } catch (_) {
      // No revertir una operación confirmada por fallo temporal en bitácora.
    }
  }
}

/// Servicio MVC para bandeja móvil, comunicados institucionales (`RF-23`, `RF-24`)
/// y solicitudes de rectificación Ley 1581 de 2012 (`RF-19`).
class NotificationService {
  NotificationService({
    HiveService? hiveService,
    RemoteNotificationDataSource? remoteDataSource,
  })  : _hiveService = hiveService ?? HiveService(),
        _remoteDataSource =
            remoteDataSource ?? FirestoreNotificationDataSource();

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteNotificationDataSource _remoteDataSource;

  /// Lista las notificaciones visibles para un productor específico (aislamiento estricto)
  /// junto con los comunicados institucionales generales (`destinoProductorId == null`).
  Future<({List<AppNotificationModel> notifications, bool fromCache})>
      listForProducer({
    required String productorId,
    String? userUid,
  }) async {
    final String cleanProdId = productorId.trim();
    final String? cleanUid =
        userUid?.trim().isEmpty == true ? null : userUid?.trim();

    try {
      final List<AppNotificationModel> remote =
          await _remoteDataSource.fetchNotifications(
        productorId: cleanProdId,
        userUid: cleanUid,
      );
      final List<AppNotificationModel> localCached =
          await _hiveService.getCachedNotifications();
      final Map<String, AppNotificationModel> localById =
          <String, AppNotificationModel>{
        for (final AppNotificationModel n in localCached) n.notificacionId: n,
      };

      final List<AppNotificationModel> scoped = remote
          .where(
            (AppNotificationModel n) => _belongsToProducerOrBroadcast(
              n,
              productorId: cleanProdId,
              userUid: cleanUid,
            ),
          )
          .map((AppNotificationModel n) {
            final AppNotificationModel? prev = localById[n.notificacionId];
            return prev != null && prev.leida && !n.leida
                ? n.copyWith(leida: true)
                : n;
          })
          .toList();

      // Preservar alertas locales recientes aún pendientes de reflejarse en consulta remota.
      final Set<String> seenIds =
          scoped.map((AppNotificationModel n) => n.notificacionId).toSet();
      for (final AppNotificationModel local in localCached) {
        if (!seenIds.contains(local.notificacionId) &&
            _belongsToProducerOrBroadcast(
              local,
              productorId: cleanProdId,
              userUid: cleanUid,
            )) {
          scoped.add(local);
        }
      }

      scoped.sort(
        (AppNotificationModel a, AppNotificationModel b) =>
            b.fechaEnvio.compareTo(a.fechaEnvio),
      );
      await _hiveService.cacheNotifications(scoped);
      return (notifications: scoped, fromCache: false);
    } catch (_) {
      final List<AppNotificationModel> cached =
          await _hiveService.getCachedNotifications();
      final List<AppNotificationModel> scoped = cached
          .where(
            (AppNotificationModel n) => _belongsToProducerOrBroadcast(
              n,
              productorId: cleanProdId,
              userUid: cleanUid,
            ),
          )
          .toList()
        ..sort(
          (AppNotificationModel a, AppNotificationModel b) =>
              b.fechaEnvio.compareTo(a.fechaEnvio),
        );
      return (notifications: scoped, fromCache: true);
    }
  }

  /// Lista todas las notificaciones y comunicados para consulta administrativa.
  Future<({List<AppNotificationModel> notifications, bool fromCache})>
      listAllNotifications() async {
    try {
      final List<AppNotificationModel> remote =
          await _remoteDataSource.fetchNotifications();
      remote.sort(
        (AppNotificationModel a, AppNotificationModel b) =>
            b.fechaEnvio.compareTo(a.fechaEnvio),
      );
      await _hiveService.cacheNotifications(remote);
      return (notifications: remote, fromCache: false);
    } catch (_) {
      final List<AppNotificationModel> cached =
          await _hiveService.getCachedNotifications();
      cached.sort(
        (AppNotificationModel a, AppNotificationModel b) =>
            b.fechaEnvio.compareTo(a.fechaEnvio),
      );
      return (notifications: cached, fromCache: true);
    }
  }

  /// Envía un comunicado general o aviso dirigido desde administración (`ADMIN`, `RF-24`).
  Future<AppNotificationModel> sendInstitutionalBroadcast({
    required UserModel actor,
    required String titulo,
    required String mensaje,
    String? destinoProductorId,
  }) async {
    if (!actor.isAdmin) {
      throw NotificationServiceException(
        'Solo el Administrador Central puede emitir comunicados institucionales.',
      );
    }

    final String cleanTitle = titulo.trim();
    final String cleanBody = mensaje.trim();
    if (cleanTitle.length < 3) {
      throw NotificationServiceException(
        'Ingresa un asunto o título de al menos 3 caracteres.',
      );
    }
    if (cleanBody.length < 5) {
      throw NotificationServiceException(
        'Ingresa el contenido del comunicado (mínimo 5 caracteres).',
      );
    }

    final String? cleanTarget =
        destinoProductorId?.trim().isEmpty == true
            ? null
            : destinoProductorId?.trim();

    final DateTime nowUtc = DateTime.now().toUtc();
    final AppNotificationModel notification = AppNotificationModel(
      notificacionId: _uuid.v4(),
      titulo: cleanTitle,
      mensaje: cleanBody,
      tipo: 'COMUNICADO',
      destinoProductorId: cleanTarget,
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
        'destinoProductorId': cleanTarget ?? 'GENERAL',
        'actorNombre': actor.nombreCompleto,
      },
      motivo: cleanTarget == null
          ? 'Comunicado institucional general'
          : 'Aviso institucional dirigido',
      usuarioUid: actor.uid,
      timestamp: nowUtc,
    );

    try {
      await _remoteDataSource.upsertNotification(notification);
      await _remoteDataSource.appendAuditLog(log);
    } catch (_) {
      throw NotificationServiceException(
        'No fue posible enviar el comunicado en la nube. Verifica tu conexión e intenta de nuevo.',
      );
    }

    await _hiveService.upsertNotification(notification);
    return notification;
  }

  /// Registra solicitud de rectificación de datos personales (Ley 1581 de 2012, `RF-19`).
  Future<AppNotificationModel> submitDataRectificationRequest({
    required ProducerModel producer,
    required UserModel actor,
    required String campo,
    required String detalle,
  }) async {
    if (actor.isProductor) {
      final bool ownsRecord = producer.uidUsuario == actor.uid ||
          producer.cedula.trim() == actor.documento.trim();
      if (!ownsRecord) {
        throw NotificationServiceException(
          'No estás autorizado para solicitar rectificación sobre otro productor.',
        );
      }
    }

    final String cleanField = campo.trim();
    final String cleanDetail = detalle.trim();
    if (cleanField.isEmpty) {
      throw NotificationServiceException(
        'Selecciona o especifica el dato que deseas rectificar.',
      );
    }
    if (cleanDetail.length < 5) {
      throw NotificationServiceException(
        'Describe el cambio solicitado con al menos 5 caracteres.',
      );
    }

    final DateTime nowUtc = DateTime.now().toUtc();
    final AppNotificationModel requestNotification = AppNotificationModel(
      notificacionId: _uuid.v4(),
      titulo: 'Solicitud Habeas Data · ${producer.codigoAsociado}',
      mensaje: 'Campo: $cleanField · Solicitud: $cleanDetail',
      tipo: 'RECTIFICACION',
      destinoProductorId: producer.productorId,
      fechaEnvio: nowUtc,
      leida: false,
    );

    final AuditLogModel log = AuditLogModel(
      logId: _uuid.v4(),
      entidadAfectada: AppConstants.producersCollection,
      registroId: producer.productorId,
      accion: 'SOLICITAR_RECTIFICACION',
      valorNuevo: <String, dynamic>{
        'codigoAsociado': producer.codigoAsociado,
        'campo': cleanField,
        'detalle': cleanDetail,
        'solicitanteUid': actor.uid,
      },
      motivo: 'Solicitud de rectificación Ley 1581 de 2012: $cleanField',
      usuarioUid: actor.uid,
      timestamp: nowUtc,
    );

    await _hiveService.upsertNotification(requestNotification);
    try {
      await _remoteDataSource.upsertNotification(requestNotification);
      await _remoteDataSource.appendAuditLog(log);
    } catch (_) {
      throw NotificationServiceException(
        'No se pudo enviar la solicitud al servidor. Verifica tu conexión e intenta de nuevo.',
      );
    }
    return requestNotification;
  }

  /// Marca una notificación como leída tanto en Hive como en Firestore.
  Future<void> markAsRead(String notificacionId) async {
    final List<AppNotificationModel> cached =
        await _hiveService.getCachedNotifications();
    for (final AppNotificationModel n in cached) {
      if (n.notificacionId == notificacionId && !n.leida) {
        await _hiveService.upsertNotification(n.copyWith(leida: true));
      }
    }
    try {
      await _remoteDataSource.markNotificationRead(notificacionId);
    } catch (_) {
      // Mantiene lectura local ante caída de red sin fallar en UI.
    }
  }

  Future<void> markAllAsRead(List<String> notificacionIds) async {
    for (final String id in notificacionIds) {
      await markAsRead(id);
    }
  }

  static bool _belongsToProducerOrBroadcast(
    AppNotificationModel notification, {
    required String productorId,
    String? userUid,
  }) {
    final String? dest = notification.destinoProductorId?.trim();
    if (dest == null || dest.isEmpty) {
      return true;
    }
    if (dest == productorId) {
      return true;
    }
    if (userUid != null && userUid.isNotEmpty && dest == userUid) {
      return true;
    }
    return false;
  }
}
