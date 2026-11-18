import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'settlement_calculator.dart';

enum ReportRangeType { daily, quincenal, monthly, custom }

/// Resumen consolidado de producción por ganadero para un rango de fechas (`RF-17`, `RF-18`).
class ProducerProductionSummary {
  const ProducerProductionSummary({
    required this.productorId,
    required this.codigoAsociado,
    required this.nombreProductor,
    required this.cedula,
    required this.vereda,
    required this.morningLiters,
    required this.afternoonLiters,
    required this.totalLiters,
    required this.deliveryCount,
    required this.activeDaysCount,
    required this.periodDaysCount,
    required this.dailyAverageLiters,
    required this.settledAmount,
    required this.pendingEstimateAmount,
  });

  final String productorId;
  final String codigoAsociado;
  final String nombreProductor;
  final String cedula;
  final String vereda;
  final double morningLiters;
  final double afternoonLiters;
  final double totalLiters;
  final int deliveryCount;
  final int activeDaysCount;
  final int periodDaysCount;
  final double dailyAverageLiters;
  final double settledAmount;
  final double pendingEstimateAmount;

  double get totalEconomicValue =>
      SettlementCalculator.roundToCents(settledAmount + pendingEstimateAmount);
}

/// Fuente remota abstracta de bitácora de auditoría en solo lectura (`RNF-07`).
abstract class RemoteAuditDataSource {
  Future<List<AuditLogModel>> fetchAuditLogs({int limit = 250});
}

class FirestoreAuditDataSource implements RemoteAuditDataSource {
  FirestoreAuditDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  Future<List<AuditLogModel>> fetchRecordHistory(String id) async {
    final snapshot = await _db.collection(AppConstants.auditLogsCollection)
        .where('registroId', isEqualTo: id).get();
    return snapshot.docs.map((doc) => AuditLogModel.fromMap(doc.data(), documentId: doc.id)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<List<AuditLogModel>> fetchAuditLogs({int limit = 250}) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.auditLogsCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              AuditLogModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }
}

/// Servicio analítico para reporte individual de ganaderos, consolidados y bitácora inmutable (`RF-17`, `RF-18`, `RNF-07`).
class ReportService {
  ReportService({
    RemoteAuditDataSource? remoteAuditDataSource,
  }) : _remoteAuditDataSource =
            remoteAuditDataSource ?? FirestoreAuditDataSource();

  final RemoteAuditDataSource _remoteAuditDataSource;

  Future<List<AuditLogModel>> listRecordHistory(String id) async {
    final source = _remoteAuditDataSource;
    if (source is FirestoreAuditDataSource) return source.fetchRecordHistory(id);
    return (await listAuditLogs()).where((log) => log.registroId == id).toList();
  }

  Future<List<AuditLogModel>> listAuditLogs({int limit = 250}) async {
    try {
      final List<AuditLogModel> logs =
          await _remoteAuditDataSource.fetchAuditLogs(limit: limit);
      logs.sort(
        (AuditLogModel a, AuditLogModel b) => b.timestamp.compareTo(a.timestamp),
      );
      return logs;
    } catch (_) {
      return <AuditLogModel>[];
    }
  }

  /// Construye períodos predefinidos (diario, quincenal, mensual).
  static QuincenaPeriod buildPeriodForType(
    ReportRangeType type, {
    DateTime? referenceDate,
  }) {
    final DateTime now = referenceDate ?? DateTime.now();
    switch (type) {
      case ReportRangeType.daily:
        final String iso = AppFormatters.toIsoDate(now);
        return QuincenaPeriod(
          startDate: iso,
          endDate: iso,
          label: 'Diario (${AppFormatters.formatIsoDate(iso)})',
        );
      case ReportRangeType.quincenal:
        return QuincenaPeriod.currentForDate(now);
      case ReportRangeType.monthly:
        final DateTime start = DateTime(now.year, now.month, 1);
        final DateTime end = DateTime(now.year, now.month + 1, 0);
        return QuincenaPeriod(
          startDate: AppFormatters.toIsoDate(start),
          endDate: AppFormatters.toIsoDate(end),
          label:
              'Mensual ${now.month.toString().padLeft(2, '0')}/${now.year}',
        );
      case ReportRangeType.custom:
        return QuincenaPeriod.currentForDate(now);
    }
  }

  static int computePeriodDaysCount(QuincenaPeriod period) {
    final DateTime? start = DateTime.tryParse(period.startDate);
    final DateTime? end = DateTime.tryParse(period.endDate);
    if (start == null || end == null) return 1;
    final int diff = end.difference(start).inDays + 1;
    return diff < 1 ? 1 : diff;
  }

  /// Genera resúmenes de producción individual y consolidada para el rango [period].
  static List<ProducerProductionSummary> buildProducerSummaries({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    required List<SettlementModel> settlements,
    required double activePricePerLiter,
    String? filterProducerId,
  }) {
    final Map<String, ProducerModel> producerById = <String, ProducerModel>{
      for (final ProducerModel p in producers) p.productorId: p,
    };
    final Map<String, SettlementModel> settlementById =
        <String, SettlementModel>{
      for (final SettlementModel s in settlements) s.liquidacionId: s,
    };

    final Map<String, List<MilkReceptionModel>> grouped =
        <String, List<MilkReceptionModel>>{};

    for (final MilkReceptionModel r in receptions) {
      if (r.anulado) continue;
      if (!period.containsIsoDate(r.fechaEntrega)) continue;
      if (filterProducerId != null &&
          filterProducerId.isNotEmpty &&
          r.productorId != filterProducerId) {
        continue;
      }
      grouped.putIfAbsent(r.productorId, () => <MilkReceptionModel>[]).add(r);
    }

    final int periodDays = computePeriodDaysCount(period);
    final List<ProducerProductionSummary> summaries =
        <ProducerProductionSummary>[];

    for (final MapEntry<String, List<MilkReceptionModel>> entry
        in grouped.entries) {
      final List<MilkReceptionModel> list = entry.value;
      int morningThousandths = 0;
      int afternoonThousandths = 0;
      double settledAmt = 0;
      double pendingAmt = 0;
      final Set<String> distinctDays = <String>{};

      for (final MilkReceptionModel r in list) {
        distinctDays.add(r.fechaEntrega);
        final int t = (r.litros * 1000).round();
        if (r.jornada.toUpperCase() == AppConstants.shiftMorning) {
          morningThousandths += t;
        } else {
          afternoonThousandths += t;
        }

        if (r.isLiquidada && settlementById.containsKey(r.liquidacionId)) {
          final SettlementModel st = settlementById[r.liquidacionId]!;
          settledAmt += SettlementCalculator.calculateTotalAmount(
            totalLiters: r.litros,
            pricePerLiter: st.precioLitroAplicado,
          );
        } else if (activePricePerLiter > 0) {
          pendingAmt += SettlementCalculator.calculateTotalAmount(
            totalLiters: r.litros,
            pricePerLiter: activePricePerLiter,
          );
        }
      }

      final double morningL = morningThousandths / 1000.0;
      final double afternoonL = afternoonThousandths / 1000.0;
      final double totalL = (morningThousandths + afternoonThousandths) / 1000.0;
      final int activeDays = distinctDays.isEmpty ? 1 : distinctDays.length;

      final ProducerModel? producer = producerById[entry.key];
      final MilkReceptionModel sample = list.first;

      summaries.add(
        ProducerProductionSummary(
          productorId: entry.key,
          codigoAsociado:
              producer?.codigoAsociado ?? sample.codigoAsociadoSnap,
          nombreProductor:
              producer?.nombreCompleto ?? sample.nombreProductorSnap,
          cedula: producer?.cedula ?? 'No registrada',
          vereda: producer?.vereda ?? 'Susa',
          morningLiters: morningL,
          afternoonLiters: afternoonL,
          totalLiters: totalL,
          deliveryCount: list.length,
          activeDaysCount: distinctDays.length,
          periodDaysCount: periodDays,
          dailyAverageLiters:
              SettlementCalculator.roundToThousandths(totalL / activeDays),
          settledAmount: SettlementCalculator.roundToCents(settledAmt),
          pendingEstimateAmount: SettlementCalculator.roundToCents(pendingAmt),
        ),
      );
    }

    summaries.sort(
      (ProducerProductionSummary a, ProducerProductionSummary b) =>
          b.totalLiters.compareTo(a.totalLiters),
    );
    return summaries;
  }

  /// Filtra recepciones válidas del rango (y opcionalmente de un productor).
  static List<MilkReceptionModel> filterReceptionsForReport({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    String? filterProducerId,
  }) {
    final List<MilkReceptionModel> result = receptions.where((MilkReceptionModel r) {
      if (r.anulado) return false;
      if (!period.containsIsoDate(r.fechaEntrega)) return false;
      if (filterProducerId != null &&
          filterProducerId.isNotEmpty &&
          r.productorId != filterProducerId) {
        return false;
      }
      return true;
    }).toList();
    result.sort((MilkReceptionModel a, MilkReceptionModel b) {
      final int d = b.fechaEntrega.compareTo(a.fechaEntrega);
      if (d != 0) return d;
      return b.horaEntrega.compareTo(a.horaEntrega);
    });
    return result;
  }

  /// Filtra liquidaciones que se solapan con el rango (y opcionalmente por productor).
  static List<SettlementModel> filterSettlementsForReport({
    required QuincenaPeriod period,
    required List<SettlementModel> settlements,
    String? filterProducerId,
  }) {
    final List<SettlementModel> result = settlements.where((SettlementModel s) {
      if (!period.overlapsWith(s.periodoInicio, s.periodoFin)) return false;
      if (filterProducerId != null &&
          filterProducerId.isNotEmpty &&
          s.productorId != filterProducerId) {
        return false;
      }
      return true;
    }).toList();
    result.sort(
      (SettlementModel a, SettlementModel b) =>
          b.fechaLiquidacion.compareTo(a.fechaLiquidacion),
    );
    return result;
  }
}
