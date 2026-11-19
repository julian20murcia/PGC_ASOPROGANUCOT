import '../../../core/constants/app_constants.dart';
import '../../../core/services/forecast_service.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';

/// Litros de un día separados por jornada.
class DayTotal {
  const DayTotal(this.day, this.morning, this.afternoon, this.deliveries);
  final DateTime day;
  final double morning;
  final double afternoon;
  final int deliveries;
  double get total => morning + afternoon;
}

class ProducerRank {
  const ProducerRank({
    required this.id,
    required this.name,
    required this.code,
    required this.liters,
    required this.deliveries,
  });
  final String id;
  final String name;
  final String code;
  final double liters;
  final int deliveries;
}

class VeredaShare {
  const VeredaShare(this.name, this.liters, this.producers);
  final String name;
  final double liters;
  final int producers;
}

/// Indicadores de un rango de fechas (y su período anterior) calculados a
/// partir de las recepciones en memoria.
class DashboardMetrics {
  const DashboardMetrics({
    required this.range,
    required this.liters,
    required this.prevLiters,
    required this.deliveries,
    required this.prevDeliveries,
    required this.producersDelivered,
    required this.prevProducersDelivered,
    required this.morning,
    required this.afternoon,
    required this.days,
    required this.prevDays,
    required this.top,
    required this.veredas,
    required this.zeroDays,
    required this.unsyncedInRange,
    required this.elapsedDays,
    required this.prevElapsedDays,
    required this.drops,
  });

  final DateRangeValue range;
  final double liters;
  final double prevLiters;
  final int deliveries;
  final int prevDeliveries;
  final int producersDelivered;
  final int prevProducersDelivered;
  final double morning;
  final double afternoon;
  final List<DayTotal> days;
  final List<DayTotal> prevDays;
  final List<ProducerRank> top;
  final List<VeredaShare> veredas;

  /// Días ya transcurridos del rango sin ninguna entrega.
  final List<DateTime> zeroDays;
  final int unsyncedInRange;

  /// Días del rango hasta hoy (para promedios honestos en rangos en curso).
  final int elapsedDays;
  final int prevElapsedDays;
  final List<ProducerDrop> drops;

  double get dailyAvg => elapsedDays > 0 ? liters / elapsedDays : 0;
  double get prevDailyAvg => prevElapsedDays > 0 ? prevLiters / prevElapsedDays : 0;

  /// Variación relativa (null si no hay base de comparación).
  static double? delta(num current, num previous) {
    if (previous <= 0) return null;
    final double d = (current - previous) / previous;
    return d.isFinite ? d : null;
  }

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static DashboardMetrics compute({
    required List<MilkReceptionModel> receptions,
    required List<ProducerModel> producers,
    required DateRangeValue range,
    required DateTime today,
  }) {
    final DateTime t = _d(today);
    int elapsed(DateRangeValue r) {
      if (r.start.isAfter(t)) return 0;
      final DateTime end = r.end.isAfter(t) ? t : r.end;
      return _daysBetween(r.start, end) + 1;
    }

    // Rango en curso: se compara contra los mismos días transcurridos del
    // período anterior (comparación justa, no 4 días contra 15).
    final int el = elapsed(range);
    final bool inProgress = range.end.isAfter(t) && el > 0;
    final DateRangeValue fullPrev = range.previous;
    final DateRangeValue prev = inProgress
        ? DateRangeValue(fullPrev.start, DateTime(fullPrev.start.year, fullPrev.start.month, fullPrev.start.day + el - 1))
        : fullPrev;
    // Máximo ~2 años de días por rango para mantener el cálculo acotado.
    List<DayTotal> buildDays(DateRangeValue r, Map<String, List<double>> byDay) {
      final int n = r.days.clamp(0, 800);
      return <DayTotal>[
        for (int i = 0; i < n; i++)
          () {
            final DateTime d = DateTime(r.start.year, r.start.month, r.start.day + i);
            final List<double>? v = byDay[_iso(d)];
            return DayTotal(d, v?[0] ?? 0, v?[1] ?? 0, (v?[2] ?? 0).round());
          }(),
      ];
    }

    final String startIso = range.startIso, endIso = range.endIso;
    final String pStartIso = prev.startIso, pEndIso = prev.endIso;
    final Map<String, List<double>> cur = <String, List<double>>{};
    final Map<String, List<double>> old = <String, List<double>>{};
    final Map<String, ProducerRank> rank = <String, ProducerRank>{};
    final Set<String> curProducers = <String>{}, prevProducers = <String>{};
    final Map<String, String> veredaById = <String, String>{
      for (final ProducerModel p in producers)
        p.productorId: p.vereda.trim().isEmpty ? 'Sin vereda' : p.vereda.trim(),
    };
    final Map<String, double> veredaLiters = <String, double>{};
    final Map<String, Set<String>> veredaProducers = <String, Set<String>>{};
    double liters = 0, prevLiters = 0, morning = 0, afternoon = 0;
    int deliveries = 0, prevDeliveries = 0, unsynced = 0;

    for (final MilkReceptionModel r in receptions) {
      if (r.anulado) continue;
      final double l = r.litros.isFinite && r.litros > 0 ? r.litros : 0;
      final String day = r.fechaEntrega;
      final bool isMorning = r.jornada == AppConstants.shiftMorning;
      if (day.compareTo(startIso) >= 0 && day.compareTo(endIso) <= 0) {
        final List<double> v = cur.putIfAbsent(day, () => <double>[0, 0, 0]);
        v[isMorning ? 0 : 1] += l;
        v[2] += 1;
        liters += l;
        deliveries++;
        if (isMorning) {
          morning += l;
        } else {
          afternoon += l;
        }
        curProducers.add(r.productorId);
        if (!r.isSynced) unsynced++;
        final ProducerRank? p = rank[r.productorId];
        rank[r.productorId] = ProducerRank(
          id: r.productorId,
          name: r.nombreProductorSnap.trim().isEmpty ? r.codigoAsociadoSnap : r.nombreProductorSnap.trim(),
          code: r.codigoAsociadoSnap,
          liters: (p?.liters ?? 0) + l,
          deliveries: (p?.deliveries ?? 0) + 1,
        );
        final String vereda = veredaById[r.productorId] ?? 'Sin vereda';
        veredaLiters[vereda] = (veredaLiters[vereda] ?? 0) + l;
        veredaProducers.putIfAbsent(vereda, () => <String>{}).add(r.productorId);
      } else if (day.compareTo(pStartIso) >= 0 && day.compareTo(pEndIso) <= 0) {
        final List<double> v = old.putIfAbsent(day, () => <double>[0, 0, 0]);
        v[isMorning ? 0 : 1] += l;
        v[2] += 1;
        prevLiters += l;
        prevDeliveries++;
        prevProducers.add(r.productorId);
      }
    }

    final List<DayTotal> allDays = buildDays(range, cur);
    final List<DayTotal> days = inProgress ? allDays.take(el).toList() : allDays;
    final List<DayTotal> prevDays = buildDays(prev, old);

    final List<DateTime> zeroDays = <DateTime>[
      for (final DayTotal d in days)
        if (d.total <= 0 && d.day.isBefore(t)) d.day,
    ];

    final List<ProducerRank> top = rank.values.toList()
      ..sort((ProducerRank a, ProducerRank b) => b.liters.compareTo(a.liters));
    final List<VeredaShare> veredas = <VeredaShare>[
      for (final MapEntry<String, double> e in veredaLiters.entries)
        VeredaShare(e.key, e.value, veredaProducers[e.key]?.length ?? 0),
    ]..sort((VeredaShare a, VeredaShare b) => b.liters.compareTo(a.liters));

    // Caídas por productor: ventana reciente = rango (mín. 7 días), sin el día en curso.
    final DateTime yesterday = DateTime(t.year, t.month, t.day - 1);
    DateTime recentEnd = range.end.isAfter(yesterday) ? yesterday : range.end;
    DateTime recentStart = range.start;
    if (_daysBetween(recentStart, recentEnd) + 1 < 7) {
      recentStart = DateTime(recentEnd.year, recentEnd.month, recentEnd.day - 13);
    }
    if (recentEnd.isBefore(recentStart)) recentEnd = recentStart;
    final List<ProducerDrop> drops = ForecastService.detectProducerDrops(
      <ProducerDelivery>[
        for (final MilkReceptionModel r in receptions)
          if (!r.anulado)
            if (DateTime.tryParse(r.fechaEntrega) case final DateTime d)
              ProducerDelivery(
                r.productorId,
                r.nombreProductorSnap.trim().isEmpty ? r.codigoAsociadoSnap : r.nombreProductorSnap.trim(),
                d,
                r.litros,
              ),
      ],
      recentStart: recentStart,
      recentEnd: recentEnd,
    );

    return DashboardMetrics(
      range: range,
      liters: liters,
      prevLiters: prevLiters,
      deliveries: deliveries,
      prevDeliveries: prevDeliveries,
      producersDelivered: curProducers.length,
      prevProducersDelivered: prevProducers.length,
      morning: morning,
      afternoon: afternoon,
      days: days,
      prevDays: prevDays,
      top: top.take(8).toList(),
      veredas: veredas,
      zeroDays: zeroDays,
      unsyncedInRange: unsynced,
      elapsedDays: el,
      prevElapsedDays: elapsed(prev),
      drops: drops,
    );
  }

  /// Totales diarios de toda la historia (serie para el pronóstico).
  static List<DailyValue> dailySeries(List<MilkReceptionModel> receptions) {
    final Map<String, double> byDay = <String, double>{};
    for (final MilkReceptionModel r in receptions) {
      if (r.anulado || !(r.litros > 0) || !r.litros.isFinite) continue;
      byDay[r.fechaEntrega] = (byDay[r.fechaEntrega] ?? 0) + r.litros;
    }
    return <DailyValue>[
      for (final MapEntry<String, double> e in byDay.entries)
        if (DateTime.tryParse(e.key) case final DateTime d) DailyValue(d, e.value),
    ];
  }
}
