import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_notification_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'hive_service.dart';
import 'settlement_calculator.dart';

class SettlementServiceException implements Exception {
  SettlementServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fuente remota abstracta para liquidaciones, cierre quincenal y pagos.
abstract class RemoteSettlementDataSource {
  Future<List<SettlementModel>> fetchSettlements();
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  });
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  });
}

class FirestoreSettlementDataSource implements RemoteSettlementDataSource {
  FirestoreSettlementDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<SettlementModel>> fetchSettlements() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.settlementsCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              SettlementModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {
    // Divide escrituras respetando el límite de 500 operaciones por WriteBatch.
    final List<_BatchOp> ops = <_BatchOp>[];

    for (final SettlementModel settlement in settlements) {
      ops.add(
        _BatchOp.set(
          _db
              .collection(AppConstants.settlementsCollection)
              .doc(settlement.liquidacionId),
          settlement.toMap(),
        ),
      );
      final List<String> recIds =
          receptionIdsBySettlement[settlement.liquidacionId] ??
              const <String>[];
      for (final String recId in recIds) {
        ops.add(
          _BatchOp.update(
            _db.collection(AppConstants.receptionsCollection).doc(recId),
            <String, dynamic>{'liquidacionId': settlement.liquidacionId},
          ),
        );
      }
    }

    for (final AppNotificationModel n in notifications) {
      ops.add(
        _BatchOp.set(
          _db
              .collection(AppConstants.notificationsCollection)
              .doc(n.notificacionId),
          n.toMap(),
        ),
      );
    }

    ops.add(
      _BatchOp.set(
        _db.collection(AppConstants.auditLogsCollection).doc(auditLog.logId),
        auditLog.toMap(),
      ),
    );

    const int chunkSize = 420;
    for (int i = 0; i < ops.length; i += chunkSize) {
      final int end =
          (i + chunkSize < ops.length) ? (i + chunkSize) : ops.length;
      final WriteBatch batch = _db.batch();
      for (final _BatchOp op in ops.sublist(i, end)) {
        op.apply(batch);
      }
      await batch.commit();
    }
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {
    final WriteBatch batch = _db.batch();
    batch.update(
      _db
          .collection(AppConstants.settlementsCollection)
          .doc(updatedSettlement.liquidacionId),
      <String, dynamic>{
        'estadoPago': updatedSettlement.estadoPago,
        'fechaPago': updatedSettlement.fechaPago?.toUtc().toIso8601String(),
        'observacionPago': updatedSettlement.observacionPago,
      },
    );
    batch.set(
      _db
          .collection(AppConstants.notificationsCollection)
          .doc(notification.notificacionId),
      notification.toMap(),
    );
    batch.set(
      _db.collection(AppConstants.auditLogsCollection).doc(auditLog.logId),
      auditLog.toMap(),
    );
    await batch.commit();
  }
}

class _BatchOp {
  _BatchOp.set(this.ref, this.data) : isUpdate = false;
  _BatchOp.update(this.ref, this.data) : isUpdate = true;

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  final bool isUpdate;

  void apply(WriteBatch batch) {
    if (isUpdate) {
      batch.update(ref, data);
    } else {
      batch.set(ref, data);
    }
  }
}

/// Servicio MVC de cierre quincenal atómico, emisión de comprobantes y registro de pagos (`RF-13` a `RF-15`).
class SettlementService {
  SettlementService({
    HiveService? hiveService,
    RemoteSettlementDataSource? remoteDataSource,
  })  : _hiveService = hiveService ?? HiveService(),
        _remoteDataSource =
            remoteDataSource ?? FirestoreSettlementDataSource();

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteSettlementDataSource _remoteDataSource;

  Future<({List<SettlementModel> settlements, bool fromCache})>
      listSettlements() async {
    try {
      final List<SettlementModel> remote =
          await _remoteDataSource.fetchSettlements();
      remote.sort(
        (SettlementModel a, SettlementModel b) =>
            b.fechaLiquidacion.compareTo(a.fechaLiquidacion),
      );
      await _hiveService.cacheSettlements(remote);
      return (settlements: remote, fromCache: false);
    } catch (_) {
      final List<SettlementModel> cached =
          await _hiveService.getCachedSettlements();
      return (settlements: cached, fromCache: true);
    }
  }

  /// Construye la previsualización determinista de cierre para un rango dado.
  SettlementPreviewResult buildPreview({
    required QuincenaPeriod period,
    required double pricePerLiter,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    required List<SettlementModel> existingSettlements,
  }) {
    return SettlementCalculator.buildPreview(
      period: period,
      pricePerLiter: pricePerLiter,
      receptions: receptions,
      producers: producers,
      existingSettlements: existingSettlements,
    );
  }

  /// Ejecuta el cierre quincenal atómico solo para `ADMIN` (`RF-13`, `HU-07`).
  Future<List<SettlementModel>> closeQuincena({
    required UserModel actor,
    required QuincenaPeriod period,
    required double pricePerLiter,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    List<SettlementModel>? existingSettlements,
    bool blockIfUnsynced = true,
  }) async {
    if (!actor.isAdmin) {
      throw SettlementServiceException(
        'Solo el Administrador Central puede ejecutar el cierre quincenal.',
      );
    }

    if (pricePerLiter <= 0) {
      throw SettlementServiceException(
        'Configura una tarifa vigente por litro mayor a cero antes de liquidar.',
      );
    }

    final List<SettlementModel> currentHistory = existingSettlements ??
        (await listSettlements()).settlements;

    final SettlementPreviewResult preview = buildPreview(
      period: period,
      pricePerLiter: pricePerLiter,
      receptions: receptions,
      producers: producers,
      existingSettlements: currentHistory,
    );

    if (blockIfUnsynced && preview.hasPendingSync) {
      throw SettlementServiceException(
        'Existen ${preview.pendingSyncReceptions.length} entrega(s) en el rango pendientes por sincronizar. Sincroniza antes de cerrar la quincena.',
      );
    }

    if (!preview.hasEligibleCandidates) {
      if (preview.alreadySettledProducerIds.isNotEmpty) {
        throw SettlementServiceException(
          'Los productores con entregas en ${period.label} ya cuentan con liquidación cerrada en este período.',
        );
      }
      throw SettlementServiceException(
        'No hay entregas válidas y sincronizadas pendientes por liquidar en el rango seleccionado.',
      );
    }

    final DateTime nowUtc = DateTime.now().toUtc();
    final int comprobanteYear = int.tryParse(period.endDate.split('-').first) ??
        nowUtc.year;

    final List<SettlementModel> createdSettlements = <SettlementModel>[];
    final Map<String, List<String>> receptionIdsBySettlement =
        <String, List<String>>{};
    final List<AppNotificationModel> notifications = <AppNotificationModel>[];

    for (int idx = 0; idx < preview.candidates.length; idx++) {
      final SettlementCandidate candidate = preview.candidates[idx];
      final String liquidacionId = _uuid.v4();
      final String comprobanteNumber =
          SettlementCalculator.nextComprobanteNumber(
        year: comprobanteYear,
        existingSettlements: currentHistory,
        offset: idx,
      );
      final List<String> recIds = candidate.receptions
          .map((MilkReceptionModel r) => r.recepcionId)
          .toList();

      final String hashIntegridad = SettlementCalculator.computeIntegrityHash(
        liquidacionId: liquidacionId,
        numeroComprobante: comprobanteNumber,
        productorId: candidate.productorId,
        cedula: candidate.cedula,
        periodoInicio: period.startDate,
        periodoFin: period.endDate,
        totalLitros: candidate.totalLiters,
        cantidadEntregas: candidate.deliveryCount,
        precioLitroAplicado: candidate.precioPorLitro,
        valorTotalPagar: candidate.valorTotalPagar,
        recepcionIds: recIds,
      );

      final SettlementModel settlement = SettlementModel(
        liquidacionId: liquidacionId,
        productorId: candidate.productorId,
        nombreProductorSnap: candidate.nombreProductor,
        cedulaProductorSnap: candidate.cedula,
        periodoInicio: period.startDate,
        periodoFin: period.endDate,
        quincenaLabel: period.label,
        totalLitros: candidate.totalLiters,
        cantidadEntregas: candidate.deliveryCount,
        precioLitroAplicado: candidate.precioPorLitro,
        valorTotalPagar: candidate.valorTotalPagar,
        estadoPago: 'PENDIENTE',
        fechaLiquidacion: nowUtc,
        numeroComprobante: comprobanteNumber,
        hashIntegridad: hashIntegridad,
        creadoPorUid: actor.uid,
      );

      createdSettlements.add(settlement);
      receptionIdsBySettlement[liquidacionId] = recIds;

      notifications.add(
        AppNotificationModel(
          notificacionId: _uuid.v4(),
          titulo: 'Liquidación ${period.label} disponible',
          mensaje:
              'Comprobante $comprobanteNumber: ${AppFormatters.formatLiters(candidate.totalLiters)} liquidados por ${AppFormatters.formatCurrency(candidate.valorTotalPagar)}.',
          tipo: 'CIERRE_QUINCENA',
          destinoProductorId: candidate.productorId,
          fechaEnvio: nowUtc,
          leida: false,
        ),
      );
    }

    final AuditLogModel auditLog = AuditLogModel(
      logId: _uuid.v4(),
      modulo: 'LIQUIDACIONES',
      accion: 'CIERRE_QUINCENAL',
      referenciaId: '${period.startDate}_${period.endDate}',
      valorNuevo: <String, dynamic>{
        'quincenaLabel': period.label,
        'cantidadComprobantes': createdSettlements.length,
        'totalLitros': preview.totalLiters,
        'tarifaAplicada': preview.precioPorLitro,
        'valorTotal': preview.totalAmountToPay,
      },
      motivo: 'Cierre quincenal ${period.label}',
      usuarioUid: actor.uid,
      usuarioNombre: actor.nombreCompleto,
      fechaEvento: nowUtc,
    );

    try {
      await _remoteDataSource.commitQuincenaClose(
        settlements: createdSettlements,
        receptionIdsBySettlement: receptionIdsBySettlement,
        notifications: notifications,
        auditLog: auditLog,
      );
    } catch (_) {
      throw SettlementServiceException(
        'No fue posible completar el cierre en la nube. Ningún registro fue alterado.',
      );
    }

    // Reflejar inmediatamente el cierre atómico en el respaldo local Hive.
    for (final SettlementModel settlement in createdSettlements) {
      await _hiveService.upsertSettlement(settlement);
      final List<String> recIds =
          receptionIdsBySettlement[settlement.liquidacionId] ??
              const <String>[];
      if (recIds.isNotEmpty) {
        await _hiveService.assignSettlementToReceptions(
          recepcionIds: recIds,
          liquidacionId: settlement.liquidacionId,
        );
      }
    }
    for (final AppNotificationModel n in notifications) {
      await _hiveService.upsertNotification(n);
    }

    return createdSettlements;
  }

  /// Marca una liquidación cerrada como `PAGADA`, registra auditoría y notifica al productor (`RF-15`).
  Future<SettlementModel> markAsPaid({
    required UserModel actor,
    required SettlementModel settlement,
    required String observacionPago,
    DateTime? fechaPago,
  }) async {
    if (!actor.isAdmin) {
      throw SettlementServiceException(
        'Solo el Administrador Central puede confirmar desembolsos.',
      );
    }
    if (settlement.isPagada) {
      throw SettlementServiceException(
        'La liquidación ${settlement.numeroComprobante} ya se encuentra pagada.',
      );
    }

    final String obs = observacionPago.trim();
    if (obs.length < 3) {
      throw SettlementServiceException(
        'Ingresa una referencia u observación de pago (ej: transferencia o efectivo).',
      );
    }

    final DateTime paymentUtc = (fechaPago ?? DateTime.now()).toUtc();
    final SettlementModel updated = settlement.copyWith(
      estadoPago: 'PAGADA',
      fechaPago: paymentUtc,
      observacionPago: obs,
    );

    final AppNotificationModel notification = AppNotificationModel(
      notificacionId: _uuid.v4(),
      titulo: 'Pago confirmado (${settlement.numeroComprobante})',
      mensaje:
          'Se registró el pago de ${AppFormatters.formatCurrency(settlement.valorTotalPagar)} correspondiente a ${settlement.quincenaLabel}. $obs',
      tipo: 'PAGO',
      destinoProductorId: settlement.productorId,
      fechaEnvio: paymentUtc,
      leida: false,
    );

    final AuditLogModel auditLog = AuditLogModel(
      logId: _uuid.v4(),
      modulo: 'LIQUIDACIONES',
      accion: 'CONFIRMAR_PAGO',
      referenciaId: settlement.liquidacionId,
      valorAnterior: <String, dynamic>{
        'estadoPago': settlement.estadoPago,
        'numeroComprobante': settlement.numeroComprobante,
      },
      valorNuevo: <String, dynamic>{
        'estadoPago': 'PAGADA',
        'fechaPago': paymentUtc.toIso8601String(),
        'observacionPago': obs,
      },
      motivo: obs,
      usuarioUid: actor.uid,
      usuarioNombre: actor.nombreCompleto,
      fechaEvento: paymentUtc,
    );

    try {
      await _remoteDataSource.markSettlementAsPaid(
        updatedSettlement: updated,
        notification: notification,
        auditLog: auditLog,
      );
    } catch (_) {
      throw SettlementServiceException(
        'No se pudo confirmar el pago en línea. Verifica tu conexión e intenta de nuevo.',
      );
    }

    await _hiveService.upsertSettlement(updated);
    await _hiveService.upsertNotification(notification);
    return updated;
  }
}
