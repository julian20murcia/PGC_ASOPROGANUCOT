import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/reception_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/views/desktop/reception_module_view.dart';
import 'package:provider/provider.dart';

class _MockFirebaseUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

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

ProducerModel _producer(String id, String code, String nombre) => ProducerModel(
  productorId: id,
  codigoAsociado: code,
  cedula: '10735001$id',
  nombres: nombre,
  apellidos: 'Pérez',
  telefono: '3101112233',
  nombreFinca: 'La Pradera',
  vereda: 'La Glorieta',
  estado: 'ACTIVO',
  aceptoHabeasData: true,
  fechaAutorizacionDatos: DateTime.utc(2026, 1, 1),
  fechaCreacion: DateTime.utc(2026, 1, 1),
);

Future<ReceptionController> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final HiveService hive = HiveService(enablePersistence: false);
  final ReceptionController ctrl = ReceptionController(
    hiveService: hive,
    receptionService: ReceptionService(
      hiveService: hive,
      remoteDataSource: _Receptions(),
    ),
    producerService: ProducerService(
      hiveService: hive,
      remoteDataSource: _Producers(<ProducerModel>[
        _producer('1', 'ASO-001', 'María'),
        _producer('2', 'ASO-002', 'José'),
      ]),
    ),
  );
  final _MockFirebaseUserService users = _MockFirebaseUserService();
  when(() => users.currentFirebaseUser).thenReturn(null);
  final AuthController auth = AuthController(
    userService: users,
    hiveService: hive,
    fcmService: _MockFcmService(),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<UserController>.value(
          value: UserController(userService: users),
        ),
        ChangeNotifierProvider<ReceptionController>.value(value: ctrl),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: ReceptionModuleView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return ctrl;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final Size size in <Size>[
    const Size(1366, 860),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'Módulo de recepción sin desbordes a ${size.width.toInt()}×${size.height.toInt()}',
      (WidgetTester tester) async {
        await _pump(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.text('Captura rápida en planta'), findsOneWidget);
        expect(find.text('Litros recibidos hoy'), findsOneWidget);
        expect(find.text('Registrar entrega'), findsOneWidget);
        expect(find.text('Planilla'), findsOneWidget);
        expect(find.text('ASO-001'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Registra en la planilla con teclado y por captura rápida, sin diálogos',
    (WidgetTester tester) async {
      final ReceptionController ctrl = await _pump(
        tester,
        const Size(1366, 860),
      );

      // Planilla: celda Mañana de hoy del primer productor.
      await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-0')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('planilla-editor')),
        '20',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(ctrl.rangeTotalLiters, 20);
      expect(ctrl.rangeMorningLiters, 20);

      // Captura rápida: código + Enter, litros + Enter.
      await tester.tap(find.byKey(const ValueKey<String>('captura-productor')));
      await tester.enterText(
        find.byKey(const ValueKey<String>('captura-productor')),
        'ASO-002',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(ctrl.selectedProducer?.codigoAsociado, 'ASO-002');
      await tester.enterText(
        find.byKey(const ValueKey<String>('captura-litros')),
        '15,5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(ctrl.rangeTotalLiters, 35.5);

      // Registros: la vista lista ambas entregas.
      await tester.tap(find.text('Registros'));
      await tester.pumpAndSettle();
      expect(find.text('20 L'), findsOneWidget);
      expect(find.text('15,5 L'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
