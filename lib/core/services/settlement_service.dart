import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'firebase_callable.dart';
import 'firestore_audit.dart';
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

  /// Consulta acotada por `productorId` cumpliendo aislamiento en portal móvil (`RF-22`).
  Future<List<SettlementModel>> fetchSettlementsForProducer(
    String productorId,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.settlementsCollection)
        .where('productorId', isEqualTo: productorId.trim())
        .get();
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
    final String? token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) {
      throw SettlementServiceException('Inicia sesión para cerrar la quincena.');
    }
    final result = await callFirebaseFunction('closeMilkSettlements', <String, dynamic>{
      'groups': [
        for (int i = 0; i < settlements.length; i++)
          <String, dynamic>{
            'settlement': settlements[i].toMap(),
            'receptionIds': receptionIdsBySettlement[settlements[i].liquidacionId],
            'notification': {'notificacionId': notifications[i].notificacionId},
          },
      ],
    }, idToken: token, timeout: const Duration(seconds: 130));
    if (result['error'] != null) {
      throw SettlementServiceException('${result['completed']} de ${settlements.length} liquidaciones confirmadas. ${result['error']}');
    }
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {
    final record = _db.collection(AppConstants.settlementsCollection)
        .doc(updatedSettlement.liquidacionId);
    await _db.runTransaction((Transaction transaction) async {
      final before = (await transaction.get(record)).data();
      if (before == null || before['estadoPago'] != 'PENDIENTE') {
        throw SettlementServiceException('La liquidación ya no está pendiente. Actualiza la lista.');
      }
      writeAuditedVersion(db: _db, transaction: transaction, record: record, before: before,
        after: <String, dynamic>{
          ...before,
          'estadoPago': updatedSettlement.estadoPago,
          'fechaPago': updatedSettlement.fechaPago?.toUtc().toIso8601String(),
          'observacionPago': updatedSettlement.observacionPago,
        }, event: auditLog,
      );
      transaction.set(_db.collection(AppConstants.notificationsCollection).doc(notification.notificacionId),
        notification.toMap(),
      );
    });
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

  /// Lista exclusivamente las liquidaciones de un productor (`RF-22`, `RNF-05`).
  Future<({List<SettlementModel> settlements, bool fromCache})>
      listForProducer(String productorId) async {
    final String cleanId = productorId.trim();
    if (_remoteDataSource is FirestoreSettlementDataSource) {
      try {
        final List<SettlementModel> remote =
            await _remoteDataSource.fetchSettlementsForProducer(cleanId);
        remote.sort(
          (SettlementModel a, SettlementModel b) =>
              b.fechaLiquidacion.compareTo(a.fechaLiquidacion),
        );
        for (final settlement in remote) {
          await _hiveService.upsertSettlement(settlement);
        }
        return (settlements: remote, fromCache: false);
      } catch (_) {
        final List<SettlementModel> cached =
            (await _hiveService.getCachedSettlements())
                .where((SettlementModel s) => s.productorId == cleanId)
                .toList();
        return (settlements: cached, fromCache: true);
      }
    }

    final result = await listSettlements();
    final List<SettlementModel> scoped = result.settlements
        .where((SettlementModel s) => s.productorId == cleanId)
        .toList();
    return (settlements: scoped, fromCache: result.fromCache);
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
      entidadAfectada: AppConstants.settlementsCollection,
      registroId: '${period.startDate}_${period.endDate}',
      accion: 'LIQUIDAR',
      valorNuevo: <String, dynamic>{
        'quincenaLabel': period.label,
        'cantidadComprobantes': createdSettlements.length,
        'totalLitros': preview.totalLiters,
        'tarifaAplicada': preview.precioPorLitro,
        'valorTotal': preview.totalAmountToPay,
        'actorNombre': actor.nombreCompleto,
      },
      motivo: 'Cierre quincenal ${period.label}',
      usuarioUid: actor.uid,
      timestamp: nowUtc,
    );

    try {
      await _remoteDataSource.commitQuincenaClose(
        settlements: createdSettlements,
        receptionIdsBySettlement: receptionIdsBySettlement,
        notifications: notifications,
        auditLog: auditLog,
      );
    } on SettlementServiceException {
      rethrow;
    } catch (_) {
      throw SettlementServiceException(
        'No se pudo verificar el cierre completo. Actualiza las liquidaciones antes de reintentar.',
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
      entidadAfectada: AppConstants.settlementsCollection,
      registroId: settlement.liquidacionId,
      accion: 'EDITAR',
      valorAnterior: <String, dynamic>{
        'estadoPago': settlement.estadoPago,
        'numeroComprobante': settlement.numeroComprobante,
      },
      valorNuevo: <String, dynamic>{
        'estadoPago': 'PAGADA',
        'fechaPago': paymentUtc.toIso8601String(),
        'observacionPago': obs,
        'actorNombre': actor.nombreCompleto,
      },
      motivo: obs,
      usuarioUid: actor.uid,
      timestamp: paymentUtc,
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
