import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/rate_controller.dart';
import 'package:pgc_asoproganucot/controllers/settlement_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/finance_config_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/core/utils/formatters.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/rates_module_view.dart';
import 'package:pgc_asoproganucot/views/desktop/settlements_module_view.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements AuthController {
  _FakeAuth(this.currentUser);
  @override
  final UserModel? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  }) async => items[updatedSettlement.liquidacionId] = updatedSettlement;
}

class _NoFinance extends FinanceConfigService {
  @override
  Future<FinanceConfig> load() async => FinanceConfig.empty;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final UserModel admin = UserModel(
    uid: 'admin',
    nombreCompleto: 'Admin Planta',
    documento: '1000',
    correo: 'a@a.co',
    telefono: '3100000000',
    rol: AppConstants.roleAdmin,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: DateTime.utc(2026, 1, 1),
  );

  Future<({SettlementController settlements, RateController rates})>
  setup() async {
    final HiveService hive = HiveService(enablePersistence: false);
    final _Receptions recs = _Receptions();
    final RateService rateService = RateService(
      hiveService: hive,
      remoteDataSource: _Rates(),
    );
    await rateService.createNewRate(
      actor: admin,
      precioPorLitro: 1850,
      fechaInicioVigencia: DateTime.now().subtract(const Duration(days: 90)),
      observacion: 'Tarifa inicial',
    );
    final QuincenaPeriod prev = QuincenaPeriod.previousForDate(DateTime.now());
    final List<String> days = DailyDeliveryMatrix.daysBetween(
      prev.startDate,
      prev.endDate,
    );
    int n = 0;
    for (int p = 0; p < 6; p++) {
      for (final String d in days.take(10)) {
        for (final String shift in <String>[
          AppConstants.shiftMorning,
          AppConstants.shiftAfternoon,
        ]) {
          final MilkReceptionModel r = MilkReceptionModel(
            recepcionId: 'r${n++}',
            productorId: 'P$p',
            codigoAsociadoSnap: 'ASO-00$p',
            nombreProductorSnap: 'Productor de prueba con nombre largo $p',
            litros: 10.5 + p,
            fechaEntrega: d,
            horaEntrega: '06:00:00',
            jornada: shift,
            operarioUid: 'op',
            syncStatus: AppConstants.syncSynced,
            isSynced: true,
            createdAt: DateTime.now().toUtc(),
          );
          recs.docs[r.recepcionId] = r;
          await hive.saveReception(r);
        }
      }
    }
    final SettlementController settlements = SettlementController(
      settlementService: SettlementService(
        hiveService: hive,
        remoteDataSource: _Settlements(recs.docs),
      ),
      receptionService: ReceptionService(
        hiveService: hive,
        remoteDataSource: recs,
      ),
      producerService: ProducerService(
        hiveService: hive,
        remoteDataSource: _Producers(),
      ),
      rateService: rateService,
    );
    final RateController rates = RateController(
      rateService: rateService,
      financeService: _NoFinance(),
    );
    return (settlements: settlements, rates: rates);
  }

  Widget host(Widget child, SettlementController s, RateController r) =>
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(admin)),
          ChangeNotifierProvider<SettlementController>.value(value: s),
          ChangeNotifierProvider<RateController>.value(value: r),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(body: child),
        ),
      );

  for (final Size size in const <Size>[Size(1280, 720), Size(1036, 640)]) {
    testWidgets(
      'Liquidaciones: cierre guiado en 3 pasos, detalle con productores y registros diarios a ${size.width.toInt()}×${size.height.toInt()}',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ({SettlementController settlements, RateController rates}) c =
            await tester.runAsync(setup) ?? (throw StateError('setup'));
        await tester.pumpWidget(
          host(const SettlementsModuleView(), c.settlements, c.rates),
        );
        await tester.runAsync(() => c.settlements.loadData());
        await tester.pump();

        expect(find.text('Liquidaciones Quincenales'), findsOneWidget);
        expect(find.text('Ejecutar cierre quincenal'), findsOneWidget);
        expect(find.text('Aún no hay quincenas cerradas'), findsOneWidget);
        expect(find.textContaining('está por cerrar'), findsOneWidget);

        await tester.tap(find.text('Cerrar quincena'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Paso 1 de 3'), findsOneWidget);
        expect(find.textContaining('Tarifa que se aplicará'), findsOneWidget);

        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Paso 2 de 3'), findsOneWidget);
        expect(find.text('6 de 6 productores incluidos'), findsOneWidget);
        // Excluye al primero.
        await tester.tap(find.byType(Checkbox).at(1));
        await tester.pump();
        expect(find.text('5 de 6 productores incluidos'), findsOneWidget);

        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Paso 3 de 3'), findsOneWidget);
        expect(
          find.textContaining('Se generan 5 comprobantes'),
          findsOneWidget,
        );

        await tester.runAsync(() async {
          await tester.tap(find.text('Cerrar quincena (5)'));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();
        expect(find.text('Quincena cerrada'), findsOneWidget);
        expect(c.settlements.allSettlements.length, 5);

        await tester.tap(find.text('Ver quincena cerrada'));
        await tester.pumpAndSettle();
        final QuincenaPeriod prev = QuincenaPeriod.previousForDate(
          DateTime.now(),
        );
        expect(find.text(prev.label), findsWidgets);
        expect(find.text('Productores (5)'), findsOneWidget);
        expect(find.text('Descargar quincena'), findsOneWidget);
        expect(
          find.text('COMP-${prev.endDate.substring(0, 4)}-0001'),
          findsOneWidget,
        );

        await tester.tap(find.text('Registros diarios'));
        await tester.pumpAndSettle();
        expect(find.text('Total por día'), findsOneWidget);
        expect(
          find.text(
            AppFormatters.formatLiters(
              c.settlements.periodGroups.single.totalLiters,
              withUnit: false,
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Volver a quincenas'));
        await tester.pumpAndSettle();
        expect(find.text('Quincenas cerradas'), findsOneWidget);
        expect(find.text('0 de 5 pagadas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Tarifas: precio vigente, historial, formulario e impacto a ${size.width.toInt()}×${size.height.toInt()}',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ({SettlementController settlements, RateController rates}) c =
            await tester.runAsync(setup) ?? (throw StateError('setup'));
        await tester.pumpWidget(
          host(const RatesModuleView(), c.settlements, c.rates),
        );
        await tester.runAsync(() async {
          await c.rates.loadRates();
          await c.settlements.loadData();
        });
        await tester.pump();

        expect(find.text('Tarifa vigente actual'), findsOneWidget);
        expect(find.text('Nueva tarifa vigente'), findsOneWidget);
        expect(find.text('Historial de tarifas'), findsOneWidget);
        expect(find.text('Parámetros financieros'), findsOneWidget);
        expect(find.text(r'$ 1.850'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
