import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/activity_presenter.dart';
import 'package:pgc_asoproganucot/core/services/broadcast_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';

class _FakeBackend implements BroadcastBackend {
  final List<AppNotificationModel> stored = <AppNotificationModel>[];
  final List<AuditLogModel> logs = <AuditLogModel>[];
  bool fail = false;

  @override
  Future<List<AppNotificationModel>> fetchBroadcasts() async {
    if (fail) throw Exception('offline');
    return List<AppNotificationModel>.from(stored);
  }

  @override
  Future<void> commitSend(AppNotificationModel notification, AuditLogModel log) async {
    if (fail) throw Exception('offline');
    stored.add(notification);
    logs.add(log);
  }

  @override
  Future<void> commitDelete(AppNotificationModel notification, AuditLogModel log) async {
    if (fail) throw Exception('offline');
    stored.removeWhere((AppNotificationModel n) => n.notificacionId == notification.notificacionId);
    logs.add(log);
  }
}

UserModel _user(String rol, {Map<String, List<String>>? permisos}) => UserModel(
      uid: 'u-$rol',
      nombreCompleto: 'Ana Gómez',
      documento: '1073500100',
      correo: 'ana@asoproganucot.com',
      telefono: '',
      rol: rol,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: DateTime.utc(2026),
      permisos: permisos,
    );

void main() {
  late _FakeBackend backend;
  late BroadcastService service;
  final UserModel admin = _user(AppConstants.roleAdmin);

  setUp(() {
    backend = _FakeBackend();
    service = BroadcastService(backend: backend);
  });

  test('envía comunicado general con el mismo formato y su auditoría', () async {
    final AppNotificationModel n = await service.send(
      actor: admin,
      titulo: '  Cambio   de horario ',
      mensaje: 'Mañana la recepción abre a las 5:30 a. m.',
    );
    expect(n.tipo, 'COMUNICADO');
    expect(n.titulo, 'Cambio de horario');
    expect(n.destinoProductorId, isNull);
    expect(n.leida, isFalse);
    expect(n.toMap().keys, containsAll(<String>['notificacionId', 'titulo', 'mensaje', 'tipo', 'destinoProductorId', 'fechaEnvio', 'leida']));
    final AuditLogModel log = backend.logs.single;
    expect(log.entidadAfectada, AppConstants.notificationsCollection);
    expect(log.accion, 'CREAR');
    expect(log.registroId, n.notificacionId);
    expect(log.usuarioUid, admin.uid);
    expect(log.valorNuevo!['destinoProductorId'], 'GENERAL');
    expect(ActivityPresenter().present(log).description, 'envió el comunicado "Cambio de horario" a todos los productores');
  });

  test('envía a un productor específico', () async {
    final AppNotificationModel n = await service.send(
      actor: admin,
      titulo: 'Pago disponible',
      mensaje: 'Tu pago de la quincena ya está listo.',
      destinoProductorId: 'p-1',
      destinoNombre: 'Pedro Ruiz',
    );
    expect(n.destinoProductorId, 'p-1');
    expect(backend.logs.single.valorNuevo!['destinoNombre'], 'Pedro Ruiz');
  });

  test('valida título y mensaje (vacíos, cortos, largos y repetidos)', () async {
    expect(BroadcastRules.validateTitle(''), isNotNull);
    expect(BroadcastRules.validateTitle('ab'), isNotNull);
    expect(BroadcastRules.validateTitle('A' * 81), isNotNull);
    expect(BroadcastRules.validateTitle('Holaaaaaaa'), isNotNull);
    expect(BroadcastRules.validateTitle('Aviso importante'), isNull);
    expect(BroadcastRules.validateMessage('hola'), isNotNull);
    expect(BroadcastRules.validateMessage('x' * 501), isNotNull);
    expect(BroadcastRules.validateMessage('Mensaje claro para todos.'), isNull);
    await expectLater(
      service.send(actor: admin, titulo: 'ok', mensaje: 'Mensaje válido aquí'),
      throwsA(isA<BroadcastException>()),
    );
    await expectLater(
      service.send(actor: admin, titulo: 'Título válido', mensaje: 'x' * 600),
      throwsA(isA<BroadcastException>()),
    );
    expect(backend.stored, isEmpty);
  });

  test('respeta permisos de comunicados', () async {
    final UserModel viewer = _user(AppConstants.roleOperario,
        permisos: const <String, List<String>>{'comunicados': <String>['ver']});
    await expectLater(
      service.send(actor: viewer, titulo: 'Aviso importante', mensaje: 'Mensaje válido aquí'),
      throwsA(isA<BroadcastException>()),
    );
    final AppNotificationModel n =
        await service.send(actor: admin, titulo: 'Aviso importante', mensaje: 'Mensaje válido aquí');
    await expectLater(service.delete(actor: viewer, notification: n), throwsA(isA<BroadcastException>()));
    expect(backend.stored.length, 1);
  });

  test('elimina y deja registro ELIMINAR legible', () async {
    final AppNotificationModel n =
        await service.send(actor: admin, titulo: 'Aviso importante', mensaje: 'Mensaje válido aquí');
    await service.delete(actor: admin, notification: n);
    expect(backend.stored, isEmpty);
    final AuditLogModel log = backend.logs.last;
    expect(log.accion, 'ELIMINAR');
    expect(log.valorAnterior!['titulo'], 'Aviso importante');
    expect(ActivityPresenter().present(log).kind, ActivityKind.delete);
  });

  test('historial ordenado y errores de red con mensaje claro', () async {
    backend.stored.addAll(<AppNotificationModel>[
      AppNotificationModel(notificacionId: 'a', titulo: 'Viejo', mensaje: 'm', tipo: 'COMUNICADO', fechaEnvio: DateTime.utc(2026, 1, 1)),
      AppNotificationModel(notificacionId: 'b', titulo: 'Nuevo', mensaje: 'm', tipo: 'COMUNICADO', fechaEnvio: DateTime.utc(2026, 11, 1)),
    ]);
    final List<AppNotificationModel> list = await service.listSent();
    expect(list.first.titulo, 'Nuevo');
    backend.fail = true;
    await expectLater(service.listSent(), throwsA(isA<BroadcastException>()));
    await expectLater(
      service.send(actor: admin, titulo: 'Aviso importante', mensaje: 'Mensaje válido aquí'),
      throwsA(predicate((Object e) => e is BroadcastException && e.message.contains('conexión'))),
    );
  });
}
