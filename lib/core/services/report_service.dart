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

// ════════════════════════════════════════════════════════════════════════
// Catálogo de reportes: cada reporte produce un [ReportDataset] que alimenta
// la vista previa, el PDF, el Excel y el CSV con la misma información.
// ════════════════════════════════════════════════════════════════════════

enum ReportColumnType { text, integer, liters, money, date, percent }

class ReportColumn {
  const ReportColumn(this.header, {this.type = ReportColumnType.text, this.flex = 2});
  final String header;
  final ReportColumnType type;
  final int flex;

  bool get alignRight =>
      type == ReportColumnType.integer ||
      type == ReportColumnType.liters ||
      type == ReportColumnType.money ||
      type == ReportColumnType.percent;
}

class ReportKpi {
  const ReportKpi(this.label, this.value, {this.hint});
  final String label;
  final String value;
  final String? hint;
}

/// Datos tabulares de un reporte listos para vista previa y exportación.
class ReportDataset {
  const ReportDataset({
    this.kind,
    required this.title,
    required this.periodLabel,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.totals,
    this.kpis = const <ReportKpi>[],
    this.emptyMessage = 'No hay datos para el período seleccionado.',
  });

  final ReportKind? kind;
  final String title;
  final String? subtitle;
  final String periodLabel;
  final List<ReportColumn> columns;

  /// Valores crudos: `num` para cifras, `String` para textos y fechas.
  final List<List<Object?>> rows;
  final List<Object?>? totals;
  final List<ReportKpi> kpis;
  final String emptyMessage;

  bool get isEmpty => rows.isEmpty;

  /// Texto de una celda para la vista previa y el PDF.
  static String formatCell(Object? v, ReportColumnType type) {
    if (v == null) return '';
    if (v is num) {
      switch (type) {
        case ReportColumnType.liters:
          return AppFormatters.formatLiters(v.toDouble());
        case ReportColumnType.money:
          return AppFormatters.formatCurrency(v.toDouble());
        case ReportColumnType.integer:
          return AppFormatters.formatCurrency(v.toDouble(), symbol: '');
        case ReportColumnType.percent:
          return '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')} %';
        case ReportColumnType.text:
        case ReportColumnType.date:
          return v.toString();
      }
    }
    return v.toString();
  }
}

/// Reportes disponibles en el catálogo.
enum ReportKind {
  consolidated,
  producerSummary,
  settlements,
  shiftComparison,
  inactiveProducers,
  corrections;

  String get title => switch (this) {
        ReportKind.consolidated => 'Consolidado de recepción',
        ReportKind.producerSummary => 'Resumen por productor',
        ReportKind.settlements => 'Liquidaciones y pagos',
        ReportKind.shiftComparison => 'Comparativo mañana / tarde',
        ReportKind.inactiveProducers => 'Productores sin entregas',
        ReportKind.corrections => 'Correcciones y anulaciones',
      };

  String get description => switch (this) {
        ReportKind.consolidated => 'Todas las entregas del período con fecha, jornada y litros.',
        ReportKind.producerSummary => 'Litros, entregas, promedio diario y valor por productor.',
        ReportKind.settlements => 'Comprobantes emitidos, valores y estado de pago.',
        ReportKind.shiftComparison => 'Litros por día separados por jornada de mañana y tarde.',
        ReportKind.inactiveProducers => 'Productores activos que no entregaron leche en el período.',
        ReportKind.corrections => 'Cambios de litros y entregas anuladas, con responsable y motivo.',
      };

  bool get usesProducerFilter =>
      this == ReportKind.consolidated ||
      this == ReportKind.producerSummary ||
      this == ReportKind.settlements ||
      this == ReportKind.shiftComparison ||
      this == ReportKind.corrections;

  bool get usesShiftFilter => this == ReportKind.consolidated;
}

/// Construye los datasets del catálogo (funciones puras).
class ReportCatalog {
  ReportCatalog._();

  static String _shift(String j) => j.toUpperCase() == AppConstants.shiftMorning ? 'Mañana' : 'Tarde';

  static String _liters(double v) => AppFormatters.formatLiters(v);

  static double _round3(double v) => SettlementCalculator.roundToThousandths(v);

  static ReportDataset consolidated({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    String? producerId,
    String? shift,
  }) {
    final List<MilkReceptionModel> list = ReportService.filterReceptionsForReport(
      period: period,
      receptions: receptions,
      filterProducerId: producerId,
    ).where((MilkReceptionModel r) => shift == null || r.jornada.toUpperCase() == shift).toList();
    final double total = _round3(list.fold<double>(0, (double s, MilkReceptionModel r) => s + r.litros));
    final int producers = list.map((MilkReceptionModel r) => r.productorId).toSet().length;
    final int days = list.map((MilkReceptionModel r) => r.fechaEntrega).toSet().length;
    return ReportDataset(
      kind: ReportKind.consolidated,
      title: ReportKind.consolidated.title,
      periodLabel: period.label,
      subtitle: shift == null ? null : 'Jornada: ${_shift(shift)}',
      columns: const <ReportColumn>[
        ReportColumn('Fecha', type: ReportColumnType.date),
        ReportColumn('Hora', type: ReportColumnType.date, flex: 1),
        ReportColumn('Código', flex: 1),
        ReportColumn('Productor', flex: 4),
        ReportColumn('Jornada', flex: 1),
        ReportColumn('Litros', type: ReportColumnType.liters),
        ReportColumn('Estado'),
      ],
      rows: <List<Object?>>[
        for (final MilkReceptionModel r in list)
          <Object?>[
            AppFormatters.formatIsoDate(r.fechaEntrega),
            r.horaEntrega.length >= 5 ? r.horaEntrega.substring(0, 5) : r.horaEntrega,
            r.codigoAsociadoSnap,
            r.nombreProductorSnap,
            _shift(r.jornada),
            r.litros,
            r.isLiquidada ? 'Liquidada' : 'Por liquidar',
          ],
      ],
      totals: <Object?>['Total', null, null, '${list.length} entregas', null, total, null],
      kpis: <ReportKpi>[
        ReportKpi('Litros recibidos', _liters(total)),
        ReportKpi('Entregas', '${list.length}'),
        ReportKpi('Productores', '$producers'),
        ReportKpi('Promedio por día', _liters(days == 0 ? 0 : total / days), hint: '$days ${days == 1 ? 'día' : 'días'} con entregas'),
      ],
    );
  }

  static ReportDataset producerSummary({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    required List<SettlementModel> settlements,
    required double activePricePerLiter,
    String? producerId,
  }) {
    final List<ProducerProductionSummary> list = ReportService.buildProducerSummaries(
      period: period,
      receptions: receptions,
      producers: producers,
      settlements: settlements,
      activePricePerLiter: activePricePerLiter,
      filterProducerId: producerId,
    );
    final double liters =
        _round3(list.fold<double>(0, (double s, ProducerProductionSummary p) => s + p.totalLiters));
    final double value =
        list.fold<double>(0, (double s, ProducerProductionSummary p) => s + p.totalEconomicValue);
    final int deliveries = list.fold<int>(0, (int s, ProducerProductionSummary p) => s + p.deliveryCount);
    final double avg = list.isEmpty
        ? 0
        : list.fold<double>(0, (double s, ProducerProductionSummary p) => s + p.dailyAverageLiters) /
            list.length;
    return ReportDataset(
      kind: ReportKind.producerSummary,
      title: ReportKind.producerSummary.title,
      periodLabel: period.label,
      subtitle: activePricePerLiter > 0
          ? 'Lo no liquidado se valora con la tarifa vigente de ${AppFormatters.formatCurrency(activePricePerLiter)}/L'
          : null,
      columns: const <ReportColumn>[
        ReportColumn('Código', flex: 1),
        ReportColumn('Productor', flex: 4),
        ReportColumn('Vereda'),
        ReportColumn('Entregas', type: ReportColumnType.integer, flex: 1),
        ReportColumn('Mañana', type: ReportColumnType.liters),
        ReportColumn('Tarde', type: ReportColumnType.liters),
        ReportColumn('Total', type: ReportColumnType.liters),
        ReportColumn('Prom./día', type: ReportColumnType.liters),
        ReportColumn('Valor', type: ReportColumnType.money),
      ],
      rows: <List<Object?>>[
        for (final ProducerProductionSummary s in list)
          <Object?>[
            s.codigoAsociado,
            s.nombreProductor,
            s.vereda,
            s.deliveryCount,
            s.morningLiters,
            s.afternoonLiters,
            s.totalLiters,
            s.dailyAverageLiters,
            s.totalEconomicValue,
          ],
      ],
      totals: <Object?>[
        'Total',
        '${list.length} productores',
        null,
        deliveries,
        _round3(list.fold<double>(0, (double s, ProducerProductionSummary p) => s + p.morningLiters)),
        _round3(list.fold<double>(0, (double s, ProducerProductionSummary p) => s + p.afternoonLiters)),
        liters,
        null,
        SettlementCalculator.roundToCents(value),
      ],
      kpis: <ReportKpi>[
        ReportKpi('Productores con entregas', '${list.length}'),
        ReportKpi('Litros', _liters(liters), hint: '$deliveries entregas'),
        ReportKpi('Promedio diario por productor', _liters(avg)),
        ReportKpi('Valor del período', AppFormatters.formatCurrency(value)),
      ],
    );
  }

  static ReportDataset settlementsReport({
    required QuincenaPeriod period,
    required List<SettlementModel> settlements,
    String? producerId,
  }) {
    final List<SettlementModel> list = ReportService.filterSettlementsForReport(
      period: period,
      settlements: settlements,
      filterProducerId: producerId,
    );
    final double total = list.fold<double>(0, (double s, SettlementModel x) => s + x.valorTotalPagar);
    final List<SettlementModel> paidList = list.where((SettlementModel x) => x.isPagada).toList();
    final double paid = paidList.fold<double>(0, (double s, SettlementModel x) => s + x.valorTotalPagar);
    final double liters = _round3(list.fold<double>(0, (double s, SettlementModel x) => s + x.totalLitros));
    return ReportDataset(
      kind: ReportKind.settlements,
      title: ReportKind.settlements.title,
      periodLabel: period.label,
      emptyMessage: 'No hay comprobantes emitidos que coincidan con el período.',
      columns: const <ReportColumn>[
        ReportColumn('Comprobante'),
        ReportColumn('Productor', flex: 4),
        ReportColumn('Quincena', flex: 3),
        ReportColumn('Entregas', type: ReportColumnType.integer, flex: 1),
        ReportColumn('Litros', type: ReportColumnType.liters),
        ReportColumn('Tarifa', type: ReportColumnType.money),
        ReportColumn('Valor', type: ReportColumnType.money),
        ReportColumn('Estado', flex: 1),
        ReportColumn('Fecha de pago', type: ReportColumnType.date),
      ],
      rows: <List<Object?>>[
        for (final SettlementModel s in list)
          <Object?>[
            s.numeroComprobante,
            s.nombreProductorSnap,
            s.quincenaLabel,
            s.cantidadEntregas,
            s.totalLitros,
            s.precioLitroAplicado,
            s.valorTotalPagar,
            s.isPagada ? 'Pagada' : 'Pendiente',
            s.fechaPago == null ? '' : AppFormatters.formatDate(s.fechaPago!),
          ],
      ],
      totals: <Object?>[
        'Total',
        '${list.length} comprobantes',
        null,
        list.fold<int>(0, (int s, SettlementModel x) => s + x.cantidadEntregas),
        liters,
        null,
        SettlementCalculator.roundToCents(total),
        null,
        null,
      ],
      kpis: <ReportKpi>[
        ReportKpi('Comprobantes', '${list.length}', hint: _liters(liters)),
        ReportKpi('Valor liquidado', AppFormatters.formatCurrency(total)),
        ReportKpi('Pagado', AppFormatters.formatCurrency(paid), hint: '${paidList.length} pagados'),
        ReportKpi('Pendiente de pago', AppFormatters.formatCurrency(total - paid),
            hint: '${list.length - paidList.length} pendientes'),
      ],
    );
  }

  static ReportDataset shiftComparison({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    String? producerId,
  }) {
    final List<MilkReceptionModel> list = ReportService.filterReceptionsForReport(
      period: period,
      receptions: receptions,
      filterProducerId: producerId,
    );
    // Por día: [ml mañana, entregas mañana, ml tarde, entregas tarde]
    final Map<String, List<int>> byDay = <String, List<int>>{};
    for (final MilkReceptionModel r in list) {
      final List<int> acc = byDay.putIfAbsent(r.fechaEntrega, () => <int>[0, 0, 0, 0]);
      final int ml = (r.litros * 1000).round();
      if (r.jornada.toUpperCase() == AppConstants.shiftMorning) {
        acc[0] += ml;
        acc[1]++;
      } else {
        acc[2] += ml;
        acc[3]++;
      }
    }
    final List<String> days = byDay.keys.toList()..sort();
    int mlM = 0;
    int mlT = 0;
    int nM = 0;
    int nT = 0;
    String? peakDay;
    int peak = -1;
    final List<List<Object?>> rows = <List<Object?>>[];
    for (final String d in days) {
      final List<int> a = byDay[d]!;
      mlM += a[0];
      mlT += a[2];
      nM += a[1];
      nT += a[3];
      final int dayTotal = a[0] + a[2];
      if (dayTotal > peak) {
        peak = dayTotal;
        peakDay = d;
      }
      rows.add(<Object?>[
        AppFormatters.formatIsoDate(d),
        a[0] / 1000,
        a[1],
        a[2] / 1000,
        a[3],
        dayTotal / 1000,
        dayTotal == 0 ? 0 : a[0] / dayTotal,
      ]);
    }
    final int all = mlM + mlT;
    return ReportDataset(
      kind: ReportKind.shiftComparison,
      title: ReportKind.shiftComparison.title,
      periodLabel: period.label,
      columns: const <ReportColumn>[
        ReportColumn('Fecha', type: ReportColumnType.date),
        ReportColumn('Litros mañana', type: ReportColumnType.liters),
        ReportColumn('Entregas mañana', type: ReportColumnType.integer),
        ReportColumn('Litros tarde', type: ReportColumnType.liters),
        ReportColumn('Entregas tarde', type: ReportColumnType.integer),
        ReportColumn('Total', type: ReportColumnType.liters),
        ReportColumn('% mañana', type: ReportColumnType.percent),
      ],
      rows: rows,
      totals: <Object?>['Total', mlM / 1000, nM, mlT / 1000, nT, all / 1000, all == 0 ? 0 : mlM / all],
      kpis: <ReportKpi>[
        ReportKpi('Jornada mañana', _liters(mlM / 1000), hint: '$nM entregas'),
        ReportKpi('Jornada tarde', _liters(mlT / 1000), hint: '$nT entregas'),
        ReportKpi('Participación mañana', all == 0 ? '—' : '${(mlM * 100 / all).toStringAsFixed(0)} %'),
        ReportKpi(
          'Día de mayor acopio',
          peakDay == null ? '—' : AppFormatters.formatIsoDate(peakDay),
          hint: peak <= 0 ? null : _liters(peak / 1000),
        ),
      ],
    );
  }

  static ReportDataset inactiveProducers({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    DateTime? today,
  }) {
    final Set<String> delivered = <String>{
      for (final MilkReceptionModel r in receptions)
        if (!r.anulado && period.containsIsoDate(r.fechaEntrega)) r.productorId,
    };
    final Map<String, String> lastDelivery = <String, String>{};
    for (final MilkReceptionModel r in receptions) {
      if (r.anulado) continue;
      final String? prev = lastDelivery[r.productorId];
      if (prev == null || r.fechaEntrega.compareTo(prev) > 0) lastDelivery[r.productorId] = r.fechaEntrega;
    }
    final List<ProducerModel> active = producers.where((ProducerModel p) => p.isActivo).toList();
    final List<ProducerModel> missing =
        active.where((ProducerModel p) => !delivered.contains(p.productorId)).toList()
          ..sort((ProducerModel a, ProducerModel b) {
            final String la = lastDelivery[a.productorId] ?? '';
            final String lb = lastDelivery[b.productorId] ?? '';
            final int c = la.compareTo(lb);
            return c != 0 ? c : a.nombreCompleto.compareTo(b.nombreCompleto);
          });
    final DateTime now = today ?? DateTime.now();
    final DateTime todayDate = DateTime(now.year, now.month, now.day);
    final List<List<Object?>> rows = <List<Object?>>[];
    for (final ProducerModel p in missing) {
      final String? last = lastDelivery[p.productorId];
      final DateTime? lastDate = last == null ? null : DateTime.tryParse(last);
      rows.add(<Object?>[
        p.codigoAsociado,
        p.nombreCompleto,
        p.cedula,
        p.vereda,
        p.telefono,
        last == null ? 'Nunca' : AppFormatters.formatIsoDate(last),
        lastDate == null ? null : todayDate.difference(lastDate).inDays,
      ]);
    }
    return ReportDataset(
      kind: ReportKind.inactiveProducers,
      title: ReportKind.inactiveProducers.title,
      periodLabel: period.label,
      emptyMessage: 'Todos los productores activos entregaron leche en este período.',
      columns: const <ReportColumn>[
        ReportColumn('Código', flex: 1),
        ReportColumn('Productor', flex: 4),
        ReportColumn('Cédula'),
        ReportColumn('Vereda'),
        ReportColumn('Teléfono'),
        ReportColumn('Última entrega', type: ReportColumnType.date),
        ReportColumn('Días sin entregar', type: ReportColumnType.integer),
      ],
      rows: rows,
      kpis: <ReportKpi>[
        ReportKpi('Productores activos', '${active.length}'),
        ReportKpi('Sin entregas', '${missing.length}'),
        ReportKpi('Con entregas', '${active.length - missing.length}'),
        ReportKpi(
          'Participación',
          active.isEmpty
              ? '—'
              : '${((active.length - missing.length) * 100 / active.length).toStringAsFixed(0)} %',
        ),
      ],
    );
  }

  /// Correcciones de litros y anulaciones. Usa la bitácora cuando está
  /// disponible y, en su defecto, el estado de las entregas.
  static ReportDataset corrections({
    required QuincenaPeriod period,
    required List<MilkReceptionModel> receptions,
    required List<AuditLogModel> auditLogs,
    Map<String, String> userNames = const <String, String>{},
    String? producerId,
  }) {
    final Map<String, MilkReceptionModel> byId = <String, MilkReceptionModel>{
      for (final MilkReceptionModel r in receptions) r.recepcionId: r,
    };
    String userName(String uid) {
      final String? known = userNames[uid];
      if (known != null) return known;
      if (uid.isEmpty) return '—';
      return 'Usuario ${uid.length > 6 ? uid.substring(0, 6) : uid}…';
    }

    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

    final List<_CorrectionRow> items = <_CorrectionRow>[];
    final Set<String> annulledLogged = <String>{};
    for (final AuditLogModel log in auditLogs) {
      if (log.entidadAfectada != AppConstants.receptionsCollection) continue;
      if (log.accion != 'EDITAR' && log.accion != 'ANULAR') continue;
      final String localIso = AppFormatters.toIsoDate(log.timestamp.toLocal());
      if (!period.containsIsoDate(localIso)) continue;
      final Map<String, dynamic> snap = <String, dynamic>{...?log.valorAnterior, ...?log.valorNuevo};
      final MilkReceptionModel? r = byId[log.registroId];
      final String pid = (snap['productorId'] ?? r?.productorId ?? '').toString();
      if (producerId != null && producerId.isNotEmpty && pid != producerId) continue;
      final bool annul = log.accion == 'ANULAR';
      if (annul) annulledLogged.add(log.registroId);
      final double? before = asDouble(log.valorAnterior?['litros']);
      final double? after = asDouble(log.valorNuevo?['litros']);
      items.add(_CorrectionRow(
        when: log.timestamp.toLocal(),
        annul: annul,
        producer: (snap['nombreProductorSnap'] ?? r?.nombreProductorSnap ?? '—').toString(),
        delivery: _deliveryLabel(
          (snap['jornada'] ?? r?.jornada)?.toString(),
          (snap['fechaEntrega'] ?? r?.fechaEntrega)?.toString(),
        ),
        before: before ?? (annul ? r?.litros : null),
        after: annul ? 0 : (after ?? r?.litros),
        user: userName(log.usuarioUid),
        reason: log.motivo ?? '',
      ));
    }
    // Anulaciones sin registro de bitácora disponible.
    for (final MilkReceptionModel r in receptions) {
      if (!r.anulado || annulledLogged.contains(r.recepcionId)) continue;
      if (!period.containsIsoDate(r.fechaEntrega)) continue;
      if (producerId != null && producerId.isNotEmpty && r.productorId != producerId) continue;
      items.add(_CorrectionRow(
        when: (r.updatedAt ?? r.createdAt).toLocal(),
        annul: true,
        producer: r.nombreProductorSnap,
        delivery: _deliveryLabel(r.jornada, r.fechaEntrega),
        before: r.litros,
        after: 0,
        user: userName(r.updatedByUid ?? ''),
        reason: r.motivoAnulacion ?? '',
      ));
    }
    items.sort((_CorrectionRow a, _CorrectionRow b) => b.when.compareTo(a.when));
    final int annulCount = items.where((_CorrectionRow i) => i.annul).length;
    final double annulLiters = items
        .where((_CorrectionRow i) => i.annul)
        .fold<double>(0, (double s, _CorrectionRow i) => s + (i.before ?? 0));
    final double netAdjust = items
        .where((_CorrectionRow i) => !i.annul && i.before != null && i.after != null)
        .fold<double>(0, (double s, _CorrectionRow i) => s + (i.after! - i.before!));
    return ReportDataset(
      kind: ReportKind.corrections,
      title: ReportKind.corrections.title,
      periodLabel: period.label,
      emptyMessage: 'No hubo correcciones ni anulaciones en este período.',
      columns: const <ReportColumn>[
        ReportColumn('Fecha y hora', type: ReportColumnType.date),
        ReportColumn('Tipo', flex: 1),
        ReportColumn('Productor', flex: 3),
        ReportColumn('Entrega'),
        ReportColumn('Antes', type: ReportColumnType.liters),
        ReportColumn('Después', type: ReportColumnType.liters),
        ReportColumn('Responsable', flex: 3),
        ReportColumn('Motivo', flex: 4),
      ],
      rows: <List<Object?>>[
        for (final _CorrectionRow i in items)
          <Object?>[
            AppFormatters.formatDateTime(i.when, useLocal: false),
            i.annul ? 'Anulación' : 'Corrección',
            i.producer,
            i.delivery,
            i.before,
            i.annul ? null : i.after,
            i.user,
            i.reason,
          ],
      ],
      kpis: <ReportKpi>[
        ReportKpi('Correcciones', '${items.length - annulCount}'),
        ReportKpi('Anulaciones', '$annulCount'),
        ReportKpi('Litros anulados', _liters(annulLiters)),
        ReportKpi('Ajuste neto por correcciones', '${netAdjust >= 0 ? '+' : '−'}${_liters(netAdjust.abs())}'),
      ],
    );
  }

  static String _deliveryLabel(String? jornada, String? fecha) {
    final List<String> parts = <String>[
      if (jornada != null && jornada.isNotEmpty) _shift(jornada),
      if (fecha != null && fecha.isNotEmpty) AppFormatters.formatIsoDate(fecha),
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _CorrectionRow {
  const _CorrectionRow({
    required this.when,
    required this.annul,
    required this.producer,
    required this.delivery,
    required this.before,
    required this.after,
    required this.user,
    required this.reason,
  });

  final DateTime when;
  final bool annul;
  final String producer;
  final String delivery;
  final double? before;
  final double? after;
  final String user;
  final String reason;
}
