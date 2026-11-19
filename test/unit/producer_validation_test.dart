import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/producer_controller.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';

class _InMemoryRemoteProducerDataSource implements RemoteProducerDataSource {
  final Map<String, ProducerModel> producers = <String, ProducerModel>{};
  final List<AuditLogModel> auditLogs = <AuditLogModel>[];
  bool shouldFail = false;

  @override
  Future<List<ProducerModel>> fetchProducers() async {
    if (shouldFail) {
      throw Exception('Sin red');
    }
    return producers.values.toList();
  }

  @override
  Future<void> upsertProducer(ProducerModel producer) async {
    if (shouldFail) {
      throw Exception('Sin red');
    }
    producers[producer.productorId] = producer;
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    auditLogs.add(log);
  }
}

class _FakeAccountLinker implements ProducerAccountLinker {
  String nextUid = 'linked-mobile-uid-1';
  bool called = false;
  String? lastCedula;
  String? lastEmail;

  @override
  Future<String> linkOrCreateProducerAccount({
    required String nombreCompleto,
    required String cedula,
    required String correo,
    required String telefono,
    required String password,
    required bool activo,
    required String actorUid,
  }) async {
    called = true;
    lastCedula = cedula;
    lastEmail = correo;
    return nextUid;
  }
}

void main() {
  group('ProducerService validaciones de unicidad, Habeas Data y vinculación', () {
    late HiveService memoryHive;
    late _InMemoryRemoteProducerDataSource remoteDs;
    late _FakeAccountLinker accountLinker;
    late ProducerService service;

    setUp(() {
      memoryHive = HiveService(enablePersistence: false);
      remoteDs = _InMemoryRemoteProducerDataSource();
      accountLinker = _FakeAccountLinker();
      service = ProducerService(
        hiveService: memoryHive,
        remoteDataSource: remoteDs,
        accountLinker: accountLinker,
      );
    });

    test('Bloquea creación si aceptoHabeasData es false', () async {
      await expectLater(
        () => service.createProducer(
          codigoAsociado: 'ASO-001',
          cedula: '1073500111',
          nombres: 'Pedro',
          apellidos: 'Martínez',
          telefono: '3101112233',
          nombreFinca: 'El Bosque',
          vereda: 'La Glorieta',
          estado: 'ACTIVO',
          aceptoHabeasData: false,
          actorUid: 'admin-1',
        ),
        throwsA(isA<ProducerServiceException>()),
      );

      expect(remoteDs.producers, isEmpty);
      expect(await memoryHive.getCachedProducers(), isEmpty);
    });

    test('Registra productor con Habeas Data válido, auditoría y cuenta móvil vinculada', () async {
      final ProducerModel created = await service.createProducer(
        codigoAsociado: 'aso-001',
        cedula: '1073500222',
        nombres: 'Lucía',
        apellidos: 'Pineda',
        telefono: '3112223344',
        nombreFinca: 'San Isidro',
        vereda: 'El Crucero',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-uid-9',
        createMobileAccount: true,
        mobileEmail: 'lucia@finca.co',
        mobilePassword: 'Password123',
      );

      expect(created.codigoAsociado, 'ASO-001');
      expect(created.hasValidHabeasData, isTrue);
      expect(created.autorizadoPorUid, 'admin-uid-9');
      expect(created.fechaAutorizacionDatos, isNotNull);
      expect(created.soporteAutorizacion, isNotNull);
      expect(created.soporteAutorizacion, startsWith('AUT-PLANTA-ASO-001-'));
      expect(created.soporteAutorizacion!.length, lessThanOrEqualTo(120));
      expect(created.uidUsuario, 'linked-mobile-uid-1');
      expect(created.isSynced, isTrue);
      expect(accountLinker.called, isTrue);
      expect(accountLinker.lastCedula, '1073500222');
      expect(remoteDs.auditLogs.length, 1);
      expect(remoteDs.auditLogs.first.accion, 'CREAR');

      final ProducerModel withExplicitRef = await service.createProducer(
        codigoAsociado: 'aso-002',
        cedula: '1073500299',
        nombres: 'Carlos',
        apellidos: 'Rojas',
        telefono: '3112223399',
        nombreFinca: 'La Palma',
        vereda: 'El Crucero',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-uid-9',
        authorizationReference: 'ACTA-2026-09',
      );
      expect(withExplicitRef.soporteAutorizacion, 'ACTA-2026-09');
    });

    test('Rechaza duplicados por cédula o código asociado (case-insensitive)', () async {
      await service.createProducer(
        codigoAsociado: 'ASO-001',
        cedula: '1073500333',
        nombres: 'Jorge',
        apellidos: 'Ruiz',
        telefono: '3100001111',
        nombreFinca: 'La Esperanza',
        vereda: 'Cascajal',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-1',
      );

      // Misma cédula con distinto código -> error
      await expectLater(
        () => service.createProducer(
          codigoAsociado: 'ASO-002',
          cedula: '1073500333',
          nombres: 'Otro',
          apellidos: 'Ganadero',
          telefono: '3120002222',
          nombreFinca: 'Otra Finca',
          vereda: 'Cascajal',
          estado: 'ACTIVO',
          aceptoHabeasData: true,
          actorUid: 'admin-1',
        ),
        throwsA(isA<ProducerServiceException>()),
      );

      // Mismo código en minúscula con distinta cédula -> error
      await expectLater(
        () => service.createProducer(
          codigoAsociado: 'aso-001',
          cedula: '1073500444',
          nombres: 'Otro',
          apellidos: 'Ganadero',
          telefono: '3120002222',
          nombreFinca: 'Otra Finca',
          vereda: 'Cascajal',
          estado: 'ACTIVO',
          aceptoHabeasData: true,
          actorUid: 'admin-1',
        ),
        throwsA(isA<ProducerServiceException>()),
      );
    });

    test('Cambia estado ACTIVO <-> INACTIVO sin eliminar historial', () async {
      final ProducerModel created = await service.createProducer(
        codigoAsociado: 'ASO-005',
        cedula: '1073500555',
        nombres: 'Rosa',
        apellidos: 'Vargas',
        telefono: '3134445566',
        nombreFinca: 'Las Acacias',
        vereda: 'Punta Grande',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-1',
      );
      expect(created.isActivo, isTrue);

      final ProducerModel inactive = await service.toggleProducerStatus(
        producer: created,
        actorUid: 'admin-1',
      );
      expect(inactive.isActivo, isFalse);
      expect(inactive.productorId, created.productorId);

      final List<ProducerModel> cached = await memoryHive.getCachedProducers();
      expect(cached.length, 1);
      expect(cached.first.estado, 'INACTIVO');
    });
  });

  group('ProducerController filtros, búsqueda offline y sugerencia de código', () {
    late HiveService memoryHive;
    late _InMemoryRemoteProducerDataSource remoteDs;
    late ProducerService service;
    late ProducerController controller;

    setUp(() {
      memoryHive = HiveService(enablePersistence: false);
      remoteDs = _InMemoryRemoteProducerDataSource();
      service = ProducerService(
        hiveService: memoryHive,
        remoteDataSource: remoteDs,
      );
      controller = ProducerController(producerService: service);
    });

    test('Carga, filtra por vereda/búsqueda offline y sugiere siguiente código ASO-XXX', () async {
      await controller.createProducer(
        codigoAsociado: 'ASO-001',
        cedula: '1073500101',
        nombres: 'Mario',
        apellidos: 'Castillo',
        telefono: '3101110001',
        nombreFinca: 'El Roble',
        vereda: 'La Glorieta',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-1',
      );
      await controller.createProducer(
        codigoAsociado: 'ASO-009',
        cedula: '1073500102',
        nombres: 'Elena',
        apellidos: 'Cortés',
        telefono: '3101110002',
        nombreFinca: 'Villa Elena',
        vereda: 'Cascajal',
        estado: 'INACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-1',
      );

      expect(controller.suggestedNextCode(), 'ASO-010');

      // Simular corte de internet y recargar desde Hive
      remoteDs.shouldFail = true;
      await controller.loadProducers();
      expect(controller.isFromOfflineCache, isTrue);
      expect(controller.totalCount, 2);
      expect(controller.activeCount, 1);

      controller.setVeredaFilter('Cascajal');
      expect(controller.filteredProducers.length, 1);
      expect(controller.filteredProducers.first.codigoAsociado, 'ASO-009');

      controller.clearFilters();
      controller.setSearchQuery('Castillo');
      expect(controller.filteredProducers.length, 1);
      expect(controller.filteredProducers.first.vereda, 'La Glorieta');
    });
  });
}
