import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/rate_controller.dart';
import 'package:pgc_asoproganucot/controllers/settlement_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/file_export_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/services/settlement_pdf_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/settlements/settlement_exports.dart';

final DateTime _now = DateTime.utc(2026, 11, 18, 9);

MilkReceptionModel _rec(
  String id,
  String producer,
  String date,
  String shift,
  double liters, {
  bool anulado = false,
  bool synced = true,
  String? liquidacionId,
  String name = 'Productor',
}) => MilkReceptionModel(
  recepcionId: id,
  productorId: producer,
  codigoAsociadoSnap: 'COD-$producer',
  nombreProductorSnap: name,
  litros: liters,
  fechaEntrega: date,
  horaEntrega: shift == AppConstants.shiftMorning ? '06:00:00' : '16:00:00',
  jornada: shift,
  operarioUid: 'op',
  syncStatus: synced ? AppConstants.syncSynced : AppConstants.syncPending,
  isSynced: synced,
  anulado: anulado,
  liquidacionId: liquidacionId,
  createdAt: _now,
);

SettlementModel _settlement(
  String id,
  String producer,
  String start,
  String end, {
  double liters = 100,
  double value = 185000,
  bool paid = false,
  String label = '1ra Quincena Nov 2026',
  int deliveries = 10,
  DateTime? closed,
}) => SettlementModel(
  liquidacionId: id,
  productorId: producer,
  nombreProductorSnap: 'Productor $producer',
  cedulaProductorSnap: '10735$producer',
  periodoInicio: start,
  periodoFin: end,
  quincenaLabel: label,
  totalLitros: liters,
  cantidadEntregas: deliveries,
  precioLitroAplicado: 1850,
  valorTotalPagar: value,
  estadoPago: paid ? 'PAGADA' : 'PENDIENTE',
  fechaPago: paid ? _now : null,
  observacionPago: paid ? 'Transferencia' : null,
  fechaLiquidacion: closed ?? _now,
  numeroComprobante: 'COMP-2026-${id.padLeft(4, '0')}',
  hashIntegridad: 'ab12cd34ef56' * 5 + 'abcd',
  creadoPorUid: 'admin',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpanishNumberWords (valor en letras COP)', () {
    test('casos básicos y apócope', () {
      expect(SpanishNumberWords.pesos(0), 'CERO PESOS M/CTE');
      expect(SpanishNumberWords.pesos(1), 'UN PESO M/CTE');
      expect(SpanishNumberWords.pesos(21), 'VEINTIÚN PESOS M/CTE');
      expect(SpanishNumberWords.pesos(31), 'TREINTA Y UN PESOS M/CTE');
      expect(SpanishNumberWords.pesos(100), 'CIEN PESOS M/CTE');
      expect(SpanishNumberWords.pesos(101), 'CIENTO UN PESOS M/CTE');
      expect(SpanishNumberWords.pesos(1000), 'MIL PESOS M/CTE');
      expect(SpanishNumberWords.pesos(21000), 'VEINTIÚN MIL PESOS M/CTE');
      expect(
        SpanishNumberWords.pesos(1850),
        'MIL OCHOCIENTOS CINCUENTA PESOS M/CTE',
      );
      expect(
        SpanishNumberWords.pesos(716),
        'SETECIENTOS DIECISÉIS PESOS M/CTE',
      );
    });

    test('millones, "de pesos" y centavos', () {
      expect(SpanishNumberWords.pesos(1000000), 'UN MILLÓN DE PESOS M/CTE');
      expect(
        SpanishNumberWords.pesos(2500000),
        'DOS MILLONES QUINIENTOS MIL PESOS M/CTE',
      );
      expect(
        SpanishNumberWords.pesos(1000000000),
        'MIL MILLONES DE PESOS M/CTE',
      );
      expect(
        SpanishNumberWords.pesos(61512.5),
        'SESENTA Y UN MIL QUINIENTOS DOCE PESOS CON CINCUENTA CENTAVOS M/CTE',
      );
      expect(SpanishNumberWords.pesos(0.01), 'CERO PESOS CON UN CENTAVO M/CTE');
      expect(
        SpanishNumberWords.pesos(1234567.89),
        'UN MILLÓN DOSCIENTOS TREINTA Y CUATRO MIL QUINIENTOS SESENTA Y SIETE PESOS CON OCHENTA Y NUEVE CENTAVOS M/CTE',
      );
      expect(
        SpanishNumberWords.pesos(1000000000000),
        'UN BILLÓN DE PESOS M/CTE',
      );
    });

    test('valores extremos no rompen', () {
      expect(SpanishNumberWords.pesos(double.nan), '');
      expect(SpanishNumberWords.pesos(double.infinity), '');
      expect(SpanishNumberWords.pesos(1e25), '');
      expect(SpanishNumberWords.pesos(-5), 'MENOS CINCO PESOS M/CTE');
      expect(
        SpanishNumberWords.integer(
          999999999999999,
        ).startsWith('novecientos noventa y nueve billones'),
        isTrue,
      );
    });
  });

  group('SettlementCalculator casos extremos', () {
    test('redondeo a centavos y números grandes', () {
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 0.001,
          pricePerLiter: 1850,
        ),
        1.85,
      );
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 0,
          pricePerLiter: 1850,
        ),
        0,
      );
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 12.345,
          pricePerLiter: 1850.555,
        ),
        22845.16,
      );
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 1000000,
          pricePerLiter: 99999,
        ),
        99999000000,
      );
      expect(SettlementCalculator.roundToCents(1234.567), 1234.57);
      expect(SettlementCalculator.roundToCents(-1.234), -1.23);
      expect(SettlementCalculator.roundToThousandths(0.1 + 0.2), 0.3);
      // 0,1 L × 3 entregas no debe arrastrar error binario.
      double sum = 0;
      for (int i = 0; i < 3; i++) {
        sum += 0.1;
      }
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: sum,
          pricePerLiter: 1000,
        ),
        300,
      );
    });

    test('código de verificación corto', () {
      expect(
        SettlementCalculator.verificationCode('ab12cd34ef56aaaa'),
        'AB12-CD34-EF56',
      );
      expect(SettlementCalculator.verificationCode(''), 'N/D');
      expect(SettlementCalculator.verificationCode('abc'), 'ABC');
    });
  });

  group('DailyDeliveryMatrix', () {
    test('días del rango (incluye cambio de mes, orden inverso y tope)', () {
      expect(
        DailyDeliveryMatrix.daysBetween('2026-02-27', '2026-03-02'),
        <String>['2026-02-27', '2026-02-28', '2026-03-01', '2026-03-02'],
      );
      expect(
        DailyDeliveryMatrix.daysBetween('2026-11-03', '2026-11-01').length,
        3,
      );
      expect(
        DailyDeliveryMatrix.daysBetween('2020-01-01', '2030-01-01').length,
        DailyDeliveryMatrix.maxDays,
      );
      expect(DailyDeliveryMatrix.daysBetween('basura', '2026-01-01'), isEmpty);
    });

    test('agrupa M/T por día con totales por fila y columna', () {
      final List<MilkReceptionModel> recs = <MilkReceptionModel>[
        _rec(
          '1',
          'A',
          '2026-11-01',
          AppConstants.shiftMorning,
          10.5,
          name: 'Zuluaga',
        ),
        _rec(
          '2',
          'A',
          '2026-11-01',
          AppConstants.shiftAfternoon,
          8.25,
          name: 'Zuluaga',
        ),
        _rec(
          '3',
          'A',
          '2026-11-02',
          AppConstants.shiftMorning,
          0.1,
          name: 'Zuluaga',
        ),
        _rec(
          '4',
          'B',
          '2026-11-02',
          AppConstants.shiftMorning,
          20,
          name: 'Álvarez',
        ),
        _rec(
          '5',
          'B',
          '2026-11-02',
          AppConstants.shiftMorning,
          0.2,
          name: 'Álvarez',
        ),
        _rec(
          '6',
          'B',
          '2026-11-03',
          AppConstants.shiftAfternoon,
          99,
          anulado: true,
          name: 'Álvarez',
        ),
        _rec(
          '7',
          'B',
          '2026-11-20',
          AppConstants.shiftAfternoon,
          50,
          name: 'Álvarez',
        ), // fuera de rango
      ];
      final DailyDeliveryMatrix m = DailyDeliveryMatrix.build(
        startIso: '2026-11-01',
        endIso: '2026-11-04',
        receptions: recs,
        producerOrder: <({String productorId, String codigo, String nombre})>[
          (productorId: 'C', codigo: 'C-1', nombre: 'Sin entregas'),
        ],
      );
      expect(m.days.length, 4);
      expect(m.rows.map((DailyMatrixRow r) => r.productorId).toList(), <String>[
        'C',
        'B',
        'A',
      ]);
      final DailyMatrixRow a = m.rows.firstWhere(
        (DailyMatrixRow r) => r.productorId == 'A',
      );
      expect(a.cell('2026-11-01').morning, 10.5);
      expect(a.cell('2026-11-01').afternoon, 8.25);
      expect(a.total, 18.85);
      expect(a.deliveryDays, 2);
      final DailyMatrixRow b = m.rows.firstWhere(
        (DailyMatrixRow r) => r.productorId == 'B',
      );
      expect(b.cell('2026-11-02').morning, 20.2);
      expect(b.total, 20.2);
      expect(m.rows.first.total, 0);
      expect(m.columnTotal('2026-11-02').morning, 20.3);
      expect(m.columnTotal('2026-11-02').afternoon, 0);
      expect(m.grandTotal, 39.05);
      expect(m.grandMorning + m.grandAfternoon, closeTo(m.grandTotal, 1e-9));
      expect(m.emptyDays, <String>['2026-11-03', '2026-11-04']);
    });
  });

  group('SettlementPeriodGroup', () {
    test('agrupa por período, ordena y totaliza al centavo', () {
      final List<SettlementPeriodGroup> groups =
          SettlementPeriodGroup.groupAll(<SettlementModel>[
            _settlement(
              '1',
              'A',
              '2026-11-01',
              '2026-11-15',
              liters: 100.1,
              value: 185185.0,
              paid: true,
            ),
            _settlement(
              '2',
              'B',
              '2026-11-01',
              '2026-11-15',
              liters: 0.2,
              value: 370.1,
            ),
            _settlement(
              '3',
              'A',
              '2026-10-16',
              '2026-10-31',
              label: '2da Quincena Oct 2026',
              closed: DateTime.utc(2026, 11, 1),
            ),
          ]);
      expect(groups.length, 2);
      expect(groups.first.periodoInicio, '2026-11-01');
      final SettlementPeriodGroup g = groups.first;
      expect(g.producerCount, 2);
      expect(g.paidCount, 1);
      expect(g.pendingCount, 1);
      expect(g.totalLiters, 100.3);
      expect(g.totalAmount, 185555.1);
      expect(g.paidAmount, 185185.0);
      expect(g.pendingAmount, 370.1);
      expect(g.paidRatio, 0.5);
      expect(g.fullyPaid, isFalse);
      expect(g.key, '2026-11-01_2026-11-15');
      expect(groups.last.label, '2da Quincena Oct 2026');
    });
  });

  group('Exportaciones de quincena', () {
    final SettlementPeriodGroup group =
        SettlementPeriodGroup.groupAll(<SettlementModel>[
          _settlement(
            '1',
            'A',
            '2026-11-01',
            '2026-11-15',
            liters: 18.75,
            value: 34687.5,
          ),
          _settlement(
            '2',
            'B',
            '2026-11-01',
            '2026-11-15',
            liters: 20,
            value: 37000,
            paid: true,
          ),
        ]).first;
    final List<MilkReceptionModel> recs = <MilkReceptionModel>[
      _rec(
        'r1',
        'A',
        '2026-11-01',
        AppConstants.shiftMorning,
        10.5,
        liquidacionId: '1',
        name: 'Productor A',
      ),
      _rec(
        'r2',
        'A',
        '2026-11-01',
        AppConstants.shiftAfternoon,
        8.25,
        liquidacionId: '1',
        name: 'Productor A',
      ),
      _rec(
        'r3',
        'B',
        '2026-11-03',
        AppConstants.shiftMorning,
        20,
        liquidacionId: '2',
        name: '=B Productor',
      ),
    ];
    final DailyDeliveryMatrix matrix = DailyDeliveryMatrix.build(
      startIso: group.periodoInicio,
      endIso: group.periodoFin,
      receptions: recs,
    );

    test(
      'Excel contiene las hojas Resumen, Registros diarios y Productores',
      () {
        final Uint8List bytes = SettlementExports.buildXlsx(
          group: group,
          matrix: matrix,
        );
        final Archive zip = ZipDecoder().decodeBytes(bytes);
        final List<String> names = zip.files
            .map((ArchiveFile f) => f.name)
            .toList();
        expect(
          names,
          containsAll(<String>[
            'xl/workbook.xml',
            'xl/worksheets/sheet1.xml',
            'xl/worksheets/sheet2.xml',
            'xl/worksheets/sheet3.xml',
          ]),
        );
        final String workbook = utf8.decode(
          zip.findFile('xl/workbook.xml')!.content as List<int>,
        );
        expect(workbook, contains('name="Resumen"'));
        expect(workbook, contains('name="Registros diarios"'));
        expect(workbook, contains('name="Productores"'));
        final String daily = utf8.decode(
          zip.findFile('xl/worksheets/sheet2.xml')!.content as List<int>,
        );
        // 15 días × 2 jornadas + código + productor + 3 totales.
        expect(daily, contains('Dom 01/11 M'));
        expect(daily, contains('<v>10.5</v>'));
        final String producers = utf8.decode(
          zip.findFile('xl/worksheets/sheet3.xml')!.content as List<int>,
        );
        expect(producers, contains('COMP-2026-0001'));
        expect(producers, contains('PAGADA'));
      },
    );

    test('hoja diaria tiene columnas M/T por día y totales', () {
      final TableSheet sheet = SettlementExports.dailySheet(matrix);
      expect(sheet.columns.length, 2 + 15 * 2 + 3);
      expect(sheet.rows.length, 2);
      expect(sheet.totals!.last, 38.75);
    });

    test(
      'CSV plano por entrega, con BOM, separador ; y sin inyección de fórmulas',
      () {
        final Uint8List bytes = CsvBuilder.build(
          SettlementExports.flatRecordsSheet(group, recs),
        );
        final String text = utf8.decode(bytes);
        expect(bytes.take(3).toList(), <int>[0xEF, 0xBB, 0xBF]);
        final List<String> lines = text.trim().split('\n');
        expect(lines.first, contains('Fecha;Jornada;Código;Productor;Litros'));
        expect(lines.length, 4);
        expect(text, contains("'=B Productor"));
        expect(text, contains('Mañana'));
      },
    );

    test(
      'PDF consolidado y comprobante con valores enormes generan %PDF',
      () async {
        final Uint8List report =
            await SettlementPdfService.buildPeriodReportPdfBytes(
              group: group,
              matrix: matrix,
            );
        expect(String.fromCharCodes(report.take(4)), '%PDF');

        final SettlementModel huge = _settlement(
          '9',
          'A',
          '2026-11-01',
          '2026-11-15',
          liters: 9999999.999,
          value: 999999999999.99,
        );
        final Uint8List voucher =
            await SettlementPdfService.buildVoucherPdfBytes(
              settlement: huge,
              receptions: recs,
            );
        expect(String.fromCharCodes(voucher.take(4)), '%PDF');
        expect(
          SettlementPdfService.voucherFileName(huge),
          'Comprobante_COMP-2026-0009.pdf',
        );
        expect(
          SettlementPdfService.voucherShareText(huge),
          contains('pendiente de pago'),
        );
      },
    );
  });

  group('SettlementController: previsualización y exclusión de productores', () {
    test(
      'cierra solo los productores incluidos y deja abiertos los excluidos',
      () async {
        final HiveService hive = HiveService(enablePersistence: false);
        final _Receptions remoteRecs = _Receptions();
        final _Settlements remoteSet = _Settlements(remoteRecs.docs);
        final _Rates remoteRates = _Rates();
        final RateService rateService = RateService(
          hiveService: hive,
          remoteDataSource: remoteRates,
        );
        final UserModel admin = UserModel(
          uid: 'admin',
          nombreCompleto: 'Admin',
          documento: '1000',
          correo: 'a@a.co',
          telefono: '3100000000',
          rol: AppConstants.roleAdmin,
          activo: true,
          fcmTokens: const <String>[],
          fechaCreacion: _now,
        );
        await rateService.createNewRate(
          actor: admin,
          precioPorLitro: 2000,
          fechaInicioVigencia: DateTime.utc(2026, 10, 1),
          observacion: 'Tarifa de prueba',
        );
        for (final MilkReceptionModel r in <MilkReceptionModel>[
          _rec('a1', 'A', '2026-11-02', AppConstants.shiftMorning, 10),
          _rec('a2', 'A', '2026-11-03', AppConstants.shiftAfternoon, 5.5),
          _rec('b1', 'B', '2026-11-02', AppConstants.shiftMorning, 7),
        ]) {
          remoteRecs.docs[r.recepcionId] = r;
          await hive.saveReception(r);
        }
        final SettlementController ctrl = SettlementController(
          settlementService: SettlementService(
            hiveService: hive,
            remoteDataSource: remoteSet,
          ),
          receptionService: ReceptionService(
            hiveService: hive,
            remoteDataSource: remoteRecs,
          ),
          producerService: ProducerService(
            hiveService: hive,
            remoteDataSource: _Producers(),
          ),
          rateService: rateService,
        );
        await ctrl.loadData();
        final QuincenaPeriod q = QuincenaPeriod.forHalfMonth(
          year: 2026,
          month: 11,
          firstHalf: true,
        );

        final SettlementPreviewResult full = ctrl.previewForPeriod(q);
        expect(full.candidates.length, 2);
        expect(full.totalAmountToPay, 45000);
        final SettlementPreviewResult partial = ctrl.previewForPeriod(
          q,
          excludedProducerIds: <String>{'B'},
        );
        expect(partial.candidates.single.productorId, 'A');
        expect(partial.totalAmountToPay, 31000);

        final bool ok = await ctrl.executeQuincenaClose(
          actor: admin,
          period: q,
          excludedProducerIds: <String>{'B'},
        );
        expect(ok, isTrue, reason: ctrl.errorMessage);
        expect(ctrl.lastClosedCount, 1);
        expect(ctrl.allSettlements.single.productorId, 'A');
        expect(ctrl.periodGroups.single.totalAmount, 31000);
        expect(ctrl.receptionsForGroup(ctrl.periodGroups.single).length, 2);

        // B quedó abierto para un cierre posterior; A no se vuelve a liquidar.
        final SettlementPreviewResult after = ctrl.previewForPeriod(q);
        expect(after.candidates.single.productorId, 'B');

        final bool paid = await ctrl.confirmPayment(
          actor: admin,
          settlement: ctrl.allSettlements.single,
          observacionPago: 'Efectivo',
          fechaPago: DateTime(2026, 11, 17, 10),
        );
        expect(paid, isTrue);
        expect(ctrl.allSettlements.single.fechaPago!.toLocal().day, 17);
      },
    );

    test('impacto de nueva tarifa sobre los litros de la quincena', () {
      final ({double cost, double currentCost, double diff, double? percent})
      r = RateController.impact(
        liters: 1000.5,
        newPrice: 1900,
        currentPrice: 1850,
      );
      expect(r.cost, 1900950);
      expect(r.currentCost, 1850925);
      expect(r.diff, 50025);
      expect(r.percent, closeTo(2.7027, 1e-3));
      expect(
        RateController.impact(liters: 10, newPrice: 1, currentPrice: 0).percent,
        isNull,
      );
    });
  });
}

class _Receptions implements RemoteReceptionDataSource {
  final Map<String, MilkReceptionModel> docs = <String, MilkReceptionModel>{};
  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async =>
      docs.values.toList();
  @override
  Future<void> upsertReception(MilkReceptionModel reception) async =>
      docs[reception.recepcionId] = reception;
  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Producers implements RemoteProducerDataSource {
  @override
  Future<List<ProducerModel>> fetchProducers() async => <ProducerModel>[];
  @override
  Future<void> upsertProducer(ProducerModel producer) async {}
  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Rates implements RemoteRateDataSource {
  final Map<String, MilkRateModel> items = <String, MilkRateModel>{};
  @override
  Future<List<MilkRateModel>> fetchRates() async => items.values.toList();
  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {
    for (final MilkRateModel r in rates) {
      items[r.tarifaId] = r;
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Settlements implements RemoteSettlementDataSource {
  _Settlements(this.recs);
  final Map<String, MilkReceptionModel> recs;
  final Map<String, SettlementModel> items = <String, SettlementModel>{};

  @override
  Future<List<SettlementModel>> fetchSettlements() async =>
      items.values.toList();

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {
    for (final SettlementModel s in settlements) {
      items[s.liquidacionId] = s;
      for (final String id
          in receptionIdsBySettlement[s.liquidacionId] ?? const <String>[]) {
        recs[id] = recs[id]!.copyWith(liquidacionId: s.liquidacionId);
      }
    }
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {
    items[updatedSettlement.liquidacionId] = updatedSettlement;
  }
}
