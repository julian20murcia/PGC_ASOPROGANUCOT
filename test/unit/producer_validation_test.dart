import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/producer_controller.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/app_date_range_picker.dart';

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
  group(
    'ProducerService validaciones de unicidad, Habeas Data y vinculación',
    () {
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

      test(
        'Registra productor con Habeas Data válido, auditoría y cuenta móvil vinculada',
        () async {
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
          // Constancia automática cuando no se escribe soporte (flujo de main).
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
        },
      );

      test(
        'Rechaza duplicados por cédula o código asociado (case-insensitive)',
        () async {
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
        },
      );

      test(
        'Cambia estado ACTIVO <-> INACTIVO sin eliminar historial',
        () async {
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

          final List<ProducerModel> cached = await memoryHive
              .getCachedProducers();
          expect(cached.length, 1);
          expect(cached.first.estado, 'INACTIVO');
        },
      );
    },
  );

  group(
    'ProducerController filtros, búsqueda offline y sugerencia de código',
    () {
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

      test(
        'Carga, filtra por vereda/búsqueda offline y sugiere siguiente código ASO-XXX',
        () async {
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
        },
      );
    },
  );

  group('ProducerRules: validaciones extremas', () {
    test(
      'Nombres: rechaza letras repetidas, números, emojis y textos larguísimos',
      () {
        expect(ProducerRules.names('Juliaaaaannnnnn'), isNotNull);
        expect(ProducerRules.names('Juan2'), 'Solo se permiten letras');
        expect(ProducerRules.names('Juan 😀'), 'Solo se permiten letras');
        expect(ProducerRules.names('A' * 200), isNotNull);
        expect(ProducerRules.names('Ab' * 100), contains('Máximo'));
        expect(ProducerRules.names('   '), isNotNull);
        expect(ProducerRules.names('J'), isNotNull);
        expect(ProducerRules.names('José Luis'), isNull);
        expect(ProducerRules.surnames("D'Alessandro-Núñez"), isNull);
      },
    );

    test(
      'Cédula: solo dígitos, entre 5 y 12, sin repetidos absurdos ni números gigantes',
      () {
        expect(ProducerRules.document('10735abc'), 'Solo números');
        expect(ProducerRules.document('1073-500'), 'Solo números');
        expect(ProducerRules.document('10000000000000000000000000'), isNotNull);
        expect(ProducerRules.document('1234'), isNotNull);
        expect(ProducerRules.document('1111111'), 'Documento no válido');
        expect(ProducerRules.document('🙂12345'), isNotNull);
        expect(ProducerRules.document('1073500123'), isNull);
      },
    );

    test('Teléfono: exactamente 10 dígitos de celular, sin letras', () {
      expect(ProducerRules.phone('310123456a'), isNotNull);
      expect(ProducerRules.phone('31012345678901234567890'), isNotNull);
      expect(ProducerRules.phone('310123'), isNotNull);
      expect(ProducerRules.phone(''), isNotNull);
      expect(ProducerRules.phone('3101234567'), isNull);
    });

    test('Código de asociado, finca y vereda', () {
      expect(ProducerRules.code('ASO-001'), isNull);
      expect(ProducerRules.code('aso-001'), isNull);
      expect(ProducerRules.code('ASO--1'), isNotNull);
      expect(ProducerRules.code('-ASO'), isNotNull);
      expect(ProducerRules.code('ASO-0000000001'), contains('Máximo'));
      expect(ProducerRules.code('ASO 1'), isNotNull);

      expect(ProducerRules.farm('El Porvenir N.º 2'), isNull);
      expect(ProducerRules.farm('Finca 🐄'), isNotNull);
      expect(ProducerRules.farm('12345'), isNotNull);
      expect(ProducerRules.farm('x' * 61), isNotNull);
      expect(ProducerRules.farm('Laaaaaaa Finca'), isNotNull);
      expect(ProducerRules.vereda('La Glorieta'), isNull);
      expect(ProducerRules.vereda('V' * 41), isNotNull);
      expect(ProducerRules.vereda('<script>'), isNotNull);
    });

    test('Soporte de autorización: obligatorio y máximo 120 caracteres', () {
      expect(ProducerRules.authorizationReference(''), isNull); // opcional (constancia automática)
      expect(ProducerRules.authorizationReference('a' * 121), isNotNull);
      expect(
        ProducerRules.authorizationReference('Formato 045 · Carpeta 2026'),
        isNull,
      );
    });

    test('normalize recorta, colapsa espacios y capitaliza nombres', () {
      final ProducerInput input = ProducerRules.normalize(
        codigoAsociado: '  aso-007 ',
        cedula: ' 1073500999 ',
        nombres: '  josé    LUIS ',
        apellidos: 'pérez   gómez',
        telefono: '3101234567',
        nombreFinca: '  El    Porvenir ',
        vereda: ' La   Glorieta',
        estado: 'inactivo',
      );
      expect(input.codigoAsociado, 'ASO-007');
      expect(input.cedula, '1073500999');
      expect(input.nombres, 'José Luis');
      expect(input.apellidos, 'Pérez Gómez');
      expect(input.nombreFinca, 'El Porvenir');
      expect(input.vereda, 'La Glorieta');
      expect(input.estado, 'INACTIVO');
    });
  });

  group(
    'ProducerService aplica las validaciones en el servidor (no solo en la UI)',
    () {
      late HiveService memoryHive;
      late _InMemoryRemoteProducerDataSource remoteDs;
      late ProducerService service;

      setUp(() {
        memoryHive = HiveService(enablePersistence: false);
        remoteDs = _InMemoryRemoteProducerDataSource();
        service = ProducerService(
          hiveService: memoryHive,
          remoteDataSource: remoteDs,
        );
      });

      Future<ProducerModel> create({
        String code = 'ASO-001',
        String cedula = '1073500111',
        String nombres = 'Pedro',
        String apellidos = 'Martínez',
        String telefono = '3101112233',
        String finca = 'El Bosque',
        String vereda = 'La Glorieta',
        String? soporte,
      }) => service.createProducer(
        codigoAsociado: code,
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        telefono: telefono,
        nombreFinca: finca,
        vereda: vereda,
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        actorUid: 'admin-1',
        authorizationReference: soporte,
      );

      test('Rechaza entradas extremas sin escribir nada', () async {
        final List<Future<ProducerModel> Function()> invalid =
            <Future<ProducerModel> Function()>[
              () => create(nombres: 'Juliaaaaaannnnnnn'),
              () => create(nombres: 'N' * 200),
              () => create(apellidos: 'Pérez 😀'),
              () => create(cedula: '10735abc'),
              () => create(cedula: '10000000000000000000000000'),
              () => create(telefono: '31O1112233'),
              () => create(telefono: '99999999999999999999'),
              () => create(code: 'ASO 001'),
              () => create(finca: '🐄🐄🐄'),
              () => create(vereda: 'V' * 200),
              () => create(soporte: 's' * 121),
            ];
        for (final Future<ProducerModel> Function() attempt in invalid) {
          await expectLater(attempt, throwsA(isA<ProducerServiceException>()));
        }
        expect(remoteDs.producers, isEmpty);
        expect(await memoryHive.getCachedProducers(), isEmpty);
      });

      test('Guarda los datos normalizados', () async {
        final ProducerModel p = await create(
          nombres: '  pedro    antonio ',
          apellidos: 'MARTÍNEZ',
          code: 'aso-010',
          finca: ' El   Bosque ',
        );
        expect(p.nombres, 'Pedro Antonio');
        expect(p.apellidos, 'Martínez');
        expect(p.codigoAsociado, 'ASO-010');
        expect(p.nombreFinca, 'El Bosque');
      });

      test('La edición también valida y respeta unicidad de cédula', () async {
        final ProducerModel a = await create();
        await create(code: 'ASO-002', cedula: '1073500222');
        await expectLater(
          () => service.updateProducer(
            previous: a,
            codigoAsociado: a.codigoAsociado,
            cedula: '1073500222',
            nombres: a.nombres,
            apellidos: a.apellidos,
            telefono: a.telefono,
            nombreFinca: a.nombreFinca,
            vereda: a.vereda,
            estado: 'ACTIVO',
            aceptoHabeasData: true,
            actorUid: 'admin-1',
          ),
          throwsA(isA<ProducerServiceException>()),
        );
        await expectLater(
          () => service.updateProducer(
            previous: a,
            codigoAsociado: a.codigoAsociado,
            cedula: a.cedula,
            nombres: 'Peeeedro',
            apellidos: a.apellidos,
            telefono: a.telefono,
            nombreFinca: a.nombreFinca,
            vereda: a.vereda,
            estado: 'ACTIVO',
            aceptoHabeasData: true,
            actorUid: 'admin-1',
          ),
          throwsA(isA<ProducerServiceException>()),
        );
      });
    },
  );

  group('ProducerController ordenamientos y litros por período', () {
    final DateTime today = DateTime(2026, 11, 18);

    ProducerModel producer(
      String id,
      String code,
      String name,
      DateTime created,
    ) => ProducerModel(
      productorId: id,
      codigoAsociado: code,
      cedula: '10735${id.hashCode.abs() % 100000}'.padRight(10, '0'),
      nombres: name,
      apellidos: 'Prueba',
      telefono: '3100000000',
      nombreFinca: 'Finca $name',
      vereda: 'Cascajal',
      estado: 'ACTIVO',
      aceptoHabeasData: true,
      fechaCreacion: created,
    );

    MilkReceptionModel delivery(
      String id,
      String productorId,
      double litros,
      String fecha, {
      String jornada = 'MANANA',
      bool anulado = false,
    }) => MilkReceptionModel(
      recepcionId: id,
      productorId: productorId,
      codigoAsociadoSnap: 'X',
      nombreProductorSnap: 'X',
      litros: litros,
      fechaEntrega: fecha,
      horaEntrega: '06:00:00',
      jornada: jornada,
      operarioUid: 'op-1',
      isSynced: true,
      syncStatus: 'SINCRONIZADO',
      anulado: anulado,
      createdAt: DateTime(2026, 11, 1),
    );

    late _FakeDeliverySource deliveries;
    late ProducerController controller;

    setUp(() async {
      final _InMemoryRemoteProducerDataSource remote =
          _InMemoryRemoteProducerDataSource();
      for (final ProducerModel p in <ProducerModel>[
        producer('a', 'ASO-002', 'Ana', DateTime.utc(2024, 1, 10)),
        producer('b', 'ASO-010', 'Bruno', DateTime.utc(2026, 5, 2)),
        producer('c', 'ASO-001', 'Carla', DateTime.utc(2025, 3, 15)),
        producer('d', 'ASO-003', 'Diego', DateTime.utc(2026, 11, 1)),
      ]) {
        remote.producers[p.productorId] = p;
      }
      deliveries = _FakeDeliverySource(<MilkReceptionModel>[
        delivery('1', 'a', 120, '2026-11-02'),
        delivery('2', 'a', 80.5, '2026-11-03', jornada: 'TARDE'),
        delivery('3', 'b', 900, '2026-11-05'),
        delivery('4', 'c', 40, '2026-11-10'),
        delivery('5', 'c', 4000, '2026-11-11', anulado: true),
        delivery('6', 'd', 999, '2026-10-25'), // fuera de "Este mes"
      ]);
      controller = ProducerController(
        producerService: ProducerService(
          hiveService: HiveService(enablePersistence: false),
          remoteDataSource: remote,
          deliverySource: deliveries,
        ),
        clock: () => today,
      );
      await controller.loadProducers();
      await controller.loadDeliveries();
    });

    List<String> order() => controller.filteredProducers
        .map((ProducerModel p) => p.productorId)
        .toList();

    test(
      'Período por defecto es el mes actual y suma solo entregas válidas',
      () {
        expect(controller.period, DateRangePresets.monthOf(today));
        expect(controller.statsFor('a').liters, closeTo(200.5, 0.001));
        expect(controller.statsFor('a').deliveries, 2);
        expect(controller.statsFor('a').morningLiters, 120);
        expect(controller.statsFor('a').afternoonLiters, 80.5);
        expect(controller.statsFor('c').liters, 40); // la anulada no cuenta
        expect(controller.statsFor('d').liters, 0); // octubre no cuenta
        expect(controller.statsFor('d').lastDeliveryIso, '2026-10-25');
        expect(controller.periodLiters, closeTo(1140.5, 0.001));
        expect(controller.activeWithoutDeliveries, 1);
        expect(
          deliveries.lastStart,
          '2026-10-20',
        ); // ventana de 30 días para la gráfica
      },
    );

    test('Más recientes / más antiguos por fecha de creación', () {
      controller.setSort(ProducerSortOption.recientes);
      expect(order(), <String>['d', 'b', 'c', 'a']);
      controller.setSort(ProducerSortOption.antiguos);
      expect(order(), <String>['a', 'c', 'b', 'd']);
    });

    test('Más leche / menos leche entregada en el período', () {
      controller.setSort(ProducerSortOption.masLeche);
      expect(order(), <String>['b', 'a', 'c', 'd']);
      controller.setSort(ProducerSortOption.menosLeche);
      expect(order(), <String>['d', 'c', 'a', 'b']);
    });

    test('Nombre A–Z y código natural (ASO-2 < ASO-10)', () {
      controller.setSort(ProducerSortOption.nombre);
      expect(order(), <String>['a', 'b', 'c', 'd']);
      controller.setSort(ProducerSortOption.codigo);
      expect(order(), <String>['c', 'a', 'd', 'b']);
      expect(ProducerController.compareCodes('ASO-2', 'ASO-10'), lessThan(0));
      expect(
        ProducerController.compareCodes('ASO-99999999999999999999', 'ASO-1'),
        greaterThan(0),
      );
    });

    test('Cambiar el período recalcula los litros y el orden', () async {
      await controller.setPeriod(
        DateRangeValue(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      );
      controller.setSort(ProducerSortOption.masLeche);
      expect(controller.statsFor('d').liters, 999);
      expect(order().first, 'd');
    });

    test('Detalle: serie de 30 días y últimas entregas', () {
      final ProducerDetailStats detail = controller.detailFor('a');
      expect(detail.last30Days.length, 30);
      expect(detail.last30Total, closeTo(200.5, 0.001));
      expect(detail.recent.first.fechaEntrega, '2026-11-03');
    });

    test('Sin conexión usa entregas locales y lo indica', () async {
      deliveries.fail = true;
      await controller.loadDeliveries();
      expect(controller.deliveriesFromCache, isTrue);
    });
  });
}

class _FakeDeliverySource implements ProducerDeliverySource {
  _FakeDeliverySource(this.items);
  final List<MilkReceptionModel> items;
  bool fail = false;
  String? lastStart;

  @override
  Future<List<MilkReceptionModel>> fetchDeliveries({
    required String startIso,
    required String endIso,
  }) async {
    if (fail) throw Exception('Sin red');
    lastStart = startIso;
    return items
        .where(
          (MilkReceptionModel r) =>
              r.fechaEntrega.compareTo(startIso) >= 0 &&
              r.fechaEntrega.compareTo(endIso) <= 0,
        )
        .toList();
  }
}
