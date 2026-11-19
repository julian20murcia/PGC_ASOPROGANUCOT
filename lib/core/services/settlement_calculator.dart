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

  /// Clave de orden alfabético sin tildes ni mayúsculas ("Álvarez" < "Zuluaga").
  static String sortKey(String text) {
    const String from = 'áàäâéèëêíìïîóòöôúùüûñç';
    const String to = 'aaaaeeeeiiiioooouuuunc';
    final StringBuffer sb = StringBuffer();
    for (final int rune in text.toLowerCase().trim().runes) {
      final String ch = String.fromCharCode(rune);
      final int idx = from.indexOf(ch);
      sb.write(idx >= 0 ? to[idx] : ch);
    }
    return sb.toString();
  }

  /// Código corto de verificación (primeros 12 caracteres de la huella SHA-256
  /// agrupados), útil para validar un comprobante impreso por teléfono.
  static String verificationCode(String hash) {
    final String clean = hash.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (clean.length < 12) return clean.isEmpty ? 'N/D' : clean;
    return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}';
  }
}

/// Litros de un día para un productor, separados por jornada (milésimas de litro).
class DailyShiftCell {
  const DailyShiftCell({this.morningThousandths = 0, this.afternoonThousandths = 0});

  final int morningThousandths;
  final int afternoonThousandths;

  double get morning => morningThousandths / 1000.0;
  double get afternoon => afternoonThousandths / 1000.0;
  double get total => (morningThousandths + afternoonThousandths) / 1000.0;
  bool get isEmpty => morningThousandths == 0 && afternoonThousandths == 0;

  DailyShiftCell add({required bool morning, required int thousandths}) =>
      DailyShiftCell(
        morningThousandths: morningThousandths + (morning ? thousandths : 0),
        afternoonThousandths: afternoonThousandths + (morning ? 0 : thousandths),
      );
}

/// Fila de la matriz de registros diarios (un productor).
class DailyMatrixRow {
  DailyMatrixRow({
    required this.productorId,
    required this.codigo,
    required this.nombre,
    required this.cells,
  });

  final String productorId;
  final String codigo;
  final String nombre;

  /// Día ISO (`YYYY-MM-DD`) → litros mañana/tarde.
  final Map<String, DailyShiftCell> cells;

  DailyShiftCell cell(String isoDay) => cells[isoDay] ?? const DailyShiftCell();

  int get morningThousandths => cells.values
      .fold<int>(0, (int s, DailyShiftCell c) => s + c.morningThousandths);
  int get afternoonThousandths => cells.values
      .fold<int>(0, (int s, DailyShiftCell c) => s + c.afternoonThousandths);

  double get totalMorning => morningThousandths / 1000.0;
  double get totalAfternoon => afternoonThousandths / 1000.0;
  double get total => (morningThousandths + afternoonThousandths) / 1000.0;
  int get deliveryDays => cells.values.where((DailyShiftCell c) => !c.isEmpty).length;
}

/// Matriz productores × días del período (M/T) con totales por fila y columna.
///
/// Toda la aritmética se hace en milésimas de litro (enteros) para que los
/// totales coincidan exactamente con la liquidación.
class DailyDeliveryMatrix {
  DailyDeliveryMatrix._({required this.days, required this.rows});

  /// Máximo de días que se representan (protege contra rangos absurdos).
  static const int maxDays = 62;

  final List<String> days;
  final List<DailyMatrixRow> rows;

  /// Construye la matriz con las recepciones válidas (no anuladas) del rango.
  ///
  /// [producerOrder] fija filas (incluso sin entregas) y su orden; los
  /// productores con entregas que no estén en la lista se agregan al final.
  static DailyDeliveryMatrix build({
    required String startIso,
    required String endIso,
    required List<MilkReceptionModel> receptions,
    List<({String productorId, String codigo, String nombre})> producerOrder =
        const <({String productorId, String codigo, String nombre})>[],
  }) {
    final List<String> days = daysBetween(startIso, endIso);
    final Set<String> daySet = days.toSet();
    final Map<String, DailyMatrixRow> byId = <String, DailyMatrixRow>{};
    for (final ({String productorId, String codigo, String nombre}) p in producerOrder) {
      byId.putIfAbsent(
        p.productorId,
        () => DailyMatrixRow(
          productorId: p.productorId,
          codigo: p.codigo,
          nombre: p.nombre,
          cells: <String, DailyShiftCell>{},
        ),
      );
    }
    final List<String> extraOrder = <String>[];
    for (final MilkReceptionModel r in receptions) {
      if (r.anulado) continue;
      final String day = r.fechaEntrega.trim();
      if (!daySet.contains(day)) continue;
      final int thousandths = (r.litros * 1000).round();
      if (thousandths <= 0) continue;
      final DailyMatrixRow row = byId.putIfAbsent(r.productorId, () {
        extraOrder.add(r.productorId);
        return DailyMatrixRow(
          productorId: r.productorId,
          codigo: r.codigoAsociadoSnap.isEmpty ? 'SIN-COD' : r.codigoAsociadoSnap,
          nombre: r.nombreProductorSnap,
          cells: <String, DailyShiftCell>{},
        );
      });
      final bool morning = r.jornada.toUpperCase() == AppConstants.shiftMorning;
      row.cells[day] = row.cell(day).add(morning: morning, thousandths: thousandths);
    }
    final List<DailyMatrixRow> ordered = <DailyMatrixRow>[];
    final Set<String> seen = <String>{};
    for (final ({String productorId, String codigo, String nombre}) p in producerOrder) {
      if (seen.add(p.productorId)) ordered.add(byId[p.productorId]!);
    }
    final List<DailyMatrixRow> extras = <DailyMatrixRow>[
      for (final String id in extraOrder)
        if (!seen.contains(id)) byId[id]!,
    ]..sort((DailyMatrixRow a, DailyMatrixRow b) =>
        SettlementCalculator.sortKey(a.nombre).compareTo(SettlementCalculator.sortKey(b.nombre)));
    return DailyDeliveryMatrix._(days: days, rows: <DailyMatrixRow>[...ordered, ...extras]);
  }

  /// Días ISO entre [startIso] y [endIso] (inclusive), máximo [maxDays].
  static List<String> daysBetween(String startIso, String endIso) {
    final DateTime? s = DateTime.tryParse(startIso.trim());
    final DateTime? e = DateTime.tryParse(endIso.trim());
    if (s == null || e == null) return const <String>[];
    DateTime a = DateTime(s.year, s.month, s.day);
    DateTime b = DateTime(e.year, e.month, e.day);
    if (a.isAfter(b)) {
      final DateTime t = a;
      a = b;
      b = t;
    }
    final List<String> out = <String>[];
    DateTime d = a;
    while (!d.isAfter(b) && out.length < maxDays) {
      out.add(AppFormatters.toIsoDate(d));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// Totales por día (columna).
  DailyShiftCell columnTotal(String isoDay) {
    int m = 0;
    int t = 0;
    for (final DailyMatrixRow r in rows) {
      final DailyShiftCell c = r.cell(isoDay);
      m += c.morningThousandths;
      t += c.afternoonThousandths;
    }
    return DailyShiftCell(morningThousandths: m, afternoonThousandths: t);
  }

  int get grandTotalThousandths => rows.fold<int>(
        0,
        (int s, DailyMatrixRow r) => s + r.morningThousandths + r.afternoonThousandths,
      );

  double get grandTotal => grandTotalThousandths / 1000.0;
  double get grandMorning =>
      rows.fold<int>(0, (int s, DailyMatrixRow r) => s + r.morningThousandths) / 1000.0;
  double get grandAfternoon =>
      rows.fold<int>(0, (int s, DailyMatrixRow r) => s + r.afternoonThousandths) / 1000.0;

  /// Días del período sin ninguna entrega registrada.
  List<String> get emptyDays =>
      days.where((String d) => columnTotal(d).isEmpty).toList();
}

/// Liquidaciones cerradas agrupadas por período (`periodoInicio`–`periodoFin`).
class SettlementPeriodGroup {
  SettlementPeriodGroup({
    required this.periodoInicio,
    required this.periodoFin,
    required this.label,
    required List<SettlementModel> settlements,
  }) : settlements = List<SettlementModel>.unmodifiable(
          List<SettlementModel>.from(settlements)
            ..sort((SettlementModel a, SettlementModel b) => SettlementCalculator.sortKey(a.nombreProductorSnap)
                .compareTo(SettlementCalculator.sortKey(b.nombreProductorSnap))),
        );

  final String periodoInicio;
  final String periodoFin;
  final String label;
  final List<SettlementModel> settlements;

  String get key => '${periodoInicio}_$periodoFin';
  int get producerCount => settlements.length;
  int get paidCount => settlements.where((SettlementModel s) => s.isPagada).length;
  int get pendingCount => producerCount - paidCount;
  bool get fullyPaid => producerCount > 0 && pendingCount == 0;
  double get paidRatio => producerCount == 0 ? 0 : paidCount / producerCount;

  int get deliveries =>
      settlements.fold<int>(0, (int s, SettlementModel x) => s + x.cantidadEntregas);

  double get totalLiters =>
      settlements.fold<int>(0, (int s, SettlementModel x) => s + (x.totalLitros * 1000).round()) /
      1000.0;

  double get totalAmount => _sumCents(settlements);
  double get paidAmount =>
      _sumCents(settlements.where((SettlementModel s) => s.isPagada));
  double get pendingAmount =>
      _sumCents(settlements.where((SettlementModel s) => !s.isPagada));

  /// Precio promedio ponderado por litro.
  double get averagePrice =>
      totalLiters <= 0 ? 0 : SettlementCalculator.roundToCents(totalAmount / totalLiters);

  DateTime get closedAt => settlements
      .map((SettlementModel s) => s.fechaLiquidacion)
      .fold<DateTime>(
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        (DateTime a, DateTime b) => b.isAfter(a) ? b : a,
      );

  static double _sumCents(Iterable<SettlementModel> items) =>
      items.fold<int>(0, (int s, SettlementModel x) => s + (x.valorTotalPagar * 100).round()) /
      100.0;

  /// Agrupa y ordena del período más reciente al más antiguo.
  static List<SettlementPeriodGroup> groupAll(List<SettlementModel> settlements) {
    final Map<String, List<SettlementModel>> map = <String, List<SettlementModel>>{};
    for (final SettlementModel s in settlements) {
      map.putIfAbsent('${s.periodoInicio}_${s.periodoFin}', () => <SettlementModel>[]).add(s);
    }
    final List<SettlementPeriodGroup> groups = map.values.map((List<SettlementModel> items) {
      final SettlementModel first = items.first;
      final String label = first.quincenaLabel.trim().isNotEmpty
          ? first.quincenaLabel.trim()
          : '${AppFormatters.formatIsoDate(first.periodoInicio)} - ${AppFormatters.formatIsoDate(first.periodoFin)}';
      return SettlementPeriodGroup(
        periodoInicio: first.periodoInicio,
        periodoFin: first.periodoFin,
        label: label,
        settlements: items,
      );
    }).toList()
      ..sort((SettlementPeriodGroup a, SettlementPeriodGroup b) {
        final int c = b.periodoFin.compareTo(a.periodoFin);
        return c != 0 ? c : b.periodoInicio.compareTo(a.periodoInicio);
      });
    return groups;
  }
}

/// Conversión de valores a letras en español (pesos colombianos).
class SpanishNumberWords {
  SpanishNumberWords._();

  /// Mayor entero soportado (por debajo de mil billones).
  static const int maxSupported = 999999999999999;

  static const List<String> _units = <String>[
    'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
  ];
  static const List<String> _teens = <String>[
    'diez', 'once', 'doce', 'trece', 'catorce', 'quince',
    'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve',
  ];
  static const List<String> _twenties = <String>[
    'veinte', 'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro',
    'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve',
  ];
  static const List<String> _tens = <String>[
    '', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa',
  ];
  static const List<String> _hundreds = <String>[
    '', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos',
    'seiscientos', 'setecientos', 'ochocientos', 'novecientos',
  ];

  /// Entero en letras. [apocope] usa "un"/"veintiún" (antes de un sustantivo).
  static String integer(int n, {bool apocope = false}) {
    if (n < 0) return 'menos ${integer(-n, apocope: apocope)}';
    if (n == 0) return 'cero';
    if (n > maxSupported) return n.toString();
    final List<String> parts = <String>[];
    final int billones = n ~/ 1000000000000;
    int rest = n % 1000000000000;
    if (billones > 0) {
      parts.add(billones == 1 ? 'un billón' : '${_upToMillion(billones, true)} billones');
    }
    final int millones = rest ~/ 1000000;
    rest = rest % 1000000;
    if (millones > 0) {
      parts.add(millones == 1 ? 'un millón' : '${_upToMillion(millones, true)} millones');
    }
    if (rest > 0) parts.add(_upToMillion(rest, apocope));
    return parts.join(' ');
  }

  static String _upToMillion(int n, bool apocope) {
    final int miles = n ~/ 1000;
    final int rest = n % 1000;
    final List<String> parts = <String>[];
    if (miles > 0) parts.add(miles == 1 ? 'mil' : '${_below1000(miles, true)} mil');
    if (rest > 0) parts.add(_below1000(rest, apocope));
    return parts.join(' ');
  }

  static String _below1000(int n, bool apocope) {
    if (n == 100) return 'cien';
    final int h = n ~/ 100;
    final int r = n % 100;
    final List<String> parts = <String>[];
    if (h > 0) parts.add(_hundreds[h]);
    if (r > 0) parts.add(_below100(r, apocope));
    return parts.join(' ');
  }

  static String _below100(int n, bool apocope) {
    if (n < 10) return (n == 1 && apocope) ? 'un' : _units[n];
    if (n < 20) return _teens[n - 10];
    if (n < 30) return (n == 21 && apocope) ? 'veintiún' : _twenties[n - 20];
    final int t = n ~/ 10;
    final int u = n % 10;
    if (u == 0) return _tens[t];
    return '${_tens[t]} y ${(u == 1 && apocope) ? 'un' : _units[u]}';
  }

  /// Valor en pesos colombianos en letras, p. ej. `1850.5` →
  /// "MIL OCHOCIENTOS CINCUENTA PESOS CON CINCUENTA CENTAVOS M/CTE".
  /// Devuelve cadena vacía si el valor no es finito o excede lo soportado.
  static String pesos(double amount) {
    if (!amount.isFinite) return '';
    final double abs = amount.abs();
    if (abs > maxSupported) return '';
    final int totalCents = (abs * 100).round();
    final int whole = totalCents ~/ 100;
    final int cents = totalCents % 100;
    final StringBuffer sb = StringBuffer();
    if (amount < 0 && totalCents > 0) sb.write('menos ');
    if (whole == 1) {
      sb.write('un peso');
    } else {
      sb.write(integer(whole, apocope: true));
      final bool exactMillions = whole >= 1000000 && whole % 1000000 == 0;
      sb.write(exactMillions ? ' de pesos' : ' pesos');
    }
    if (cents > 0) {
      sb.write(' con ');
      sb.write(cents == 1 ? 'un centavo' : '${integer(cents, apocope: true)} centavos');
    }
    sb.write(' M/CTE');
    return sb.toString().toUpperCase();
  }
}
