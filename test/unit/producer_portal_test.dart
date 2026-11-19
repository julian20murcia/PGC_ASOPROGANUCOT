import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/controllers/producer_portal_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_pdf_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/portal_fakes.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Fase 7 · Portal Móvil del Productor y Alertas Push', () {
    test(
      'Paso 7.1, 7.3, 7.4 y 7.5: Aislamiento estricto por UID, KPIs de Resumen, filtros de entregas y comprobantes PDF',
      () async {
        final HiveService hive = HiveService(enablePersistence: false);
        final InMemoryNotificationRemote notifRemote = InMemoryNotificationRemote();
        await notifRemote.upsertNotification(
          notice('n-broadcast', titulo: 'Reunión mensual en planta Susa', at: DateTime.utc(2026, 11, 18, 12)),
        );
        await notifRemote.upsertNotification(
          notice('n-prod-a', dest: 'prod-a', tipo: 'ENTREGA', at: DateTime.utc(2026, 11, 18, 11)),
        );
        await notifRemote.upsertNotification(
          notice('n-prod-b-privado', dest: 'prod-b', tipo: 'PAGO', at: DateTime.utc(2026, 11, 18, 10)),
        );

        final List<MilkReceptionModel> receptions = <MilkReceptionModel>[
          reception('r-a-1', '2026-11-18', 42.5),
          reception('r-a-2', '2026-11-17', 27.5, jornada: AppConstants.shiftAfternoon, hora: '16:40:00'),
          reception('r-a-old-month', '2026-11-05', 100, hora: '07:00:00', liquidacionId: 'liq-a-1'),
          reception('r-a-null', '2026-11-17', 10, anulado: true),
          reception('r-b-1', '2026-11-18', 999, productorId: 'prod-b'),
        ];
        final List<SettlementModel> settlements = <SettlementModel>[
          settlement(),
          settlement(id: 'liq-b-1', productorId: 'prod-b', litros: 500, valor: 975000, pagada: false, comprobante: 'LIQ-2026-0002'),
        ];

        final ProducerPortalController ctrl = buildPortalController(
          hive: hive,
          receptions: receptions,
          settlements: settlements,
          notifRemote: notifRemote,
        );
        await ctrl.loadPortalForUser(producerUserA, referenceDate: DateTime(2026, 11, 18, 12));

        // Aislamiento estricto (Paso 7.1)
        expect(ctrl.activeProducer?.productorId, 'prod-a');
        expect(ctrl.allReceptions.length, 3);
        expect(ctrl.allReceptions.any((MilkReceptionModel r) => r.productorId == 'prod-b'), isFalse);
        expect(ctrl.settlements.length, 1);
        expect(ctrl.allNotifications.length, 2);
        expect(ctrl.allNotifications.any((AppNotificationModel n) => n.notificacionId == 'n-prod-b-privado'), isFalse);
        expect(ctrl.hasLoaded, isTrue);

        // Inicio (Paso 7.3)
        expect(ctrl.quincenaLiters, 70.0);
        expect(ctrl.quincenaDeliveriesCount, 2);
        expect(ctrl.quincenaEstimatedAmount, 136500);
        expect(ctrl.monthLiters, 170.0);
        expect(ctrl.last7DaysSeries.length, 7);
        expect(ctrl.last7DaysSeries.last.morningLiters, 42.5);
        expect(ctrl.lastDaysSeries(30).length, 30);
        expect(ctrl.quincenaMorningLiters, 42.5);
        expect(ctrl.quincenaAfternoonLiters, 27.5);
        expect(ctrl.quincenaAverageDailyLiters, 35.0);
        expect(ctrl.deliveryStreakDays, 2); // 17 y 18 de noviembre
        expect(ctrl.bestDayLast30?.isoDate, '2026-11-05');
        expect(ctrl.previousQuincena.start, '2026-11-01');
        expect(ctrl.previousQuincenaLiters, 100.0);
        // Día 3 de la quincena vs. días 1–3 de la anterior (sin entregas) → sin base.
        expect(ctrl.quincenaDeltaPercent, isNull);
        expect(ctrl.quincenaElapsedDays, 3);
        expect(ctrl.quincenaTotalDays, 15);
        expect(ctrl.daysToQuincenaClose, 12);

        // Calendario: mapeo M/T y anuladas por separado.
        final Map<String, DayDeliverySummary> days = ctrl.daySummaries;
        expect(days['2026-11-18']!.hasMorning, isTrue);
        expect(days['2026-11-18']!.hasAfternoon, isFalse);
        expect(days['2026-11-17']!.afternoonLiters, 27.5);
        expect(days['2026-11-17']!.annulled.length, 1);
        expect(days['2026-11-17']!.totalLiters, 27.5);
        expect(days['2026-11-05']!.allSettled, isTrue);
        expect(ctrl.earliestDeliveryDate, '2026-11-05');
        final MilkReceptionModel settled = ctrl.allReceptions.firstWhere((MilkReceptionModel r) => r.recepcionId == 'r-a-old-month');
        expect(ctrl.settlementForReception(settled)?.numeroComprobante, 'LIQ-2026-0001');
        expect(ctrl.priceForReception(settled), 1950);

        // Filtros heredados (Paso 7.4)
        expect(ctrl.filteredReceptions.length, 2);
        ctrl.setPeriodFilter('MES');
        expect(ctrl.filteredReceptions.length, 3);
        ctrl.setShiftFilter(AppConstants.shiftAfternoon);
        expect(ctrl.filteredTotalLiters, 27.5);
        ctrl.clearDeliveryFilters();
        expect(ctrl.periodFilter, 'QUINCENA');

        // Liquidaciones y PDF (Paso 7.5)
        final SettlementModel sA = ctrl.settlements.first;
        final List<MilkReceptionModel> recsForPdf = ctrl.receptionsForSettlement(sA);
        expect(recsForPdf.length, 1);
        final Uint8List pdfBytes = await SettlementPdfService.buildVoucherPdfBytes(
          settlement: sA,
          receptions: recsForPdf,
          producer: ctrl.activeProducer,
        );
        expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
      },
    );

    test(
      'Paso 7.2, 7.6 y 7.7: Solicitud Habeas Data Ley 1581, alerta de entrega, parseo FCM, comunicados ADMIN y lectura',
      () async {
        final HiveService hive = HiveService(enablePersistence: false);
        final InMemoryNotificationRemote notifRemote = InMemoryNotificationRemote();
        final ProducerPortalController ctrl = buildPortalController(
          hive: hive,
          receptions: <MilkReceptionModel>[],
          settlements: <SettlementModel>[],
          notifRemote: notifRemote,
        );
        await ctrl.loadPortalForUser(producerUserA, referenceDate: DateTime(2026, 11, 18, 9));

        final bool rectOk = await ctrl.submitRectificationRequest(
          actor: producerUserA,
          campo: 'Teléfono de contacto',
          detalle: 'Dato correcto: 3205559988',
        );
        expect(rectOk, isTrue);
        expect(notifRemote.logs.single.accion, 'SOLICITAR_RECTIFICACION');
        expect(ctrl.allNotifications.any((AppNotificationModel n) => n.tipo == 'RECTIFICACION'), isTrue);

        expect(
          await ctrl.sendBroadcast(actor: producerUserA, titulo: 'Intento no autorizado', mensaje: 'No permitido para productores.'),
          isFalse,
        );
        expect(
          await ctrl.sendBroadcast(actor: adminUser, titulo: 'Jornada de calidad', mensaje: 'Limpieza de cantinas antes del acopio.'),
          isTrue,
        );
        expect(ctrl.unreadNotificationsCount, 2);
        await ctrl.markNotificationRead(ctrl.allNotifications.first.notificacionId);
        expect(ctrl.unreadNotificationsCount, 1);
        await ctrl.markAllRead();
        expect(ctrl.unreadNotificationsCount, 0);

        final ReceptionService recService = ReceptionService(
          hiveService: hive,
          remoteDataSource: InMemoryReceptionRemote(<MilkReceptionModel>[]),
        );
        await recService.registerReception(
          producer: producerA,
          litros: 19.5,
          jornada: AppConstants.shiftMorning,
          operarioUid: 'op-1',
          isOnline: false,
        );
        final List<AppNotificationModel> hiveNotifs = await hive.getCachedNotifications();
        expect(hiveNotifs.any((AppNotificationModel n) => n.tipo == 'ENTREGA' && n.destinoProductorId == 'prod-a'), isTrue);

        final AppNotificationModel? parsedFcm = FcmService.parseRemoteMessageData(
          <String, dynamic>{'notificacionId': 'fcm-1', 'tipo': 'PAGO', 'destinoProductorId': 'prod-a'},
          title: 'Pago efectuado',
          body: r'Transferencia por $ 195.000 confirmada.',
        );
        expect(parsedFcm!.tipo, 'PAGO');
      },
    );
  });

  group('Bandeja de avisos móvil', () {
    test('Agrupa en Hoy, Ayer, Esta semana y Anteriores (orden descendente)', () {
      final DateTime now = DateTime(2026, 11, 18, 15);
      final List<NotificationGroup> groups = ProducerPortalController.groupNotifications(
        <AppNotificationModel>[
          notice('old', at: DateTime(2026, 10, 1, 9)),
          notice('today-early', at: DateTime(2026, 11, 18, 6)),
          notice('yesterday', at: DateTime(2026, 11, 17, 23, 59)),
          notice('week', at: DateTime(2026, 11, 13, 8)),
          notice('today-late', at: DateTime(2026, 11, 18, 14)),
          notice('eight-days', at: DateTime(2026, 11, 10, 8)),
        ],
        now: now,
      );
      expect(groups.map((NotificationGroup g) => g.label).toList(), <String>['Hoy', 'Ayer', 'Esta semana', 'Anteriores']);
      expect(groups[0].items.map((AppNotificationModel n) => n.notificacionId), <String>['today-late', 'today-early']);
      expect(groups[1].items.single.notificacionId, 'yesterday');
      expect(groups[2].items.single.notificacionId, 'week');
      expect(groups[3].items.map((AppNotificationModel n) => n.notificacionId), <String>['eight-days', 'old']);
      expect(ProducerPortalController.groupNotifications(<AppNotificationModel>[], now: now), isEmpty);
    });

    Future<(ProducerPortalController, InMemoryNotificationRemote, MemoryPortalPreferences, HiveService)> setup() async {
      final HiveService hive = HiveService(enablePersistence: false);
      final InMemoryNotificationRemote remote = InMemoryNotificationRemote();
      final MemoryPortalPreferences prefs = MemoryPortalPreferences();
      await remote.upsertNotification(notice('general', at: DateTime.utc(2026, 11, 18, 8)));
      await remote.upsertNotification(notice('personal', dest: 'prod-a', tipo: 'PAGO', at: DateTime.utc(2026, 11, 18, 9)));
      await remote.upsertNotification(notice('rect', dest: 'prod-a', tipo: 'RECTIFICACION', at: DateTime.utc(2026, 11, 18, 7)));
      final ProducerPortalController ctrl = buildPortalController(
        hive: hive,
        receptions: <MilkReceptionModel>[],
        settlements: <SettlementModel>[],
        notifRemote: remote,
        preferences: prefs,
      );
      await ctrl.loadPortalForUser(producerUserA, referenceDate: DateTime(2026, 11, 18, 12));
      return (ctrl, remote, prefs, hive);
    }

    test('Borrar UNO: personal se elimina en la nube; general y rectificación se ocultan por usuario', () async {
      final (ProducerPortalController ctrl, InMemoryNotificationRemote remote, MemoryPortalPreferences prefs, HiveService hive) =
          await setup();
      expect(ctrl.allNotifications.length, 3);

      expect(await ctrl.deleteNotification('personal'), isTrue);
      expect(remote.deletedIds, <String>['personal']);
      expect((await hive.getCachedNotifications()).any((AppNotificationModel n) => n.notificacionId == 'personal'), isFalse);

      expect(await ctrl.deleteNotification('general'), isTrue);
      expect(await ctrl.deleteNotification('rect'), isTrue);
      expect(remote.deletedIds, <String>['personal'], reason: 'Comunicados y solicitudes Habeas Data no se borran en Firestore');
      expect(prefs.hidden['uid-prod-a'], <String>{'general', 'rect'});
      expect(ctrl.allNotifications, isEmpty);

      // Al recargar, los ocultos siguen ocultos para este usuario.
      await ctrl.loadPortalForUser(producerUserA, referenceDate: DateTime(2026, 11, 18, 12));
      expect(ctrl.allNotifications, isEmpty);
    });

    test('Deshacer un borrado provisional lo restaura sin tocar la nube', () async {
      final (ProducerPortalController ctrl, InMemoryNotificationRemote remote, _, _) = await setup();
      ctrl.stageNotificationRemoval('personal');
      expect(ctrl.allNotifications.length, 2);
      ctrl.undoNotificationRemoval('personal');
      expect(ctrl.allNotifications.length, 3);
      expect(ctrl.allNotifications.first.notificacionId, 'personal'); // orden por fecha
      expect(remote.deletedIds, isEmpty);
    });

    test('Si la nube falla, el aviso vuelve a la bandeja con mensaje de error', () async {
      final (ProducerPortalController ctrl, InMemoryNotificationRemote remote, _, _) = await setup();
      remote.failDeletes = true;
      expect(await ctrl.deleteNotification('personal'), isFalse);
      expect(ctrl.allNotifications.any((AppNotificationModel n) => n.notificacionId == 'personal'), isTrue);
      expect(ctrl.errorMessage, isNotNull);
    });

    test('Borrar TODAS vacía la bandeja respetando el tipo de cada aviso', () async {
      final (ProducerPortalController ctrl, InMemoryNotificationRemote remote, MemoryPortalPreferences prefs, _) = await setup();
      final int n = await ctrl.clearAllNotifications();
      expect(n, 3);
      expect(ctrl.allNotifications, isEmpty);
      expect(ctrl.unreadNotificationsCount, 0);
      expect(remote.deletedIds, <String>['personal']);
      expect(prefs.hidden['uid-prod-a'], containsAll(<String>['general', 'rect']));
      expect(await ctrl.clearAllNotifications(), 0);
    });
  });

  group('Calendario y estadísticas', () {
    test('buildDaySummaries separa jornadas y anuladas', () {
      final Map<String, DayDeliverySummary> map = ProducerPortalController.buildDaySummaries(<MilkReceptionModel>[
        reception('a', '2026-11-03', 20, hora: '07:00:00'),
        reception('b', '2026-11-03', 15, jornada: AppConstants.shiftAfternoon, hora: '16:00:00'),
        reception('c', '2026-11-04', 9, jornada: AppConstants.shiftAfternoon),
        reception('d', '2026-11-05', 50, anulado: true),
      ]);
      expect(map['2026-11-03']!.morningLiters, 20);
      expect(map['2026-11-03']!.afternoonLiters, 15);
      expect(map['2026-11-03']!.totalLiters, 35);
      expect(map['2026-11-04']!.hasMorning, isFalse);
      expect(map['2026-11-04']!.hasAfternoon, isTrue);
      expect(map['2026-11-05']!.hasDeliveries, isFalse);
      expect(map['2026-11-05']!.annulled.single.recepcionId, 'd');
      expect(map['2026-11-05']!.isEmpty, isFalse);
    });

    test('Racha de días consecutivos (hoy o desde ayer)', () {
      final DateTime today = DateTime(2026, 11, 18);
      expect(ProducerPortalController.computeStreak(<String>{'2026-11-18', '2026-11-17', '2026-11-15'}, today), 2);
      expect(ProducerPortalController.computeStreak(<String>{'2026-11-17', '2026-11-16'}, today), 2);
      expect(ProducerPortalController.computeStreak(<String>{'2026-11-10'}, today), 0);
      expect(ProducerPortalController.computeStreak(<String>{'2026-12-01', '2026-11-30'}, DateTime(2026, 12, 1)), 2);
    });

    test('Variación frente a la quincena anterior con la misma cantidad de días', () async {
      final ProducerPortalController ctrl = buildPortalController(
        hive: HiveService(enablePersistence: false),
        receptions: <MilkReceptionModel>[
          reception('p1', '2026-11-01', 100),
          reception('p2', '2026-11-02', 100),
          reception('p3', '2026-11-10', 999), // fuera de los primeros 2 días
          reception('c1', '2026-11-16', 150),
          reception('c2', '2026-11-17', 150),
        ],
        settlements: <SettlementModel>[],
        notifRemote: InMemoryNotificationRemote(),
      );
      await ctrl.loadPortalForUser(producerUserA, referenceDate: DateTime(2026, 11, 17, 10));
      expect(ctrl.quincenaDeltaPercent, closeTo(50, 0.001));
      expect(ctrl.previousQuincenaLiters, 1199);
    });
  });

  group('Preferencias locales (shared_preferences)', () {
    test('El recorrido queda marcado por usuario y los ocultos persisten', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPrefsPortalPreferences prefs = SharedPrefsPortalPreferences();
      expect(await prefs.isTourDone('u1'), isFalse);
      await prefs.setTourDone('u1', true);
      expect(await prefs.isTourDone('u1'), isTrue);
      expect(await prefs.isTourDone('u2'), isFalse);
      final SharedPreferences raw = await SharedPreferences.getInstance();
      expect(raw.getBool('tour_done_u1'), isTrue);

      await prefs.saveHiddenNotificationIds('u1', <String>{'a', 'b'});
      expect(await SharedPrefsPortalPreferences().hiddenNotificationIds('u1'), <String>{'a', 'b'});
      expect(await prefs.hiddenNotificationIds('u2'), isEmpty);
    });
  });
}
