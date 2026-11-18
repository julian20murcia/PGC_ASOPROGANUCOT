import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/rate_controller.dart';
import 'package:pgc_asoproganucot/controllers/settlement_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
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

class _InMemoryRemoteRateDataSource implements RemoteRateDataSource {
  final Map<String, MilkRateModel> remoteRates = <String, MilkRateModel>{};
  final List<AuditLogModel> auditLogs = <AuditLogModel>[];

  @override
  Future<List<MilkRateModel>> fetchRates() async => remoteRates.values.toList();

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {
    for (final MilkRateModel r in rates) {
      remoteRates[r.tarifaId] = r;
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    auditLogs.add(log);
  }
}

class _InMemoryRemoteSettlementDataSource
    implements RemoteSettlementDataSource {
  _InMemoryRemoteSettlementDataSource({this.receptionsStore});

  final Map<String, MilkReceptionModel>? receptionsStore;
  final Map<String, SettlementModel> remoteSettlements =
      <String, SettlementModel>{};
  final List<AppNotificationModel> notifications = <AppNotificationModel>[];
  final List<AuditLogModel> auditLogs = <AuditLogModel>[];

  @override
  Future<List<SettlementModel>> fetchSettlements() async =>
      remoteSettlements.values.toList();

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {
    for (final SettlementModel s in settlements) {
      remoteSettlements[s.liquidacionId] = s;
      if (receptionsStore != null) {
        final List<String> recIds =
            receptionIdsBySettlement[s.liquidacionId] ?? const <String>[];
        for (final String recId in recIds) {
          final MilkReceptionModel? r = receptionsStore![recId];
          if (r != null) {
            receptionsStore![recId] = r.copyWith(liquidacionId: s.liquidacionId);
          }
        }
      }
    }
    this.notifications.addAll(notifications);
    auditLogs.add(auditLog);
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {
    remoteSettlements[updatedSettlement.liquidacionId] = updatedSettlement;
    notifications.add(notification);
    auditLogs.add(auditLog);
  }
}

class _InMemoryRemoteReceptionSource implements RemoteReceptionDataSource {
  final Map<String, MilkReceptionModel> remoteDocs =
      <String, MilkReceptionModel>{};

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async =>
      remoteDocs.values.toList();

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    remoteDocs[reception.recepcionId] = reception;
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemoryProducerSource implements RemoteProducerDataSource {
  _InMemoryProducerSource(this.items);
  final List<ProducerModel> items;

  @override
  Future<List<ProducerModel>> fetchProducers() async => items;

  @override
  Future<void> upsertProducer(ProducerModel producer) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

void main() {
  final DateTime refNow = DateTime.utc(2026, 11, 18, 9, 0);

  final UserModel adminActor = UserModel(
    uid: 'admin-uid-1',
    nombreCompleto: 'Administrador Planta',
    documento: '1000',
    correo: 'admin@asoproganucot.com',
    telefono: '3100000001',
    rol: AppConstants.roleAdmin,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: refNow,
  );

  final UserModel operarioActor = adminActor.copyWith(
    uid: 'operario-uid-1',
    nombreCompleto: 'Operario Planta',
    rol: AppConstants.roleOperario,
  );

  final UserModel productorActor = adminActor.copyWith(
    uid: 'productor-uid-1',
    nombreCompleto: 'Productor Campo',
    rol: AppConstants.roleProductor,
  );

  final ProducerModel producer1 = ProducerModel(
    productorId: 'prod-1',
    codigoAsociado: 'ASO-001',
    cedula: '1073500111',
    nombres: 'María',
    apellidos: 'Gómez',
    telefono: '3101112233',
    nombreFinca: 'La Pradera',
    vereda: 'La Glorieta',
    estado: 'ACTIVO',
    aceptoHabeasData: true,
    fechaAutorizacionDatos: refNow,
    fechaCreacion: refNow,
  );

  MilkReceptionModel syncedDelivery({
    required String id,
    required String date,
    required String shift,
    required double liters,
    bool anulado = false,
    bool isSynced = true,
  }) {
    return MilkReceptionModel(
      recepcionId: id,
      productorId: producer1.productorId,
      codigoAsociadoSnap: producer1.codigoAsociado,
      nombreProductorSnap: producer1.nombreCompleto,
      litros: liters,
      fechaEntrega: date,
      horaEntrega: shift == AppConstants.shiftMorning ? '06:30:00' : '16:15:00',
      jornada: shift,
      operarioUid: operarioActor.uid,
      syncStatus:
          isSynced ? AppConstants.syncSynced : AppConstants.syncPending,
      isSynced: isSynced,
      anulado: anulado,
      createdAt: refNow,
    );
  }

  group('SettlementCalculator exactitud matemática, exclusiones y no duplicidad',
      () {
    test('Multiplica litros decimales por tarifa vigente con exactitud al centavo',
        () {
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 15.25,
          pricePerLiter: 1850.50,
        ),
        28220.13,
      );
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 40.5,
          pricePerLiter: 1850.75,
        ),
        74955.38,
      );
      // Suma libre de deriva IEEE 754 (0.1 + 0.2 == 0.3 exacto).
      expect(
        SettlementCalculator.calculateTotalAmount(
          totalLiters: 0.1 + 0.2,
          pricePerLiter: 2000,
        ),
        600.0,
      );
    });

    test(
        'Agrupa Mañana/Tarde, excluye anuladas/pendientes/fuera de rango y evita doble liquidación',
        () {
      final QuincenaPeriod q1Nov = QuincenaPeriod.forHalfMonth(
        year: 2026,
        month: 11,
        firstHalf: true,
      );
      expect(q1Nov.startDate, '2026-11-01');
      expect(q1Nov.endDate, '2026-11-15');

      final List<MilkReceptionModel> deliveries = <MilkReceptionModel>[
        syncedDelivery(
          id: 'r1',
          date: '2026-11-02',
          shift: AppConstants.shiftMorning,
          liters: 12.1,
        ),
        syncedDelivery(
          id: 'r2',
          date: '2026-11-02',
          shift: AppConstants.shiftAfternoon,
          liters: 8.2,
        ),
        syncedDelivery(
          id: 'r3-anulada',
          date: '2026-11-03',
          shift: AppConstants.shiftMorning,
          liters: 50.0,
          anulado: true,
        ),
        syncedDelivery(
          id: 'r4-offline',
          date: '2026-11-04',
          shift: AppConstants.shiftMorning,
          liters: 15.0,
          isSynced: false,
        ),
        syncedDelivery(
          id: 'r5-fuera',
          date: '2026-11-16',
          shift: AppConstants.shiftMorning,
          liters: 30.0,
        ),
      ];

      final SettlementPreviewResult preview = SettlementCalculator.buildPreview(
        period: q1Nov,
        pricePerLiter: 1850,
        receptions: deliveries,
        producers: <ProducerModel>[producer1],
        existingSettlements: const <SettlementModel>[],
      );

      expect(preview.excludedAnuladasCount, 1);
      expect(preview.pendingSyncReceptions.length, 1);
      expect(preview.candidates.length, 1);

      final SettlementCandidate c = preview.candidates.first;
      expect(c.morningLiters, 12.1);
      expect(c.afternoonLiters, 8.2);
      expect(c.totalLiters, 20.3);
      expect(c.valorTotalPagar, 37555.0);
      expect(c.deliveryCount, 2);

      // Si ya existe una liquidación sobre un rango superpuesto, excluye al productor.
      final SettlementModel existingOverlap = SettlementModel(
        liquidacionId: 'liq-prev',
        productorId: producer1.productorId,
        nombreProductorSnap: producer1.nombreCompleto,
        cedulaProductorSnap: producer1.cedula,
        periodoInicio: '2026-11-01',
        periodoFin: '2026-11-15',
        quincenaLabel: '1ra Quincena Nov 2026',
        totalLitros: 20.3,
        cantidadEntregas: 2,
        precioLitroAplicado: 1850,
        valorTotalPagar: 37555,
        fechaLiquidacion: refNow,
        numeroComprobante: 'COMP-2026-0001',
        hashIntegridad: 'abc',
        creadoPorUid: adminActor.uid,
      );

      final SettlementPreviewResult duplicatePreview =
          SettlementCalculator.buildPreview(
        period: QuincenaPeriod.custom(
          DateTime(2026, 11, 10),
          DateTime(2026, 11, 20),
        ),
        pricePerLiter: 1850,
        receptions: deliveries,
        producers: <ProducerModel>[producer1],
        existingSettlements: <SettlementModel>[existingOverlap],
      );
      expect(duplicatePreview.candidates, isEmpty);
      expect(duplicatePreview.alreadySettledProducerIds,
          contains(producer1.productorId));
    });
  });

  group('RateService, SettlementService RBAC, Cierre Atómico, Pago y PDF', () {
    test('Tarifas históricas preservan precios anteriores y exigen rol ADMIN',
        () async {
      final HiveService memoryHive = HiveService(enablePersistence: false);
      final _InMemoryRemoteRateDataSource remoteRates =
          _InMemoryRemoteRateDataSource();
      final RateService rateService = RateService(
        hiveService: memoryHive,
        remoteDataSource: remoteRates,
      );
      final RateController rateController = RateController(
        rateService: rateService,
      );

      // OPERARIO y PRODUCTOR no pueden actualizar tarifas.
      await expectLater(
        () => rateService.createNewRate(
          actor: operarioActor,
          precioPorLitro: 1900,
          fechaInicioVigencia: DateTime.utc(2026, 11, 1),
          observacion: 'Intento sin permiso',
        ),
        throwsA(isA<RateServiceException>()),
      );
      await expectLater(
        () => rateService.createNewRate(
          actor: productorActor,
          precioPorLitro: 1900,
          fechaInicioVigencia: DateTime.utc(2026, 11, 1),
          observacion: 'Intento productor',
        ),
        throwsA(isA<RateServiceException>()),
      );

      // ADMIN crea tarifa base y luego actualiza sin sobrescribir la histórica.
      final bool firstOk = await rateController.createRate(
        actor: adminActor,
        precioPorLitro: 1800,
        fechaInicioVigencia: DateTime.utc(2026, 11, 1),
        observacion: 'Tarifa inicial noviembre',
      );
      expect(firstOk, isTrue);

      final bool secondOk = await rateController.createRate(
        actor: adminActor,
        precioPorLitro: 1920,
        fechaInicioVigencia: DateTime.utc(2026, 11, 16),
        observacion: 'Ajuste segunda quincena',
      );
      expect(secondOk, isTrue);
      expect(rateController.rates.length, 2);
      expect(rateController.activeRate?.precioPorLitro, 1920);
      expect(rateController.previousRate?.precioPorLitro, 1800);
      expect(rateController.previousRate?.activa, isFalse);
      expect(rateController.previousRate?.fechaFinVigencia, isNotNull);
      expect(rateController.variationAmount, 120);
      expect(remoteRates.auditLogs.length, 2);
    });

    test(
        'Ejecuta cierre atómico, bloquea doble cierre, impide mutar entregas liquidadas, confirma pago y genera PDF',
        () async {
      final HiveService memoryHive = HiveService(enablePersistence: false);
      final _InMemoryRemoteReceptionSource remoteReceptions =
          _InMemoryRemoteReceptionSource();
      final _InMemoryRemoteSettlementDataSource remoteSettlements =
          _InMemoryRemoteSettlementDataSource(
        receptionsStore: remoteReceptions.remoteDocs,
      );
      final _InMemoryRemoteRateDataSource remoteRates =
          _InMemoryRemoteRateDataSource();

      final RateService rateService = RateService(
        hiveService: memoryHive,
        remoteDataSource: remoteRates,
      );
      await rateService.createNewRate(
        actor: adminActor,
        precioPorLitro: 1850,
        fechaInicioVigencia: DateTime.utc(2026, 11, 1),
        observacion: 'Tarifa base cierre',
      );

      final MilkReceptionModel d1 = syncedDelivery(
        id: 'rec-ok-1',
        date: '2026-11-05',
        shift: AppConstants.shiftMorning,
        liters: 14.5,
      );
      final MilkReceptionModel d2 = syncedDelivery(
        id: 'rec-ok-2',
        date: '2026-11-05',
        shift: AppConstants.shiftAfternoon,
        liters: 10.75,
      );
      final MilkReceptionModel dOffline = syncedDelivery(
        id: 'rec-pending',
        date: '2026-11-06',
        shift: AppConstants.shiftMorning,
        liters: 8.0,
        isSynced: false,
      );

      await memoryHive.saveReception(d1);
      await memoryHive.saveReception(d2);
      await memoryHive.saveReception(dOffline);
      remoteReceptions.remoteDocs[d1.recepcionId] = d1;
      remoteReceptions.remoteDocs[d2.recepcionId] = d2;

      final SettlementService settlementService = SettlementService(
        hiveService: memoryHive,
        remoteDataSource: remoteSettlements,
      );
      final QuincenaPeriod q1 = QuincenaPeriod.forHalfMonth(
        year: 2026,
        month: 11,
        firstHalf: true,
      );

      // Productor y Operario bloqueados por RBAC.
      await expectLater(
        () => settlementService.closeQuincena(
          actor: operarioActor,
          period: q1,
          pricePerLiter: 1850,
          receptions: <MilkReceptionModel>[d1, d2],
          producers: <ProducerModel>[producer1],
        ),
        throwsA(isA<SettlementServiceException>()),
      );
      await expectLater(
        () => settlementService.closeQuincena(
          actor: productorActor,
          period: q1,
          pricePerLiter: 1850,
          receptions: <MilkReceptionModel>[d1, d2],
          producers: <ProducerModel>[producer1],
        ),
        throwsA(isA<SettlementServiceException>()),
      );

      // Bloquea si hay entregas sin sincronizar en el rango.
      await expectLater(
        () => settlementService.closeQuincena(
          actor: adminActor,
          period: q1,
          pricePerLiter: 1850,
          receptions: <MilkReceptionModel>[d1, d2, dOffline],
          producers: <ProducerModel>[producer1],
        ),
        throwsA(isA<SettlementServiceException>()),
      );

      // Al sincronizar la entrega pendiente y ejecutar cierre via SettlementController:
      final MilkReceptionModel dOfflineSynced = dOffline.copyWith(
        isSynced: true,
        syncStatus: AppConstants.syncSynced,
      );
      await memoryHive.markReceptionsAsSynced(<String>[dOffline.recepcionId]);
      remoteReceptions.remoteDocs[dOffline.recepcionId] = dOfflineSynced;

      final SettlementController controller = SettlementController(
        settlementService: settlementService,
        receptionService: ReceptionService(
          hiveService: memoryHive,
          remoteDataSource: remoteReceptions,
        ),
        producerService: ProducerService(
          hiveService: memoryHive,
          remoteDataSource: _InMemoryProducerSource(<ProducerModel>[producer1]),
        ),
        rateService: rateService,
      );
      controller.setPeriod(q1);
      await controller.loadData();

      expect(controller.preview?.candidates.length, 1);
      expect(controller.preview?.totalLiters, 33.25);
      // 33.25 * 1850 = 61512.50
      expect(controller.preview?.totalAmountToPay, 61512.50);

      final bool closed = await controller.executeQuincenaClose(
        actor: adminActor,
      );
      expect(closed, isTrue);
      expect(controller.allSettlements.length, 1);

      final SettlementModel emitted = controller.allSettlements.first;
      expect(emitted.numeroComprobante, 'COMP-2026-0001');
      expect(emitted.totalLitros, 33.25);
      expect(emitted.valorTotalPagar, 61512.50);
      expect(emitted.hashIntegridad.length, 64);
      expect(emitted.isPagada, isFalse);

      // Las entregas quedan ligadas e inmutables en Hive tras el cierre.
      final MilkReceptionModel? lockedDelivery =
          await memoryHive.getReceptionById(d1.recepcionId);
      expect(lockedDelivery?.liquidacionId, emitted.liquidacionId);
      await expectLater(
        () => memoryHive.saveReception(lockedDelivery!.copyWith(litros: 99)),
        throwsStateError,
      );

      // No permite doble cierre sobre el mismo período ni rango superpuesto.
      await expectLater(
        () => settlementService.closeQuincena(
          actor: adminActor,
          period: q1,
          pricePerLiter: 1850,
          receptions: controller.allReceptions,
          producers: controller.allProducers,
          existingSettlements: controller.allSettlements,
        ),
        throwsA(isA<SettlementServiceException>()),
      );

      // Confirmar pago (PENDIENTE -> PAGADA) y generar PDF válido.
      final bool paidOk = await controller.confirmPayment(
        actor: adminActor,
        settlement: emitted,
        observacionPago: 'Transferencia Bancolombia #9901',
      );
      expect(paidOk, isTrue);
      final SettlementModel paidSettlement = controller.allSettlements.first;
      expect(paidSettlement.isPagada, isTrue);
      expect(paidSettlement.fechaPago, isNotNull);
      expect(remoteSettlements.notifications.length, 2); // Cierre + Pago

      final Uint8List pdfBytes =
          await SettlementPdfService.buildVoucherPdfBytes(
        settlement: paidSettlement,
        receptions: controller.receptionsForSettlement(paidSettlement),
        producer: producer1,
      );
      expect(pdfBytes.length, greaterThan(1500));
      // Cabecera estándar "%PDF"
      expect(pdfBytes.sublist(0, 4), <int>[0x25, 0x50, 0x44, 0x46]);
    });
  });
}
