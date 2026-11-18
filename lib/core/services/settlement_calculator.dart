import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';

/// Definición de período de liquidación quincenal o rango personalizado (`YYYY-MM-DD`).
class QuincenaPeriod {
  const QuincenaPeriod({
    required this.startDate,
    required this.endDate,
    required this.label,
  });

  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String label;

  static const List<String> _monthShortNames = <String>[
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];

  /// Construye quincena estándar (`1–15` o `16–fin de mes`) de acuerdo con el calendario real.
  factory QuincenaPeriod.forHalfMonth({
    required int year,
    required int month,
    required bool firstHalf,
  }) {
    final int lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final int startDay = firstHalf ? 1 : 16;
    final int endDay = firstHalf ? 15 : lastDayOfMonth;

    final String startIso = AppFormatters.toIsoDate(
      DateTime(year, month, startDay),
    );
    final String endIso = AppFormatters.toIsoDate(
      DateTime(year, month, endDay),
    );
    final String monthName = _monthShortNames[(month - 1).clamp(0, 11)];
    final String ordinal = firstHalf ? '1ra Quincena' : '2da Quincena';

    return QuincenaPeriod(
      startDate: startIso,
      endDate: endIso,
      label: '$ordinal $monthName $year',
    );
  }

  /// Quincena en curso para la fecha dada.
  factory QuincenaPeriod.currentForDate(DateTime date) =>
      QuincenaPeriod.forHalfMonth(
        year: date.year,
        month: date.month,
        firstHalf: date.day <= 15,
      );

  /// Quincena inmediatamente anterior a la fecha dada (ideal para ejecutar cierres).
  factory QuincenaPeriod.previousForDate(DateTime date) {
    if (date.day > 15) {
      return QuincenaPeriod.forHalfMonth(
        year: date.year,
        month: date.month,
        firstHalf: true,
      );
    }
    final int prevMonth = date.month == 1 ? 12 : date.month - 1;
    final int prevYear = date.month == 1 ? date.year - 1 : date.year;
    return QuincenaPeriod.forHalfMonth(
      year: prevYear,
      month: prevMonth,
      firstHalf: false,
    );
  }

  /// Rango personalizado validado de fechas.
  factory QuincenaPeriod.custom(DateTime start, DateTime end) {
    final DateTime orderedStart = start.isAfter(end) ? end : start;
    final DateTime orderedEnd = start.isAfter(end) ? start : end;
    final String startIso = AppFormatters.toIsoDate(orderedStart);
    final String endIso = AppFormatters.toIsoDate(orderedEnd);
    return QuincenaPeriod(
      startDate: startIso,
      endDate: endIso,
      label:
          '${AppFormatters.formatIsoDate(startIso)} - ${AppFormatters.formatIsoDate(endIso)}',
    );
  }

  bool containsIsoDate(String fechaEntrega) {
    final String normalized = fechaEntrega.trim();
    if (normalized.isEmpty) return false;
    return normalized.compareTo(startDate) >= 0 &&
        normalized.compareTo(endDate) <= 0;
  }

  bool overlapsWith(String otherStart, String otherEnd) {
    final String aStart = otherStart.trim();
    final String aEnd = otherEnd.trim();
    if (aStart.isEmpty || aEnd.isEmpty) return false;
    return aStart.compareTo(endDate) <= 0 && aEnd.compareTo(startDate) >= 0;
  }
}

/// Candidato individual de liquidación por productor para previsualización de cierre.
class SettlementCandidate {
  const SettlementCandidate({
    required this.productorId,
    required this.codigoAsociado,
    required this.nombreProductor,
    required this.cedula,
    required this.morningLiters,
    required this.afternoonLiters,
    required this.totalLiters,
    required this.precioPorLitro,
    required this.valorTotalPagar,
    required this.receptions,
  });

  final String productorId;
  final String codigoAsociado;
  final String nombreProductor;
  final String cedula;
  final double morningLiters;
  final double afternoonLiters;
  final double totalLiters;
  final double precioPorLitro;
  final double valorTotalPagar;
  final List<MilkReceptionModel> receptions;

  int get deliveryCount => receptions.length;
}

/// Resultado consolidado de previsualización de un corte quincenal.
class SettlementPreviewResult {
  const SettlementPreviewResult({
    required this.period,
    required this.precioPorLitro,
    required this.candidates,
    required this.pendingSyncReceptions,
    required this.excludedAnuladasCount,
    required this.alreadySettledDeliveriesCount,
    required this.alreadySettledProducerIds,
  });

  final QuincenaPeriod period;
  final double precioPorLitro;
  final List<SettlementCandidate> candidates;
  final List<MilkReceptionModel> pendingSyncReceptions;
  final int excludedAnuladasCount;
  final int alreadySettledDeliveriesCount;
  final Set<String> alreadySettledProducerIds;

  double get totalLiters => SettlementCalculator.roundToThousandths(
        candidates.fold<double>(
          0,
          (double sum, SettlementCandidate c) => sum + c.totalLiters,
        ),
      );

  double get totalAmountToPay => SettlementCalculator.roundToCents(
        candidates.fold<double>(
          0,
          (double sum, SettlementCandidate c) => sum + c.valorTotalPagar,
        ),
      );

  int get totalDeliveries => candidates.fold<int>(
        0,
        (int sum, SettlementCandidate c) => sum + c.deliveryCount,
      );

  bool get hasPendingSync => pendingSyncReceptions.isNotEmpty;
  bool get hasEligibleCandidates => candidates.isNotEmpty;
}

/// Motor matemático determinista de liquidación quincenal (`RF-13`, `CHK-04`).
/// Trabaja con aritmética de punto fijo para evitar derivas de coma flotante.
class SettlementCalculator {
  SettlementCalculator._();

  static double roundToCents(double value) =>
      (value * 100).roundToDouble() / 100;

  static double roundToThousandths(double value) =>
      (value * 1000).roundToDouble() / 1000;

  /// Multiplica `totalLiters * pricePerLiter` con exactitud determinista al centavo.
  static double calculateTotalAmount({
    required double totalLiters,
    required double pricePerLiter,
  }) {
    final int thousandths = (totalLiters * 1000).round();
    final int rateCents = (pricePerLiter * 100).round();
    final int totalCents = ((thousandths * rateCents) / 1000).round();
    return totalCents / 100.0;
  }

  /// Agrupa recepciones elegibles del período por productor, excluyendo anuladas,
  /// no sincronizadas, entregas ya liquidadas y productores ya cerrados en ese rango.
  static SettlementPreviewResult buildPreview({
    required QuincenaPeriod period,
    required double pricePerLiter,
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    required List<SettlementModel> existingSettlements,
  }) {
    final Map<String, ProducerModel> producerById = <String, ProducerModel>{
      for (final ProducerModel p in producers) p.productorId: p,
    };

    final Set<String> settledProducersInRange = existingSettlements
        .where(
          (SettlementModel s) => period.overlapsWith(s.periodoInicio, s.periodoFin),
        )
        .map((SettlementModel s) => s.productorId.trim())
        .toSet();

    int anuladasCount = 0;
    int settledDeliveriesCount = 0;
    final List<MilkReceptionModel> unsyncedInRange = <MilkReceptionModel>[];
    final Map<String, List<MilkReceptionModel>> groupedByProducer =
        <String, List<MilkReceptionModel>>{};

    for (final MilkReceptionModel reception in receptions) {
      if (!period.containsIsoDate(reception.fechaEntrega)) {
        continue;
      }
      if (reception.anulado) {
        anuladasCount++;
        continue;
      }
      if (reception.isLiquidada) {
        settledDeliveriesCount++;
        continue;
      }
      if (!reception.isSynced ||
          reception.syncStatus != AppConstants.syncSynced) {
        unsyncedInRange.add(reception);
        continue;
      }
      if (settledProducersInRange.contains(reception.productorId.trim())) {
        // Previene doble liquidación sobre el mismo rango de fechas.
        continue;
      }

      groupedByProducer
          .putIfAbsent(reception.productorId, () => <MilkReceptionModel>[])
          .add(reception);
    }

    final List<SettlementCandidate> candidates = <SettlementCandidate>[];
    final double normalizedPrice = roundToCents(pricePerLiter);

    for (final MapEntry<String, List<MilkReceptionModel>> entry
        in groupedByProducer.entries) {
      final List<MilkReceptionModel> items = List<MilkReceptionModel>.from(
        entry.value,
      )..sort((MilkReceptionModel a, MilkReceptionModel b) {
          final int dateCmp = a.fechaEntrega.compareTo(b.fechaEntrega);
          if (dateCmp != 0) return dateCmp;
          return a.horaEntrega.compareTo(b.horaEntrega);
        });

      int morningThousandths = 0;
      int afternoonThousandths = 0;
      for (final MilkReceptionModel item in items) {
        final int thousandths = (item.litros * 1000).round();
        if (item.jornada.toUpperCase() == AppConstants.shiftMorning) {
          morningThousandths += thousandths;
        } else {
          afternoonThousandths += thousandths;
        }
      }

      final int totalThousandths = morningThousandths + afternoonThousandths;
      if (totalThousandths <= 0) continue;

      final double morningLiters = morningThousandths / 1000.0;
      final double afternoonLiters = afternoonThousandths / 1000.0;
      final double totalLiters = totalThousandths / 1000.0;
      final double totalPay = calculateTotalAmount(
        totalLiters: totalLiters,
        pricePerLiter: normalizedPrice,
      );

      final ProducerModel? producer = producerById[entry.key];
      final MilkReceptionModel sample = items.first;

      candidates.add(
        SettlementCandidate(
          productorId: entry.key,
          codigoAsociado: producer?.codigoAsociado ??
              (sample.codigoAsociadoSnap.isNotEmpty
                  ? sample.codigoAsociadoSnap
                  : 'SIN-COD'),
          nombreProductor:
              producer?.nombreCompleto ?? sample.nombreProductorSnap,
          cedula: producer?.cedula ?? 'No registrada',
          morningLiters: morningLiters,
          afternoonLiters: afternoonLiters,
          totalLiters: totalLiters,
          precioPorLitro: normalizedPrice,
          valorTotalPagar: totalPay,
          receptions: items,
        ),
      );
    }

    candidates.sort(
      (SettlementCandidate a, SettlementCandidate b) => a.nombreProductor
          .toLowerCase()
          .compareTo(b.nombreProductor.toLowerCase()),
    );

    return SettlementPreviewResult(
      period: period,
      precioPorLitro: normalizedPrice,
      candidates: candidates,
      pendingSyncReceptions: unsyncedInRange,
      excludedAnuladasCount: anuladasCount,
      alreadySettledDeliveriesCount: settledDeliveriesCount,
      alreadySettledProducerIds: settledProducersInRange,
    );
  }

  /// Genera el siguiente consecutivo `COMP-YYYY-XXXX` evitando colisiones.
  static String nextComprobanteNumber({
    required int year,
    required List<SettlementModel> existingSettlements,
    required int offset,
  }) {
    final String prefix = 'COMP-$year-';
    int maxSeq = 0;
    for (final SettlementModel s in existingSettlements) {
      final String code = s.numeroComprobante.trim().toUpperCase();
      if (!code.startsWith(prefix)) continue;
      final int? parsed = int.tryParse(code.substring(prefix.length));
      if (parsed != null && parsed > maxSeq) {
        maxSeq = parsed;
      }
    }
    final int next = maxSeq + 1 + offset;
    return '$prefix${next.toString().padLeft(4, '0')}';
  }

  /// Calcula huella criptográfica SHA-256 íntegra acorde con la Ley 527 de 1999.
  static String computeIntegrityHash({
    required String liquidacionId,
    required String numeroComprobante,
    required String productorId,
    required String cedula,
    required String periodoInicio,
    required String periodoFin,
    required double totalLitros,
    required int cantidadEntregas,
    required double precioLitroAplicado,
    required double valorTotalPagar,
    required List<String> recepcionIds,
  }) {
    final List<String> sortedIds = List<String>.from(recepcionIds)..sort();
    final String canonicalPayload = <String>[
      liquidacionId.trim(),
      numeroComprobante.trim(),
      productorId.trim(),
      cedula.trim(),
      periodoInicio.trim(),
      periodoFin.trim(),
      (totalLitros * 1000).round().toString(),
      cantidadEntregas.toString(),
      (precioLitroAplicado * 100).round().toString(),
      (valorTotalPagar * 100).round().toString(),
      sortedIds.join(','),
    ].join('|');

    return sha256.convert(utf8.encode(canonicalPayload)).toString();
  }
}
