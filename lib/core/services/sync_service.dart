import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/milk_reception_model.dart';
import '../constants/app_constants.dart';
import 'hive_service.dart';

/// Puerta de enlace remota para subir lotes de recepciones de manera idempotente.
abstract class RemoteReceptionGateway {
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions);
}

/// Implementación por defecto con `WriteBatch` en Cloud Firestore usando
/// `recepcionId` (UUID v4) como clave de documento para garantizar idempotencia.
class FirestoreReceptionGateway implements RemoteReceptionGateway {
  FirestoreReceptionGateway({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions) async {
    if (receptions.isEmpty) {
      return;
    }
    final WriteBatch batch = _db.batch();
    final CollectionReference<Map<String, dynamic>> col =
        _db.collection(AppConstants.receptionsCollection);

    for (final MilkReceptionModel reception in receptions) {
      final MilkReceptionModel syncedPayload = reception.copyWith(
        syncStatus: AppConstants.syncSynced,
        isSynced: true,
      );
      batch.set(
        col.doc(reception.recepcionId),
        syncedPayload.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
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
    try {
      final List<MilkReceptionModel> pending =
          await hiveService.getPendingReceptions();
      if (pending.isEmpty) {
        return const SyncExecutionResult(
          syncedCount: 0,
          remainingPendingCount: 0,
        );
      }

      // Enviar en lotes seguros (máx. 400 operaciones por WriteBatch de Firestore).
      int totalSynced = 0;
      const int maxBatchSize = 400;
      for (int offset = 0; offset < pending.length; offset += maxBatchSize) {
        final int end = (offset + maxBatchSize).clamp(0, pending.length);
        final List<MilkReceptionModel> slice = pending.sublist(offset, end);

        await _remoteGateway.uploadReceptionsBatch(slice);
        await hiveService.markReceptionsAsSynced(
          slice.map((MilkReceptionModel r) => r.recepcionId).toList(),
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
        syncedCount: 0,
        remainingPendingCount: remaining,
        error: e.toString(),
      );
    } finally {
      _isSyncInProgress = false;
    }
  }
}
