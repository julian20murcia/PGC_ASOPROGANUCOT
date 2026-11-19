import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/views/desktop/reception/reception_grid_logic.dart';

ProducerModel _producer(String id, String code, {String estado = 'ACTIVO'}) =>
    ProducerModel(
      productorId: id,
      codigoAsociado: code,
      cedula: '10735${id.hashCode.abs() % 100000}',
      nombres: 'Productor',
      apellidos: code,
      telefono: '3101112233',
      nombreFinca: 'Finca $code',
      vereda: 'La Glorieta',
      estado: estado,
      aceptoHabeasData: true,
      fechaAutorizacionDatos: DateTime.utc(2026, 1, 1),
      fechaCreacion: DateTime.utc(2026, 1, 1),
    );

MilkReceptionModel _rec(
  String id,
  String productorId,
  String fecha,
  String jornada,
  double litros, {
  bool anulado = false,
  String? liquidacionId,
  bool synced = true,
}) => MilkReceptionModel(
  recepcionId: id,
  productorId: productorId,
  codigoAsociadoSnap: 'C-$productorId',
  nombreProductorSnap: 'Nombre $productorId',
  litros: litros,
  fechaEntrega: fecha,
  horaEntrega: '06:30:00',
  jornada: jornada,
  operarioUid: 'op-1',
  isSynced: synced,
  syncStatus: synced ? AppConstants.syncSynced : AppConstants.syncPending,
  anulado: anulado,
  liquidacionId: liquidacionId,
  createdAt: DateTime.utc(2026, 11, 1),
);

void main() {
  group('parseLitersInput', () {
    test('acepta formatos colombianos e internacionales', () {
      expect(parseLitersInput('12,5').value, 12.5);
      expect(parseLitersInput('12.5').value, 12.5);
      expect(parseLitersInput('12.75').value, 12.75);
      expect(parseLitersInput('1.250').value, 1250);
      expect(parseLitersInput('1.250,75').value, 1250.75);
      expect(parseLitersInput('  38 ').value, 38);
      expect(parseLitersInput('5000').value, 5000);
      expect(parseLitersInput('12,346').value, 12.35); // redondeo a 2 decimales
    });

    test('vacío se reporta como vacío, no como error', () {
      final LitersParseResult r = parseLitersInput('   ');
      expect(r.isEmpty, isTrue);
      expect(r.isValid, isFalse);
      expect(r.error, isNull);
    });

    test('rechaza letras y símbolos', () {
      for (final String bad in <String>[
        'abc',
        '12a',
        'e5',
        '1e3',
        '-5',
        '12;5',
        'NaN',
        'Infinity',
      ]) {
        final LitersParseResult r = parseLitersInput(bad);
        expect(r.isValid, isFalse, reason: bad);
        expect(r.error, isNotNull, reason: bad);
      }
    });

    test('rechaza números gigantes y por encima de 5.000 L', () {
      expect(parseLitersInput('10000000000000').isValid, isFalse);
      expect(parseLitersInput('10000000000000000000000000').isValid, isFalse);
      expect(parseLitersInput('5000,01').isValid, isFalse);
      expect(parseLitersInput('5001').error, contains('5.000'));
    });

    test('rechaza cero, comas dobles y solo separadores', () {
      expect(parseLitersInput('0').isValid, isFalse);
      expect(parseLitersInput('0,001').isValid, isFalse);
      expect(parseLitersInput('1,2,3').isValid, isFalse);
      expect(parseLitersInput('.,').isValid, isFalse);
    });

    test('formato colombiano para mostrar', () {
      expect(formatLitersCo(14.5), '14,5');
      expect(formatLitersCo(1250), '1.250');
      expect(formatLitersCo(12.75), '12,75');
    });
  });

  group('motivos automáticos', () {
    test('corrección y anulación superan los 5 caracteres exigidos', () {
      final String reason = autoCorrectionReason(12.5, 14);
      expect(reason, 'Corrección en planilla: 12,5 L → 14 L');
      expect(reason.trim().length, greaterThanOrEqualTo(5));
      final String annul = autoAnnulReason(
        _rec('r', 'p', '2026-11-18', AppConstants.shiftAfternoon, 9),
      );
      expect(annul.trim().length, greaterThanOrEqualTo(5));
      expect(annul, contains('tarde'));
    });
  });

  group('moveInGrid', () {
    const int rows = 3;
    const int cols = 4;
    test('flechas se detienen en los bordes', () {
      expect(
        moveInGrid(const GridPos(0, 0), GridMove.up, rows: rows, cols: cols),
        const GridPos(0, 0),
      );
      expect(
        moveInGrid(const GridPos(0, 0), GridMove.left, rows: rows, cols: cols),
        const GridPos(0, 0),
      );
      expect(
        moveInGrid(const GridPos(2, 3), GridMove.down, rows: rows, cols: cols),
        const GridPos(2, 3),
      );
      expect(
        moveInGrid(const GridPos(2, 3), GridMove.right, rows: rows, cols: cols),
        const GridPos(2, 3),
      );
      expect(
        moveInGrid(const GridPos(1, 1), GridMove.down, rows: rows, cols: cols),
        const GridPos(2, 1),
      );
      expect(
        moveInGrid(const GridPos(1, 1), GridMove.right, rows: rows, cols: cols),
        const GridPos(1, 2),
      );
    });

    test('Tab y Shift+Tab saltan de fila como Excel', () {
      expect(
        moveInGrid(const GridPos(0, 3), GridMove.next, rows: rows, cols: cols),
        const GridPos(1, 0),
      );
      expect(
        moveInGrid(
          const GridPos(1, 0),
          GridMove.previous,
          rows: rows,
          cols: cols,
        ),
        const GridPos(0, 3),
      );
      expect(
        moveInGrid(const GridPos(2, 3), GridMove.next, rows: rows, cols: cols),
        const GridPos(2, 3),
      );
      expect(
        moveInGrid(
          const GridPos(0, 0),
          GridMove.previous,
          rows: rows,
          cols: cols,
        ),
        const GridPos(0, 0),
      );
    });

    test('Inicio / Fin y posiciones fuera de rango', () {
      expect(
        moveInGrid(const GridPos(1, 2), GridMove.home, rows: rows, cols: cols),
        const GridPos(1, 0),
      );
      expect(
        moveInGrid(const GridPos(1, 2), GridMove.end, rows: rows, cols: cols),
        const GridPos(1, 3),
      );
      expect(
        moveInGrid(const GridPos(99, 99), GridMove.up, rows: rows, cols: cols),
        const GridPos(1, 3),
      );
      expect(
        moveInGrid(const GridPos(0, 0), GridMove.down, rows: 0, cols: 0),
        const GridPos(0, 0),
      );
    });

    test('solo los dígitos inician edición directa', () {
      expect(startsDirectEdit('7'), isTrue);
      expect(startsDirectEdit('a'), isFalse);
      expect(startsDirectEdit(null), isFalse);
      expect(startsDirectEdit('12'), isFalse);
    });
  });

  group('PlanillaMatrix', () {
    test('construye productor × día × jornada con totales', () {
      final List<ProducerModel> producers = <ProducerModel>[
        _producer('p2', 'ASO-002'),
        _producer('p1', 'ASO-001'),
      ];
      final List<MilkReceptionModel> recs = <MilkReceptionModel>[
        _rec('a', 'p1', '2026-11-01', AppConstants.shiftMorning, 10),
        _rec('b', 'p1', '2026-11-01', AppConstants.shiftAfternoon, 5.5),
        _rec('c', 'p2', '2026-11-02', AppConstants.shiftMorning, 20),
        _rec(
          'd',
          'p2',
          '2026-11-02',
          AppConstants.shiftAfternoon,
          99,
          anulado: true,
        ),
        _rec(
          'e',
          'p1',
          '2026-10-31',
          AppConstants.shiftMorning,
          50,
        ), // fuera del rango
        _rec(
          'f',
          'p9',
          '2026-11-03',
          AppConstants.shiftMorning,
          7,
        ), // productor inactivo
      ];
      final PlanillaMatrix m = PlanillaMatrix.build(
        activeProducers: producers,
        receptions: recs,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 3),
      );
      expect(m.days.length, 3);
      expect(m.columnCount, 6);
      expect(m.rows.map((PlanillaRow r) => r.codigo).toList(), <String>[
        'ASO-001',
        'ASO-002',
        'C-p9',
      ]);
      final PlanillaRow p1 = m.rows[0];
      expect(p1.cells[0].liters, 10);
      expect(p1.cells[1].liters, 5.5);
      expect(p1.total, 15.5);
      expect(p1.shiftTotal(0), 10);
      final PlanillaRow p2 = m.rows[1];
      expect(p2.cells[2].liters, 20);
      expect(p2.cells[3].isEmpty, isTrue);
      expect(p2.cells[3].isAnnulledOnly, isTrue);
      expect(m.rows[2].isActiveProducer, isFalse);
      expect(m.rows[2].producer, isNull);
      expect(m.dayTotal(0), 15.5);
      expect(m.dayTotal(1), 20);
      expect(m.columnTotal(4), 7);
      expect(m.grandTotal, 42.5);
      expect(PlanillaMatrix.shiftOf(3), AppConstants.shiftAfternoon);
      expect(m.dayOf(3), DateTime(2026, 11, 2));
    });

    test('marca múltiples, liquidadas y pendientes', () {
      final PlanillaMatrix m = PlanillaMatrix.build(
        activeProducers: <ProducerModel>[_producer('p1', 'ASO-001')],
        receptions: <MilkReceptionModel>[
          _rec('a', 'p1', '2026-11-01', AppConstants.shiftMorning, 10),
          _rec('b', 'p1', '2026-11-01', AppConstants.shiftMorning, 3),
          _rec(
            'c',
            'p1',
            '2026-11-01',
            AppConstants.shiftAfternoon,
            4,
            liquidacionId: 'liq',
          ),
          _rec(
            'd',
            'p1',
            '2026-11-02',
            AppConstants.shiftMorning,
            4,
            synced: false,
          ),
        ],
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
      );
      final PlanillaRow r = m.rows.single;
      expect(r.cells[0].hasMultiple, isTrue);
      expect(r.cells[0].single, isNull);
      expect(r.cells[0].liters, 13);
      expect(r.cells[1].isSettled, isTrue);
      expect(r.cells[2].isPending, isTrue);
      expect(r.cells[2].single?.recepcionId, 'd');
    });

    test('31 días × 100 productores se construye rápido', () {
      final List<ProducerModel> producers = <ProducerModel>[
        for (int i = 0; i < 100; i++)
          _producer('p$i', 'ASO-${i.toString().padLeft(3, '0')}'),
      ];
      final List<MilkReceptionModel> recs = <MilkReceptionModel>[
        for (int i = 0; i < 100; i++)
          for (int d = 1; d <= 31; d++) ...<MilkReceptionModel>[
            _rec(
              'm$i-$d',
              'p$i',
              '2026-12-${d.toString().padLeft(2, '0')}',
              AppConstants.shiftMorning,
              10,
            ),
            _rec(
              't$i-$d',
              'p$i',
              '2026-12-${d.toString().padLeft(2, '0')}',
              AppConstants.shiftAfternoon,
              5,
            ),
          ],
      ];
      final Stopwatch sw = Stopwatch()..start();
      final PlanillaMatrix m = PlanillaMatrix.build(
        activeProducers: producers,
        receptions: recs,
        start: DateTime(2026, 12, 1),
        end: DateTime(2026, 12, 31),
      );
      sw.stop();
      expect(m.rows.length, 100);
      expect(m.columnCount, 62);
      expect(m.grandTotal, 100 * 31 * 15);
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('rangos', () {
    test('daysBetween incluye extremos y cruza meses', () {
      final List<DateTime> days = daysBetween(
        DateTime(2026, 10, 30),
        DateTime(2026, 11, 2),
      );
      expect(days.map(isoOf).toList(), <String>[
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
      ]);
    });

    test('filterByIsoRange filtra por fecha de entrega', () {
      final List<MilkReceptionModel> items = <MilkReceptionModel>[
        _rec('a', 'p', '2026-11-01', AppConstants.shiftMorning, 1),
        _rec('b', 'p', '2026-11-15', AppConstants.shiftMorning, 1),
        _rec('c', 'p', '2026-11-16', AppConstants.shiftMorning, 1),
      ];
      expect(
        filterByIsoRange(
          items,
          '2026-11-01',
          '2026-11-15',
        ).map((MilkReceptionModel r) => r.recepcionId),
        <String>['a', 'b'],
      );
    });

    test('isFutureDay compara solo la fecha', () {
      final DateTime now = DateTime(2026, 11, 18, 23, 59);
      expect(isFutureDay(DateTime(2026, 11, 18), now), isFalse);
      expect(isFutureDay(DateTime(2026, 11, 19), now), isTrue);
    });
  });
}
