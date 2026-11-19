import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pgc_asoproganucot/controllers/rectification_inbox_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/security/permissions.dart';
import 'package:pgc_asoproganucot/core/services/rectification_inbox_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/rectifications/rectification_inbox_button.dart';
import 'package:provider/provider.dart';

class _FakeInboxService extends RectificationInboxService {
  final StreamController<List<RectificationRequest>> feed = StreamController<List<RectificationRequest>>.broadcast();
  final List<String> attended = <String>[];
  bool failAttend = false;

  @override
  Stream<List<RectificationRequest>> watch() => feed.stream;

  @override
  Future<void> markAttended(String id, {required String staffUid}) async {
    if (failAttend) throw Exception('sin red');
    attended.add(id);
  }
}

UserModel _user(String rol, {Map<String, List<String>>? permisos, String uid = 'u1'}) => UserModel(
      uid: uid,
      nombreCompleto: 'Usuario $rol',
      documento: '1073500001',
      correo: 'u@asoproganucott.test',
      telefono: '3001234567',
      rol: rol,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: DateTime.utc(2026, 1, 1),
      permisos: permisos,
    );

RectificationRequest _req(String id, {bool atendida = false, int minute = 0}) => RectificationRequest(
      id: id,
      productorId: 'p-$id',
      codigoAsociado: 'ASO-00$id',
      campo: 'Teléfono',
      detalle: 'Mi número correcto es 3110000000',
      fecha: DateTime.utc(2026, 11, 19, 10, minute),
      atendida: atendida,
      nombreProductor: 'Productor $id',
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  group('RectificationRequest.fromMap', () {
    test('interpreta título, mensaje, fecha ISO y estado', () {
      final RectificationRequest r = RectificationRequest.fromMap('n1', <String, dynamic>{
        'titulo': 'Solicitud Habeas Data · ASO-014',
        'mensaje': 'Campo: Vereda · Solicitud: Vivo en la vereda Coquira',
        'destinoProductorId': ' prod-14 ',
        'fechaEnvio': '2026-11-19T15:30:00.000Z',
        'leida': false,
      });
      expect(r.id, 'n1');
      expect(r.codigoAsociado, 'ASO-014');
      expect(r.campo, 'Vereda');
      expect(r.detalle, 'Vivo en la vereda Coquira');
      expect(r.productorId, 'prod-14');
      expect(r.fecha, DateTime.utc(2026, 11, 19, 15, 30));
      expect(r.atendida, isFalse);
      expect(r.withName('Ana Pérez').nombreProductor, 'Ana Pérez');
    });

    test('tolera mensajes sin el formato esperado y datos faltantes', () {
      final RectificationRequest r = RectificationRequest.fromMap('n2', <String, dynamic>{
        'mensaje': 'Texto libre',
        'leida': true,
      });
      expect(r.codigoAsociado, '');
      expect(r.campo, '');
      expect(r.detalle, 'Texto libre');
      expect(r.atendida, isTrue);
      expect(r.fecha, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });
  });

  group('RectificationInboxController', () {
    test('solo administradores y operarios con productores.editar atienden solicitudes', () {
      expect(RectificationInboxController.canAttend(_user(AppConstants.roleAdmin)), isTrue);
      expect(RectificationInboxController.canAttend(_user(AppConstants.roleOperario)), isFalse);
      expect(
        RectificationInboxController.canAttend(_user(AppConstants.roleOperario, permisos: <String, List<String>>{
          Permissions.productores: <String>[PermAction.ver, PermAction.editar],
        })),
        isTrue,
      );
      expect(RectificationInboxController.canAttend(_user(AppConstants.roleProductor)), isFalse);
    });

    test('cuenta pendientes, avisa solo las nuevas y marca como atendida', () async {
      final _FakeInboxService service = _FakeInboxService();
      final RectificationInboxController ctrl = RectificationInboxController(service: service);
      final List<RectificationRequest> arrivals = <RectificationRequest>[];
      final StreamSubscription<RectificationRequest> sub = ctrl.arrivals.listen(arrivals.add);

      ctrl.bind(_user(AppConstants.roleAdmin));
      expect(ctrl.isActive, isTrue);

      service.feed.add(<RectificationRequest>[_req('1'), _req('2', atendida: true)]);
      await pumpEventQueue();
      expect(ctrl.items.length, 2);
      expect(ctrl.pendingCount, 1);
      expect(arrivals, isEmpty, reason: 'la carga inicial no genera avisos');

      service.feed.add(<RectificationRequest>[_req('3', minute: 5), _req('1'), _req('2', atendida: true)]);
      await pumpEventQueue();
      expect(ctrl.pendingCount, 2);
      expect(arrivals.map((RectificationRequest r) => r.id), <String>['3']);

      expect(await ctrl.markAttended(_req('3')), isTrue);
      expect(service.attended, <String>['3']);

      service.failAttend = true;
      expect(await ctrl.markAttended(_req('1')), isFalse);
      expect(ctrl.errorMessage, isNotNull);

      ctrl.unbind();
      expect(ctrl.isActive, isFalse);
      expect(ctrl.items, isEmpty);
      await sub.cancel();
      ctrl.dispose();
    });

    test('no escucha para usuarios sin permiso ni sin Firebase inicializado', () async {
      final _FakeInboxService service = _FakeInboxService();
      final RectificationInboxController withService = RectificationInboxController(service: service);
      withService.bind(_user(AppConstants.roleProductor));
      expect(withService.isActive, isFalse);
      expect(await withService.markAttended(_req('1')), isFalse);

      final RectificationInboxController noFirebase = RectificationInboxController();
      noFirebase.bind(_user(AppConstants.roleAdmin));
      expect(noFirebase.isActive, isFalse);
    });
  });

  group('RectificationInboxButton', () {
    Future<_FakeInboxService> pump(WidgetTester tester, {bool withProvider = true}) async {
      final _FakeInboxService service = _FakeInboxService();
      final Widget button = RectificationInboxButton(user: _user(AppConstants.roleAdmin));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: withProvider
              ? ChangeNotifierProvider<RectificationInboxController>(
                  create: (_) => RectificationInboxController(service: service),
                  child: button,
                )
              : button,
        ),
      ));
      return service;
    }

    testWidgets('sin controlador registrado no muestra nada', (WidgetTester tester) async {
      await pump(tester, withProvider: false);
      expect(find.byKey(const ValueKey<String>('rectificaciones-campana')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('muestra el contador, abre la bandeja y atiende una solicitud', (WidgetTester tester) async {
      final _FakeInboxService service = await pump(tester);
      service.feed.add(<RectificationRequest>[_req('1'), _req('2', atendida: true)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('1'), findsOneWidget);

      // Llega una solicitud nueva: aviso emergente.
      service.feed.add(<RectificationRequest>[_req('3', minute: 9), _req('1'), _req('2', atendida: true)]);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Nueva solicitud de corrección de datos'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('rectificaciones-campana')));
      await tester.pumpAndSettle();
      expect(find.text('Solicitudes de corrección de datos'), findsOneWidget);
      expect(find.text('Productor 3'), findsOneWidget);
      expect(find.text('Productor 2'), findsNothing, reason: 'las atendidas se ocultan por defecto');

      await tester.tap(find.text('Marcar como atendida').first);
      await tester.pumpAndSettle();
      expect(service.attended, <String>['3']);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Productor 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
