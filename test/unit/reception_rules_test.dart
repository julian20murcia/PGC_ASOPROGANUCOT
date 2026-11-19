import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/reception_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';

class _InMemoryRemoteReceptionDataSource implements RemoteReceptionDataSource {
  final Map<String, MilkReceptionModel> remoteDocs =
      <String, MilkReceptionModel>{};
  final List<AuditLogModel> auditLogs = <AuditLogModel>[];
  bool shouldFail = false;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async {
    if (shouldFail) throw Exception('Sin red');
    return remoteDocs.values.toList();
  }

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    if (shouldFail) throw Exception('Sin red');
    remoteDocs[reception.recepcionId] = reception;
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    auditLogs.add(log);
  }
}

class _InMemoryProducerDataSource implements RemoteProducerDataSource {
  _InMemoryProducerDataSource(this.items);
  final List<ProducerModel> items;

  @override
  Future<List<ProducerModel>> fetchProducers() async => items;

  @override
  Future<void> upsertProducer(ProducerModel producer) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

void main() {
  final DateTime refNow = DateTime.utc(2026, 11, 18, 8, 30);

  final ProducerModel activeProducer = ProducerModel(
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

  final ProducerModel inactiveProducer = activeProducer.copyWith(
    productorId: 'prod-2',
    codigoAsociado: 'ASO-002',
    cedula: '1073500222',
    estado: 'INACTIVO',
  );

  final UserModel adminActor = UserModel(
    uid: 'admin-1',
    nombreCompleto: 'Admin Planta',
    documento: '100',
    correo: 'admin@asoproganucot.com',
    telefono: '',
    rol: AppConstants.roleAdmin,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: refNow,
  );

  final UserModel operarioActor = UserModel(
    uid: 'op-1',
    nombreCompleto: 'Operario Planta',
    documento: '200',
    correo: 'op@asoproganucot.com',
    telefono: '',
    rol: AppConstants.roleOperario,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: refNow,
  );

  group('ReceptionService reglas de captura, duplicados, Hive y auditoría', () {
    late HiveService memoryHive;
    late _InMemoryRemoteReceptionDataSource remoteDs;
    late ReceptionService service;

    setUp(() {
      memoryHive = HiveService(enablePersistence: false);
      remoteDs = _InMemoryRemoteReceptionDataSource();
      service = ReceptionService(
        hiveService: memoryHive,
        remoteDataSource: remoteDs,
      );
    });

    test('Rechaza litros <= 0 o productor inactivo', () async {
      await expectLater(
        () => service.registerReception(
          producer: activeProducer,
          litros: 0,
          jornada: AppConstants.shiftMorning,
          operarioUid: operarioActor.uid,
        ),
        throwsA(isA<ReceptionServiceException>()),
      );

      await expectLater(
        () => service.registerReception(
          producer: inactiveProducer,
          litros: 25.5,
          jornada: AppConstants.shiftMorning,
          operarioUid: operarioActor.uid,
        ),
        throwsA(isA<ReceptionServiceException>()),
      );
    });

    test('Guarda primero en Hive offline y sincroniza luego al recuperar red', () async {
      remoteDs.shouldFail = true;
      final MilkReceptionModel offline = await service.registerReception(
        producer: activeProducer,
        litros: 38.4,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        timestamp: refNow,
        isOnline: false,
      );

      expect(offline.recepcionId, isNotEmpty);
      expect(offline.isSynced, isFalse);
      expect(offline.syncStatus, AppConstants.syncPending);
      expect((await memoryHive.getPendingReceptions()).length, 1);

      remoteDs.shouldFail = false;
      final syncRes = await service.syncPending();
      expect(syncRes.syncedCount, 1);
      expect(syncRes.remainingPendingCount, 0);

      final MilkReceptionModel? synced =
          await memoryHive.getReceptionById(offline.recepcionId);
      expect(synced?.isSynced, isTrue);
      expect(remoteDs.remoteDocs[offline.recepcionId]?.litros, 38.4);
    });

    test('Detecta entrega duplicada en mismo turno y permite confirmar si allowDuplicate=true', () async {
      await service.registerReception(
        producer: activeProducer,
        litros: 30.0,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        timestamp: refNow,
      );

      // Segundo registro en la misma fecha y jornada -> alerta duplicado
      await expectLater(
        () => service.registerReception(
          producer: activeProducer,
          litros: 12.5,
          jornada: AppConstants.shiftMorning,
          operarioUid: operarioActor.uid,
          timestamp: refNow.add(const Duration(minutes: 20)),
        ),
        throwsA(isA<DuplicateReceptionException>()),
      );

      // Si el operario confirma explícitamente allowDuplicate=true, guarda segunda entrega
      final MilkReceptionModel confirmed = await service.registerReception(
        producer: activeProducer,
        litros: 12.5,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        timestamp: refNow.add(const Duration(minutes: 20)),
        allowDuplicate: true,
      );
      expect(confirmed.litros, 12.5);
      expect((await memoryHive.getReceptions()).length, 2);

      // En jornada TARDE del mismo día NO es duplicado
      final MilkReceptionModel afternoon = await service.registerReception(
        producer: activeProducer,
        litros: 18.0,
        jornada: AppConstants.shiftAfternoon,
        operarioUid: operarioActor.uid,
        timestamp: refNow.add(const Duration(hours: 8)),
      );
      expect(afternoon.jornada, AppConstants.shiftAfternoon);
    });

    test('Solo ADMIN puede corregir/anular con motivo y bloquea edición tras liquidación', () async {
      final MilkReceptionModel created = await service.registerReception(
        producer: activeProducer,
        litros: 40.0,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        timestamp: refNow,
      );

      // OPERARIO no puede corregir
      await expectLater(
        () => service.editReceptionLitros(
          existing: created,
          nuevosLitros: 42.0,
          motivo: 'Ajuste de báscula',
          actor: operarioActor,
        ),
        throwsA(isA<ReceptionServiceException>()),
      );

      // ADMIN sí corrige y genera auditoría EDITAR
      final MilkReceptionModel edited = await service.editReceptionLitros(
        existing: created,
        nuevosLitros: 42.5,
        motivo: 'Error al leer cantina #3',
        actor: adminActor,
      );
      expect(edited.litros, 42.5);
      expect(remoteDs.auditLogs.any((AuditLogModel l) => l.accion == 'EDITAR'), isTrue);

      // Entrega liquidada no puede editarse ni anularse ni por ADMIN
      final MilkReceptionModel settled = edited.copyWith(liquidacionId: 'liq-1');
      await expectLater(
        () => service.editReceptionLitros(
          existing: settled,
          nuevosLitros: 10.0,
          motivo: 'Intento post-liquidación',
          actor: adminActor,
        ),
        throwsA(isA<ReceptionServiceException>()),
      );
      await expectLater(
        () => service.annulReception(
          existing: settled,
          motivo: 'Anulación post-liquidación',
          actor: adminActor,
        ),
        throwsA(isA<ReceptionServiceException>()),
      );

      // Anulación válida pre-liquidación genera log ANULAR
      final MilkReceptionModel annulled = await service.annulReception(
        existing: edited,
        motivo: 'Registro duplicado accidental',
        actor: adminActor,
      );
      expect(annulled.anulado, isTrue);
      expect(remoteDs.auditLogs.any((AuditLogModel l) => l.accion == 'ANULAR'), isTrue);
    });
  });

  group('ReceptionController captura rápida y KPIs operativos', () {
    test('Resuelve productor por código, registra entregas Mañana/Tarde y calcula KPIs', () async {
      final HiveService memoryHive = HiveService(enablePersistence: false);
      final _InMemoryRemoteReceptionDataSource remoteRec =
          _InMemoryRemoteReceptionDataSource();
      final ProducerService producerService = ProducerService(
        hiveService: memoryHive,
        remoteDataSource: _InMemoryProducerDataSource(<ProducerModel>[activeProducer]),
      );
      final ReceptionService receptionService = ReceptionService(
        hiveService: memoryHive,
        remoteDataSource: remoteRec,
      );
      final ReceptionController ctrl = ReceptionController(
        hiveService: memoryHive,
        receptionService: receptionService,
        producerService: producerService,
      );

      await ctrl.loadReceptions(isOnlineOverride: true);
      expect(ctrl.findExactProducer('aso-001')?.productorId, 'prod-1');

      ctrl.selectProducer(activeProducer);
      ctrl.setSelectedShift(AppConstants.shiftMorning);
      final resMorning = await ctrl.registerDelivery(
        litros: 25.0,
        operarioUid: operarioActor.uid,
        timestamp: DateTime.now(),
      );
      expect(resMorning.saved, isTrue);

      ctrl.selectProducer(activeProducer);
      ctrl.setSelectedShift(AppConstants.shiftAfternoon);
      final resAfternoon = await ctrl.registerDelivery(
        litros: 17.5,
        operarioUid: operarioActor.uid,
        timestamp: DateTime.now(),
      );
      expect(resAfternoon.saved, isTrue);

      expect(ctrl.todayMorningLiters, 25.0);
      expect(ctrl.todayAfternoonLiters, 17.5);
      expect(ctrl.todayTotalLiters, 42.5);
      expect(ctrl.todayDeliveriesCount, 2);
      expect(ctrl.quincenaTotalLiters, 42.5);
    });

    test('Agrupa planilla por productor y días, filtra por jornada, navega quincenas y registra por fecha', () async {
      final HiveService memoryHive = HiveService(enablePersistence: false);
      final _InMemoryRemoteReceptionDataSource remoteRec =
          _InMemoryRemoteReceptionDataSource();
      final ProducerModel secondProducer = activeProducer.copyWith(
        productorId: 'prod-2',
        codigoAsociado: 'ASO-002',
        cedula: '1073500999',
        nombres: 'Pedro',
        apellidos: 'Alarcón',
      );
      final ProducerService producerService = ProducerService(
        hiveService: memoryHive,
        remoteDataSource: _InMemoryProducerDataSource(<ProducerModel>[
          activeProducer,
          secondProducer,
        ]),
      );
      final ReceptionService receptionService = ReceptionService(
        hiveService: memoryHive,
        remoteDataSource: remoteRec,
      );
      final ReceptionController ctrl = ReceptionController(
        hiveService: memoryHive,
        receptionService: receptionService,
        producerService: producerService,
      );

      await ctrl.loadReceptions(isOnlineOverride: true);
      expect(ctrl.viewMode, ReceptionViewMode.matrix);
      expect(ctrl.isCurrentMatrixQuincena, isTrue);
      expect(ctrl.canGoNextMatrixQuincena, isFalse);

      final DateTime firstDayInQuincena = ctrl.matrixDays.first;
      final String firstDayStr = ReceptionService.formatDate(firstDayInQuincena);
      final DateTime auditTimestamp = DateTime.utc(2026, 11, 18, 14, 20);

      final res1 = await ctrl.registerDeliveryForProducer(
        producer: activeProducer,
        litros: 20.0,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        fechaEntrega: firstDayStr,
        timestamp: auditTimestamp,
      );
      final res2 = await ctrl.registerDeliveryForProducer(
        producer: activeProducer,
        litros: 15.0,
        jornada: AppConstants.shiftAfternoon,
        operarioUid: operarioActor.uid,
        fechaEntrega: firstDayStr,
        timestamp: auditTimestamp,
      );
      final res3 = await ctrl.registerDeliveryForProducer(
        producer: secondProducer,
        litros: 10.5,
        jornada: AppConstants.shiftMorning,
        operarioUid: operarioActor.uid,
        fechaEntrega: firstDayStr,
        timestamp: auditTimestamp,
      );
      expect(res1.saved && res2.saved && res3.saved, isTrue);

      // El createdAt conserva la marca temporal real (Ley 527) mientras fechaEntrega apunta a la celda elegida
      expect(ctrl.allReceptions.first.fechaEntrega, firstDayStr);
      expect(ctrl.allReceptions.first.createdAt, auditTimestamp);

      // Agrupación de planilla completa (M + T)
      expect(ctrl.matrixRows.length, 2);
      expect(ctrl.matrixRows[0].producer.codigoAsociado, 'ASO-001');
      expect(ctrl.matrixRows[0].morningLitersForDate(firstDayStr), 20.0);
      expect(ctrl.matrixRows[0].afternoonLitersForDate(firstDayStr), 15.0);
      expect(ctrl.matrixRows[0].litersForDate(firstDayStr), 35.0);
      expect(ctrl.matrixRows[0].totalLiters, 35.0);
      expect(ctrl.matrixRows[1].totalLiters, 10.5);
      expect(ctrl.matrixDayTotals[firstDayStr], 45.5);
      expect(ctrl.matrixGrandTotal, 45.5);
      expect(ctrl.matrixTotalDeliveries, 3);

      // Filtro por jornada TARDE
      ctrl.setShiftFilter(AppConstants.shiftAfternoon);
      expect(ctrl.matrixRows[0].litersForDate(firstDayStr), 15.0);
      expect(ctrl.matrixRows[1].litersForDate(firstDayStr), 0.0);
      expect(ctrl.matrixGrandTotal, 15.0);

      ctrl.setShiftFilter('ALL');
      final String currentLabel = ctrl.matrixQuincenaLabel;
      ctrl.previousMatrixQuincena();
      expect(ctrl.matrixQuincenaLabel, isNot(currentLabel));
      expect(ctrl.isCurrentMatrixQuincena, isFalse);
      expect(ctrl.canGoNextMatrixQuincena, isTrue);

      ctrl.nextMatrixQuincena();
      expect(ctrl.matrixQuincenaLabel, currentLabel);
      expect(ctrl.isCurrentMatrixQuincena, isTrue);
    });
  });
}
