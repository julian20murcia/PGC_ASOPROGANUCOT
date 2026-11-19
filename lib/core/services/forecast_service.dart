import 'dart:math' as math;

import '../utils/formatters.dart';

/// Motor de pronóstico estadístico de ASOPROGANUCOTT (Dart puro, sin Flutter).
///
/// Flujo:
/// 1. Construye la serie diaria de litros (huecos = 0) hasta el último día
///    completo (ayer).
/// 2. Ajusta varios modelos candidatos: ingenuo estacional semanal, medias
///    móviles, regresión lineal con estacionalidad semanal, Holt amortiguado
///    y Holt-Winters aditivo semanal (parámetros por búsqueda en rejilla).
/// 3. Elige el mejor por validación cruzada de origen rodante (backtesting)
///    minimizando sMAPE, y estima bandas de predicción al 80 % a partir de
///    los errores de esos backtests.
/// 4. Agrega a meses, proyecta finanzas (compra, ingresos, costos operativos,
///    resultado neto) y redacta conclusiones en lenguaje natural.
///
/// Todo es determinista y no lanza excepciones con series vacías, constantes,
/// con ceros o con valores enormes (la serie se normaliza por su escala).

/// Valor diario (litros) de la serie histórica.
class DailyValue {
  const DailyValue(this.day, this.value);
  final DateTime day;
  final double value;
}

enum ForecastModelKind { seasonalNaive, movingAverage, linearTrend, holt, holtWinters }

extension ForecastModelKindLabel on ForecastModelKind {
  String get label => switch (this) {
        ForecastModelKind.seasonalNaive => 'Ingenuo estacional semanal',
        ForecastModelKind.movingAverage => 'Media móvil',
        ForecastModelKind.linearTrend => 'Regresión lineal con tendencia',
        ForecastModelKind.holt => 'Holt (suavizado exponencial doble)',
        ForecastModelKind.holtWinters => 'Holt-Winters aditivo semanal',
      };
}

/// Puntaje de backtesting de un modelo candidato.
class ModelScore {
  const ModelScore({
    required this.kind,
    required this.label,
    required this.smape,
    required this.mape,
    required this.wape,
    required this.folds,
    required this.params,
  });

  final ForecastModelKind kind;
  final String label;

  /// Error porcentual absoluto simétrico medio (0 = perfecto). Fracción.
  final double smape;

  /// MAPE sobre días con litros > 0 (null si no hubo días evaluables).
  final double? mape;

  /// Error absoluto ponderado (Σ|e| / Σ|real|).
  final double wape;
  final int folds;
  final String params;

  /// Precisión histórica estimada (1 − sMAPE), entre 0 y 1.
  double get accuracy => (1 - smape).clamp(0.0, 1.0).toDouble();
}

/// Punto diario proyectado con banda de predicción al 80 %.
class ForecastPoint {
  const ForecastPoint(this.day, this.value, this.low, this.high);
  final DateTime day;
  final double value;
  final double low;
  final double high;
}

/// Total mensual observado (histórico).
class MonthActual {
  const MonthActual(this.month, this.liters, {this.partial = false});
  final DateTime month;
  final double liters;
  final bool partial;
}

/// Proyección de un mes calendario.
class MonthProjection {
  const MonthProjection({
    required this.month,
    required this.liters,
    required this.litersLow,
    required this.litersHigh,
    required this.actualLiters,
    required this.isCurrent,
    required this.purchaseCost,
    required this.purchaseCostLow,
    required this.purchaseCostHigh,
    this.revenue,
    this.operatingCost,
    this.net,
    this.netLow,
    this.netHigh,
  });

  final DateTime month;
  final double liters;
  final double litersLow;
  final double litersHigh;

  /// Litros ya registrados en el mes (solo el mes en curso).
  final double actualLiters;
  final bool isCurrent;
  final double purchaseCost;
  final double purchaseCostLow;
  final double purchaseCostHigh;
  final double? revenue;
  final double? operatingCost;
  final double? net;
  final double? netLow;
  final double? netHigh;

  String get label => ForecastService.monthLabel(month);
}

/// Tendencia reciente de la producción.
class TrendSummary {
  const TrendSummary({
    required this.monthlyRate,
    required this.since,
    required this.significant,
    required this.weeks,
  });

  static const TrendSummary none =
      TrendSummary(monthlyRate: 0, since: null, significant: false, weeks: 0);

  /// Variación mensual relativa (0.04 = +4 % mensual).
  final double monthlyRate;
  final DateTime? since;
  final bool significant;
  final int weeks;

  bool get rising => significant && monthlyRate > 0;
  bool get falling => significant && monthlyRate < 0;
}

/// Parámetros financieros para la proyección.
class FinanceInputs {
  const FinanceInputs({
    required this.purchasePricePerLiter,
    this.salePricePerLiter = 0,
    this.monthlyOperatingCost = 0,
  });

  /// Tarifa vigente pagada al productor por litro.
  final double purchasePricePerLiter;

  /// Precio de venta del litro (0 = sin configurar).
  final double salePricePerLiter;
  final double monthlyOperatingCost;

  bool get isConfigured => _finite(salePricePerLiter) > 0;
}

/// `computing`: la proyección se está calculando en segundo plano.
enum ForecastStatus { ok, insufficient, computing }

enum InsightTone { positive, negative, neutral, warning }

class ForecastInsight {
  const ForecastInsight(this.text, {this.tone = InsightTone.neutral});
  final String text;
  final InsightTone tone;
}

/// Caída de entregas de un productor frente a su propio promedio.
class ProducerDrop {
  const ProducerDrop({
    required this.producerId,
    required this.name,
    required this.baselineDaily,
    required this.recentDaily,
    required this.change,
    required this.daysSinceLast,
  });

  final String producerId;
  final String name;
  final double baselineDaily;
  final double recentDaily;

  /// Variación relativa (−0.35 = cayó 35 %).
  final double change;

  /// Días desde su última entrega (null si nunca entregó en la ventana).
  final int? daysSinceLast;
}

/// Entrega individual usada para detectar caídas por productor.
class ProducerDelivery {
  const ProducerDelivery(this.producerId, this.name, this.day, this.liters);
  final String producerId;
  final String name;
  final DateTime day;
  final double liters;
}

/// Resultado completo del pronóstico.
class ForecastResult {
  const ForecastResult({
    required this.status,
    required this.historyDays,
    required this.minDays,
    this.message,
    this.best,
    this.candidates = const <ModelScore>[],
    this.daily = const <ForecastPoint>[],
    this.history = const <MonthActual>[],
    this.currentMonth,
    this.months = const <MonthProjection>[],
    this.trend = TrendSummary.none,
    this.weekdayPattern = const <double>[],
    this.finance,
    this.lastCompleteDay,
  });

  final ForecastStatus status;
  final String? message;

  /// Días de historia (desde la primera entrega hasta ayer).
  final int historyDays;
  final int minDays;
  final ModelScore? best;
  final List<ModelScore> candidates;
  final List<ForecastPoint> daily;
  final List<MonthActual> history;
  final MonthProjection? currentMonth;
  final List<MonthProjection> months;
  final TrendSummary trend;

  /// Desviación relativa por día de la semana (índice 0 = lunes).
  final List<double> weekdayPattern;
  final FinanceInputs? finance;
  final DateTime? lastCompleteDay;

  bool get isOk => status == ForecastStatus.ok;
  int get missingDays => math.max(0, minDays - historyDays);
  double? get accuracy => best?.accuracy;
  bool get financeConfigured => finance?.isConfigured ?? false;

  double get totalLiters => months.fold(0.0, (double a, MonthProjection m) => a + m.liters);
  double get totalLitersLow => months.fold(0.0, (double a, MonthProjection m) => a + m.litersLow);
  double get totalLitersHigh => months.fold(0.0, (double a, MonthProjection m) => a + m.litersHigh);
  double get totalPurchase => months.fold(0.0, (double a, MonthProjection m) => a + m.purchaseCost);
  double? get totalRevenue =>
      financeConfigured ? months.fold<double>(0.0, (double a, MonthProjection m) => a + (m.revenue ?? 0)) : null;
  double? get totalNet =>
      financeConfigured ? months.fold<double>(0.0, (double a, MonthProjection m) => a + (m.net ?? 0)) : null;
  double? get totalNetLow =>
      financeConfigured ? months.fold<double>(0.0, (double a, MonthProjection m) => a + (m.netLow ?? 0)) : null;
  double? get totalNetHigh =>
      financeConfigured ? months.fold<double>(0.0, (double a, MonthProjection m) => a + (m.netHigh ?? 0)) : null;

  /// Etiqueta de confianza: alta / media / baja.
  String get confidenceLabel {
    final double acc = accuracy ?? 0;
    if (acc >= 0.9 && historyDays >= 60) return 'alta';
    if (acc >= 0.8) return 'media';
    return 'baja';
  }
}

double _finite(double v) => v.isFinite ? v : 0;

// ─────────────────────────────────────────────────────────────────────────────
// Modelos
// ─────────────────────────────────────────────────────────────────────────────

class _Fit {
  const _Fit(this.forecast, this.params);
  final List<double> forecast;
  final String params;
}

abstract class _Model {
  ForecastModelKind get kind;
  String get label;
  int get minTrain;

  /// Penalización mínima por complejidad para desempatar a favor de lo simple.
  double get complexity;
  _Fit fit(List<double> y, int h);
}

String _p(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

class _SeasonalNaive extends _Model {
  static const int m = 7;
  @override
  ForecastModelKind get kind => ForecastModelKind.seasonalNaive;
  @override
  String get label => kind.label;
  @override
  int get minTrain => m;
  @override
  double get complexity => 0.002;

  @override
  _Fit fit(List<double> y, int h) {
    final int n = y.length;
    return _Fit(
      List<double>.generate(h, (int i) => y[n - m + (i % m)]),
      'm=7',
    );
  }
}

class _MovingAverage extends _Model {
  _MovingAverage(this.window);
  final int window;
  @override
  ForecastModelKind get kind => ForecastModelKind.movingAverage;
  @override
  String get label => 'Media móvil ($window días)';
  @override
  int get minTrain => window;
  @override
  double get complexity => 0.001;

  @override
  _Fit fit(List<double> y, int h) {
    final int n = y.length;
    double s = 0;
    for (int i = n - window; i < n; i++) {
      s += y[i];
    }
    final double mean = s / window;
    return _Fit(List<double>.filled(h, mean), 'ventana=$window');
  }
}

/// Regresión lineal (mínimos cuadrados) sobre los últimos [window] días con
/// índices estacionales semanales estimados de los residuos.
class _LinearTrend extends _Model {
  static const int window = 90;
  @override
  ForecastModelKind get kind => ForecastModelKind.linearTrend;
  @override
  String get label => kind.label;
  @override
  int get minTrain => 7;
  @override
  double get complexity => 0.004;

  @override
  _Fit fit(List<double> y, int h) {
    final int n = y.length;
    final int k = math.min(n, window);
    final int off = n - k;
    double st = 0, sy = 0;
    for (int j = 0; j < k; j++) {
      st += j;
      sy += y[off + j];
    }
    final double mt = st / k, my = sy / k;
    double sxy = 0, sxx = 0;
    for (int j = 0; j < k; j++) {
      sxy += (j - mt) * (y[off + j] - my);
      sxx += (j - mt) * (j - mt);
    }
    final double b = sxx > 0 ? sxy / sxx : 0;
    final double a = my - b * mt;
    final List<double> season = List<double>.filled(7, 0);
    if (k >= 14) {
      final List<int> counts = List<int>.filled(7, 0);
      for (int j = 0; j < k; j++) {
        final int phase = (off + j) % 7;
        season[phase] += y[off + j] - (a + b * j);
        counts[phase]++;
      }
      double mean = 0;
      for (int p = 0; p < 7; p++) {
        season[p] = counts[p] > 0 ? season[p] / counts[p] : 0;
        mean += season[p];
      }
      mean /= 7;
      for (int p = 0; p < 7; p++) {
        season[p] -= mean;
      }
    }
    return _Fit(
      List<double>.generate(h, (int i) {
        final int pos = n + i;
        return a + b * (k + i) + season[pos % 7];
      }),
      'pendiente=${_p(b)}/día${k >= 14 ? ' + estacionalidad semanal' : ''}',
    );
  }
}

const List<double> _alphas = <double>[0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9];
const List<double> _betas = <double>[0.01, 0.05, 0.1, 0.2, 0.4];
const List<double> _gammas = <double>[0.01, 0.05, 0.1, 0.2, 0.4];
const List<double> _phis = <double>[0.85, 0.92, 0.98, 1.0];

double _dampSum(double phi, int h) {
  if (phi == 1.0) return h.toDouble();
  double s = 0, p = 1;
  for (int i = 1; i <= h; i++) {
    p *= phi;
    s += p;
  }
  return s;
}

/// Holt con tendencia amortiguada; α, β, φ por rejilla minimizando el SSE a un paso.
class _Holt extends _Model {
  @override
  ForecastModelKind get kind => ForecastModelKind.holt;
  @override
  String get label => kind.label;
  @override
  int get minTrain => 5;
  @override
  double get complexity => 0.005;

  @override
  _Fit fit(List<double> y, int h) {
    final int n = y.length;
    final int k0 = math.min(n - 1, 4);
    final double b0 = k0 > 0 ? (y[k0] - y[0]) / k0 : 0;
    double bestSse = double.infinity;
    double bl = y[0], bb = 0, ba = 0.3, bbe = 0.1, bphi = 1;
    for (final double a in _alphas) {
      for (final double be in _betas) {
        for (final double phi in _phis) {
          double l = y[0], b = b0, sse = 0;
          for (int t = 1; t < n; t++) {
            final double f = l + phi * b;
            final double e = y[t] - f;
            sse += e * e;
            final double ln = a * y[t] + (1 - a) * f;
            b = be * (ln - l) + (1 - be) * phi * b;
            l = ln;
          }
          if (sse < bestSse) {
            bestSse = sse;
            bl = l;
            bb = b;
            ba = a;
            bbe = be;
            bphi = phi;
          }
        }
      }
    }
    return _Fit(
      List<double>.generate(h, (int i) => bl + _dampSum(bphi, i + 1) * bb),
      'α=${_p(ba)} β=${_p(bbe)} φ=${_p(bphi)}',
    );
  }
}

/// Holt-Winters aditivo con estacionalidad semanal y tendencia amortiguada.
class _HoltWinters extends _Model {
  static const int m = 7;
  @override
  ForecastModelKind get kind => ForecastModelKind.holtWinters;
  @override
  String get label => kind.label;
  @override
  int get minTrain => 2 * m;
  @override
  double get complexity => 0.006;

  @override
  _Fit fit(List<double> y, int h) {
    final int n = y.length;
    double mean1 = 0, mean2 = 0;
    for (int i = 0; i < m; i++) {
      mean1 += y[i];
      mean2 += y[m + i];
    }
    mean1 /= m;
    mean2 /= m;
    final double b0 = (mean2 - mean1) / m;
    final double l0 = mean1 + b0 * (m - 1) / 2;
    // Estacionalidad inicial: promedio de desvíos de hasta 4 temporadas completas.
    final int seasons = math.min(n ~/ m, 4);
    final List<double> s0 = List<double>.filled(m, 0);
    for (int k = 0; k < seasons; k++) {
      double sm = 0;
      for (int i = 0; i < m; i++) {
        sm += y[k * m + i];
      }
      sm /= m;
      for (int i = 0; i < m; i++) {
        s0[i] += (y[k * m + i] - sm) / seasons;
      }
    }

    double bestSse = double.infinity;
    double bl = l0, bb = b0, ba = 0.3, bbe = 0.1, bg = 0.1, bphi = 1;
    List<double> bs = List<double>.from(s0);
    final List<double> s = List<double>.filled(m, 0);
    for (final double a in _alphas) {
      for (final double be in _betas) {
        for (final double g in _gammas) {
          for (final double phi in _phis) {
            for (int i = 0; i < m; i++) {
              s[i] = s0[i];
            }
            double l = l0, b = b0, sse = 0;
            for (int t = m; t < n; t++) {
              final int p = t % m;
              final double base = l + phi * b;
              final double e = y[t] - (base + s[p]);
              sse += e * e;
              if (sse >= bestSse) break;
              final double ln = a * (y[t] - s[p]) + (1 - a) * base;
              b = be * (ln - l) + (1 - be) * phi * b;
              s[p] = g * (y[t] - ln) + (1 - g) * s[p];
              l = ln;
            }
            if (sse < bestSse) {
              bestSse = sse;
              bl = l;
              bb = b;
              ba = a;
              bbe = be;
              bg = g;
              bphi = phi;
              bs = List<double>.from(s);
            }
          }
        }
      }
    }
    return _Fit(
      List<double>.generate(h, (int i) {
        final int t = n - 1 + (i + 1);
        return bl + _dampSum(bphi, i + 1) * bb + bs[t % m];
      }),
      'α=${_p(ba)} β=${_p(bbe)} γ=${_p(bg)} φ=${_p(bphi)}',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Servicio
// ─────────────────────────────────────────────────────────────────────────────

class _Backtest {
  _Backtest(this.model, this.smape, this.mape, this.wape, this.folds, this.stepRmse, this.windowRelRms);
  final _Model model;
  final double smape;
  final double? mape;
  final double wape;
  final int folds;

  /// RMSE por paso del horizonte (escala normalizada).
  final List<double> stepRmse;

  /// Error relativo RMS del total de la ventana de prueba.
  final double windowRelRms;
}

class ForecastService {
  const ForecastService();

  static const int minHistoryDays = 14;
  static const int holtWintersMinDays = 21;
  static const int maxHistoryDays = 730;
  static const double z80 = 1.2816;

  static const List<String> _monthsLong = <String>[
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const List<String> _monthsShort = <String>[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  static const List<String> weekdaysLong = <String>[
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos',
  ];

  static String monthLabel(DateTime m) => '${_monthsShort[m.month - 1]} ${m.year}';
  static String monthLabelLong(DateTime m) => '${_monthsLong[m.month - 1]} ${m.year}';
  static String dayLabel(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static int _key(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Días calendario entre [a] y [b] (inmune a cambios de horario).
  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  /// Construye la serie diaria entre la primera entrega con litros > 0 y
  /// [end] (inclusive), rellenando con 0 los días sin datos.
  static ({DateTime? start, List<double> values}) buildDailySeries(
    List<DailyValue> data,
    DateTime end,
  ) {
    final DateTime last = _day(end);
    final Map<int, double> byDay = <int, double>{};
    DateTime? first;
    for (final DailyValue d in data) {
      final double v = _finite(d.value);
      if (v <= 0) continue;
      final DateTime day = _day(d.day);
      if (day.isAfter(last)) continue;
      byDay[_key(day)] = (byDay[_key(day)] ?? 0) + v;
      if (first == null || day.isBefore(first)) first = day;
    }
    if (first == null) return (start: null, values: const <double>[]);
    final DateTime minStart = DateTime(last.year, last.month, last.day - (maxHistoryDays - 1));
    if (first.isBefore(minStart)) first = minStart;
    final List<double> out = <double>[];
    for (int i = 0;; i++) {
      final DateTime d = DateTime(first.year, first.month, first.day + i);
      if (d.isAfter(last)) break;
      final double v = byDay[_key(d)] ?? 0;
      out.add(v.isFinite ? v : 0);
    }
    return (start: first, values: out);
  }

  List<_Model> _candidates(int n) => <_Model>[
        _SeasonalNaive(),
        _MovingAverage(7),
        if (n >= 21) _MovingAverage(14),
        if (n >= 42) _MovingAverage(28),
        _LinearTrend(),
        _Holt(),
        if (n >= holtWintersMinDays) _HoltWinters(),
      ];

  _Backtest? _evaluate(_Model model, List<double> y, int h, List<int> origins) {
    double smapeSum = 0, mapeSum = 0, absErr = 0, absAct = 0;
    int smapeN = 0, mapeN = 0, folds = 0;
    final List<double> sq = List<double>.filled(h, 0);
    final List<int> sqN = List<int>.filled(h, 0);
    double relSq = 0;
    for (final int o in origins) {
      if (o < model.minTrain || o + h > y.length) continue;
      final List<double> f = model.fit(y.sublist(0, o), h).forecast;
      double sa = 0, sf = 0;
      for (int k = 0; k < h; k++) {
        final double a = y[o + k];
        final double p = math.max(0.0, _finite(f[k]));
        final double e = a - p;
        final double den = a.abs() + p.abs();
        smapeSum += den > 0 ? 2 * e.abs() / den : 0;
        smapeN++;
        if (a > 0) {
          mapeSum += e.abs() / a;
          mapeN++;
        }
        absErr += e.abs();
        absAct += a.abs();
        sq[k] += e * e;
        sqN[k]++;
        sa += a;
        sf += p;
      }
      final double rel = sf > 0 ? (sa - sf) / sf : (sa > 0 ? 1.0 : 0.0);
      relSq += rel * rel;
      folds++;
    }
    if (folds == 0) return null;
    // sMAPE reportado en escala 0–1 (mitad del sMAPE clásico 0–200 %).
    final double smape = smapeSum / smapeN / 2;
    return _Backtest(
      model,
      smape.isFinite ? smape : 1,
      mapeN > 0 ? mapeSum / mapeN : null,
      absAct > 0 ? absErr / absAct : (absErr > 0 ? 1 : 0),
      folds,
      List<double>.generate(h, (int k) => sqN[k] > 0 ? math.sqrt(sq[k] / sqN[k]) : 0),
      math.sqrt(relSq / folds),
    );
  }

  /// Ejecuta el pronóstico completo.
  ///
  /// [today] es la fecha actual: la serie se corta en el día anterior (último
  /// día completo) y se proyecta hasta el final del mes número [horizonMonths]
  /// posterior al mes en curso.
  ForecastResult forecast(
    List<DailyValue> data, {
    required DateTime today,
    int horizonMonths = 5,
    FinanceInputs? finance,
  }) {
    final DateTime t0 = _day(today);
    final DateTime lastComplete = DateTime(t0.year, t0.month, t0.day - 1);
    final ({DateTime? start, List<double> values}) series = buildDailySeries(data, lastComplete);
    final List<double> raw = series.values;
    final int n = raw.length;
    if (series.start == null || n < minHistoryDays) {
      final int missing = minHistoryDays - n;
      return ForecastResult(
        status: ForecastStatus.insufficient,
        historyDays: n,
        minDays: minHistoryDays,
        finance: finance,
        lastCompleteDay: lastComplete,
        message: n == 0
            ? 'Aún no hay entregas registradas para proyectar. Se necesitan al menos $minHistoryDays días de historia.'
            : 'Hay $n ${n == 1 ? 'día' : 'días'} de historia; faltan $missing ${missing == 1 ? 'día' : 'días'} '
                'para generar una proyección confiable (mínimo $minHistoryDays).',
      );
    }
    final DateTime start = series.start!;

    // Normalización por escala: evita desbordes con valores enormes.
    double scale = 0;
    for (final double v in raw) {
      if (v > scale) scale = v;
    }
    if (!(scale > 0) || !scale.isFinite) scale = 1;
    final List<double> y = raw.map((double v) => v / scale).toList(growable: false);

    // Backtesting de origen rodante.
    final int h = (n ~/ 4).clamp(7, 56);
    final int step = math.max(7, h ~/ 2);
    final List<int> origins = <int>[];
    for (int j = 0; j < 5; j++) {
      final int o = n - h - j * step;
      if (o < 7) break;
      origins.add(o);
    }
    final List<_Backtest> scored = <_Backtest>[];
    for (final _Model m in _candidates(n)) {
      final _Backtest? b = _evaluate(m, y, h, origins);
      if (b != null) scored.add(b);
    }
    scored.sort((_Backtest a, _Backtest b) =>
        (a.smape + a.model.complexity * 1e-3).compareTo(b.smape + b.model.complexity * 1e-3));
    if (scored.isEmpty) {
      return ForecastResult(
        status: ForecastStatus.insufficient,
        historyDays: n,
        minDays: minHistoryDays,
        finance: finance,
        lastCompleteDay: lastComplete,
        message: 'No fue posible evaluar modelos con la historia disponible.',
      );
    }
    final _Backtest best = scored.first;

    // Horizonte: desde hoy hasta el fin del mes N posterior.
    final DateTime curMonth = DateTime(t0.year, t0.month, 1);
    final DateTime horizonEnd = DateTime(t0.year, t0.month + horizonMonths + 1, 0);
    final int hTotal = _daysBetween(t0, horizonEnd) + 1;
    final _Fit fit = best.model.fit(y, hTotal);

    final List<ForecastPoint> daily = <ForecastPoint>[];
    for (int i = 0; i < hTotal; i++) {
      final DateTime d = DateTime(t0.year, t0.month, t0.day + i);
      final double v = math.max(0.0, _finite(fit.forecast[i])) * scale;
      final int k = math.min(i, h - 1);
      double sigma = best.stepRmse[k] * scale;
      if (i >= h) sigma *= math.sqrt((i + 1) / h);
      final double low = math.max(0.0, v - z80 * sigma);
      final double high = v + z80 * sigma;
      daily.add(ForecastPoint(d, _finite(v), _finite(low), _finite(high)));
    }

    // Incertidumbre relativa de totales (desde errores de ventana en backtest).
    double relSigma = math.max(best.windowRelRms, 0.03);
    if (best.folds < 3) relSigma *= 1.5;

    final FinanceInputs fin = finance ?? const FinanceInputs(purchasePricePerLiter: 0);
    MonthProjection project(DateTime month, {required bool isCurrent}) {
      final DateTime mEnd = DateTime(month.year, month.month + 1, 0);
      double fc = 0;
      int midOffset = 0;
      int count = 0;
      for (int i = 0; i < daily.length; i++) {
        final DateTime d = daily[i].day;
        if (d.year == month.year && d.month == month.month) {
          fc += daily[i].value;
          midOffset += i + 1;
          count++;
        }
      }
      double actual = 0;
      if (isCurrent) {
        for (int i = 0; i < n; i++) {
          final DateTime d = DateTime(start.year, start.month, start.day + i);
          if (d.year == month.year && d.month == month.month && !d.isAfter(mEnd)) actual += raw[i];
        }
      }
      final double meanDays = count > 0 ? midOffset / count : 1;
      final double rel = math.min(0.95, relSigma * math.sqrt(math.max(1.0, meanDays / h)));
      final double liters = _finite(actual + fc);
      final double low = _finite(actual + math.max(0.0, fc * (1 - z80 * rel)));
      final double high = _finite(actual + fc * (1 + z80 * rel));
      final double price = _finite(fin.purchasePricePerLiter);
      double? revenue, op, net, netLow, netHigh;
      if (fin.isConfigured) {
        final double sale = _finite(fin.salePricePerLiter);
        op = _finite(fin.monthlyOperatingCost);
        revenue = liters * sale;
        double netOf(double l) => l * (sale - price) - op!;
        net = _finite(netOf(liters));
        final double a = _finite(netOf(low)), b = _finite(netOf(high));
        netLow = math.min(a, b);
        netHigh = math.max(a, b);
      }
      return MonthProjection(
        month: month,
        liters: liters,
        litersLow: low,
        litersHigh: high,
        actualLiters: actual,
        isCurrent: isCurrent,
        purchaseCost: _finite(liters * price),
        purchaseCostLow: _finite(low * price),
        purchaseCostHigh: _finite(high * price),
        revenue: revenue == null ? null : _finite(revenue),
        operatingCost: op,
        net: net,
        netLow: netLow,
        netHigh: netHigh,
      );
    }

    final MonthProjection current = project(curMonth, isCurrent: true);
    final List<MonthProjection> months = <MonthProjection>[
      for (int i = 1; i <= horizonMonths; i++)
        project(DateTime(t0.year, t0.month + i, 1), isCurrent: false),
    ];

    // Histórico mensual (últimos 6 meses con datos).
    final Map<int, double> monthly = <int, double>{};
    for (int i = 0; i < n; i++) {
      final DateTime d = DateTime(start.year, start.month, start.day + i);
      final int key = d.year * 100 + d.month;
      monthly[key] = (monthly[key] ?? 0) + raw[i];
    }
    final List<int> keys = monthly.keys.toList()..sort();
    final List<MonthActual> history = <MonthActual>[
      for (final int k in keys.skip(math.max(0, keys.length - 6)))
        MonthActual(
          DateTime(k ~/ 100, k % 100, 1),
          monthly[k]!,
          partial: (k == curMonth.year * 100 + curMonth.month) ||
              (k == start.year * 100 + start.month && start.day > 1),
        ),
    ];

    return ForecastResult(
      status: ForecastStatus.ok,
      historyDays: n,
      minDays: minHistoryDays,
      best: _score(best, fit.params),
      candidates: <ModelScore>[for (final _Backtest b in scored) _score(b, b == best ? fit.params : '')],
      daily: daily,
      history: history,
      currentMonth: current,
      months: months,
      trend: _trend(raw, start),
      weekdayPattern: _weekdayPattern(raw, start),
      finance: finance,
      lastCompleteDay: lastComplete,
    );
  }

  ModelScore _score(_Backtest b, String params) => ModelScore(
        kind: b.model.kind,
        label: b.model.label,
        smape: b.smape,
        mape: b.mape,
        wape: b.wape,
        folds: b.folds,
        params: params,
      );

  /// Tendencia: regresión sobre totales semanales (elimina el patrón semanal).
  static TrendSummary _trend(List<double> raw, DateTime start) {
    final int weeksAvail = raw.length ~/ 7;
    final int weeks = math.min(weeksAvail, 17);
    if (weeks < 6) return TrendSummary.none;
    final int off = raw.length - weeks * 7;
    final List<double> w = List<double>.filled(weeks, 0);
    for (int i = 0; i < weeks * 7; i++) {
      w[i ~/ 7] += raw[off + i];
    }
    double sx = 0, sy = 0;
    for (int i = 0; i < weeks; i++) {
      sx += i;
      sy += w[i];
    }
    final double mx = sx / weeks, my = sy / weeks;
    if (!(my > 0)) return TrendSummary.none;
    double sxy = 0, sxx = 0;
    for (int i = 0; i < weeks; i++) {
      sxy += (i - mx) * (w[i] - my);
      sxx += (i - mx) * (i - mx);
    }
    final double b = sxx > 0 ? sxy / sxx : 0;
    final double a = my - b * mx;
    double sse = 0;
    for (int i = 0; i < weeks; i++) {
      final double e = w[i] - (a + b * i);
      sse += e * e;
    }
    final double se = sxx > 0 ? math.sqrt(sse / (weeks - 2) / sxx) : 0;
    final double tStat = se > 0 ? b / se : (b != 0 ? double.infinity : 0);
    final double rate = _finite(b * (30.44 / 7) / my);
    return TrendSummary(
      monthlyRate: rate,
      since: DateTime(start.year, start.month, start.day + off),
      significant: tStat.abs() >= 2.5 && rate.abs() >= 0.01,
      weeks: weeks,
    );
  }

  /// Desviación relativa de cada día de la semana (lun..dom) en las últimas 8 semanas.
  static List<double> _weekdayPattern(List<double> raw, DateTime start) {
    final int days = math.min(raw.length - raw.length % 7, 56);
    if (days < 14) return const <double>[];
    final int off = raw.length - days;
    final List<double> sum = List<double>.filled(7, 0);
    final List<int> cnt = List<int>.filled(7, 0);
    double total = 0;
    for (int i = off; i < raw.length; i++) {
      final int wd = DateTime(start.year, start.month, start.day + i).weekday - 1;
      sum[wd] += raw[i];
      cnt[wd]++;
      total += raw[i];
    }
    final double mean = total / days;
    if (!(mean > 0)) return const <double>[];
    return List<double>.generate(7, (int i) => cnt[i] > 0 ? _finite(sum[i] / cnt[i] / mean - 1) : 0);
  }

  /// Detecta productores con caída de entregas ≥ [threshold] frente a su
  /// promedio diario de los [baselineDays] días anteriores a [recentStart].
  static List<ProducerDrop> detectProducerDrops(
    List<ProducerDelivery> deliveries, {
    required DateTime recentStart,
    required DateTime recentEnd,
    int baselineDays = 60,
    double threshold = 0.30,
    int minBaselineDeliveries = 4,
  }) {
    final DateTime rs = _day(recentStart);
    final DateTime re = _day(recentEnd);
    final DateTime bs = DateTime(rs.year, rs.month, rs.day - baselineDays);
    final int recentDays = _daysBetween(rs, re) + 1;
    if (recentDays <= 0) return const <ProducerDrop>[];
    final Map<String, double> base = <String, double>{};
    final Map<String, int> baseN = <String, int>{};
    final Map<String, DateTime> firstSeen = <String, DateTime>{};
    final Map<String, double> recent = <String, double>{};
    final Map<String, DateTime> lastSeen = <String, DateTime>{};
    final Map<String, String> names = <String, String>{};
    for (final ProducerDelivery d in deliveries) {
      final double v = _finite(d.liters);
      if (v <= 0) continue;
      final DateTime day = _day(d.day);
      names[d.producerId] = d.name;
      if (!day.isAfter(re)) {
        final DateTime? ls = lastSeen[d.producerId];
        if (ls == null || day.isAfter(ls)) lastSeen[d.producerId] = day;
      }
      if (!day.isBefore(bs) && day.isBefore(rs)) {
        base[d.producerId] = (base[d.producerId] ?? 0) + v;
        baseN[d.producerId] = (baseN[d.producerId] ?? 0) + 1;
        final DateTime? fs = firstSeen[d.producerId];
        if (fs == null || day.isBefore(fs)) firstSeen[d.producerId] = day;
      } else if (!day.isBefore(rs) && !day.isAfter(re)) {
        recent[d.producerId] = (recent[d.producerId] ?? 0) + v;
      }
    }
    final List<ProducerDrop> out = <ProducerDrop>[];
    for (final String id in base.keys) {
      if ((baseN[id] ?? 0) < minBaselineDeliveries) continue;
      final int baseSpan = _daysBetween(firstSeen[id]!, rs).clamp(1, baselineDays);
      final double bd = base[id]! / baseSpan;
      if (!(bd > 0)) continue;
      final double rd = (recent[id] ?? 0) / recentDays;
      final double change = rd / bd - 1;
      if (change <= -threshold) {
        out.add(ProducerDrop(
          producerId: id,
          name: names[id] ?? id,
          baselineDaily: bd,
          recentDaily: rd,
          change: _finite(change),
          daysSinceLast: lastSeen[id] == null ? null : _daysBetween(lastSeen[id]!, re),
        ));
      }
    }
    out.sort((ProducerDrop a, ProducerDrop b) => a.change.compareTo(b.change));
    return out;
  }

  static String _money(double v) => AppFormatters.formatCurrency(v.roundToDouble());
  static String _liters(double v) => AppFormatters.formatLiters(v.roundToDouble());
  static String _pct(double f) => '${(f.abs() * 100).toStringAsFixed(f.abs() < 0.1 ? 1 : 0).replaceAll('.', ',')} %';

  /// Redacta conclusiones en lenguaje natural a partir del pronóstico.
  static List<ForecastInsight> buildInsights(
    ForecastResult r, {
    List<ProducerDrop> drops = const <ProducerDrop>[],
    int maxDrops = 2,
  }) {
    final List<ForecastInsight> out = <ForecastInsight>[];
    if (!r.isOk) {
      if (r.message != null) out.add(ForecastInsight(r.message!, tone: InsightTone.warning));
    } else {
      final MonthProjection? cur = r.currentMonth;
      final MonthProjection? last = r.months.isEmpty ? null : r.months.last;
      if (r.financeConfigured && last != null) {
        final double net = r.totalNet ?? 0, lo = r.totalNetLow ?? 0, hi = r.totalNetHigh ?? 0;
        final String when = ForecastService.monthLabelLong(last.month);
        if (lo >= 0 || hi <= 0) {
          final bool gain = net >= 0;
          out.add(ForecastInsight(
            'Si la tendencia actual se mantiene, en $when la asociación tendría una '
            '${gain ? 'ganancia' : 'pérdida'} acumulada de ${_money(net.abs())} '
            '(rango ${_money(math.min(lo.abs(), hi.abs()))} – ${_money(math.max(lo.abs(), hi.abs()))}).',
            tone: gain ? InsightTone.positive : InsightTone.negative,
          ));
        } else {
          out.add(ForecastInsight(
            'Si la tendencia actual se mantiene, en $when el resultado acumulado sería de '
            '${net >= 0 ? 'ganancia' : 'pérdida'} de ${_money(net.abs())}, pero el rango va desde una pérdida de '
            '${_money(lo.abs())} hasta una ganancia de ${_money(hi)}.',
            tone: InsightTone.warning,
          ));
        }
        final FinanceInputs f = r.finance!;
        final double margin = f.salePricePerLiter - f.purchasePricePerLiter;
        if (margin <= 0) {
          out.add(ForecastInsight(
            'El precio de venta (${_money(f.salePricePerLiter)}/L) no cubre la tarifa pagada al productor '
            '(${_money(f.purchasePricePerLiter)}/L): cada litro acopiado genera pérdida.',
            tone: InsightTone.negative,
          ));
        } else if (f.monthlyOperatingCost > 0) {
          final double breakEven = f.monthlyOperatingCost / margin;
          final double avg = r.totalLiters / math.max(1, r.months.length);
          out.add(ForecastInsight(
            'Para cubrir los costos operativos se necesitan ${_liters(breakEven)} al mes; '
            'la proyección promedio es ${_liters(avg)} al mes '
            '(${avg >= breakEven ? '${_pct(avg / breakEven - 1)} por encima' : '${_pct(1 - avg / breakEven)} por debajo'} del punto de equilibrio).',
            tone: avg >= breakEven ? InsightTone.positive : InsightTone.negative,
          ));
        }
      } else if (last != null) {
        out.add(ForecastInsight(
          'Si la tendencia se mantiene, entre ${ForecastService.monthLabelLong(r.months.first.month)} y '
          '${ForecastService.monthLabelLong(last.month)} se acopiarían ${_liters(r.totalLiters)} '
          '(rango ${_liters(r.totalLitersLow)} – ${_liters(r.totalLitersHigh)}) con un costo de compra de ${_money(r.totalPurchase)}.',
        ));
      }
      if (cur != null) {
        out.add(ForecastInsight(
          '${_cap(ForecastService.monthLabelLong(cur.month))} cerraría con cerca de ${_liters(cur.liters)} '
          '(${_liters(cur.actualLiters)} ya registrados).',
        ));
      }
      final TrendSummary t = r.trend;
      if (t.significant && t.since != null) {
        out.add(ForecastInsight(
          'La producción viene ${t.monthlyRate < 0 ? 'cayendo' : 'creciendo'} ${_pct(t.monthlyRate)} mensual '
          'desde el ${ForecastService.dayLabel(t.since!)}.',
          tone: t.monthlyRate < 0 ? InsightTone.negative : InsightTone.positive,
        ));
      } else if (t.weeks >= 6) {
        out.add(ForecastInsight('La producción se mantiene estable en las últimas ${t.weeks} semanas (sin tendencia significativa).'));
      }
      if (r.weekdayPattern.length == 7) {
        int lo = 0;
        for (int i = 1; i < 7; i++) {
          if (r.weekdayPattern[i] < r.weekdayPattern[lo]) lo = i;
        }
        if (r.weekdayPattern[lo] <= -0.10) {
          out.add(ForecastInsight(
            'Los ${weekdaysLong[lo]} se acopia ${_pct(r.weekdayPattern[lo])} menos que el promedio diario.',
          ));
        }
      }
    }
    for (final ProducerDrop d in drops.take(maxDrops)) {
      out.add(ForecastInsight(
        d.recentDaily <= 0
            ? '${d.name} no ha entregado leche en el período${d.daysSinceLast != null ? ' (última entrega hace ${d.daysSinceLast} días)' : ''}.'
            : 'El productor ${d.name} redujo sus entregas ${_pct(d.change)} frente a su promedio.',
        tone: InsightTone.warning,
      ));
    }
    return out;
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
