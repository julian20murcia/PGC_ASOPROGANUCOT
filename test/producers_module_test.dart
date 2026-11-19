import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/producer_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/privacy_notice.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/producers/producer_form_wizard.dart';
import 'package:pgc_asoproganucot/views/desktop/producers_module_view.dart';
import 'package:provider/provider.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcm extends Mock implements FcmService {}

class _FakeAuth extends AuthController {
  _FakeAuth(this._user)
    : super(
        userService: _MockUserService(),
        hiveService: HiveService(enablePersistence: false),
        fcmService: _MockFcm(),
      );
  final UserModel _user;

  @override
  UserModel? get currentUser => _user;
}

class _MemoryRemote implements RemoteProducerDataSource {
  final Map<String, ProducerModel> items = <String, ProducerModel>{};

  @override
  Future<List<ProducerModel>> fetchProducers() async => items.values.toList();

  @override
  Future<void> upsertProducer(ProducerModel producer) async =>
      items[producer.productorId] = producer;

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _NoDeliveries implements ProducerDeliverySource {
  @override
  Future<List<MilkReceptionModel>> fetchDeliveries({
    required String startIso,
    required String endIso,
  }) async => const <MilkReceptionModel>[];
}

final PrivacyNotice _notice = PrivacyNotice.fromMap(const <String, dynamic>{
  'version': '1.0 de prueba',
  'responsable': 'Asociación de prueba',
  'direccion': 'Sede de prueba',
  'correo': 'privacidad@example.com',
  'telefono': '5550000',
  'politicaUrl': 'https://example.com/politica',
  'finalidades': 'Registro de entregas y liquidación.',
  'derechos': 'Consulta y rectificación de datos.',
});

UserModel _admin() => UserModel(
  uid: 'uid-admin',
  nombreCompleto: 'Admin Prueba',
  documento: '1073500123',
  correo: 'admin@example.com',
  telefono: '3101234567',
  rol: AppConstants.roleAdmin,
  activo: true,
  fcmTokens: const <String>[],
  fechaCreacion: DateTime.utc(2026, 1, 1),
);

Finder _input(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _MemoryRemote remote;
  late ProducerController ctrl;

  setUp(() {
    remote = _MemoryRemote();
    remote.items['p1'] = ProducerModel(
      productorId: 'p1',
      codigoAsociado: 'ASO-001',
      cedula: '1073500001',
      nombres: 'Mario',
      apellidos: 'Castillo',
      telefono: '3101110001',
      nombreFinca: 'El Roble',
      vereda: 'La Glorieta',
      estado: 'ACTIVO',
      aceptoHabeasData: true,
      fechaCreacion: DateTime.utc(2025, 1, 1),
    );
    ctrl = ProducerController(
      producerService: ProducerService(
        hiveService: HiveService(enablePersistence: false),
        remoteDataSource: remote,
        deliverySource: _NoDeliveries(),
      ),
      privacyNoticeLoader: () async => _notice,
    );
  });

  Widget host(Widget child) => MultiProvider(
    providers: <ChangeNotifierProvider<dynamic>>[
      ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(_admin())),
      ChangeNotifierProvider<UserController>(
        create: (_) => UserController(userService: _MockUserService()),
      ),
      ChangeNotifierProvider<ProducerController>.value(value: ctrl),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(body: child),
    ),
  );

  Future<void> openWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await ctrl.loadProducers();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () => showProducerWizard(
                context,
                actorUid: 'uid-admin',
                canCreateAppAccess: true,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Asistente: errores en línea por paso y avance con Siguiente / Enter',
    (WidgetTester tester) async {
      await openWizard(tester);

      expect(find.text('Registrar productor'), findsOneWidget);
      expect(find.text('Datos personales'), findsWidgets);
      expect(find.text('Paso 1 de 4'), findsOneWidget);

      // Siguiente sin datos: errores en línea y no avanza.
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();
      expect(find.text('Los nombres es obligatorio'), findsOneWidget);
      expect(find.text('El documento es obligatorio'), findsOneWidget);
      expect(find.text('Paso 1 de 4'), findsOneWidget);

      // Los formateadores bloquean letras repetidas, números y textos larguísimos.
      await tester.enterText(
        _input(ProducerWizardKeys.nombres),
        'Juliaaaan123',
      );
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(_input(ProducerWizardKeys.nombres))
            .controller
            .text,
        isNot(contains('aaa')),
      );
      expect(
        tester
            .widget<EditableText>(_input(ProducerWizardKeys.nombres))
            .controller
            .text,
        isNot(contains('1')),
      );
      await tester.enterText(
        _input(ProducerWizardKeys.cedula),
        '10735abc00000000000000',
      );
      await tester.pump();
      final String cedula = tester
          .widget<EditableText>(_input(ProducerWizardKeys.cedula))
          .controller
          .text;
      expect(cedula, matches(RegExp(r'^\d{0,12}$')));

      // Cédula duplicada -> error en línea.
      await tester.enterText(_input(ProducerWizardKeys.nombres), 'José Luis');
      await tester.enterText(_input(ProducerWizardKeys.apellidos), 'Pérez');
      await tester.enterText(_input(ProducerWizardKeys.cedula), '1073500001');
      await tester.enterText(_input(ProducerWizardKeys.telefono), '310123');
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();
      expect(find.text('Ya registrada para Mario Castillo'), findsOneWidget);
      expect(
        find.text('Celular de 10 dígitos (ej. 3101234567)'),
        findsOneWidget,
      );

      await tester.enterText(_input(ProducerWizardKeys.cedula), '1073500999');
      await tester.enterText(_input(ProducerWizardKeys.telefono), '3101234567');
      // Enter en el último campo avanza.
      await tester.showKeyboard(_input(ProducerWizardKeys.telefono));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Paso 2 de 4'), findsOneWidget);

      // Paso 2: código sugerido y vereda con autocompletar.
      expect(
        tester
            .widget<EditableText>(_input(ProducerWizardKeys.codigo))
            .controller
            .text,
        'ASO-002',
      );
      await tester.enterText(_input(ProducerWizardKeys.codigo), 'ASO-001');
      await tester.enterText(_input(ProducerWizardKeys.finca), '🐄🐄');
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();
      expect(find.text('Ya asignado a Mario Castillo'), findsOneWidget);
      expect(find.text('Paso 2 de 4'), findsOneWidget);

      await tester.enterText(_input(ProducerWizardKeys.codigo), 'ASO-002');
      await tester.enterText(_input(ProducerWizardKeys.finca), 'El Porvenir');
      await tester.enterText(_input(ProducerWizardKeys.vereda), 'glo');
      await tester.pumpAndSettle();
      expect(find.text('La Glorieta'), findsOneWidget);
      await tester.tap(find.text('La Glorieta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();

      // Paso 3: Habeas Data.
      expect(find.text('Paso 3 de 4'), findsOneWidget);
      expect(find.text('Versión 1.0 de prueba'), findsOneWidget);
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();
      expect(
        find.text('Marca la casilla para confirmar la autorización.'),
        findsOneWidget,
      );
      // El soporte es opcional: sin él se genera una constancia automática.
      expect(
        find.text('Indica dónde quedó el soporte de la autorización'),
        findsNothing,
      );
      expect(find.text('Soporte de autorización (opcional)'), findsOneWidget);

      await tester.tap(find.byKey(ProducerWizardKeys.consent));
      await tester.enterText(
        _input(ProducerWizardKeys.soporte),
        'Formato firmado 045',
      );
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();

      // Paso 4: revisión y guardado.
      expect(find.text('Paso 4 de 4'), findsOneWidget);
      expect(find.text('José Luis Pérez'), findsOneWidget);
      expect(find.text('ASO-002'), findsOneWidget);
      expect(find.text('Guardar productor'), findsOneWidget);

      // Atrás conserva lo escrito.
      await tester.tap(find.byKey(ProducerWizardKeys.back));
      await tester.pumpAndSettle();
      expect(find.text('Paso 3 de 4'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(_input(ProducerWizardKeys.soporte))
            .controller
            .text,
        'Formato firmado 045',
      );
      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ProducerWizardKeys.next));
      await tester.pumpAndSettle();
      expect(find.text('Productor registrado'), findsOneWidget);
      expect(find.byKey(ProducerWizardKeys.appAccess), findsOneWidget);
      final ProducerModel saved = remote.items.values.firstWhere(
        (ProducerModel p) => p.cedula == '1073500999',
      );
      expect(saved.nombreCompleto, 'José Luis Pérez');
      expect(saved.vereda, 'La Glorieta');
      expect(saved.soporteAutorizacion, 'Formato firmado 045');

      await tester.tap(find.byKey(ProducerWizardKeys.done));
      await tester.pumpAndSettle();
      expect(find.text('Productor registrado'), findsNothing);
    },
  );

  testWidgets('Asistente: aviso de privacidad con error permite reintentar', (
    WidgetTester tester,
  ) async {
    int reads = 0;
    ctrl = ProducerController(
      producerService: ProducerService(
        hiveService: HiveService(enablePersistence: false),
        remoteDataSource: remote,
        deliverySource: _NoDeliveries(),
      ),
      privacyNoticeLoader: () async {
        if (++reads == 1) {
          throw const FormatException('Falta publicar el aviso institucional.');
        }
        return _notice;
      },
    );
    await openWizard(tester);
    await tester.enterText(_input(ProducerWizardKeys.nombres), 'Ana');
    await tester.enterText(_input(ProducerWizardKeys.apellidos), 'Ruiz');
    await tester.enterText(_input(ProducerWizardKeys.cedula), '1073500888');
    await tester.enterText(_input(ProducerWizardKeys.telefono), '3101234560');
    await tester.tap(find.byKey(ProducerWizardKeys.next));
    await tester.pumpAndSettle();
    await tester.enterText(_input(ProducerWizardKeys.finca), 'La Esperanza');
    await tester.enterText(_input(ProducerWizardKeys.vereda), 'Cascajal');
    await tester.tap(find.byKey(ProducerWizardKeys.next));
    await tester.pumpAndSettle();

    expect(find.text('Falta publicar el aviso institucional.'), findsOneWidget);
    await tester.tap(find.byKey(ProducerWizardKeys.next));
    await tester.pumpAndSettle();
    expect(
      find.text('Espera a que cargue el aviso de privacidad para continuar.'),
      findsOneWidget,
    );
    expect(find.text('Paso 3 de 4'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Versión 1.0 de prueba'), findsOneWidget);
  });

  testWidgets('Módulo a 1280x720: tabla, orden y panel lateral sin desbordes', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const ProducersModuleView()));
    await tester.pumpAndSettle();

    expect(find.text('Productores'), findsOneWidget);
    expect(find.text('Productores activos'), findsOneWidget);
    expect(find.text('Nuevo productor'), findsOneWidget);
    expect(find.text('Mario Castillo'), findsOneWidget);
    expect(find.text('Orden: Más recientes'), findsOneWidget);

    await tester.tap(find.text('Mario Castillo'));
    await tester.pumpAndSettle();
    expect(find.text('Últimas entregas'.toUpperCase()), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Inactivar'), findsOneWidget);
    expect(find.text('Crear acceso app'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Crear acceso app'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in const <Size>[
    Size(1020, 680),
    Size(760, 560),
    Size(420, 760),
  ]) {
    testWidgets(
      'Módulo sin desbordes en ${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(const ProducersModuleView()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mario Castillo'));
        await tester.pumpAndSettle();
        expect(find.text('Datos del productor'.toUpperCase()), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
