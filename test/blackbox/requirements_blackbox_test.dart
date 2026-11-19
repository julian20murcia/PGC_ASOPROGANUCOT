/// PRUEBAS DE CAJA NEGRA — Particiones de equivalencia y análisis de valores límite.
///
/// Se diseñaron a partir de los REQUISITOS (no del código): cada grupo indica
/// el requisito o regla de negocio y cada caso la clase de equivalencia o el
/// valor límite que representa. Solo se usa la interfaz pública del sistema.
@Tags(<String>['caja-negra'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/utils/input_rules.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';

/// Caso de prueba de un validador: entrada, ¿válida?, clase que representa.
typedef Case = ({String? input, bool valid, String clase});

void checkCases(String? Function(String?) validator, List<Case> cases) {
  for (final Case c in cases) {
    final String? error = validator(c.input);
    expect(error == null, c.valid, reason: '[${c.clase}] entrada="${c.input}" → error=$error');
  }
}

ProducerModel producer(String id, {String estado = 'ACTIVO'}) => ProducerModel(
      productorId: id,
      codigoAsociado: 'ASO-$id',
      cedula: '10${id.hashCode.abs() % 100000000}',
      nombres: 'Productor',
      apellidos: id,
      telefono: '3101234567',
      nombreFinca: 'Finca $id',
      vereda: 'Centro',
      estado: estado,
      aceptoHabeasData: true,
      fechaCreacion: DateTime.utc(2026),
    );

MilkReceptionModel reception(
  String id,
  String productorId,
  String fecha,
  double litros, {
  String jornada = AppConstants.shiftMorning,
  bool anulado = false,
  bool synced = true,
  String? liquidacionId,
}) =>
    MilkReceptionModel(
      recepcionId: id,
      productorId: productorId,
      codigoAsociadoSnap: 'ASO-$productorId',
      nombreProductorSnap: 'Productor $productorId',
      litros: litros,
      fechaEntrega: fecha,
      horaEntrega: '06:30',
      jornada: jornada,
      operarioUid: 'op1',
      isSynced: synced,
      syncStatus: synced ? AppConstants.syncSynced : AppConstants.syncPending,
      anulado: anulado,
      liquidacionId: liquidacionId,
      createdAt: DateTime.utc(2026, 11, 1),
    );

SettlementModel settlement(String productorId, String inicio, String fin, String comprobante) => SettlementModel(
      liquidacionId: 'liq-$productorId-$inicio',
      productorId: productorId,
      nombreProductorSnap: 'P',
      cedulaProductorSnap: '1',
      periodoInicio: inicio,
      periodoFin: fin,
      quincenaLabel: 'Q',
      totalLitros: 10,
      cantidadEntregas: 1,
      precioLitroAplicado: 1850,
      valorTotalPagar: 18500,
      fechaLiquidacion: DateTime.utc(2026, 11, 16),
      numeroComprobante: comprobante,
      hashIntegridad: 'h',
      creadoPorUid: 'admin',
    );

void main() {
  group('RF-05 Registro de productores · validación de datos personales', () {
    test('Documento de identidad: 5 a 12 dígitos numéricos, no repetidos', () {
      checkCases(AppValidators.document, <Case>[
        (input: '', valid: false, clase: 'vacío'),
        (input: '   ', valid: false, clase: 'solo espacios'),
        (input: '1234', valid: false, clase: 'límite inferior − 1 (4 dígitos)'),
        (input: '12345', valid: true, clase: 'límite inferior (5 dígitos)'),
        (input: '1012345678', valid: true, clase: 'cédula típica (10 dígitos)'),
        (input: '123456789012', valid: true, clase: 'límite superior (12 dígitos)'),
        (input: '1234567890123', valid: false, clase: 'límite superior + 1 (13 dígitos)'),
        (input: '10123A5678', valid: false, clase: 'contiene letras'),
        (input: '1.012.345', valid: false, clase: 'contiene separadores'),
        (input: '-12345', valid: false, clase: 'signo negativo'),
        (input: '1111111', valid: false, clase: 'todos los dígitos iguales'),
      ]);
    });

    test('Teléfono: celular colombiano (3 + 9 dígitos) o fijo (60 + 8 dígitos)', () {
      checkCases(AppValidators.phone, <Case>[
        (input: '', valid: false, clase: 'vacío (obligatorio)'),
        (input: '3101234567', valid: true, clase: 'celular válido'),
        (input: '310123456', valid: false, clase: 'celular de 9 dígitos'),
        (input: '31012345678', valid: false, clase: 'celular de 11 dígitos'),
        (input: '6012345678', valid: true, clase: 'fijo nacional válido'),
        (input: '2101234567', valid: false, clase: 'prefijo inexistente'),
        (input: '310-123-4567', valid: false, clase: 'con guiones'),
      ]);
      expect(AppValidators.phone('', required: false), isNull, reason: 'opcional vacío es válido');
    });

    test('Nombre: 2 a 40 letras (con tildes y ñ), sin números ni letras repetidas', () {
      checkCases(AppValidators.personName, <Case>[
        (input: '', valid: false, clase: 'vacío'),
        (input: 'A', valid: false, clase: 'límite inferior − 1 (1 letra)'),
        (input: 'Al', valid: true, clase: 'límite inferior (2 letras)'),
        (input: 'José Ñúñez', valid: true, clase: 'tildes y eñe'),
        (input: 'María-José', valid: true, clase: 'guion permitido'),
        (input: 'Ana3', valid: false, clase: 'contiene número'),
        (input: 'Ana@', valid: false, clase: 'símbolo no permitido'),
        (input: 'Aaa', valid: false, clase: 'letra repetida 3 veces'),
        (input: 'abcdefghij' * 4, valid: true, clase: 'límite superior (40)'),
        (input: '${'abcdefghij' * 4}k', valid: false, clase: 'límite superior + 1 (41)'),
      ]);
    });

    test('Correo electrónico y contraseña segura (mínimo 8, letras y números)', () {
      checkCases(AppValidators.email, <Case>[
        (input: 'ana@asoproganucott.co', valid: true, clase: 'correo válido'),
        (input: 'ana@asoproganucott', valid: false, clase: 'sin dominio de nivel superior'),
        (input: 'ana.asoproganucott.co', valid: false, clase: 'sin arroba'),
        (input: '', valid: false, clase: 'vacío'),
        (input: '${'a' * 75}@x.co', valid: true, clase: 'límite superior (80 caracteres)'),
        (input: '${'a' * 76}@x.co', valid: false, clase: 'límite superior + 1 (81 caracteres)'),
      ]);
      checkCases(AppValidators.password, <Case>[
        (input: 'abc1234', valid: false, clase: 'límite inferior − 1 (7)'),
        (input: 'abcd1234', valid: true, clase: 'límite inferior (8) con letras y números'),
        (input: 'abcdefgh', valid: false, clase: 'solo letras'),
        (input: '12345678', valid: false, clase: 'solo números'),
        (input: '', valid: false, clase: 'vacía'),
      ]);
    });
  });

  group('RF-08 Recepción de leche · litros por entrega (0 < L ≤ 5.000)', () {
    test('valores límite y clases inválidas', () {
      checkCases(AppValidators.liters, <Case>[
        (input: '', valid: false, clase: 'vacío'),
        (input: 'veinte', valid: false, clase: 'no numérico'),
        (input: '0', valid: false, clase: 'cero'),
        (input: '-5', valid: false, clase: 'negativo'),
        (input: '0,01', valid: true, clase: 'mínimo positivo (coma decimal)'),
        (input: '25,5', valid: true, clase: 'decimal típico'),
        (input: '4.999,99', valid: true, clase: 'justo bajo el límite (separador de miles)'),
        (input: '5.000', valid: true, clase: 'límite superior exacto'),
        (input: '5.000,01', valid: false, clase: 'límite superior + 0,01'),
        (input: '100.000', valid: false, clase: 'muy superior al límite'),
      ]);
    });
  });

  group('RF-13 Quincenas · cortes 1–15 y 16–fin de mes', () {
    test('el día 15 pertenece a la 1ra quincena y el 16 a la 2da', () {
      expect(QuincenaPeriod.currentForDate(DateTime(2026, 11, 15)).endDate, '2026-11-15');
      expect(QuincenaPeriod.currentForDate(DateTime(2026, 11, 16)).startDate, '2026-11-16');
      expect(QuincenaPeriod.currentForDate(DateTime(2026, 11, 1)).startDate, '2026-11-01');
    });

    test('la 2da quincena termina el último día real del mes (28, 29, 30 o 31)', () {
      String end(int y, int m) => QuincenaPeriod.forHalfMonth(year: y, month: m, firstHalf: false).endDate;
      expect(end(2027, 2), '2027-02-28', reason: 'febrero no bisiesto');
      expect(end(2028, 2), '2028-02-29', reason: 'febrero bisiesto');
      expect(end(2100, 2), '2100-02-28', reason: 'año secular no bisiesto');
      expect(end(2026, 4), '2026-04-30');
      expect(end(2026, 12), '2026-12-31');
    });

    test('la quincena anterior cruza correctamente de año', () {
      final QuincenaPeriod p = QuincenaPeriod.previousForDate(DateTime(2027, 1, 10));
      expect(p.startDate, '2026-12-16');
      expect(p.endDate, '2026-12-31');
      final QuincenaPeriod q = QuincenaPeriod.previousForDate(DateTime(2027, 1, 20));
      expect(q.startDate, '2027-01-01');
      expect(q.endDate, '2027-01-15');
    });

    test('pertenencia de una fecha: límites incluidos, vecinos excluidos', () {
      final QuincenaPeriod p = QuincenaPeriod.forHalfMonth(year: 2026, month: 11, firstHalf: true);
      expect(p.containsIsoDate('2026-10-31'), isFalse);
      expect(p.containsIsoDate('2026-11-01'), isTrue);
      expect(p.containsIsoDate('2026-11-15'), isTrue);
      expect(p.containsIsoDate('2026-11-16'), isFalse);
      expect(p.containsIsoDate(''), isFalse);
    });

    test('rango personalizado con fechas invertidas se ordena', () {
      final QuincenaPeriod p = QuincenaPeriod.custom(DateTime(2026, 11, 20), DateTime(2026, 11, 5));
      expect(p.startDate, '2026-11-05');
      expect(p.endDate, '2026-11-20');
    });
  });

  group('RF-13 Liquidación · valor a pagar = litros × precio, exacto al centavo', () {
    test('tabla de decisión de montos', () {
      final List<({double l, double p, double esperado})> casos = <({double l, double p, double esperado})>[
        (l: 0, p: 1850, esperado: 0),
        (l: 1, p: 1850, esperado: 1850),
        (l: 1.5, p: 1850, esperado: 2775),
        (l: 0.001, p: 1850, esperado: 1.85),
        (l: 0.1 + 0.2, p: 1000, esperado: 300), // 0,30000000000000004 L no debe producir centavos espurios
        (l: 33.333, p: 1850.55, esperado: 61684.38),
        (l: 5000, p: 99999, esperado: 499995000),
      ];
      for (final c in casos) {
        expect(SettlementCalculator.calculateTotalAmount(totalLiters: c.l, pricePerLiter: c.p), c.esperado,
            reason: '${c.l} L × ${c.p}');
      }
    });

    test('la pre-liquidación excluye anuladas, ya liquidadas, otras fechas y avisa las no sincronizadas', () {
      final QuincenaPeriod q = QuincenaPeriod.forHalfMonth(year: 2026, month: 11, firstHalf: true);
      final SettlementPreviewResult r = SettlementCalculator.buildPreview(
        period: q,
        pricePerLiter: 2000,
        producers: <ProducerModel>[producer('p1'), producer('p2')],
        existingSettlements: const <SettlementModel>[],
        receptions: <MilkReceptionModel>[
          reception('a', 'p1', '2026-11-01', 10),
          reception('b', 'p1', '2026-11-15', 5, jornada: AppConstants.shiftAfternoon),
          reception('c', 'p1', '2026-11-16', 99), // fuera del período
          reception('d', 'p1', '2026-11-05', 50, anulado: true), // anulada
          reception('e', 'p2', '2026-11-03', 8, liquidacionId: 'liq-vieja'), // ya liquidada
          reception('f', 'p2', '2026-11-04', 7, synced: false), // pendiente de sincronizar
        ],
      );
      final SettlementCandidate p1 = r.candidates.firstWhere((SettlementCandidate c) => c.productorId == 'p1');
      expect(p1.totalLiters, 15);
      expect(p1.morningLiters, 10);
      expect(p1.afternoonLiters, 5);
      expect(p1.valorTotalPagar, 30000);
      expect(p1.deliveryCount, 2);
      expect(r.excludedAnuladasCount, 1);
      expect(r.hasPendingSync, isTrue);
      expect(r.pendingSyncReceptions.single.recepcionId, 'f');
    });

    test('un productor ya liquidado en la quincena no se vuelve a liquidar (no doble pago)', () {
      final QuincenaPeriod q = QuincenaPeriod.forHalfMonth(year: 2026, month: 11, firstHalf: true);
      final SettlementPreviewResult r = SettlementCalculator.buildPreview(
        period: q,
        pricePerLiter: 2000,
        producers: <ProducerModel>[producer('p1')],
        existingSettlements: <SettlementModel>[settlement('p1', '2026-11-01', '2026-11-15', 'COMP-2026-0001')],
        receptions: <MilkReceptionModel>[reception('a', 'p1', '2026-11-02', 10)],
      );
      expect(r.candidates, isEmpty);
      expect(r.alreadySettledProducerIds, contains('p1'));
    });
  });

  group('RF-14 Comprobantes · numeración consecutiva por año', () {
    test('primer comprobante, consecutivo, desfase y años independientes', () {
      expect(SettlementCalculator.nextComprobanteNumber(year: 2026, existingSettlements: const <SettlementModel>[], offset: 0),
          'COMP-2026-0001');
      final List<SettlementModel> prev = <SettlementModel>[
        settlement('p1', '2026-10-01', '2026-10-15', 'COMP-2026-0009'),
        settlement('p2', '2025-12-16', '2025-12-31', 'COMP-2025-0450'),
      ];
      expect(SettlementCalculator.nextComprobanteNumber(year: 2026, existingSettlements: prev, offset: 0), 'COMP-2026-0010');
      expect(SettlementCalculator.nextComprobanteNumber(year: 2026, existingSettlements: prev, offset: 2), 'COMP-2026-0012');
      expect(SettlementCalculator.nextComprobanteNumber(year: 2027, existingSettlements: prev, offset: 0), 'COMP-2027-0001');
    });
  });

  group('Ley 527 de 1999 · huella de integridad SHA-256 del comprobante', () {
    String hash({double litros = 15, double valor = 30000, List<String> ids = const <String>['a', 'b']}) =>
        SettlementCalculator.computeIntegrityHash(
          liquidacionId: 'L1',
          numeroComprobante: 'COMP-2026-0001',
          productorId: 'p1',
          cedula: '1012345678',
          periodoInicio: '2026-11-01',
          periodoFin: '2026-11-15',
          totalLitros: litros,
          cantidadEntregas: ids.length,
          precioLitroAplicado: 2000,
          valorTotalPagar: valor,
          recepcionIds: ids,
        );

    test('es determinista, de 64 caracteres hexadecimales e independiente del orden de las entregas', () {
      expect(hash(), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash(), hash());
      expect(hash(ids: <String>['b', 'a']), hash(ids: <String>['a', 'b']));
    });

    test('cualquier alteración del contenido cambia la huella (detección de fraude)', () {
      final String original = hash();
      expect(hash(litros: 15.001), isNot(original), reason: '1 mL más');
      expect(hash(valor: 30000.01), isNot(original), reason: '1 centavo más');
      expect(hash(ids: <String>['a', 'b', 'c']), isNot(original), reason: 'una entrega extra');
    });

    test('el código de verificación impreso deriva de la huella', () {
      expect(SettlementCalculator.verificationCode('abcdef0123456789'), 'ABCD-EF01-2345');
      expect(SettlementCalculator.verificationCode(''), 'N/D');
    });
  });

  group('RF-12 Tarifas · precio vigente según la fecha de la entrega', () {
    final List<MilkRateModel> tarifas = <MilkRateModel>[
      MilkRateModel(
        tarifaId: 'vieja',
        precioPorLitro: 1700,
        fechaInicioVigencia: DateTime.utc(2026, 1, 1),
        fechaFinVigencia: DateTime.utc(2026, 6, 30, 23, 59, 59),
        observacion: 'Primer semestre',
        registradoPorUid: 'admin',
        activa: false,
      ),
      MilkRateModel(
        tarifaId: 'nueva',
        precioPorLitro: 1850,
        fechaInicioVigencia: DateTime.utc(2026, 7, 1),
        observacion: 'Segundo semestre',
        registradoPorUid: 'admin',
      ),
    ];

    test('en el inicio exacto de la vigencia aplica la tarifa nueva', () {
      expect(RateService.resolveRateForDate(tarifas, DateTime.utc(2026, 7, 1))!.tarifaId, 'nueva');
    });

    test('después del inicio aplica la vigente; sin tarifas no hay precio', () {
      expect(RateService.resolveRateForDate(tarifas, DateTime.utc(2026, 11, 19))!.precioPorLitro, 1850);
      expect(RateService.resolveRateForDate(const <MilkRateModel>[], DateTime.utc(2026, 11, 19)), isNull);
    });
  });

  group('Comprobante en letras (requisito contable)', () {
    test('montos en palabras con la moneda colombiana', () {
      String w(double v) => SpanishNumberWords.pesos(v).toLowerCase();
      expect(w(1), 'un peso m/cte');
      expect(w(1000000), contains('un millón de pesos'));
      expect(w(21), contains('veintiún pesos'));
      expect(w(1850.5), contains('con cincuenta centavos'));
      expect(SpanishNumberWords.pesos(2775), endsWith('M/CTE'));
      expect(SpanishNumberWords.pesos(double.nan), '');
    });
  });
}
