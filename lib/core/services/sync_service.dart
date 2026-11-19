import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../constants/app_constants.dart';
import 'firestore_audit.dart';
import 'hive_service.dart';

/// Puerta de enlace remota para subir lotes de recepciones de manera idempotente.
abstract class RemoteReceptionGateway {
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions);
}

/// Crea cada entrega y su versión original en una única transacción.
class FirestoreReceptionGateway implements RemoteReceptionGateway {
  FirestoreReceptionGateway({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions) async {
    for (final MilkReceptionModel reception in receptions) {
      final Map<String, dynamic> payload = reception.copyWith(
        syncStatus: AppConstants.syncSynced,
        isSynced: true,
      ).toMap();
      final record = _db.collection(AppConstants.receptionsCollection)
          .doc(reception.recepcionId);
      await _db.runTransaction((Transaction transaction) async {
        final existing = (await transaction.get(record)).data();
        if (existing != null) {
          if (existing['operarioUid'] != reception.operarioUid ||
              existing['createdAt'] != payload['createdAt']) {
            throw StateError('El identificador de la entrega ya está en uso.');
          }
          if (existing['auditLogId'] == null &&
              (existing['litros'] != reception.litros ||
                (existing['anulado'] == true) != reception.anulado)) {
            throw StateError('Una entrega antigua pendiente difiere de la versión remota. Consulta la bitácora con el administrador.');
          }
          return; // Reintento de subida tras confirmación remota.
        }
        if (reception.anulado || reception.isLiquidada) {
          throw StateError('La entrega pendiente ya contiene cambios previos. Consulta la bitácora con el administrador.');
        }
        writeAuditedVersion(
          db: _db,
          transaction: transaction,
          record: record,
          before: null,
          after: payload,
          event: AuditLogModel(
            logId: 'recepcion_${reception.recepcionId}',
            entidadAfectada: AppConstants.receptionsCollection,
            registroId: reception.recepcionId,
            accion: 'CREAR',
            usuarioUid: reception.operarioUid,
            timestamp: reception.createdAt,
          ),
        );
        final String notificationId = 'notif_entrega_${reception.recepcionId}';
        final String shiftLabel =
            reception.jornada.toUpperCase() == AppConstants.shiftAfternoon
                ? 'Tarde'
                : 'Mañana';
        transaction.set(
          _db.collection(AppConstants.notificationsCollection).doc(notificationId),
          <String, dynamic>{
            'notificacionId': notificationId,
            'titulo': 'Entrega registrada ($shiftLabel)',
            'mensaje':
                'Se registraron ${reception.litros.toStringAsFixed(1)} L de leche cruda el ${reception.fechaEntrega} a las ${reception.horaEntrega} ($shiftLabel).',
            'tipo': 'ENTREGA',
            'destinoProductorId': reception.productorId,
            'fechaEnvio': payload['createdAt'],
            'leida': false,
          },
        );
      });
    }
  }
}

/// Resultado de un barrido de sincronización.
class SyncExecutionResult {
  const SyncExecutionResult({
    required this.syncedCount,
    required this.remainingPendingCount,
    this.error,
  });

  final int syncedCount;
  final int remainingPendingCount;
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;
}

/// Motor de sincronización Offline-First (Hive -> Firestore).
class SyncService {
  SyncService({
    required this.hiveService,
    RemoteReceptionGateway? remoteGateway,
  }) : _remoteGateway = remoteGateway ?? FirestoreReceptionGateway();

  final HiveService hiveService;
  final RemoteReceptionGateway _remoteGateway;

  bool _isSyncInProgress = false;

  /// Escritura local prioritaria en Hive con estado `PENDIENTE`.
  Future<MilkReceptionModel> registerReceptionOfflineFirst(
    MilkReceptionModel reception, {
    bool tryImmediateSync = false,
  }) async {
    final MilkReceptionModel localRecord = reception.copyWith(
      isSynced: false,
      syncStatus: AppConstants.syncPending,
    );
    await hiveService.saveReception(localRecord);

    if (tryImmediateSync) {
      final SyncExecutionResult result = await syncPendingReceptions();
      if (!result.hasError) {
        final MilkReceptionModel? refreshed =
            await hiveService.getReceptionById(localRecord.recepcionId);
        if (refreshed != null) {
          return refreshed;
        }
      }
    }
    return localRecord;
  }

  /// Sube en orden cronológico todos los registros pendientes de Hive
  /// usando clave primaria UUID v4 para evitar duplicados al reintentar.
  Future<SyncExecutionResult> syncPendingReceptions() async {
    if (_isSyncInProgress) {
      final int pendingNow = (await hiveService.getPendingReceptions()).length;
      return SyncExecutionResult(
        syncedCount: 0,
        remainingPendingCount: pendingNow,
      );
    }

    _isSyncInProgress = true;
    int totalSynced = 0;
    try {
      List<MilkReceptionModel> pending =
          await hiveService.getPendingReceptions();
      final RemoteReceptionGateway gateway = _remoteGateway;
      if (gateway is FirestoreReceptionGateway) {
        final String? uid = gateway.currentUid;
        pending = pending.where((MilkReceptionModel r) => r.operarioUid == uid).toList();
      }
      if (pending.isEmpty) {
        return SyncExecutionResult(
          syncedCount: 0,
          remainingPendingCount: (await hiveService.getPendingReceptions()).length,
        );
      }

      final int maxBatchSize = gateway is FirestoreReceptionGateway ? 1 : 400;
      for (int offset = 0; offset < pending.length; offset += maxBatchSize) {
        final int end = (offset + maxBatchSize).clamp(0, pending.length);
        final List<MilkReceptionModel> slice = pending.sublist(offset, end);

        await _remoteGateway.uploadReceptionsBatch(slice);
        await hiveService.markReceptionsAsSynced(
          slice.map((MilkReceptionModel r) => r.recepcionId).toList(),
          audited: gateway is FirestoreReceptionGateway,
        );
        totalSynced += slice.length;
      }

      final int remaining = (await hiveService.getPendingReceptions()).length;
      return SyncExecutionResult(
        syncedCount: totalSynced,
        remainingPendingCount: remaining,
      );
    } catch (e) {
      final int remaining = (await hiveService.getPendingReceptions()).length;
      return SyncExecutionResult(
        syncedCount: totalSynced,
        remainingPendingCount: remaining,
        error: e.toString(),
      );
    } finally {
      _isSyncInProgress = false;
    }
  }
}
