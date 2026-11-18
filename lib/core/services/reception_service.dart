import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_notification_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import 'hive_service.dart';
import 'sync_service.dart';

class ReceptionServiceException implements Exception {
  ReceptionServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DuplicateReceptionException implements Exception {
  DuplicateReceptionException(this.existingReception);
  final MilkReceptionModel existingReception;
}

/// Fuente remota abstracta de recepciones y auditoría para soportar pruebas unitarias.
abstract class RemoteReceptionDataSource {
  Future<List<MilkReceptionModel>> fetchReceptions();
  Future<void> upsertReception(MilkReceptionModel reception);
  Future<void> appendAuditLog(AuditLogModel log);
}

class FirestoreReceptionDataSource implements RemoteReceptionDataSource {
  FirestoreReceptionDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.receptionsCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MilkReceptionModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  /// Consulta acotada por `productorId` acorde con el aislamiento de `firestore.rules`.
  Future<List<MilkReceptionModel>> fetchReceptionsForProducer(
    String productorId,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.receptionsCollection)
        .where('productorId', isEqualTo: productorId.trim())
        .get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MilkReceptionModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    await _db
        .collection(AppConstants.receptionsCollection)
        .doc(reception.recepcionId)
        .set(reception.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    try {
      await _db
          .collection(AppConstants.auditLogsCollection)
          .doc(log.logId)
          .set(log.toMap());
    } catch (_) {
      // No revertir el registro local ante falla temporal en bitácora.
    }
  }

  Future<void> upsertNotification(AppNotificationModel notification) async {
    try {
      await _db
          .collection(AppConstants.notificationsCollection)
          .doc(notification.notificacionId)
          .set(notification.toMap(), SetOptions(merge: true));
    } catch (_) {
      // No bloquear la recepción ante falla temporal en notificaciones push.
    }
  }
}

/// Servicio MVC Offline-First para registro, alerta de duplicados y corrección auditada de recepciones (`RF-08` a `RF-11`).
class ReceptionService {
  ReceptionService({
    HiveService? hiveService,
    RemoteReceptionDataSource? remoteDataSource,
    this.syncService,
  })  : _hiveService = hiveService ?? HiveService(),
        _remoteDataSource =
            remoteDataSource ?? FirestoreReceptionDataSource();

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteReceptionDataSource _remoteDataSource;
  final SyncService? syncService;

  SyncService get _effectiveSyncService =>
      syncService ??
      SyncService(
        hiveService: _hiveService,
        remoteGateway: _DelegatingReceptionGateway(_remoteDataSource),
      );

  static String defaultShiftForTime(DateTime now) =>
      now.hour < 12 ? AppConstants.shiftMorning : AppConstants.shiftAfternoon;

  static String _pad2(int value) => value < 10 ? '0$value' : '$value';

  static String formatDate(DateTime dt) =>
      '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)}';

  static String formatTime(DateTime dt) =>
      '${_pad2(dt.hour)}:${_pad2(dt.minute)}:${_pad2(dt.second)}';

  /// Rango de corte quincenal estándar: días 1–15 y días 16–fin de mes.
  static ({String start, String end, String label}) currentQuincenaRange(
    DateTime ref,
  ) {
    final DateTime local = ref.toLocal();
    final int lastDayOfMonth = DateTime(local.year, local.month + 1, 0).day;
    final bool isFirstHalf = local.day <= 15;
    final DateTime start =
        DateTime(local.year, local.month, isFirstHalf ? 1 : 16);
    final DateTime end =
        DateTime(local.year, local.month, isFirstHalf ? 15 : lastDayOfMonth);
    final String label = isFirstHalf
        ? '1ª quincena · ${_pad2(local.month)}/${local.year}'
        : '2ª quincena · ${_pad2(local.month)}/${local.year}';
    return (start: formatDate(start), end: formatDate(end), label: label);
  }

  Future<({List<MilkReceptionModel> receptions, bool fromCache})>
      listReceptions() async {
    final List<MilkReceptionModel> local = await _hiveService.getReceptions();
    final Map<String, MilkReceptionModel> pendingLocal =
        <String, MilkReceptionModel>{};
    for (final MilkReceptionModel item in local) {
      if (!item.isSynced || item.syncStatus != AppConstants.syncSynced) {
        pendingLocal[item.recepcionId] = item;
      }
    }

    try {
      final List<MilkReceptionModel> remote =
          await _remoteDataSource.fetchReceptions();
      final Map<String, MilkReceptionModel> merged =
          <String, MilkReceptionModel>{};
      for (final MilkReceptionModel item in remote) {
        merged[item.recepcionId] = item.copyWith(
          isSynced: true,
          syncStatus: AppConstants.syncSynced,
        );
      }
      // Preservar registros locales aún pendientes por subir.
      merged.addAll(pendingLocal);

      final List<MilkReceptionModel> combined = merged.values.toList()
        ..sort(
          (MilkReceptionModel a, MilkReceptionModel b) =>
              b.createdAt.compareTo(a.createdAt),
        );
      await _hiveService.cacheReceptions(combined);
      return (receptions: combined, fromCache: false);
    } catch (_) {
      return (receptions: local, fromCache: true);
    }
  }

  /// Lista exclusivamente las entregas de un productor (`RF-20`, `RF-21`, `RNF-05`).
  Future<({List<MilkReceptionModel> receptions, bool fromCache})>
      listForProducer(String productorId) async {
    final String cleanId = productorId.trim();
    if (_remoteDataSource is FirestoreReceptionDataSource) {
      final List<MilkReceptionModel> localScoped = (await _hiveService
              .getReceptions())
          .where((MilkReceptionModel r) => r.productorId == cleanId)
          .toList();
      try {
        final List<MilkReceptionModel> remote =
            await _remoteDataSource.fetchReceptionsForProducer(cleanId);
        final Map<String, MilkReceptionModel> merged =
            <String, MilkReceptionModel>{};
        for (final MilkReceptionModel item in remote) {
          if (item.productorId == cleanId) {
            merged[item.recepcionId] = item.copyWith(
              isSynced: true,
              syncStatus: AppConstants.syncSynced,
            );
          }
        }
        for (final MilkReceptionModel pending in localScoped) {
          if (!pending.isSynced ||
              pending.syncStatus != AppConstants.syncSynced) {
            merged[pending.recepcionId] = pending;
          }
        }
        final List<MilkReceptionModel> combined = merged.values.toList()
          ..sort(
            (MilkReceptionModel a, MilkReceptionModel b) =>
                b.createdAt.compareTo(a.createdAt),
          );
        await _hiveService.cacheReceptions(combined);
        return (receptions: combined, fromCache: false);
      } catch (_) {
        return (receptions: localScoped, fromCache: true);
      }
    }

    final result = await listReceptions();
    final List<MilkReceptionModel> scoped = result.receptions
        .where((MilkReceptionModel r) => r.productorId == cleanId)
        .toList();
    return (receptions: scoped, fromCache: result.fromCache);
  }

  /// Verifica si ya existe entrega activa para el mismo productor, fecha y jornada (`RF-09`).
  Future<MilkReceptionModel?> findDuplicate({
    required String productorId,
    required String fechaEntrega,
    required String jornada,
    String? excludeRecepcionId,
  }) async {
    final List<MilkReceptionModel> existing =
        await _hiveService.getReceptions();
    final String targetKey =
        '${productorId.trim()}_${fechaEntrega.trim()}_${jornada.trim().toUpperCase()}';

    for (final MilkReceptionModel item in existing) {
      if (item.anulado) continue;
      if (excludeRecepcionId != null &&
          item.recepcionId == excludeRecepcionId) {
        continue;
      }
      if (item.duplicateKey == targetKey) {
        return item;
      }
    }
    return null;
  }

  /// Registra primero localmente en Hive y sincroniza en segundo plano si hay red.
  Future<MilkReceptionModel> registerReception({
    required ProducerModel producer,
    required double litros,
    required String jornada,
    required String operarioUid,
    DateTime? timestamp,
    bool allowDuplicate = false,
    bool isOnline = true,
  }) async {
    if (!producer.isActivo) {
      throw ReceptionServiceException(
        'El productor "${producer.nombreCompleto}" está inactivo y no puede registrar entregas.',
      );
    }
    if (litros.isNaN || litros.isInfinite || litros <= 0) {
      throw ReceptionServiceException(
        'La cantidad de litros debe ser mayor a cero.',
      );
    }
    if (litros > 5000) {
      throw ReceptionServiceException(
        'La cantidad ingresada (${litros.toStringAsFixed(1)} L) supera el límite operativo por entrega.',
      );
    }

    final DateTime nowLocal = (timestamp ?? DateTime.now()).toLocal();
    final String fechaEntrega = formatDate(nowLocal);
    final String horaEntrega = formatTime(nowLocal);
    final String cleanShift = jornada.trim().toUpperCase() ==
            AppConstants.shiftAfternoon
        ? AppConstants.shiftAfternoon
        : AppConstants.shiftMorning;

    if (!allowDuplicate) {
      final MilkReceptionModel? existing = await findDuplicate(
        productorId: producer.productorId,
        fechaEntrega: fechaEntrega,
        jornada: cleanShift,
      );
      if (existing != null) {
        throw DuplicateReceptionException(existing);
      }
    }

    final MilkReceptionModel draft = MilkReceptionModel(
      recepcionId: _uuid.v4(),
      productorId: producer.productorId,
      codigoAsociadoSnap: producer.codigoAsociado,
      nombreProductorSnap: producer.nombreCompleto,
      litros: double.parse(litros.toStringAsFixed(2)),
      fechaEntrega: fechaEntrega,
      horaEntrega: horaEntrega,
      jornada: cleanShift,
      operarioUid: operarioUid,
      syncStatus: AppConstants.syncPending,
      isSynced: false,
      createdAt: nowLocal.toUtc(),
    );

    final MilkReceptionModel saved =
        await _effectiveSyncService.registerReceptionOfflineFirst(
      draft,
      tryImmediateSync: isOnline,
    );

    final String shiftLabel =
        cleanShift == AppConstants.shiftAfternoon ? 'Tarde' : 'Mañana';
    final AppNotificationModel deliveryNotification = AppNotificationModel(
      notificacionId: 'notif_entrega_${saved.recepcionId}',
      titulo: 'Entrega registrada ($shiftLabel)',
      mensaje:
          'Se registraron ${saved.litros.toStringAsFixed(1)} L de leche cruda el $fechaEntrega a las $horaEntrega.',
      tipo: 'ENTREGA',
      destinoProductorId: producer.productorId,
      fechaEnvio: nowLocal.toUtc(),
      leida: false,
    );
    await _hiveService.upsertNotification(deliveryNotification);

    if (saved.isSynced) {
      await _remoteDataSource.appendAuditLog(
        AuditLogModel(
          logId: _uuid.v4(),
          entidadAfectada: AppConstants.receptionsCollection,
          registroId: saved.recepcionId,
          accion: 'CREAR',
          valorNuevo: saved.toMap(),
          usuarioUid: operarioUid,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      if (_remoteDataSource is FirestoreReceptionDataSource) {
        await _remoteDataSource.upsertNotification(deliveryNotification);
      }
    }

    return saved;
  }

  /// Corrige litros (solo ADMIN y previo a liquidación) con bitácora obligatoria.
  Future<MilkReceptionModel> editReceptionLitros({
    required MilkReceptionModel existing,
    required double nuevosLitros,
    required String motivo,
    required UserModel actor,
  }) async {
    if (nuevosLitros.isNaN || nuevosLitros.isInfinite || nuevosLitros <= 0) {
      throw ReceptionServiceException(
        'Los litros corregidos deben ser mayores a cero.',
      );
    }
    return _applyAdminCorrection(
      existing: existing,
      actor: actor,
      motivo: motivo,
      accion: 'EDITAR',
      updated: existing.copyWith(
        litros: double.parse(nuevosLitros.toStringAsFixed(2)),
      ),
      valorAnterior: <String, dynamic>{'litros': existing.litros},
      valorNuevo: <String, dynamic>{
        'litros': double.parse(nuevosLitros.toStringAsFixed(2)),
      },
    );
  }

  /// Anula lógicamente una recepción sin borrar historial (solo ADMIN, pre-liquidación).
  Future<MilkReceptionModel> annulReception({
    required MilkReceptionModel existing,
    required String motivo,
    required UserModel actor,
  }) async {
    final String cleanReason = motivo.trim();
    return _applyAdminCorrection(
      existing: existing,
      actor: actor,
      motivo: cleanReason,
      accion: 'ANULAR',
      updated: existing.copyWith(
        anulado: true,
        motivoAnulacion: cleanReason,
      ),
      valorAnterior: <String, dynamic>{
        'anulado': existing.anulado,
        'litros': existing.litros,
      },
      valorNuevo: <String, dynamic>{
        'anulado': true,
        'motivoAnulacion': cleanReason,
      },
    );
  }

  Future<MilkReceptionModel> _applyAdminCorrection({
    required MilkReceptionModel existing,
    required UserModel actor,
    required String motivo,
    required String accion,
    required MilkReceptionModel updated,
    required Map<String, dynamic> valorAnterior,
    required Map<String, dynamic> valorNuevo,
  }) async {
    if (!actor.isAdmin) {
      throw ReceptionServiceException(
        'Solo el Administrador puede corregir o anular entregas registradas.',
      );
    }
    if (existing.isLiquidada) {
      throw ReceptionServiceException(
        'Esta entrega ya pertenece a una liquidación cerrada y no puede modificarse.',
      );
    }
    if (existing.anulado) {
      throw ReceptionServiceException(
        'Esta entrega ya fue anulada previamente.',
      );
    }
    final String cleanReason = motivo.trim();
    if (cleanReason.length < 5) {
      throw ReceptionServiceException(
        'Debes indicar el motivo de la corrección (mínimo 5 caracteres).',
      );
    }

    MilkReceptionModel toSave = updated.copyWith(
      isSynced: false,
      syncStatus: AppConstants.syncPending,
    );
    await _hiveService.saveReception(toSave);

    try {
      final MilkReceptionModel remoteCopy = toSave.copyWith(
        isSynced: true,
        syncStatus: AppConstants.syncSynced,
      );
      await _remoteDataSource.upsertReception(remoteCopy);
      await _hiveService.saveReception(remoteCopy);
      toSave = remoteCopy;
      await _remoteDataSource.appendAuditLog(
        AuditLogModel(
          logId: _uuid.v4(),
          entidadAfectada: AppConstants.receptionsCollection,
          registroId: existing.recepcionId,
          accion: accion,
          valorAnterior: valorAnterior,
          valorNuevo: valorNuevo,
          motivo: cleanReason,
          usuarioUid: actor.uid,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    } catch (_) {
      // Queda marcado pendiente para sincronización al recuperar conexión.
    }

    return toSave;
  }

  Future<SyncExecutionResult> syncPending() =>
      _effectiveSyncService.syncPendingReceptions();
}

class _DelegatingReceptionGateway implements RemoteReceptionGateway {
  _DelegatingReceptionGateway(this._remoteDataSource);

  final RemoteReceptionDataSource _remoteDataSource;

  @override
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions) async {
    for (final MilkReceptionModel item in receptions) {
      await _remoteDataSource.upsertReception(
        item.copyWith(
          isSynced: true,
          syncStatus: AppConstants.syncSynced,
        ),
      );
    }
  }
}
