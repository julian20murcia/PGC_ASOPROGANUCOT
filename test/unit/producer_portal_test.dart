import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/producer_portal_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/notification_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_pdf_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/mobile/producer_shell_view.dart';
import 'package:provider/provider.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

class _InMemoryProducerRemote implements RemoteProducerDataSource {
  _InMemoryProducerRemote(this.items);
  final List<ProducerModel> items;

  @override
  Future<List<ProducerModel>> fetchProducers() async => items;

  @override
  Future<void> upsertProducer(ProducerModel producer) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemoryReceptionRemote implements RemoteReceptionDataSource {
  _InMemoryReceptionRemote(this.items);
  final List<MilkReceptionModel> items;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async => items;

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    items.removeWhere(
      (MilkReceptionModel r) => r.recepcionId == reception.recepcionId,
    );
    items.add(reception);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemoryRateRemote implements RemoteRateDataSource {
  _InMemoryRateRemote(this.rates);
  final List<MilkRateModel> rates;

  @override
  Future<List<MilkRateModel>> fetchRates() async => rates;

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemorySettlementRemote implements RemoteSettlementDataSource {
  _InMemorySettlementRemote(this.items);
  final List<SettlementModel> items;

  @override
  Future<List<SettlementModel>> fetchSettlements() async => items;

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

class _InMemoryNotificationRemote implements RemoteNotificationDataSource {
  final List<AppNotificationModel> items = <AppNotificationModel>[];
  final List<AuditLogModel> logs = <AuditLogModel>[];

  @override
  Future<List<AppNotificationModel>> fetchNotifications({
    String? productorId,
    String? userUid,
  }) async {
    if (productorId == null && userUid == null) {
      return List<AppNotificationModel>.from(items);
    }
    return items.where((AppNotificationModel n) {
      final String? d = n.destinoProductorId;
      return d == null || d == productorId || d == userUid;
    }).toList();
  }

  @override
  Future<void> upsertNotification(AppNotificationModel notification) async {
    items.removeWhere(
      (AppNotificationModel n) =>
          n.notificacionId == notification.notificacionId,
    );
    items.add(notification);
  }

  @override
  Future<void> markNotificationRead(String notificacionId) async {
    final int idx = items.indexWhere(
      (AppNotificationModel n) => n.notificacionId == notificacionId,
    );
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(leida: true);
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    logs.add(log);
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final UserModel adminUser = UserModel(
    uid: 'uid-admin-1',
    nombreCompleto: 'Admin Susa',
    documento: '1000001',
    correo: 'admin@asoproganucott.com',
    telefono: '3100000001',
    rol: AppConstants.roleAdmin,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: DateTime.utc(2026, 1, 1),
  );

  final UserModel producerUserA = UserModel(
    uid: 'uid-prod-a',
    nombreCompleto: 'Carlos Mendoza',
    documento: '1073500111',
    correo: 'carlos@finca.com',
    telefono: '3112223344',
    rol: AppConstants.roleProductor,
    activo: true,
    fcmTokens: const <String>[],
    fechaCreacion: DateTime.utc(2026, 1, 5),
  );

  final ProducerModel producerA = ProducerModel(
    productorId: 'prod-a',
    uidUsuario: 'uid-prod-a',
    codigoAsociado: 'ASO-001',
    cedula: '1073500111',
    nombres: 'Carlos',
    apellidos: 'Mendoza',
    telefono: '3112223344',
    nombreFinca: 'La Pradera',
    vereda: 'El Tablón',
    estado: 'ACTIVO',
    aceptoHabeasData: true,
    fechaAutorizacionDatos: DateTime.utc(2026, 1, 5),
    autorizadoPorUid: 'uid-admin-1',
    fechaCreacion: DateTime.utc(2026, 1, 5),
  );

  final ProducerModel producerB = ProducerModel(
    productorId: 'prod-b',
    uidUsuario: 'uid-prod-b',
    codigoAsociado: 'ASO-002',
    cedula: '1073500222',
    nombres: 'Lucía',
    apellidos: 'Rojas',
    telefono: '3129998877',
    nombreFinca: 'San Isidro',
    vereda: 'Guatanfur',
    estado: 'ACTIVO',
    aceptoHabeasData: true,
    fechaAutorizacionDatos: DateTime.utc(2026, 1, 6),
    autorizadoPorUid: 'uid-admin-1',
    fechaCreacion: DateTime.utc(2026, 1, 6),
  );

  ProducerPortalController buildController({
    required HiveService hive,
    required List<MilkReceptionModel> receptions,
    required List<SettlementModel> settlements,
    required _InMemoryNotificationRemote notifRemote,
  }) {
    final ProducerService producerService = ProducerService(
      hiveService: hive,
      remoteDataSource: _InMemoryProducerRemote(
        <ProducerModel>[producerA, producerB],
      ),
    );
    final ReceptionService receptionService = ReceptionService(
      hiveService: hive,
      remoteDataSource: _InMemoryReceptionRemote(receptions),
    );
    final RateService rateService = RateService(
      hiveService: hive,
      remoteDataSource: _InMemoryRateRemote(
        <MilkRateModel>[
          MilkRateModel(
            tarifaId: 'rate-1',
            precioPorLitro: 1950,
            fechaInicioVigencia: DateTime.utc(2026, 1, 1),
            observacion: 'Tarifa oficial Susa',
            registradoPorUid: 'uid-admin-1',
            activa: true,
          ),
        ],
      ),
    );
    final SettlementService settlementService = SettlementService(
      hiveService: hive,
      remoteDataSource: _InMemorySettlementRemote(settlements),
    );
    final NotificationService notificationService = NotificationService(
      hiveService: hive,
      remoteDataSource: notifRemote,
    );

    return ProducerPortalController(
      hiveService: hive,
      producerService: producerService,
      receptionService: receptionService,
      rateService: rateService,
      settlementService: settlementService,
      notificationService: notificationService,
      fcmService: FcmService(),
    );
  }

  group('Fase 7 · Portal Móvil del Productor y Alertas Push', () {
    test(
      'Paso 7.1, 7.3, 7.4 y 7.5: Aislamiento estricto por UID, KPIs de Resumen, filtros de entregas y comprobantes PDF',
      () async {
        final HiveService hive = HiveService(enablePersistence: false);
        final _InMemoryNotificationRemote notifRemote =
            _InMemoryNotificationRemote();

        await notifRemote.upsertNotification(
          AppNotificationModel(
            notificacionId: 'n-broadcast',
            titulo: 'Reunión mensual en planta Susa',
            mensaje: 'Sábado 8:00 AM en la sede principal.',
            tipo: 'COMUNICADO',
            destinoProductorId: null,
            fechaEnvio: DateTime.utc(2026, 11, 18, 12),
          ),
        );
        await notifRemote.upsertNotification(
          AppNotificationModel(
            notificacionId: 'n-prod-a',
            titulo: 'Entrega registrada (Mañana)',
            mensaje: '42.5 L recibidos hoy.',
            tipo: 'ENTREGA',
            destinoProductorId: 'prod-a',
            fechaEnvio: DateTime.utc(2026, 11, 18, 11),
          ),
        );
        await notifRemote.upsertNotification(
          AppNotificationModel(
            notificacionId: 'n-prod-b-privado',
            titulo: 'Aviso privado de Lucía',
            mensaje: 'No debe ser visible para Carlos.',
            tipo: 'PAGO',
            destinoProductorId: 'prod-b',
            fechaEnvio: DateTime.utc(2026, 11, 18, 10),
          ),
        );

        final List<MilkReceptionModel> receptions = <MilkReceptionModel>[
          MilkReceptionModel(
            recepcionId: 'r-a-1',
            productorId: 'prod-a',
            codigoAsociadoSnap: 'ASO-001',
            nombreProductorSnap: 'Carlos Mendoza',
            litros: 42.5,
            fechaEntrega: '2026-11-18',
            horaEntrega: '07:15:00',
            jornada: AppConstants.shiftMorning,
            operarioUid: 'op-1',
            syncStatus: AppConstants.syncSynced,
            isSynced: true,
            createdAt: DateTime.utc(2026, 11, 18, 7, 15),
          ),
          MilkReceptionModel(
            recepcionId: 'r-a-2',
            productorId: 'prod-a',
            codigoAsociadoSnap: 'ASO-001',
            nombreProductorSnap: 'Carlos Mendoza',
            litros: 27.5,
            fechaEntrega: '2026-11-17',
            horaEntrega: '16:40:00',
            jornada: AppConstants.shiftAfternoon,
            operarioUid: 'op-1',
            syncStatus: AppConstants.syncSynced,
            isSynced: true,
            createdAt: DateTime.utc(2026, 11, 17, 16, 40),
          ),
          MilkReceptionModel(
            recepcionId: 'r-a-old-month',
            productorId: 'prod-a',
            codigoAsociadoSnap: 'ASO-001',
            nombreProductorSnap: 'Carlos Mendoza',
            litros: 100.0,
            fechaEntrega: '2026-11-05',
            horaEntrega: '07:00:00',
            jornada: AppConstants.shiftMorning,
            operarioUid: 'op-1',
            syncStatus: AppConstants.syncSynced,
            isSynced: true,
            liquidacionId: 'liq-a-1',
            createdAt: DateTime.utc(2026, 11, 5, 7, 0),
          ),
          // Entrega de otro productor B: debe quedar excluida.
          MilkReceptionModel(
            recepcionId: 'r-b-1',
            productorId: 'prod-b',
            codigoAsociadoSnap: 'ASO-002',
            nombreProductorSnap: 'Lucía Rojas',
            litros: 999.0,
            fechaEntrega: '2026-11-18',
            horaEntrega: '07:20:00',
            jornada: AppConstants.shiftMorning,
            operarioUid: 'op-1',
            syncStatus: AppConstants.syncSynced,
            isSynced: true,
            createdAt: DateTime.utc(2026, 11, 18, 7, 20),
          ),
        ];

        final List<SettlementModel> settlements = <SettlementModel>[
          SettlementModel(
            liquidacionId: 'liq-a-1',
            productorId: 'prod-a',
            nombreProductorSnap: 'Carlos Mendoza',
            cedulaProductorSnap: '1073500111',
            periodoInicio: '2026-11-01',
            periodoFin: '2026-11-15',
            quincenaLabel: '1ª quincena · 11/2026',
            totalLitros: 100.0,
            cantidadEntregas: 1,
            precioLitroAplicado: 1950,
            valorTotalPagar: 195000,
            estadoPago: 'PAGADA',
            fechaLiquidacion: DateTime.utc(2026, 11, 15, 18),
            fechaPago: DateTime.utc(2026, 11, 16, 10),
            observacionPago: 'Nequi #4502',
            numeroComprobante: 'LIQ-2026-0001',
            hashIntegridad: 'abc123',
            creadoPorUid: 'uid-admin-1',
          ),
          SettlementModel(
            liquidacionId: 'liq-b-1',
            productorId: 'prod-b',
            nombreProductorSnap: 'Lucía Rojas',
            cedulaProductorSnap: '1073500222',
            periodoInicio: '2026-11-01',
            periodoFin: '2026-11-15',
            quincenaLabel: '1ª quincena · 11/2026',
            totalLitros: 500.0,
            cantidadEntregas: 5,
            precioLitroAplicado: 1950,
            valorTotalPagar: 975000,
            estadoPago: 'PENDIENTE',
            fechaLiquidacion: DateTime.utc(2026, 11, 15, 18),
            numeroComprobante: 'LIQ-2026-0002',
            hashIntegridad: 'def456',
            creadoPorUid: 'uid-admin-1',
          ),
        ];

        final ProducerPortalController ctrl = buildController(
          hive: hive,
          receptions: receptions,
          settlements: settlements,
          notifRemote: notifRemote,
        );

        await ctrl.loadPortalForUser(
          producerUserA,
          referenceDate: DateTime(2026, 11, 18, 12, 0),
        );

        // Aislamiento estricto (Paso 7.1)
        expect(ctrl.activeProducer?.productorId, 'prod-a');
        expect(ctrl.allReceptions.length, 3);
        expect(
          ctrl.allReceptions.any((r) => r.productorId == 'prod-b'),
          isFalse,
        );
        expect(ctrl.settlements.length, 1);
        expect(ctrl.settlements.first.productorId, 'prod-a');
        expect(ctrl.allNotifications.length, 2);
        expect(
          ctrl.allNotifications.any((n) => n.notificacionId == 'n-prod-b-privado'),
          isFalse,
        );

        // Pestaña 1 Resumen (Paso 7.3)
        expect(ctrl.quincenaLiters, 70.0); // 42.5 + 27.5 (Nov 16-30)
        expect(ctrl.quincenaDeliveriesCount, 2);
        expect(ctrl.activePricePerLiter, 1950);
        expect(ctrl.quincenaEstimatedAmount, 136500); // 70 * 1950
        expect(ctrl.monthLiters, 170.0); // 42.5 + 27.5 + 100.0
        expect(ctrl.last7DaysSeries.length, 7);
        expect(ctrl.last7DaysSeries.last.morningLiters, 42.5);

        // Pestaña 2 Mis Entregas filtros (Paso 7.4)
        expect(ctrl.filteredReceptions.length, 2); // Quincena actual
        ctrl.setPeriodFilter('MES');
        expect(ctrl.filteredReceptions.length, 3);
        ctrl.setShiftFilter(AppConstants.shiftAfternoon);
        expect(ctrl.filteredReceptions.length, 1);
        expect(ctrl.filteredTotalLiters, 27.5);
        ctrl.clearDeliveryFilters();
        expect(ctrl.periodFilter, 'QUINCENA');

        // Pestaña 3 Liquidaciones y PDF (Paso 7.5)
        final SettlementModel sA = ctrl.settlements.first;
        final List<MilkReceptionModel> recsForPdf =
            ctrl.receptionsForSettlement(sA);
        expect(recsForPdf.length, 1);
        final Uint8List pdfBytes =
            await SettlementPdfService.buildVoucherPdfBytes(
          settlement: sA,
          receptions: recsForPdf,
          producer: ctrl.activeProducer,
        );
        expect(pdfBytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
      },
    );

    test(
      'Paso 7.2, 7.6 y 7.7: Solicitud Habeas Data Ley 1581, alerta de entrega, parseo FCM, comunicados ADMIN y lectura',
      () async {
        final HiveService hive = HiveService(enablePersistence: false);
        final _InMemoryNotificationRemote notifRemote =
            _InMemoryNotificationRemote();

        final ProducerPortalController ctrl = buildController(
          hive: hive,
          receptions: <MilkReceptionModel>[],
          settlements: <SettlementModel>[],
          notifRemote: notifRemote,
        );
        await ctrl.loadPortalForUser(
          producerUserA,
          referenceDate: DateTime(2026, 11, 18, 9),
        );

        // Paso 7.2: Solicitud de rectificación Ley 1581 de 2012
        final bool rectOk = await ctrl.submitRectificationRequest(
          actor: producerUserA,
          campo: 'Teléfono de contacto',
          detalle: 'Actualizar celular a 3205559988',
        );
        expect(rectOk, isTrue);
        expect(notifRemote.logs.length, 1);
        expect(notifRemote.logs.first.accion, 'SOLICITAR_RECTIFICACION');
        expect(
          ctrl.allNotifications.any((n) => n.tipo == 'RECTIFICACION'),
          isTrue,
        );

        // Paso 7.7: Comunicado institucional masivo requiere rol ADMIN
        final bool rejectedNonAdmin = await ctrl.sendBroadcast(
          actor: producerUserA,
          titulo: 'Intento no autorizado',
          mensaje: 'Un productor no puede enviar comunicados masivos.',
        );
        expect(rejectedNonAdmin, isFalse);

        final bool sentAdmin = await ctrl.sendBroadcast(
          actor: adminUser,
          titulo: 'Jornada de calidad higiénica',
          mensaje: 'Recordamos limpieza de cantinas antes del acopio.',
        );
        expect(sentAdmin, isTrue);
        expect(ctrl.unreadNotificationsCount, 2);

        // Marcado de lectura individual y masiva
        await ctrl.markNotificationRead(ctrl.allNotifications.first.notificacionId);
        expect(ctrl.unreadNotificationsCount, 1);
        await ctrl.markAllRead();
        expect(ctrl.unreadNotificationsCount, 0);

        // Paso 7.6: Registro de entrega genera alerta automática ENTREGA en Hive
        final ReceptionService recService = ReceptionService(
          hiveService: hive,
          remoteDataSource: _InMemoryReceptionRemote(<MilkReceptionModel>[]),
        );
        await recService.registerReception(
          producer: producerA,
          litros: 19.5,
          jornada: AppConstants.shiftMorning,
          operarioUid: 'op-1',
          isOnline: false,
        );
        final List<AppNotificationModel> hiveNotifs =
            await hive.getCachedNotifications();
        expect(
          hiveNotifs.any(
            (AppNotificationModel n) =>
                n.tipo == 'ENTREGA' && n.destinoProductorId == 'prod-a',
          ),
          isTrue,
        );

        // Paso 7.6: Parseo FCM de eventos en primer plano (PAGO, ENTREGA y CIERRE_QUINCENA)
        final AppNotificationModel? parsedFcm =
            FcmService.parseRemoteMessageData(
          <String, dynamic>{
            'notificacionId': 'fcm-1',
            'tipo': 'PAGO',
            'destinoProductorId': 'prod-a',
          },
          title: 'Pago efectuado',
          body: 'Transferencia por \$ 195.000 confirmada.',
        );
        expect(parsedFcm, isNotNull);
        expect(parsedFcm!.tipo, 'PAGO');

        final AppNotificationModel? parsedEntrega =
            FcmService.parseRemoteMessageData(
          <String, dynamic>{
            'notificacionId': 'notif_entrega_rec-1',
            'tipo': 'ENTREGA',
            'destinoProductorId': 'prod-a',
            'titulo': 'Entrega registrada (Mañana)',
            'mensaje': 'Se registraron 24.5 L de leche cruda el 2026-11-18.',
            'refrescarAvisos': 'true',
          },
        );
        expect(parsedEntrega, isNotNull);
        expect(parsedEntrega!.tipo, 'ENTREGA');
        expect(parsedEntrega.titulo, 'Entrega registrada (Mañana)');
        expect(parsedEntrega.mensaje, contains('24.5 L'));

        final AppNotificationModel? parsedCierre =
            FcmService.parseRemoteMessageData(
          <String, dynamic>{
            'notificacionId': 'notif_cierre_liq-1',
            'tipo': 'CIERRE_QUINCENA',
            'destinoProductorId': 'prod-a',
            'refrescarAvisos': 'true',
          },
          title: 'Cierre de 2ª quincena · 11/2026',
          body:
              'Se cerró tu quincena: 310.0 L (14 entregas) por \$620.000 COP. Comprobante COMP-2026-0001.',
        );
        expect(parsedCierre, isNotNull);
        expect(parsedCierre!.tipo, 'CIERRE_QUINCENA');
        expect(parsedCierre.mensaje, contains('310.0 L'));
      },
    );

    testWidgets(
      'Portal móvil ProducerShellView navega por las 3 pestañas, perfil Habeas Data y sin desbordamientos en campo',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final HiveService hive = HiveService(enablePersistence: false);
        final _InMemoryNotificationRemote notifRemote =
            _InMemoryNotificationRemote();
        await notifRemote.upsertNotification(
          AppNotificationModel(
            notificacionId: 'n-msg-1',
            titulo: 'Aviso de asamblea',
            mensaje: 'Reunión general el viernes en Susa.',
            tipo: 'COMUNICADO',
            destinoProductorId: null,
            fechaEnvio: DateTime.utc(2026, 11, 18, 8),
          ),
        );

        final _MockUserService mockUserService = _MockUserService();
        final _MockFcmService mockFcm = _MockFcmService();
        when(() => mockUserService.currentFirebaseUser).thenReturn(null);
        when(() => mockUserService.signInWithIdentifier(
              identifier: 'carlos@finca.com',
              password: 'Password123',
            )).thenAnswer((_) async => producerUserA);
        when(() => mockFcm.fetchDeviceTokenIfSupported())
            .thenAnswer((_) async => null);
        when(() => mockFcm.onTokenRefresh)
            .thenAnswer((_) => const Stream<String>.empty());

        final AuthController authController = AuthController(
          userService: mockUserService,
          hiveService: hive,
          fcmService: mockFcm,
        );
        await authController.initialize();
        await authController.signIn(
          identifier: 'carlos@finca.com',
          password: 'Password123',
          rememberMe: true,
        );

        final ProducerPortalController portalCtrl = buildController(
          hive: hive,
          receptions: <MilkReceptionModel>[
            MilkReceptionModel(
              recepcionId: 'r-ui-1',
              productorId: 'prod-a',
              codigoAsociadoSnap: 'ASO-001',
              nombreProductorSnap: 'Carlos Mendoza',
              litros: 33.5,
              fechaEntrega: ReceptionService.formatDate(DateTime.now()),
              horaEntrega: '07:10:00',
              jornada: AppConstants.shiftMorning,
              operarioUid: 'op-1',
              syncStatus: AppConstants.syncSynced,
              isSynced: true,
              createdAt: DateTime.now().toUtc(),
            ),
          ],
          settlements: <SettlementModel>[
            SettlementModel(
              liquidacionId: 'liq-ui-1',
              productorId: 'prod-a',
              nombreProductorSnap: 'Carlos Mendoza',
              cedulaProductorSnap: '1073500111',
              periodoInicio: '2026-11-01',
              periodoFin: '2026-11-15',
              quincenaLabel: '1ª quincena · 11/2026',
              totalLitros: 120.0,
              cantidadEntregas: 4,
              precioLitroAplicado: 1950,
              valorTotalPagar: 234000,
              estadoPago: 'PAGADA',
              fechaLiquidacion: DateTime.utc(2026, 11, 15, 18),
              fechaPago: DateTime.utc(2026, 11, 16, 10),
              numeroComprobante: 'LIQ-2026-0009',
              hashIntegridad: 'xyz',
              creadoPorUid: 'uid-admin-1',
            ),
          ],
          notifRemote: notifRemote,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: <ChangeNotifierProvider<dynamic>>[
              ChangeNotifierProvider<AuthController>.value(
                value: authController,
              ),
              ChangeNotifierProvider<ProducerPortalController>.value(
                value: portalCtrl,
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme(),
              home: const ProducerShellView(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Pestaña 1: Resumen
        expect(find.text('Acopio Quincenal'), findsOneWidget);
        expect(find.text('ASO-001'), findsOneWidget);

        // Pestaña 2: Mis Entregas (solo lectura)
        await tester.tap(find.text('Mis Entregas'));
        await tester.pump();
        expect(find.text('1 entrega(s) en filtro'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        // Pestaña 3: Liquidaciones y Avisos
        await tester.tap(find.text('Liquidaciones'));
        await tester.pump();
        expect(find.text('Comprobante LIQ-2026-0009'), findsOneWidget);
        expect(find.text('Ver PDF'), findsOneWidget);

        await tester.tap(find.text('Avisos (1)'));
        await tester.pump();
        expect(find.text('Aviso de asamblea'), findsOneWidget);

        // Abrir Perfil + Ley 1581 de 2012
        await tester.tap(find.byTooltip('Mi perfil y Habeas Data'));
        await tester.pumpAndSettle();
        expect(find.text('Mi Perfil de Asociado'), findsOneWidget);
        expect(
          find.text('Solicitar rectificación de datos (Ley 1581)'),
          findsOneWidget,
        );
      },
    );
  });
}
