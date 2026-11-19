/// PRUEBAS DE ESTRÉS Y RENDIMIENTO.
///
/// Someten los procesos críticos a volúmenes muy superiores a la operación
/// real de la asociación (≈ 60 productores y 120 entregas diarias) y verifican
/// dos cosas: (1) que los resultados sigan siendo EXACTOS bajo carga y (2) que
/// el tiempo de respuesta quede por debajo de un presupuesto máximo.
///
/// Escenario base: 1.000 productores × 2 jornadas × 61 días = 122.000 entregas
/// (≈ 17 veces el volumen anual real concentrado en dos meses).
///
/// Cada prueba imprime una línea `METRICA {json}` que el workflow recoge para
/// el informe.
@Tags(<String>['estres'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/file_export_service.dart';
import 'package:pgc_asoproganucot/core/services/forecast_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/report_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/views/desktop/reception/reception_grid_logic.dart';

const int kProducers = 1000;
const int kDays = 61;

late final List<ProducerModel> producers;
late final List<MilkReceptionModel> receptions;

/// Litros deterministas por productor/día/jornada (en milésimas exactas).
int milli(int p, int d, int s) => 5000 + ((p * 7919 + d * 104729 + s * 15485863) % 30000);

String iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ejecuta [body], mide el tiempo, registra la métrica y verifica el presupuesto.
Future<T> measure<T>(String nombre, Duration presupuesto, Future<T> Function() body, {Map<String, Object?> extra = const <String, Object?>{}}) async {
  final Stopwatch sw = Stopwatch()..start();
  final T result = await body();
  sw.stop();
  // ignore: avoid_print
  print('METRICA ${jsonEncode(<String, Object?>{
        'prueba': nombre,
        'ms': sw.elapsedMilliseconds,
        'presupuesto_ms': presupuesto.inMilliseconds,
        ...extra,
      })}');
  expect(sw.elapsed, lessThan(presupuesto), reason: '$nombre tardó ${sw.elapsedMilliseconds} ms');
  return result;
}

void main() {
  setUpAll(() {
    producers = <ProducerModel>[
      for (int p = 0; p < kProducers; p++)
        ProducerModel(
          productorId: 'p$p',
          codigoAsociado: 'ASO-${p.toString().padLeft(4, '0')}',
          cedula: '${1000000000 + p}',
          nombres: 'Productor',
          apellidos: 'Número $p',
          telefono: '3101234567',
          nombreFinca: 'Finca $p',
          vereda: 'Vereda ${p % 12}',
          estado: 'ACTIVO',
          aceptoHabeasData: true,
          fechaCreacion: DateTime.utc(2025),
        ),
    ];
    final DateTime start = DateTime(2026, 9, 1);
    receptions = <MilkReceptionModel>[
      for (int p = 0; p < kProducers; p++)
        for (int d = 0; d < kDays; d++)
          for (int s = 0; s < 2; s++)
            MilkReceptionModel(
              recepcionId: 'r-$p-$d-$s',
              productorId: 'p$p',
              codigoAsociadoSnap: 'ASO-$p',
              nombreProductorSnap: 'Productor $p',
              litros: milli(p, d, s) / 1000,
              fechaEntrega: iso(start.add(Duration(days: d))),
              horaEntrega: s == 0 ? '06:00' : '15:00',
              jornada: s == 0 ? AppConstants.shiftMorning : AppConstants.shiftAfternoon,
              operarioUid: 'op',
              isSynced: true,
              syncStatus: AppConstants.syncSynced,
              createdAt: DateTime.utc(2026, 9, 1),
            ),
    ];
  });

  test('volumen del escenario', () {
    expect(receptions.length, kProducers * kDays * 2); // 122.000
  });

  test('cierre de quincena: pre-liquidación de 1.000 productores con 30.000+ entregas, exacta al centavo', () async {
    final QuincenaPeriod q = QuincenaPeriod.forHalfMonth(year: 2026, month: 9, firstHalf: true);
    final SettlementPreviewResult r = await measure(
      'Pre-liquidación de quincena (122.000 entregas, 1.000 productores)',
      const Duration(milliseconds: 1500),
      () async => SettlementCalculator.buildPreview(
        period: q,
        pricePerLiter: 1850.55,
        receptions: receptions,
        producers: producers,
        existingSettlements: const <SettlementModel>[],
      ),
      extra: <String, Object?>{'entregas': receptions.length, 'productores': kProducers},
    );
    expect(r.candidates.length, kProducers);
    // Verificación independiente con aritmética entera (milésimas × centavos).
    int expectedCents = 0;
    for (int p = 0; p < kProducers; p++) {
      int m = 0;
      for (int d = 0; d < 15; d++) {
        m += milli(p, d, 0) + milli(p, d, 1);
      }
      expectedCents += ((m * 185055) / 1000).round();
    }
    final int gotCents = r.candidates.fold<int>(0, (int a, SettlementCandidate c) => a + (c.valorTotalPagar * 100).round());
    expect(gotCents, expectedCents, reason: 'sin derivas de coma flotante bajo carga');
    expect(r.totalDeliveries, kProducers * 15 * 2);
  });

  test('1.000.000 de cálculos de pago sin un solo centavo de error', () async {
    int mismatches = 0;
    await measure('1.000.000 cálculos litros × precio', const Duration(milliseconds: 2000), () async {
      for (int i = 0; i < 1000000; i++) {
        final int m = 1 + (i * 7919) % 5000000; // hasta 5.000 L en milésimas
        final int priceCents = 100000 + (i * 104729) % 9899900; // $1.000 a $99.000
        final double got = SettlementCalculator.calculateTotalAmount(totalLiters: m / 1000, pricePerLiter: priceCents / 100);
        final int expected = ((m * priceCents) / 1000).round();
        if ((got * 100).round() != expected) mismatches++;
      }
    }, extra: <String, Object?>{'operaciones': 1000000});
    expect(mismatches, 0);
  });

  test('planilla de recepción: matriz 1.000 productores × 61 días × 2 jornadas', () async {
    final PlanillaMatrix m = await measure(
      'Construcción de la planilla (1.000 × 122 celdas)',
      const Duration(milliseconds: 1500),
      () async => PlanillaMatrix.build(
        activeProducers: producers,
        receptions: receptions,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 31),
      ),
      extra: <String, Object?>{'celdas': kProducers * kDays * 2},
    );
    expect(m.rows.length, kProducers);
    expect(m.days.length, kDays);
    final double expected0 = <int>[for (int d = 0; d < kDays; d++) milli(0, d, 0) + milli(0, d, 1)].reduce((int a, int b) => a + b) / 1000;
    expect(m.rows.firstWhere((PlanillaRow r) => r.productorId == 'p0').total, closeTo(expected0, 1e-6));
  });

  test('reportes: resumen por productor de dos meses de operación', () async {
    final QuincenaPeriod range = QuincenaPeriod.custom(DateTime(2026, 9, 1), DateTime(2026, 10, 31));
    final List<ProducerProductionSummary> s = await measure(
      'Reporte consolidado por productor (122.000 entregas)',
      const Duration(milliseconds: 1500),
      () async => ReportService.buildProducerSummaries(
        period: range,
        receptions: receptions,
        producers: producers,
        settlements: const <SettlementModel>[],
        activePricePerLiter: 1850,
      ),
    );
    expect(s.length, kProducers);
    final double total = s.fold<double>(0, (double a, ProducerProductionSummary x) => a + x.totalLiters);
    final int expectedMilli = <int>[
      for (int p = 0; p < kProducers; p++)
        for (int d = 0; d < kDays; d++) milli(p, d, 0) + milli(p, d, 1),
    ].reduce((int a, int b) => a + b);
    expect((total * 1000).round(), expectedMilli);
  });

  test('predicción: Holt-Winters con 2 años de historia diaria', () async {
    final DateTime t0 = DateTime(2024, 11, 19);
    final List<DailyValue> series = <DailyValue>[
      for (int d = 0; d < 730; d++)
        DailyValue(
          t0.add(Duration(days: d)),
          6000 + 400 * ((d % 7) - 3) + d * 1.5 + ((d * 7919) % 300),
        ),
    ];
    final ForecastResult r = await measure(
      'Proyección de 5 meses (730 días de historia)',
      const Duration(seconds: 6),
      () async => const ForecastService().forecast(series, today: DateTime(2026, 11, 19)),
      extra: <String, Object?>{'dias_historia': 730},
    );
    expect(r.isOk, isTrue);
    expect(r.months.length, 5);
    for (final MonthProjection m in r.months) {
      expect(m.liters.isFinite && m.liters > 0, isTrue);
    }
  });

  test('exportación: libro de Excel con 50.000 filas', () async {
    final TableSheet sheet = TableSheet(
      name: 'Entregas',
      title: 'Estrés',
      columns: const <XlsxColumn>[
        XlsxColumn('Fecha', type: XlsxCellType.date),
        XlsxColumn('Código'),
        XlsxColumn('Productor', width: 30),
        XlsxColumn('Jornada'),
        XlsxColumn('Litros', type: XlsxCellType.liters),
        XlsxColumn('Valor', type: XlsxCellType.money),
      ],
      rows: <List<Object?>>[
        for (final MilkReceptionModel r in receptions.take(50000))
          <Object?>[r.fechaEntrega, r.codigoAsociadoSnap, r.nombreProductorSnap, r.jornada, r.litros, r.litros * 1850],
      ],
    );
    final List<int> bytes = await measure('Excel de 50.000 filas', const Duration(seconds: 8), () async => XlsxBuilder.build(<TableSheet>[sheet]));
    expect(bytes.length, greaterThan(100000));
    expect(bytes.sublist(0, 2), <int>[0x50, 0x4B], reason: 'archivo ZIP/XLSX válido');
  });

  test('caché local: escritura en lote y lectura de 122.000 entregas', () async {
    final HiveService hive = HiveService(enablePersistence: false);
    await hive.init();
    await measure('Caché local: guardar 122.000 entregas', const Duration(seconds: 5), () => hive.cacheReceptions(receptions));
    final List<MilkReceptionModel> back = await measure('Caché local: leer 122.000 entregas', const Duration(seconds: 5), hive.getReceptions);
    expect(back.length, receptions.length);
  });

  test('concurrencia: 200 huellas SHA-256 en paralelo son deterministas', () async {
    final List<String> ids = <String>[for (int i = 0; i < 30; i++) 'r$i'];
    final List<String> hashes = await measure('200 huellas de integridad concurrentes', const Duration(milliseconds: 1500), () {
      return Future.wait(<Future<String>>[
        for (int i = 0; i < 200; i++)
          Future<String>(() => SettlementCalculator.computeIntegrityHash(
                liquidacionId: 'L${i % 10}',
                numeroComprobante: 'COMP-2026-${(i % 10).toString().padLeft(4, '0')}',
                productorId: 'p${i % 10}',
                cedula: '1012345678',
                periodoInicio: '2026-11-01',
                periodoFin: '2026-11-15',
                totalLitros: 450.5,
                cantidadEntregas: 30,
                precioLitroAplicado: 1850,
                valorTotalPagar: 833425,
                recepcionIds: i.isEven ? ids : ids.reversed.toList(),
              )),
      ]);
    });
    expect(hashes.toSet().length, 10, reason: '10 comprobantes distintos, misma huella sin importar el orden');
  });
}
