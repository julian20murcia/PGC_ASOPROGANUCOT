import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/producer_controller.dart';
import 'package:pgc_asoproganucot/controllers/rate_controller.dart';
import 'package:pgc_asoproganucot/controllers/reception_controller.dart';
import 'package:pgc_asoproganucot/controllers/report_controller.dart';
import 'package:pgc_asoproganucot/controllers/settlement_controller.dart';
import 'package:pgc_asoproganucot/controllers/sync_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/report_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/main.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/privacy_notice.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/cow_balloon_3d_widget.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/dairy_loader.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/design_system_widgets.dart';
import 'package:provider/provider.dart';

class _MockFirebaseUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

class _FakeRemoteProducerDataSource implements RemoteProducerDataSource {
  final List<ProducerModel> _items = <ProducerModel>[];

  @override
  Future<List<ProducerModel>> fetchProducers() async =>
      List<ProducerModel>.from(_items);

  @override
  Future<void> upsertProducer(ProducerModel producer) async {
    _items.removeWhere((ProducerModel p) => p.productorId == producer.productorId);
    _items.add(producer);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _FakeRemoteReceptionDataSource implements RemoteReceptionDataSource {
  final List<MilkReceptionModel> _items = <MilkReceptionModel>[];

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async =>
      List<MilkReceptionModel>.from(_items);

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    _items.removeWhere((MilkReceptionModel r) => r.recepcionId == reception.recepcionId);
    _items.add(reception);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _FakeRemoteRateDataSource implements RemoteRateDataSource {
  final List<MilkRateModel> _rates = <MilkRateModel>[];

  @override
  Future<List<MilkRateModel>> fetchRates() async => List<MilkRateModel>.from(_rates);

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {
    for (final MilkRateModel r in rates) {
      _rates.removeWhere((MilkRateModel item) => item.tarifaId == r.tarifaId);
      _rates.add(r);
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _FakeRemoteSettlementDataSource implements RemoteSettlementDataSource {
  final List<SettlementModel> _items = <SettlementModel>[];

  @override
  Future<List<SettlementModel>> fetchSettlements() async =>
      List<SettlementModel>.from(_items);

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {
    _items.addAll(settlements);
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {}
}

class _FakeRemoteAuditDataSource implements RemoteAuditDataSource {
  @override
  Future<List<AuditLogModel>> fetchAuditLogs({int limit = 250}) async =>
      const <AuditLogModel>[];
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'Login valida credenciales, abre AdminShellView y permite navegar al módulo de Productores con Habeas Data',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final UserModel adminUser = UserModel(
      uid: 'uid-admin-1',
      nombreCompleto: 'Bradley Ballen',
      documento: '1073500123',
      correo: 'bradley@asoproganucot.com',
      telefono: '3101234567',
      rol: AppConstants.roleAdmin,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: DateTime.utc(2026, 11, 17),
    );

    final _MockFirebaseUserService mockUserService = _MockFirebaseUserService();
    final _MockFcmService mockFcmService = _MockFcmService();
    final HiveService memoryHive = HiveService(enablePersistence: false);

    when(() => mockUserService.currentFirebaseUser).thenReturn(null);
    when(
      () => mockUserService.signInWithIdentifier(
        identifier: 'bradley@asoproganucot.com',
        password: 'Password123',
      ),
    ).thenAnswer((_) async => adminUser);
    when(() => mockUserService.listUsers()).thenAnswer(
      (_) async => (users: <UserModel>[adminUser], fromCache: false),
    );
    when(() => mockUserService.signOut()).thenAnswer((_) async {});
    when(() => mockFcmService.fetchDeviceTokenIfSupported())
        .thenAnswer((_) async => null);

    final AuthController authController = AuthController(
      userService: mockUserService,
      hiveService: memoryHive,
      fcmService: mockFcmService,
    );
    await authController.initialize();

    final UserController userController = UserController(
      userService: mockUserService,
    );
    final ProducerService producerService = ProducerService(
      hiveService: memoryHive,
      remoteDataSource: _FakeRemoteProducerDataSource(),
    );
    int noticeReads = 0;
    final retriedNotice = Completer<PrivacyNotice>();
    final ProducerController producerController = ProducerController(
      producerService: producerService,
      privacyNoticeLoader: () async {
        if (++noticeReads == 1) {
          throw const FormatException(
            'Falta publicar el aviso institucional en configuracion/privacidad.',
          );
        }
        return retriedNotice.future;
      },
    );
    final ReceptionService receptionService = ReceptionService(
      hiveService: memoryHive,
      remoteDataSource: _FakeRemoteReceptionDataSource(),
    );
    final ReceptionController receptionController = ReceptionController(
      hiveService: memoryHive,
      producerService: producerService,
      receptionService: receptionService,
    );
    final RateService rateService = RateService(
      hiveService: memoryHive,
      remoteDataSource: _FakeRemoteRateDataSource(),
    );
    final RateController rateController = RateController(
      rateService: rateService,
    );
    final SettlementService settlementService = SettlementService(
      hiveService: memoryHive,
      remoteDataSource: _FakeRemoteSettlementDataSource(),
    );
    final SettlementController settlementController = SettlementController(
      settlementService: settlementService,
      receptionService: receptionService,
      producerService: producerService,
      rateService: rateService,
    );
    final SyncController syncController = SyncController(
      hiveService: memoryHive,
    );
    final ReportController reportController = ReportController(
      reportService: ReportService(
        remoteAuditDataSource: _FakeRemoteAuditDataSource(),
      ),
      receptionService: receptionService,
      producerService: producerService,
      rateService: rateService,
      settlementService: settlementService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<UserController>.value(value: userController),
          ChangeNotifierProvider<ProducerController>.value(
            value: producerController,
          ),
          ChangeNotifierProvider<ReceptionController>.value(
            value: receptionController,
          ),
          ChangeNotifierProvider<RateController>.value(value: rateController),
          ChangeNotifierProvider<SettlementController>.value(
            value: settlementController,
          ),
          ChangeNotifierProvider<SyncController>.value(value: syncController),
          ChangeNotifierProvider<ReportController>.value(
            value: reportController,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const AuthGate(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('ACCESO AL SISTEMA'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Ingresar al sistema'), findsOneWidget);
    expect(find.byType(MilkFlowBackground), findsWidgets);
    expect(find.byType(DairyLoader), findsWidgets);

    // Intento vacío debe mostrar mensaje de validación
    await tester.tap(find.text('Ingresar al sistema'));
    await tester.pump();
    expect(
      find.text('Ingresa tu correo electrónico o número de documento.'),
      findsOneWidget,
    );

    // Ingresar credenciales válidas
    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'bradley@asoproganucot.com');
    await tester.enterText(fields.at(1), 'Password123');
    await tester.tap(find.text('Ingresar al sistema'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Usuarios'), findsAtLeastNWidgets(1));
    expect(find.text('Recepción de Leche'), findsOneWidget);
    expect(find.text('Operación en planta'), findsOneWidget);
    expect(find.text('Nuevo usuario'), findsOneWidget);
    expect(find.text('Bradley Ballen'), findsAtLeastNWidgets(1));

    // Navegar al módulo de Productores
    await tester.tap(find.text('Productores').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nuevo productor'), findsOneWidget);
    expect(find.text('Productores activos'), findsOneWidget);

    // Abrir diálogo de creación y verificar bloqueo sin Habeas Data
    await tester.tap(find.text('Nuevo productor'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(
      find.text('Aviso de privacidad'),
      findsOneWidget,
    );
    expect(find.text('Guardar productor'), findsOneWidget);
    final Finder saveProducer = find.widgetWithText(
      PrimaryActionButton,
      'Guardar productor',
    );
    expect(tester.widget<PrimaryActionButton>(saveProducer).onPressed, isNull);
    expect(find.textContaining('registrar entregas de leche'), findsOneWidget);
    expect(find.textContaining('configuracion/privacidad'), findsOneWidget);
    expect(find.text('Ver copia de la política (PDF)'), findsOneWidget);
    expect(find.text('Referencia del soporte firmado o electrónico'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(noticeReads, 2);
    expect(find.text('Cargando el aviso institucional…'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    expect(tester.widget<PrimaryActionButton>(saveProducer).onPressed, isNull);

    retriedNotice.complete(PrivacyNotice.fromMap(const <String, dynamic>{
      'version': '1.0 de prueba',
      'responsable': 'Asociación de prueba',
      'direccion': 'Sede de prueba',
      'correo': 'privacidad@example.com',
      'telefono': '5550000',
      'politicaUrl': 'https://example.com/politica',
      'finalidades': 'Registro de entregas y liquidación.',
      'derechos': 'Consulta y rectificación de datos.',
    }));
    await tester.pump();
    expect(find.text('Versión 1.0 de prueba'), findsOneWidget);
    expect(find.text('Ver política de tratamiento'), findsOneWidget);
    expect(find.textContaining('privacidad@example.com'), findsOneWidget);
    expect(tester.widget<PrimaryActionButton>(saveProducer).onPressed, isNull);

    await tester.tap(find.textContaining('Entregué el aviso y el productor'));
    await tester.pump();
    expect(find.text('Referencia del soporte firmado o electrónico'), findsOneWidget);
    expect(tester.widget<PrimaryActionButton>(saveProducer).onPressed, isNotNull);

    // Cerrar diálogo y navegar a Recepción de Leche
    await tester.tap(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Recepción de Leche').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Captura rápida en planta'), findsOneWidget);
    expect(find.text('Litros recibidos hoy'), findsOneWidget);
    expect(find.text('Registrar entrega'), findsOneWidget);

    // Navegar a Tarifas por Litro y Liquidaciones
    await tester.tap(find.text('Tarifas por Litro').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nueva tarifa vigente'), findsOneWidget);
    expect(find.text('Tarifa vigente actual'), findsOneWidget);

    await tester.tap(find.text('Liquidaciones').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Liquidaciones Quincenales'), findsOneWidget);
    expect(find.text('Ejecutar cierre quincenal'), findsOneWidget);

    // Navegar a Inicio (Dashboard) y Reportes y Auditoría
    await tester.tap(find.text('Inicio').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resumen Operativo de Planta'), findsOneWidget);
    expect(find.text('Litros acopiados hoy'), findsOneWidget);

    await tester.tap(find.text('Reportes y Auditoría').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Producción por ganadero'), findsOneWidget);
    expect(find.text('Bitácora de auditoría'), findsOneWidget);
  });

  testWidgets(
      'Login móvil muestra cabecera wave moderna sin el modelo 3D y sin desbordamientos',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _MockFirebaseUserService mockUserService = _MockFirebaseUserService();
    final _MockFcmService mockFcmService = _MockFcmService();
    final HiveService memoryHive = HiveService(enablePersistence: false);
    when(() => mockUserService.currentFirebaseUser).thenReturn(null);

    final AuthController authController = AuthController(
      userService: mockUserService,
      hiveService: memoryHive,
      fcmService: mockFcmService,
    );
    await authController.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<UserController>(
            create: (_) => UserController(userService: mockUserService),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const AuthGate(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ModernWaveHeader), findsOneWidget);
    expect(find.byType(CowBalloon3DWidget), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ModernWaveHeader),
        matching: find.text('ASOPROGANUCOTT'),
      ),
      findsOneWidget,
    );
    expect(find.text('Recepción láctea y consulta de productores'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Ingresar al sistema'), findsOneWidget);

    final registration = find.text('Crear cuenta de productor');
    await tester.ensureVisible(registration);
    await tester.tap(registration);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.textContaining('El registro requiere el aviso institucional vigente'), findsOneWidget);
    expect(find.text('Enviar código por SMS'), findsNothing);
  });
}
