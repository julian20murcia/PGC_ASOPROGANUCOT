import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/services/forecast_service.dart';

/// Ruido pseudoaleatorio determinista en [-1, 1].
double _noise(int i) {
  final double x = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return (x - x.floorToDouble()) * 2 - 1;
}

List<DailyValue> _series(DateTime start, int days, double Function(int i) f) => <DailyValue>[
      for (int i = 0; i < days; i++) DailyValue(DateTime(start.year, start.month, start.day + i), f(i)),
    ];

double _mape(List<double> actual, List<double> fc) {
  double s = 0;
  for (int i = 0; i < actual.length; i++) {
    s += (actual[i] - fc[i]).abs() / actual[i];
  }
  return s / actual.length;
}

void _expectFinite(ForecastResult r) {
  for (final ForecastPoint p in r.daily) {
    expect(p.value.isFinite && p.low.isFinite && p.high.isFinite, isTrue);
    expect(p.value >= 0 && p.low >= 0, isTrue);
    expect(p.low <= p.value + 1e-6 && p.value <= p.high + 1e-6, isTrue);
  }
  for (final MonthProjection m in <MonthProjection>[...r.months, ?r.currentMonth]) {
    expect(m.liters.isFinite && m.litersLow.isFinite && m.litersHigh.isFinite, isTrue);
    expect(m.purchaseCost.isFinite, isTrue);
    if (m.net != null) expect(m.net!.isFinite && m.netLow!.isFinite && m.netHigh!.isFinite, isTrue);
  }
  if (r.best != null) {
    expect(r.best!.smape.isFinite, isTrue);
    expect(r.accuracy!.isNaN, isFalse);
  }
  expect(r.trend.monthlyRate.isFinite, isTrue);
  for (final double w in r.weekdayPattern) {
    expect(w.isFinite, isTrue);
  }
  for (final ForecastInsight i in ForecastService.buildInsights(r)) {
    expect(i.text.contains('NaN'), isFalse);
    expect(i.text.contains('Infinity'), isFalse);
  }
}

void main() {
  const ForecastService svc = ForecastService();
  const List<double> weekly = <double>[40, 25, 10, 0, -15, -30, -30]; // suma 0

  group('Precisión con series sintéticas', () {
    test('tendencia + estacionalidad semanal: error < 5 % sobre los próximos 28 días', () {
      final DateTime start = DateTime(2026, 3, 2);
      double truth(int i) => 1000 + 2.0 * i + weekly[i % 7] + 8 * _noise(i);
      const int train = 168;
      final List<DailyValue> all = _series(start, train, truth);
      final DateTime today = DateTime(start.year, start.month, start.day + train);

      final ForecastResult r = svc.forecast(all, today: today);
      expect(r.isOk, isTrue);
      final List<double> actual = <double>[for (int i = 0; i < 28; i++) 1000 + 2.0 * (train + i) + weekly[(train + i) % 7]];
      final List<double> fc = r.daily.take(28).map((ForecastPoint p) => p.value).toList();
      expect(_mape(actual, fc), lessThan(0.05));
      expect(r.best!.accuracy, greaterThan(0.95));
      // Modelo con tendencia elegido (no un promedio plano).
      expect(
        <ForecastModelKind>[ForecastModelKind.holtWinters, ForecastModelKind.linearTrend, ForecastModelKind.holt]
            .contains(r.best!.kind),
        isTrue,
        reason: 'Elegido: ${r.best!.label}',
      );
      expect(r.trend.rising, isTrue);
      _expectFinite(r);
    });

    test('estacionalidad semanal fuerte sin tendencia: error < 5 %', () {
      final DateTime start = DateTime(2026, 1, 5);
      final List<double> season = <double>[600, 620, 610, 640, 630, 300, 200];
      final List<DailyValue> all = _series(start, 120, (int i) => season[i % 7] * (1 + 0.01 * _noise(i)));
      final ForecastResult r = svc.forecast(all, today: DateTime(2026, 1, 5 + 120));
      final List<double> actual = <double>[for (int i = 120; i < 148; i++) season[i % 7]];
      final List<double> fc = r.daily.take(28).map((ForecastPoint p) => p.value).toList();
      expect(_mape(actual, fc), lessThan(0.05));
      expect(r.trend.significant, isFalse);
      // Domingos son el día más bajo.
      expect(r.weekdayPattern[6], lessThan(-0.3));
      _expectFinite(r);
    });

    test('totales mensuales proyectados cerca de la verdad (< 5 %)', () {
      final DateTime start = DateTime(2026, 1, 1);
      double truth(int i) => 800 + 1.0 * i + weekly[i % 7] * 0.5 + 5 * _noise(i);
      final DateTime today = DateTime(2026, 7, 1);
      final int n = today.difference(start).inDays;
      final ForecastResult r = svc.forecast(_series(start, n, truth), today: today, horizonMonths: 2);
      expect(r.months.length, 2);
      final MonthProjection jul = r.currentMonth!;
      double expected = 0;
      for (int i = n; i < n + 31; i++) {
        expected += 800 + 1.0 * i + weekly[i % 7] * 0.5;
      }
      expect((jul.liters - expected).abs() / expected, lessThan(0.05));
      expect(jul.litersLow <= jul.liters && jul.liters <= jul.litersHigh, isTrue);
    });

    test('caída sostenida genera insight de producción cayendo', () {
      final DateTime start = DateTime(2026, 5, 1);
      final List<DailyValue> all = _series(start, 140, (int i) => 2000 - 6.0 * i + 10 * _noise(i));
      final ForecastResult r = svc.forecast(all, today: DateTime(2026, 5, 1 + 140));
      expect(r.trend.falling, isTrue);
      final List<ForecastInsight> ins = ForecastService.buildInsights(r);
      expect(ins.any((ForecastInsight i) => i.text.contains('cayendo')), isTrue);
    });
  });

  group('Finanzas', () {
    final DateTime start = DateTime(2026, 6, 1);
    final List<DailyValue> data = _series(start, 150, (int i) => 1000 + 4 * _noise(i));
    final DateTime today = DateTime(2026, 11, 18);

    test('ganancia acumulada con precio de venta configurado', () {
      final ForecastResult r = svc.forecast(
        data,
        today: today,
        finance: const FinanceInputs(purchasePricePerLiter: 1800, salePricePerLiter: 2200, monthlyOperatingCost: 2000000),
      );
      expect(r.financeConfigured, isTrue);
      expect(r.months.length, 5);
      expect(r.months.last.month, DateTime(2027, 4, 1));
      final MonthProjection dec = r.months.first;
      expect(dec.net, closeTo(dec.liters * 400 - 2000000, 1));
      expect(dec.netLow! <= dec.net! && dec.net! <= dec.netHigh!, isTrue);
      expect(r.totalNet, greaterThan(0));
      final List<ForecastInsight> ins = ForecastService.buildInsights(r);
      expect(ins.first.text, contains('abril 2027'));
      expect(ins.first.text, contains('ganancia acumulada'));
      _expectFinite(r);
    });

    test('pérdida cuando el precio de venta no cubre la tarifa', () {
      final ForecastResult r = svc.forecast(
        data,
        today: today,
        finance: const FinanceInputs(purchasePricePerLiter: 2000, salePricePerLiter: 1900, monthlyOperatingCost: 0),
      );
      expect(r.totalNet, lessThan(0));
      final List<ForecastInsight> ins = ForecastService.buildInsights(r);
      expect(ins.any((ForecastInsight i) => i.text.contains('no cubre la tarifa')), isTrue);
    });

    test('sin configuración financiera: solo litros y costo', () {
      final ForecastResult r = svc.forecast(data, today: today, finance: const FinanceInputs(purchasePricePerLiter: 1800));
      expect(r.financeConfigured, isFalse);
      expect(r.totalNet, isNull);
      expect(r.months.first.net, isNull);
      expect(r.months.first.purchaseCost, closeTo(r.months.first.liters * 1800, 1));
    });
  });

  group('Robustez', () {
    final DateTime today = DateTime(2026, 11, 18);

    test('serie vacía', () {
      final ForecastResult r = svc.forecast(const <DailyValue>[], today: today);
      expect(r.isOk, isFalse);
      expect(r.missingDays, ForecastService.minHistoryDays);
      expect(r.message, contains('Aún no hay entregas'));
      _expectFinite(r);
    });

    test('un solo punto', () {
      final ForecastResult r = svc.forecast(<DailyValue>[DailyValue(DateTime(2026, 11, 17), 500)], today: today);
      expect(r.isOk, isFalse);
      expect(r.historyDays, 1);
      expect(r.message, contains('faltan 13 días'));
    });

    test('serie constante', () {
      final ForecastResult r = svc.forecast(_series(DateTime(2026, 9, 1), 78, (_) => 700), today: today);
      expect(r.isOk, isTrue);
      for (final ForecastPoint p in r.daily.take(30)) {
        expect(p.value, closeTo(700, 1e-6));
      }
      expect(r.best!.accuracy, closeTo(1, 1e-9));
      _expectFinite(r);
    });

    test('serie con muchos ceros y valores negativos / NaN / infinitos', () {
      final ForecastResult r = svc.forecast(
        _series(DateTime(2026, 9, 1), 78, (int i) {
          if (i % 5 == 0) return double.nan;
          if (i % 7 == 0) return double.infinity;
          if (i % 3 == 0) return -50;
          return i.isEven ? 0 : 300;
        }),
        today: today,
      );
      expect(r.isOk, isTrue);
      _expectFinite(r);
    });

    test('valores enormes no producen NaN ni infinitos', () {
      final ForecastResult r = svc.forecast(
        _series(DateTime(2026, 8, 1), 100, (int i) => 1e300 * (1 + 0.1 * _noise(i))),
        today: today,
        finance: const FinanceInputs(purchasePricePerLiter: 1e10, salePricePerLiter: 1e12, monthlyOperatingCost: 1e15),
      );
      expect(r.isOk, isTrue);
      for (final ForecastPoint p in r.daily) {
        expect(p.value.isNaN, isFalse);
      }
      expect(r.best!.smape.isFinite, isTrue);
    });

    test('valores grandes pero realistas (10^25)', () {
      final ForecastResult r = svc.forecast(
        _series(DateTime(2026, 8, 1), 100, (int i) => 1e25 + 1e23 * _noise(i)),
        today: today,
        finance: const FinanceInputs(purchasePricePerLiter: 1800, salePricePerLiter: 2100),
      );
      _expectFinite(r);
    });

    test('datos futuros se ignoran y fechas duplicadas se suman', () {
      final List<DailyValue> d = <DailyValue>[
        ..._series(DateTime(2026, 10, 1), 48, (_) => 100),
        ..._series(DateTime(2026, 10, 1), 48, (_) => 100),
        DailyValue(DateTime(2027, 1, 1), 1e9),
      ];
      final ForecastResult r = svc.forecast(d, today: today);
      expect(r.daily.first.value, closeTo(200, 1e-6));
    });
  });

  group('Caídas por productor', () {
    test('detecta caída > 30 % y productor sin entregas', () {
      final List<ProducerDelivery> d = <ProducerDelivery>[];
      final DateTime rs = DateTime(2026, 11, 1);
      for (int i = 1; i <= 60; i++) {
        final DateTime day = DateTime(2026, 11, 1 - i);
        d.add(ProducerDelivery('a', 'Ana', day, 100));
        d.add(ProducerDelivery('b', 'Beto', day, 50));
        d.add(ProducerDelivery('c', 'Carla', day, 80));
      }
      for (int i = 0; i < 15; i++) {
        final DateTime day = DateTime(2026, 11, 1 + i);
        d.add(ProducerDelivery('a', 'Ana', day, 60)); // -40 %
        d.add(ProducerDelivery('c', 'Carla', day, 78)); // estable
      }
      final List<ProducerDrop> drops =
          ForecastService.detectProducerDrops(d, recentStart: rs, recentEnd: DateTime(2026, 11, 15));
      expect(drops.map((ProducerDrop x) => x.producerId).toList(), <String>['b', 'a']);
      expect(drops[1].change, closeTo(-0.4, 1e-9));
      expect(drops[0].daysSinceLast, 15);
      final List<ForecastInsight> ins = ForecastService.buildInsights(
        const ForecastResult(status: ForecastStatus.insufficient, historyDays: 0, minDays: 14),
        drops: drops,
      );
      expect(ins.any((ForecastInsight i) => i.text.contains('Ana redujo sus entregas 40 %')), isTrue);
    });

    test('lista vacía no falla', () {
      expect(
        ForecastService.detectProducerDrops(const <ProducerDelivery>[],
            recentStart: DateTime(2026, 1, 1), recentEnd: DateTime(2026, 1, 1)),
        isEmpty,
      );
    });
  });

  test('rendimiento: 2 años de datos en menos de 2 s', () {
    final Stopwatch sw = Stopwatch()..start();
    svc.forecast(
      _series(DateTime(2024, 11, 1), 745, (int i) => 900 + 0.3 * i + weekly[i % 7] + 20 * _noise(i)),
      today: DateTime(2026, 11, 18),
    );
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
