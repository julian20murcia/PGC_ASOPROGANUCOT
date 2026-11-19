import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/report_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/security/permissions.dart';
import 'package:pgc_asoproganucot/core/services/audit_query_service.dart';
import 'package:pgc_asoproganucot/core/services/broadcast_service.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/report_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/communications_module_view.dart';
import 'package:pgc_asoproganucot/views/desktop/reports_module_view.dart';
import 'package:pgc_asoproganucot/views/desktop/users/permission_tree_editor.dart';
import 'package:pgc_asoproganucot/views/desktop/users/user_form_dialog.dart';
import 'package:pgc_asoproganucot/views/desktop/users_module_view.dart';
import 'package:provider/provider.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcm extends Mock implements FcmService {}

class _FakeAuth extends AuthController {
  _FakeAuth(this.user) : super(userService: _MockUserService(), hiveService: HiveService(enablePersistence: false), fcmService: _MockFcm());
  final UserModel user;

  @override
  UserModel? get currentUser => user;
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

class _Rates implements RemoteRateDataSource {
  @override
  Future<List<MilkRateModel>> fetchRates() async => const <MilkRateModel>[];
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

class _Audit implements RemoteAuditDataSource {
  @override
  Future<List<AuditLogModel>> fetchAuditLogs({int limit = 250}) async => const <AuditLogModel>[];
}

class _Broadcasts implements BroadcastBackend {
  final List<AppNotificationModel> stored = <AppNotificationModel>[];
  @override
  Future<void> commitDelete(AppNotificationModel notification, AuditLogModel log) async =>
      stored.removeWhere((AppNotificationModel n) => n.notificacionId == notification.notificacionId);
  @override
  Future<void> commitSend(AppNotificationModel notification, AuditLogModel log) async => stored.add(notification);
  @override
  Future<List<AppNotificationModel>> fetchBroadcasts() async => List<AppNotificationModel>.from(stored);
}

final UserModel admin = UserModel(
  uid: 'u-admin',
  nombreCompleto: 'Ana Gómez',
  documento: '1073500100',
  correo: 'ana@asoproganucot.com',
  telefono: '3101234567',
  rol: AppConstants.roleAdmin,
  activo: true,
  fcmTokens: const <String>[],
  fechaCreacion: DateTime.utc(2026, 11, 1),
  ultimoAcceso: DateTime.now().subtract(const Duration(minutes: 5)),
);

final UserModel operario = UserModel(
  uid: 'u-op',
  nombreCompleto: 'Luis Pérez',
  documento: '1073500200',
  correo: 'luis@asoproganucot.com',
  telefono: '',
  rol: AppConstants.roleOperario,
  activo: true,
  fcmTokens: const <String>[],
  fechaCreacion: DateTime.utc(2026, 11, 1),
);

void _desktop(WidgetTester tester, {Size size = const Size(1280, 720)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _app(Widget child, {required List<ChangeNotifierProvider<dynamic>> providers, AuditQueryService? audit}) {
  final Widget home = Scaffold(body: child);
  final Widget app = MultiProvider(
    providers: providers,
    child: MaterialApp(theme: AppTheme.lightTheme(), home: home),
  );
  if (audit == null) return app;
  return Provider<AuditQueryService>.value(value: audit, child: app);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Árbol de permisos', () {
    Future<Map<String, List<String>>> pumpTree(WidgetTester tester, String role) async {
      Map<String, List<String>> perms = Permissions.defaultsFor(role);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter set) => PermissionTreeEditor(
                role: role,
                value: perms,
                onChanged: (Map<String, List<String>> p) => set(() => perms = p),
              ),
            ),
          ),
        ),
      ));
      return perms;
    }

    testWidgets('marcar Editar marca Ver; quitar Ver quita el módulo; Todo y Nada', (WidgetTester tester) async {
      _desktop(tester, size: const Size(1000, 2400));
      await pumpTree(tester, AppConstants.roleOperario);
      final Finder editar = find.byKey(const ValueKey<String>('perm-productores-editar'));
      await tester.tap(editar);
      await tester.pump();
      Checkbox box(String k) => tester.widget<Checkbox>(
          find.descendant(of: find.byKey(ValueKey<String>(k)), matching: find.byType(Checkbox)));
      expect(box('perm-productores-editar').value, isTrue);
      expect(box('perm-productores-ver').value, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('perm-productores-ver')));
      await tester.pump();
      expect(box('perm-productores-editar').value, isFalse);
      expect(box('perm-productores-ver').value, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('perm-master-usuarios')));
      await tester.pump();
      expect(box('perm-usuarios-eliminar').value, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('perm-none')));
      await tester.pump();
      expect(find.textContaining('0 de ${Permissions.totalActions}'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('perm-all')));
      await tester.pump();
      expect(find.textContaining('${Permissions.totalActions} de ${Permissions.totalActions}'), findsOneWidget);
      await tester.tap(find.text('Restablecer a permisos del rol'));
      await tester.pump();
      expect(find.textContaining('los del rol'), findsOneWidget);
    });

    testWidgets('administrador bloqueado y productor oculto', (WidgetTester tester) async {
      _desktop(tester, size: const Size(1000, 2400));
      await pumpTree(tester, AppConstants.roleAdmin);
      expect(find.text('El administrador siempre tiene acceso total'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('perm-all')), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('perm-recepcion-ver')));
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(find.descendant(
                of: find.byKey(const ValueKey<String>('perm-recepcion-ver')), matching: find.byType(Checkbox)))
            .value,
        isTrue,
      );
      await pumpTree(tester, AppConstants.roleProductor);
      expect(find.text('Los productores usan solo la app móvil'), findsOneWidget);
      expect(find.byType(TriStateSwitch), findsNothing);
    });
  });

  group('Asistente de usuario', () {
    late _MockUserService service;
    late UserController users;

    setUp(() {
      service = _MockUserService();
      users = UserController(userService: service);
      when(() => service.listUsers()).thenAnswer((_) async => (users: <UserModel>[admin, operario], fromCache: false));
    });

    Future<void> openDialog(WidgetTester tester, {UserModel? edit}) async {
      _desktop(tester, size: const Size(1280, 900));
      await tester.pumpWidget(_app(
        Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () => showUserFormDialog(context, user: edit),
              child: const Text('abrir'),
            ),
          ),
        ),
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(admin)),
          ChangeNotifierProvider<UserController>.value(value: users),
        ],
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('user-form-next')));
      await tester.pumpAndSettle();
    }

    testWidgets('valida datos absurdos y no avanza', (WidgetTester tester) async {
      await openDialog(tester);
      await tester.enterText(find.byKey(const ValueKey<String>('user-name')).last, 'Julian');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey<String>('user-doc')), matching: find.byType(TextFormField)), 'abc');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey<String>('user-email')), matching: find.byType(TextFormField)), 'malo@');
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey<String>('user-pass')), matching: find.byType(TextFormField)), 'abcdefgh');
      await next(tester);
      expect(find.text('Escribe nombre y apellido'), findsOneWidget);
      expect(find.text('El documento es obligatorio'), findsOneWidget);
      expect(find.text('Correo no válido'), findsOneWidget);
      expect(find.text('Combina letras y números'), findsOneWidget);
      expect(find.text('Paso 1 de 4 · Datos'), findsOneWidget);
    });

    testWidgets('crea un operario recorriendo los 4 pasos y muestra errores del servidor', (WidgetTester tester) async {
      when(() => service.createUser(
            nombreCompleto: any(named: 'nombreCompleto'),
            documento: any(named: 'documento'),
            correo: any(named: 'correo'),
            telefono: any(named: 'telefono'),
            rol: any(named: 'rol'),
            password: any(named: 'password'),
            activo: any(named: 'activo'),
            actorUid: any(named: 'actorUid'),
            permisos: any(named: 'permisos'),
            productorId: any(named: 'productorId'),
          )).thenThrow(UserServiceException('Ya existe un usuario con el documento 1073500999.'));
      await openDialog(tester);
      Finder field(String k) => find.descendant(of: find.byKey(ValueKey<String>(k)), matching: find.byType(TextFormField));
      await tester.enterText(field('user-name'), 'Carlos Pérez');
      await tester.enterText(field('user-doc'), '1073500999');
      await tester.enterText(field('user-email'), 'carlos@asoproganucot.com');
      await tester.enterText(field('user-pass'), 'Leche2026');
      await tester.enterText(field('user-confirm'), 'Leche2026');
      await tester.pump();
      expect(find.text('Seguridad: Buena'), findsOneWidget);
      await next(tester);
      expect(find.text('Paso 2 de 4 · Rol'), findsOneWidget);

      // Productor sin productor vinculado no avanza.
      await tester.tap(find.byKey(const ValueKey<String>('role-PRODUCTOR')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Selecciona el productor al que pertenece esta cuenta'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('role-OPERARIO')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Paso 3 de 4 · Permisos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('perm-recepcion-editar')));
      await tester.pump();
      await next(tester);
      expect(find.text('Paso 4 de 4 · Revisar'), findsOneWidget);
      expect(find.text('Carlos Pérez'), findsOneWidget);
      await tester.tap(find.text('Crear usuario'));
      await tester.pumpAndSettle();
      // Error del servidor visible en línea y regreso al paso de datos.
      expect(find.byKey(const ValueKey<String>('user-form-error')), findsOneWidget);
      expect(find.text('Ya existe un usuario con el documento 1073500999.'), findsOneWidget);
      expect(find.text('Paso 1 de 4 · Datos'), findsOneWidget);

      final VerificationResult call = verify(() => service.createUser(
            nombreCompleto: 'Carlos Pérez',
            documento: '1073500999',
            correo: 'carlos@asoproganucot.com',
            telefono: '',
            rol: AppConstants.roleOperario,
            password: 'Leche2026',
            activo: true,
            actorUid: admin.uid,
            permisos: captureAny(named: 'permisos'),
            productorId: null,
          ));
      call.called(1);
      final Map<String, List<String>> sent = call.captured.single as Map<String, List<String>>;
      expect(sent[Permissions.recepcion], containsAll(<String>[PermAction.ver, PermAction.editar]));
    });
  });

  testWidgets('Módulo de usuarios: tabla, resumen de permisos y acciones', (WidgetTester tester) async {
    _desktop(tester);
    final _MockUserService service = _MockUserService();
    when(() => service.listUsers()).thenAnswer((_) async => (users: <UserModel>[admin, operario], fromCache: false));
    await tester.pumpWidget(_app(
      const UsersModuleView(),
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(admin)),
        ChangeNotifierProvider<UserController>.value(value: UserController(userService: service)),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo usuario'), findsOneWidget);
    expect(find.text('Luis Pérez'), findsOneWidget);
    expect(find.text('Acceso total'), findsOneWidget);
    final int n = Permissions.countGranted(Permissions.defaultsFor(AppConstants.roleOperario));
    expect(find.text('$n/${Permissions.totalActions}'), findsOneWidget);
    expect(find.text('hace 5 min'), findsOneWidget);
    expect(find.text('Nunca'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('user-menu-u-op')));
    await tester.pumpAndSettle();
    expect(find.text('Permisos'), findsOneWidget);
    expect(find.text('Ver actividad'), findsOneWidget);
    expect(find.text('Suspender cuenta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reportes y actividad de usuarios a 1280×720 sin desbordes', (WidgetTester tester) async {
    _desktop(tester);
    final HiveService hive = HiveService(enablePersistence: false);
    final DateTime now = DateTime.now();
    final ProducerModel p = ProducerModel(
      productorId: 'p-1',
      codigoAsociado: 'ASO-001',
      cedula: '1073500111',
      nombres: 'Pedro',
      apellidos: 'Ruiz',
      telefono: '3101112233',
      nombreFinca: 'El Mirador',
      vereda: 'La Glorieta',
      estado: 'ACTIVO',
      aceptoHabeasData: true,
      fechaCreacion: now,
    );
    final String today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final ReportController reports = ReportController(
      reportService: ReportService(remoteAuditDataSource: _Audit()),
      receptionService: ReceptionService(
        hiveService: hive,
        remoteDataSource: _Receptions(<MilkReceptionModel>[
          MilkReceptionModel(
            recepcionId: 'r1',
            productorId: 'p-1',
            codigoAsociadoSnap: 'ASO-001',
            nombreProductorSnap: 'Pedro Ruiz',
            litros: 99999999999999,
            fechaEntrega: today,
            horaEntrega: '06:00:00',
            jornada: AppConstants.shiftMorning,
            operarioUid: 'u-op',
            createdAt: now,
          ),
        ]),
      ),
      producerService: ProducerService(hiveService: hive, remoteDataSource: _Producers(<ProducerModel>[p])),
      rateService: RateService(hiveService: hive, remoteDataSource: _Rates()),
      settlementService: SettlementService(hiveService: hive, remoteDataSource: _Settlements()),
    );
    reports.setPeriodRange(now, now);
    final _MockUserService service = _MockUserService();
    when(() => service.listUsers()).thenAnswer((_) async => (users: <UserModel>[admin, operario], fromCache: false));
    final InMemoryAuditQueryService audit = InMemoryAuditQueryService(<AuditLogModel>[
      AuditLogModel(
        logId: 'l1',
        entidadAfectada: AppConstants.receptionsCollection,
        registroId: 'r1',
        accion: 'EDITAR',
        valorAnterior: const <String, dynamic>{'litros': 12.5, 'productorId': 'p-1'},
        valorNuevo: const <String, dynamic>{'litros': 14, 'productorId': 'p-1'},
        motivo: 'Error al digitar',
        usuarioUid: 'u-admin',
        timestamp: now.subtract(const Duration(minutes: 10)),
      ),
      AuditLogModel(
        logId: 'l2',
        entidadAfectada: 'usuarios',
        registroId: 'u-op',
        accion: 'INICIAR_SESION',
        usuarioUid: 'u-op',
        timestamp: now.subtract(const Duration(minutes: 20)),
      ),
    ]);
    await tester.pumpWidget(_app(
      const ReportsModuleView(),
      audit: audit,
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(admin)),
        ChangeNotifierProvider<UserController>.value(value: UserController(userService: service)),
        ChangeNotifierProvider<ReportController>.value(value: reports),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Catálogo de reportes'), findsOneWidget);
    expect(find.text('Pedro Ruiz'), findsOneWidget);
    for (final ReportKind k in ReportKind.values) {
      await tester.tap(find.text(k.title).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: k.title);
    }
    await tester.tap(find.text('Actividad de usuarios').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('corrigió los litros de Pedro Ruiz'), findsOneWidget);
    expect(find.textContaining('inició sesión'), findsOneWidget);
    await tester.tap(find.textContaining('corrigió los litros de Pedro Ruiz'));
    await tester.pumpAndSettle();
    expect(find.text('12,5 L'), findsOneWidget);
    expect(find.text('14,0 L'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Comunicados: redactar, previsualizar, enviar y eliminar', (WidgetTester tester) async {
    _desktop(tester, size: const Size(1280, 1100));
    final _Broadcasts backend = _Broadcasts();
    await tester.pumpWidget(_app(
      CommunicationsModuleView(service: BroadcastService(backend: backend)),
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>.value(value: _FakeAuth(admin)),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aún no se han enviado comunicados'), findsOneWidget);
    Finder field(String k) => find.descendant(of: find.byKey(ValueKey<String>(k)), matching: find.byType(TextFormField));
    await tester.enterText(field('broadcast-title'), 'Cambio de horario');
    await tester.enterText(field('broadcast-message'), 'Mañana se recibe desde las 5:30.');
    await tester.pump();
    expect(find.text('17/80 caracteres'), findsOneWidget);
    expect(find.text('32/500 caracteres'), findsOneWidget);
    // La vista previa refleja el texto (notificación + tarjeta dentro de la app).
    expect(find.text('Cambio de horario'), findsNWidgets(3));

    // Texto gigante se corta al límite.
    await tester.enterText(field('broadcast-message'), 'Mensaje largo. ' * 60);
    await tester.pump();
    expect(find.text('500/500 caracteres'), findsOneWidget);
    await tester.enterText(field('broadcast-message'), 'Mañana se recibe desde las 5:30.');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('broadcast-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pumpAndSettle();
    expect(backend.stored.length, 1);
    expect(find.text('Cambio de horario'), findsOneWidget); // historial (formulario limpio)
    await tester.tap(find.byTooltip('Eliminar comunicado'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();
    expect(backend.stored, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
