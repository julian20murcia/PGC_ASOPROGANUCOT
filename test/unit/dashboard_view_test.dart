import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/producer_controller.dart';
import 'package:pgc_asoproganucot/controllers/rate_controller.dart';
import 'package:pgc_asoproganucot/controllers/reception_controller.dart';
import 'package:pgc_asoproganucot/controllers/settlement_controller.dart';
import 'package:pgc_asoproganucot/controllers/sync_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/finance_config_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/dashboard_module_view.dart';
import 'package:provider/provider.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcm extends Mock implements FcmService {}

class _Auth extends AuthController {
  _Auth(this._user, {super.userService, super.hiveService, super.fcmService});
  final UserModel _user;
  @override
  UserModel? get currentUser => _user;
}

class _Producers implements RemoteProducerDataSource {
  _Producers(this.items);
  final List<ProducerModel> items;
  @override
  Future<List<ProducerModel>> fetchProducers() async => items;
  @override
  Future<void> upsertProducer(ProducerModel producer) async {}
  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Receptions implements RemoteReceptionDataSource {
  _Receptions(this.items);
  final List<MilkReceptionModel> items;
  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async => items;
  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {}
  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Rates implements RemoteRateDataSource {
  @override
  Future<List<MilkRateModel>> fetchRates() async => <MilkRateModel>[
        MilkRateModel(
          tarifaId: 't1',
          precioPorLitro: 1800,
          fechaInicioVigencia: DateTime.utc(2025, 1, 1),
          observacion: 'Tarifa',
          registradoPorUid: 'u',
        ),
      ];
  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {}
  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _Settlements implements RemoteSettlementDataSource {
  @override
  Future<List<SettlementModel>> fetchSettlements() async => const <SettlementModel>[];
  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {}
  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {}
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required int historyDays,
  FinanceConfig finance = FinanceConfig.empty,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final DateTime now = DateTime.now();
  final List<ProducerModel> producers = <ProducerModel>[
    for (int i = 0; i < 5; i++)
      ProducerModel(
        productorId: 'p$i',
        codigoAsociado: 'A-00$i',
        cedula: '10000000$i',
        nombres: <String>['Ana', 'Beto', 'Carla', 'Diego', 'Elena'][i],
        apellidos: 'Pérez',
        telefono: '3100000000',
        nombreFinca: 'Finca $i',
        vereda: i.isEven ? 'El Hato' : 'Nutrias',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        fechaCreacion: DateTime.utc(2025, 1, 1),
      ),
  ];
  final List<MilkReceptionModel> receptions = <MilkReceptionModel>[];
  for (int d = historyDays; d >= 0; d--) {
    final DateTime day = DateTime(now.year, now.month, now.day - d);
    for (int p = 0; p < 5; p++) {
      // Productor p4 deja de entregar las últimas 3 semanas (anomalía).
      if (p == 4 && d < 21) continue;
      for (final String shift in <String>[AppConstants.shiftMorning, AppConstants.shiftAfternoon]) {
        receptions.add(MilkReceptionModel(
          recepcionId: 'r-$d-$p-$shift',
          productorId: 'p$p',
          codigoAsociadoSnap: 'A-00$p',
          nombreProductorSnap: producers[p].nombreCompleto,
          litros: 40.0 + p * 10 + (d % 7) * 2,
          fechaEntrega: _iso(day),
          horaEntrega: '06:00:00',
          jornada: shift,
          operarioUid: 'op',
          isSynced: true,
          syncStatus: AppConstants.syncSynced,
          createdAt: day,
        ));
      }
    }
  }

  final HiveService hive = HiveService(enablePersistence: false);
  final _MockUserService userService = _MockUserService();
  final _MockFcm fcm = _MockFcm();
  when(() => userService.currentFirebaseUser).thenReturn(null);
  final UserModel admin = UserModel(
    uid: 'u1',
    nombreCompleto: 'Bradley Ballen',
    documento: '1073500123',
    correo: 'b@x.com',
    telefono: '3101234567',
    rol: AppConstants.roleAdmin,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: DateTime.utc(2026, 1, 1),
  );
  final ProducerService producerService = ProducerService(hiveService: hive, remoteDataSource: _Producers(producers));
  final ReceptionService receptionService =
      ReceptionService(hiveService: hive, remoteDataSource: _Receptions(receptions));
  final RateService rateService = RateService(hiveService: hive, remoteDataSource: _Rates());
  final SettlementService settlementService = SettlementService(hiveService: hive, remoteDataSource: _Settlements());

  await tester.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>.value(
          value: _Auth(admin, userService: userService, hiveService: hive, fcmService: fcm),
        ),
        ChangeNotifierProvider<UserController>.value(value: UserController(userService: userService)),
        ChangeNotifierProvider<ProducerController>.value(value: ProducerController(producerService: producerService)),
        ChangeNotifierProvider<ReceptionController>.value(
          value: ReceptionController(hiveService: hive, producerService: producerService, receptionService: receptionService),
        ),
        ChangeNotifierProvider<RateController>.value(value: RateController(rateService: rateService)),
        ChangeNotifierProvider<SettlementController>.value(
          value: SettlementController(
            settlementService: settlementService,
            receptionService: receptionService,
            producerService: producerService,
            rateService: rateService,
          ),
        ),
        ChangeNotifierProvider<SyncController>.value(value: SyncController(hiveService: hive)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: DashboardModuleView(
            onNavigateSection: (_) {},
            financeLoader: () async => finance,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('1280×720: dashboard completo sin overflow, con predicción y aviso financiero', (WidgetTester tester) async {
    await _pump(tester, size: const Size(1280, 720), historyDays: 120);
    expect(tester.takeException(), isNull);
    expect(find.text('Resumen Operativo de Planta'), findsOneWidget);
    expect(find.text('Litros acopiados hoy'), findsOneWidget);
    expect(find.text('Predicción inteligente · próximos 5 meses'), findsOneWidget);
    expect(find.textContaining('Precisión histórica'), findsOneWidget);
    expect(find.text('Configura el precio de venta en Tarifas por litro para estimar ganancias'), findsOneWidget);
    expect(find.textContaining('Elena'), findsWidgets); // caída detectada
  });

  testWidgets('1920×1080 con finanzas configuradas muestra resultado acumulado', (WidgetTester tester) async {
    await _pump(
      tester,
      size: const Size(1920, 1080),
      historyDays: 150,
      finance: const FinanceConfig(precioVentaLitro: 2300, costoOperativoMensual: 1500000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('RESULTADO NETO ACUMULADO (5 MESES)'), findsOneWidget);
    expect(find.textContaining('acumulada de'), findsOneWidget);
    expect(find.text('Configura el precio de venta en Tarifas por litro para estimar ganancias'), findsNothing);
  });

  testWidgets('pocos datos: mensaje honesto de días faltantes (ventana angosta)', (WidgetTester tester) async {
    await _pump(tester, size: const Size(800, 900), historyDays: 5);
    expect(tester.takeException(), isNull);
    expect(find.text('Datos insuficientes para proyectar'), findsOneWidget);
    expect(find.textContaining('faltan'), findsWidgets);
  });
}
