import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/activity_presenter.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';

void main() {
  final DateTime t = DateTime.utc(2026, 11, 3, 13, 30);

  AuditLogModel log({
    String id = 'l1',
    required String entity,
    required String action,
    String registroId = 'r1',
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? motivo,
    String uid = 'u-ana',
  }) =>
      AuditLogModel(
        logId: id,
        entidadAfectada: entity,
        registroId: registroId,
        accion: action,
        valorAnterior: before,
        valorNuevo: after,
        motivo: motivo,
        usuarioUid: uid,
        timestamp: t,
      );

  final ActivityDirectory dir = ActivityDirectory(
    userNames: <String, String>{'u-ana': 'Ana Gómez', 'u-op': 'Luis Operario'},
    producerNames: <String, String>{'p-1': 'Pedro Ruiz'},
  );
  final ActivityPresenter presenter = ActivityPresenter(dir);

  group('ActivityPresenter · frases por tipo', () {
    test('inicio de sesión', () {
      final ActivityEntry e = presenter.present(log(entity: 'usuarios', action: 'INICIAR_SESION'));
      expect(e.sentence, 'Ana Gómez inició sesión en la plataforma');
      expect(e.kind, ActivityKind.login);
      expect(e.module, ActivityModule.sesion);
    });

    test('corrección de litros con productor, jornada, fecha y motivo', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'productorId': 'p-1',
        'nombreProductorSnap': 'Pedro R.',
        'jornada': 'MANANA',
        'fechaEntrega': '2026-11-03',
        'litros': 12.5,
        'auditLogId': 'old',
        'updatedByUid': 'x',
      };
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.receptionsCollection,
        action: 'EDITAR',
        before: base,
        after: <String, dynamic>{...base, 'litros': 14, 'auditLogId': 'new', 'updatedByUid': 'u-ana'},
        motivo: 'Error al digitar',
      ));
      expect(
        e.sentence,
        'Ana Gómez corrigió los litros de Pedro Ruiz (mañana, 03/11/2026) de 12,5 L a 14,0 L — motivo: Error al digitar',
      );
      expect(e.kind, ActivityKind.correction);
      // Solo el campo que cambió, sin campos técnicos.
      expect(e.changes.length, 1);
      expect(e.changes.single.label, 'Litros');
      expect(e.changes.single.before, '12,5 L');
      expect(e.changes.single.after, '14,0 L');
    });

    test('corrección resuelve productor desde las entregas cargadas', () {
      final ActivityPresenter p = ActivityPresenter(ActivityDirectory(
        userNames: dir.userNames,
        producerNames: dir.producerNames,
        receptions: <String, MilkReceptionModel>{
          'r9': MilkReceptionModel(
            recepcionId: 'r9',
            productorId: 'p-1',
            codigoAsociadoSnap: 'A1',
            nombreProductorSnap: 'Pedro Ruiz',
            litros: 20,
            fechaEntrega: '2026-11-02',
            horaEntrega: '16:00:00',
            jornada: 'TARDE',
            operarioUid: 'u-op',
            createdAt: t,
          ),
        },
      ));
      final ActivityEntry e = p.present(log(
        entity: AppConstants.receptionsCollection,
        action: 'EDITAR',
        registroId: 'r9',
        before: <String, dynamic>{'litros': 20},
        after: <String, dynamic>{'litros': 18},
        motivo: 'Cantina mal medida',
      ));
      expect(e.description, 'corrigió los litros de Pedro Ruiz (tarde, 02/11/2026) de 20,0 L a 18,0 L');
    });

    test('anulación de entrega', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.receptionsCollection,
        action: 'ANULAR',
        before: <String, dynamic>{'productorId': 'p-1', 'litros': 30, 'jornada': 'TARDE', 'fechaEntrega': '2026-11-01', 'anulado': false},
        after: <String, dynamic>{'productorId': 'p-1', 'litros': 30, 'jornada': 'TARDE', 'fechaEntrega': '2026-11-01', 'anulado': true},
        motivo: 'Duplicada',
      ));
      expect(e.description, 'anuló la entrega de 30,0 L de Pedro Ruiz (tarde, 01/11/2026)');
      expect(e.kind, ActivityKind.annul);
      expect(e.changes.single.label, 'Anulada');
    });

    test('registro de entrega', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.receptionsCollection,
        action: 'CREAR',
        uid: 'u-op',
        after: <String, dynamic>{'productorId': 'p-1', 'litros': 22.25, 'jornada': 'MANANA', 'fechaEntrega': '2026-11-03'},
      ));
      expect(e.sentence, 'Luis Operario registró la entrega de Pedro Ruiz (mañana, 03/11/2026): 22,25 L');
    });

    test('creación de productor', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.producersCollection,
        action: 'CREAR',
        registroId: 'p-7',
        after: <String, dynamic>{'nombres': 'Marta', 'apellidos': 'Díaz', 'codigoAsociado': 'ASO-007', 'vereda': 'Centro'},
      ));
      expect(e.sentence, 'Ana Gómez creó el productor Marta Díaz (ASO-007)');
      expect(e.kind, ActivityKind.create);
    });

    test('inactivar productor', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.producersCollection,
        action: 'EDITAR',
        registroId: 'p-1',
        before: <String, dynamic>{'estado': 'ACTIVO'},
        after: <String, dynamic>{'estado': 'INACTIVO'},
      ));
      expect(e.description, 'inactivó al productor Pedro Ruiz');
    });

    test('cierre de quincena por productor con comprobante y entregas agrupadas', () {
      final AuditLogModel receipt = log(
        id: 'liquidacion_L1',
        entity: AppConstants.settlementsCollection,
        action: 'LIQUIDAR',
        registroId: 'L1',
        after: <String, dynamic>{
          'liquidacionId': 'L1',
          'productorId': 'p-1',
          'nombreProductorSnap': 'Pedro Ruiz',
          'periodoInicio': '2026-11-01',
          'periodoFin': '2026-11-15',
          'numeroComprobante': 'COMP-2026-0012',
        },
        motivo: '1ra Quincena Nov 2026',
      );
      final AuditLogModel r1 = log(
        id: 'cierre_L1_r1',
        entity: AppConstants.receptionsCollection,
        action: 'LIQUIDAR',
        registroId: 'r1',
        before: <String, dynamic>{'productorId': 'p-1', 'fechaEntrega': '2026-11-02'},
        after: <String, dynamic>{'productorId': 'p-1', 'fechaEntrega': '2026-11-02', 'liquidacionId': 'L1'},
        motivo: 'COMP-2026-0012',
      );
      final AuditLogModel r2 = log(
        id: 'cierre_L1_r2',
        entity: AppConstants.receptionsCollection,
        action: 'LIQUIDAR',
        registroId: 'r2',
        before: <String, dynamic>{'productorId': 'p-1', 'fechaEntrega': '2026-11-03'},
        after: <String, dynamic>{'productorId': 'p-1', 'fechaEntrega': '2026-11-03', 'liquidacionId': 'L1'},
        motivo: 'COMP-2026-0012',
      );
      final ActivityEntry e = presenter.present(receipt);
      expect(e.sentence, 'Ana Gómez cerró la quincena 1–15 nov 2026 de Pedro Ruiz (comprobante COMP-2026-0012)');
      final List<ActivityEntry> grouped = ActivityPresenter.group(presenter.presentAll(<AuditLogModel>[r1, receipt, r2]));
      expect(grouped.length, 1);
      expect(grouped.single.log.logId, 'liquidacion_L1');
      expect(grouped.single.related.length, 2);
    });

    test('pago registrado', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.settlementsCollection,
        action: 'EDITAR',
        before: <String, dynamic>{'estadoPago': 'PENDIENTE', 'numeroComprobante': 'COMP-2026-0012', 'productorId': 'p-1'},
        after: <String, dynamic>{'estadoPago': 'PAGADA', 'fechaPago': '2026-11-04T10:00:00Z', 'observacionPago': 'Transferencia'},
        motivo: 'Transferencia',
      ));
      expect(e.description, 'registró el pago de Pedro Ruiz (comprobante COMP-2026-0012)');
      expect(e.kind, ActivityKind.payment);
      expect(e.changes.any((ActivityChange c) => c.label == 'Estado de pago' && c.after == 'Pagada'), isTrue);
    });

    test('tarifa publicada', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.ratesCollection,
        action: 'CREAR',
        before: <String, dynamic>{'precioPorLitro': 1800},
        after: <String, dynamic>{'precioPorLitro': 1850, 'fechaInicioVigencia': '01/11/2026', 'actorNombre': 'Ana Gómez'},
      ));
      expect(e.description, r'publicó la tarifa $ 1.850/L vigente desde 01/11/2026 (antes $ 1.800/L)');
      expect(e.kind, ActivityKind.rate);
    });

    test('comunicado general y dirigido', () {
      final ActivityEntry g = presenter.present(log(
        entity: AppConstants.notificationsCollection,
        action: 'CREAR',
        after: <String, dynamic>{'titulo': 'Cambio de horario', 'destinoProductorId': 'GENERAL'},
      ));
      expect(g.description, 'envió el comunicado "Cambio de horario" a todos los productores');
      final ActivityEntry d = presenter.present(log(
        entity: AppConstants.notificationsCollection,
        action: 'CREAR',
        after: <String, dynamic>{'titulo': 'Pago listo', 'destinoProductorId': 'p-1'},
      ));
      expect(d.description, 'envió el comunicado "Pago listo" a Pedro Ruiz');
      final ActivityEntry del = presenter.present(log(
        entity: AppConstants.notificationsCollection,
        action: 'ELIMINAR',
        before: <String, dynamic>{'titulo': 'Pago listo', 'destinoProductorId': 'p-1'},
      ));
      expect(del.kind, ActivityKind.delete);
      expect(del.description, contains('eliminó el comunicado "Pago listo"'));
    });

    test('usuarios: crear, permisos, rol, suspensión y contraseña', () {
      final ActivityEntry created = presenter.present(log(
        entity: 'usuarios',
        action: 'CREAR',
        registroId: 'u-new',
        after: <String, dynamic>{'nombreCompleto': 'Carlos Pérez', 'rol': 'OPERARIO'},
      ));
      expect(created.sentence, 'Ana Gómez creó el usuario Carlos Pérez (Operario)');

      final ActivityEntry perms = presenter.present(log(
        entity: 'usuarios',
        action: 'EDITAR',
        registroId: 'u-op',
        before: <String, dynamic>{'nombreCompleto': 'Luis Operario', 'rol': 'OPERARIO', 'permisos': <String, dynamic>{'recepcion': <String>['ver']}},
        after: <String, dynamic>{
          'nombreCompleto': 'Luis Operario',
          'rol': 'OPERARIO',
          'permisos': <String, dynamic>{'recepcion': <String>['ver', 'editar']},
        },
        motivo: 'Cambio de permisos',
      ));
      expect(perms.description, 'cambió los permisos de Luis Operario');
      expect(perms.kind, ActivityKind.permissions);
      expect(perms.motivo, isNull);
      expect(
        ActivityPresenter.permissionDelta(perms.log.valorAnterior!['permisos'], perms.log.valorNuevo!['permisos']),
        <String>['+ Recepción de leche: Editar'],
      );

      final ActivityEntry role = presenter.present(log(
        entity: 'usuarios',
        action: 'EDITAR',
        registroId: 'u-op',
        before: <String, dynamic>{'rol': 'OPERARIO', 'activo': true},
        after: <String, dynamic>{'rol': 'ADMIN', 'activo': true},
      ));
      expect(role.description, 'cambió el rol de Luis Operario de Operario a Administrador');

      final ActivityEntry suspended = presenter.present(log(
        entity: 'usuarios',
        action: 'EDITAR',
        registroId: 'u-op',
        before: <String, dynamic>{'activo': true},
        after: <String, dynamic>{'activo': false},
        motivo: 'Cuenta suspendida',
      ));
      expect(suspended.description, 'suspendió la cuenta de Luis Operario');
      expect(suspended.kind, ActivityKind.account);

      final ActivityEntry pass = presenter.present(log(
        entity: 'usuarios',
        action: 'EDITAR',
        registroId: 'u-op',
        before: <String, dynamic>{'activo': true},
        after: <String, dynamic>{'activo': true},
        motivo: 'Cambio de contraseña',
      ));
      expect(pass.description, 'cambió la contraseña de Luis Operario');
    });

    test('solicitud de rectificación', () {
      final ActivityEntry e = presenter.present(log(
        entity: AppConstants.producersCollection,
        action: 'SOLICITAR_RECTIFICACION',
        registroId: 'p-1',
        after: <String, dynamic>{'campo': 'Teléfono', 'detalle': 'Número nuevo'},
      ));
      expect(e.description, 'solicitó rectificar "Teléfono" en los datos de Pedro Ruiz');
      expect(e.motivo, 'Número nuevo');
    });

    test('usa el nombre guardado en la bitácora si el usuario no está en el directorio', () {
      final ActivityEntry e = ActivityPresenter().present(log(
        entity: AppConstants.ratesCollection,
        action: 'CREAR',
        uid: 'zzzzzzzzzz',
        after: <String, dynamic>{'precioPorLitro': 1900, 'actorNombre': 'Beatriz León'},
      ));
      expect(e.actorName, 'Beatriz León');
      final ActivityEntry unknown = ActivityPresenter().present(log(entity: 'usuarios', action: 'INICIAR_SESION', uid: 'abcdef123456'));
      expect(unknown.actorName, 'Usuario abcdef…');
    });
  });

  group('ActivityPresenter · registros malformados no rompen', () {
    test('mapas vacíos, tipos extraños y acciones desconocidas', () {
      final List<AuditLogModel> weird = <AuditLogModel>[
        log(entity: '', action: '', uid: ''),
        log(entity: 'coleccion_rara', action: 'HACER_ALGO'),
        log(entity: AppConstants.receptionsCollection, action: 'EDITAR', before: <String, dynamic>{'litros': 'abc'}, after: <String, dynamic>{'litros': <int>[1]}),
        log(entity: AppConstants.settlementsCollection, action: 'LIQUIDAR', after: <String, dynamic>{'periodoInicio': 'no-fecha', 'periodoFin': 3}),
        log(entity: 'usuarios', action: 'EDITAR', before: <String, dynamic>{'permisos': 'texto'}, after: <String, dynamic>{'permisos': 42}),
        log(entity: AppConstants.ratesCollection, action: 'CREAR', after: <String, dynamic>{'precioPorLitro': null}),
        log(entity: AppConstants.notificationsCollection, action: 'CREAR'),
        log(entity: AppConstants.producersCollection, action: 'EDITAR', before: <String, dynamic>{'x': <String, dynamic>{'a': 1}}, after: <String, dynamic>{'x': <String, dynamic>{'a': 2}}),
      ];
      for (final AuditLogModel l in weird) {
        final ActivityEntry e = presenter.present(l);
        expect(e.sentence, isNotEmpty);
        expect(e.title, isNotEmpty);
      }
      expect(presenter.present(weird[0]).actorName, 'Usuario desconocido');
      expect(presenter.present(weird[1]).kind, ActivityKind.other);
    });

    test('fromMap tolera timestamp como texto ISO, número o ausente', () {
      final AuditLogModel iso = AuditLogModel.fromMap(<String, dynamic>{
        'entidadAfectada': 'usuarios',
        'accion': 'iniciar_sesion',
        'usuarioUid': 'u-ana',
        'timestamp': '2026-11-03T13:30:00.000Z',
      }, documentId: 'd1');
      expect(iso.timestamp, DateTime.utc(2026, 11, 3, 13, 30));
      expect(presenter.present(iso).kind, ActivityKind.login);
      final AuditLogModel ms = AuditLogModel.fromMap(<String, dynamic>{'timestamp': 1700000000000, 'valorNuevo': 'no-mapa'});
      expect(ms.valorNuevo, isNull);
      expect(presenter.present(ms).sentence, isNotEmpty);
    });

    test('diff ignora campos técnicos y los que no cambiaron', () {
      final List<ActivityChange> d = presenter.diff(
        <String, dynamic>{'litros': 10, 'updatedAt': 'a', 'auditLogId': '1', 'jornada': 'MANANA'},
        <String, dynamic>{'litros': 10.0, 'updatedAt': 'b', 'auditLogId': '2', 'jornada': 'TARDE'},
      );
      expect(d.length, 1);
      expect(d.single.toString(), 'Jornada: Mañana → Tarde');
    });
  });
}
