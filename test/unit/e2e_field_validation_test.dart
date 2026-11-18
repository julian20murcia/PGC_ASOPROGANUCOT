import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/producer_portal_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/notification_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/services/settlement_pdf_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/services/sync_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';

/// Simulador de Firestore compartido entre estación Desktop (planta Susa)
/// y dispositivo Móvil (productor en finca).
class _SharedCloudDatabase {
  final List<ProducerModel> producers = <ProducerModel>[];
  final Map<String, MilkReceptionModel> receptions =
      <String, MilkReceptionModel>{};
  final List<MilkRateModel> rates = <MilkRateModel>[];
  final Map<String, SettlementModel> settlements = <String, SettlementModel>{};
  final List<AppNotificationModel> notifications = <AppNotificationModel>[];
  final List<AuditLogModel> auditLogs = <AuditLogModel>[];
}

class _CloudProducerRemote implements RemoteProducerDataSource {
  _CloudProducerRemote(this.db);
  final _SharedCloudDatabase db;

  @override
  Future<List<ProducerModel>> fetchProducers() async =>
      List<ProducerModel>.from(db.producers);

  @override
  Future<void> upsertProducer(ProducerModel producer) async {
    db.producers.removeWhere((p) => p.productorId == producer.productorId);
    db.producers.add(producer);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async => db.auditLogs.add(log);
}

class _CloudReceptionRemote implements RemoteReceptionDataSource {
  _CloudReceptionRemote(this.db);
  final _SharedCloudDatabase db;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async =>
      db.receptions.values.toList();

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    db.receptions[reception.recepcionId] = reception;
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async => db.auditLogs.add(log);
}

class _CloudRateRemote implements RemoteRateDataSource {
  _CloudRateRemote(this.db);
  final _SharedCloudDatabase db;

  @override
  Future<List<MilkRateModel>> fetchRates() async =>
      List<MilkRateModel>.from(db.rates);

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {
    for (final MilkRateModel r in rates) {
      db.rates.removeWhere((x) => x.tarifaId == r.tarifaId);
      db.rates.add(r);
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async => db.auditLogs.add(log);
}

class _CloudSettlementRemote implements RemoteSettlementDataSource {
  _CloudSettlementRemote(this.db);
  final _SharedCloudDatabase db;

  @override
  Future<List<SettlementModel>> fetchSettlements() async =>
      db.settlements.values.toList();

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {
    for (final SettlementModel s in settlements) {
      db.settlements[s.liquidacionId] = s;
      final List<String> recIds =
          receptionIdsBySettlement[s.liquidacionId] ?? const <String>[];
      for (final String rId in recIds) {
        final MilkReceptionModel? current = db.receptions[rId];
        if (current != null) {
          db.receptions[rId] = current.copyWith(liquidacionId: s.liquidacionId);
        }
      }
    }
    db.notifications.addAll(notifications);
    db.auditLogs.add(auditLog);
  }

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {
    db.settlements[updatedSettlement.liquidacionId] = updatedSettlement;
    db.notifications.add(notification);
    db.auditLogs.add(auditLog);
  }
}

class _CloudNotificationRemote implements RemoteNotificationDataSource {
  _CloudNotificationRemote(this.db);
  final _SharedCloudDatabase db;

  @override
  Future<List<AppNotificationModel>> fetchNotifications({
    String? productorId,
    String? userUid,
  }) async {
    if (productorId == null && userUid == null) {
      return List<AppNotificationModel>.from(db.notifications);
    }
    return db.notifications.where((AppNotificationModel n) {
      final String? d = n.destinoProductorId;
      return d == null || d == productorId || d == userUid;
    }).toList();
  }

  @override
  Future<void> upsertNotification(AppNotificationModel notification) async {
    db.notifications.removeWhere(
      (n) => n.notificacionId == notification.notificacionId,
    );
    db.notifications.add(notification);
  }

  @override
  Future<void> markNotificationRead(String notificacionId) async {
    final int idx = db.notifications.indexWhere(
      (n) => n.notificacionId == notificacionId,
    );
    if (idx >= 0) {
      db.notifications[idx] = db.notifications[idx].copyWith(leida: true);
    }
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async => db.auditLogs.add(log);
}

void main() {
  group('Fase 8 · Validación Integral E2E (CHK-03, CHK-04, CHK-05)', () {
    test(
      'Flujo completo Planta Offline-First -> Reconexión -> Cierre Quincenal al centavo -> Portal Móvil -> Push FCM',
      () async {
        final _SharedCloudDatabase cloudDb = _SharedCloudDatabase();
        final HiveService desktopHive = HiveService(enablePersistence: false);
        final HiveService mobileHive = HiveService(enablePersistence: false);

        final UserModel admin = UserModel(
          uid: 'uid-admin-susa',
          nombreCompleto: 'Administrador Susa',
          documento: '10000001',
          correo: 'admin@asoproganucott.com',
          telefono: '3101112233',
          rol: AppConstants.roleAdmin,
          activo: true,
          fcmTokens: const <String>[],
          fechaCreacion: DateTime.utc(2026, 11, 1),
        );

        final UserModel producerUser = UserModel(
          uid: 'uid-prod-campo-1',
          nombreCompleto: 'Mateo Bustos',
          documento: '1073500888',
          correo: 'mateo@vereda.com',
          telefono: '3124445566',
          rol: AppConstants.roleProductor,
          activo: true,
          fcmTokens: const <String>['fcm-token-android-1'],
          fechaCreacion: DateTime.utc(2026, 11, 1),
        );

        final ProducerModel producer = ProducerModel(
          productorId: 'prod-campo-1',
          uidUsuario: producerUser.uid,
          codigoAsociado: 'ASO-014',
          cedula: '1073500888',
          nombres: 'Mateo',
          apellidos: 'Bustos',
          telefono: '3124445566',
          nombreFinca: 'Alto Bonito',
          vereda: 'El Tablón',
          estado: 'ACTIVO',
          aceptoHabeasData: true,
          fechaAutorizacionDatos: DateTime.utc(2026, 11, 1),
          autorizadoPorUid: admin.uid,
          fechaCreacion: DateTime.utc(2026, 11, 1),
        );
        cloudDb.producers.add(producer);
        cloudDb.rates.add(
          MilkRateModel(
            tarifaId: 'tarifa-nov-2026',
            precioPorLitro: 1850.40,
            fechaInicioVigencia: DateTime.utc(2026, 11, 1),
            observacion: 'Tarifa 2da quincena noviembre',
            registradoPorUid: admin.uid,
            activa: true,
          ),
        );

        // 1) CHK-03: Estación escritorio DESCONECTADA registra mañana y tarde en Hive
        final _CloudReceptionRemote desktopRecRemote =
            _CloudReceptionRemote(cloudDb);
        final ReceptionService desktopRecService = ReceptionService(
          hiveService: desktopHive,
          remoteDataSource: desktopRecRemote,
        );

        final DateTime morningTime = DateTime(2026, 11, 18, 7, 10, 0);
        final DateTime afternoonTime = DateTime(2026, 11, 18, 16, 25, 0);

        final MilkReceptionModel morningOffline =
            await desktopRecService.registerReception(
          producer: producer,
          litros: 43.25,
          jornada: AppConstants.shiftMorning,
          operarioUid: 'uid-op-1',
          timestamp: morningTime,
          isOnline: false,
        );
        final MilkReceptionModel afternoonOffline =
            await desktopRecService.registerReception(
          producer: producer,
          litros: 28.40,
          jornada: AppConstants.shiftAfternoon,
          operarioUid: 'uid-op-1',
          timestamp: afternoonTime,
          isOnline: false,
        );

        expect(morningOffline.isSynced, isFalse);
        expect(morningOffline.syncStatus, AppConstants.syncPending);
        expect(afternoonOffline.isSynced, isFalse);
        expect(cloudDb.receptions.isEmpty, isTrue);

        // Verificar generación local de alertas ENTREGA offline
        final List<AppNotificationModel> offlineAlerts =
            await desktopHive.getCachedNotifications();
        expect(
          offlineAlerts.where((n) => n.tipo == 'ENTREGA').length,
          2,
        );

        // Recuperar conectividad y ejecutar sincronización idempotente (dos veces)
        final SyncExecutionResult syncFirst =
            await desktopRecService.syncPending();
        final SyncExecutionResult syncSecond =
            await desktopRecService.syncPending();

        expect(syncFirst.syncedCount, 2);
        expect(syncFirst.remainingPendingCount, 0);
        expect(syncSecond.syncedCount, 0);
        expect(cloudDb.receptions.length, 2);
        expect(
          cloudDb.receptions.containsKey(morningOffline.recepcionId),
          isTrue,
        );
        expect(
          cloudDb.receptions.containsKey(afternoonOffline.recepcionId),
          isTrue,
        );

        // 2) CHK-04: Cierre quincenal atómico y exactitud matemática al centavo
        // 43.25 + 28.40 = 71.65 L; 71.65 * 1850.40 = 132581.16 exacto
        final QuincenaPeriod period = QuincenaPeriod.forHalfMonth(
          year: 2026,
          month: 11,
          firstHalf: false,
        );
        final SettlementService desktopSettlementService = SettlementService(
          hiveService: desktopHive,
          remoteDataSource: _CloudSettlementRemote(cloudDb),
        );

        final List<SettlementModel> closed =
            await desktopSettlementService.closeQuincena(
          actor: admin,
          period: period,
          pricePerLiter: 1850.40,
          receptions: cloudDb.receptions.values.toList(),
          producers: cloudDb.producers,
        );

        expect(closed.length, 1);
        final SettlementModel s = closed.first;
        expect(s.totalLitros, 71.65);
        expect(s.valorTotalPagar, 132581.16);
        expect(s.estadoPago, 'PENDIENTE');

        // Verificar huella criptográfica SHA-256 íntegra (Ley 527 de 1999)
        final String expectedHash = SettlementCalculator.computeIntegrityHash(
          liquidacionId: s.liquidacionId,
          numeroComprobante: s.numeroComprobante,
          productorId: producer.productorId,
          cedula: producer.cedula,
          periodoInicio: period.startDate,
          periodoFin: period.endDate,
          totalLitros: s.totalLitros,
          cantidadEntregas: s.cantidadEntregas,
          precioLitroAplicado: s.precioLitroAplicado,
          valorTotalPagar: s.valorTotalPagar,
          recepcionIds: <String>[
            morningOffline.recepcionId,
            afternoonOffline.recepcionId,
          ],
        );
        expect(s.hashIntegridad, expectedHash);

        // Confirmar inmutabilidad post-liquidación en Hive y bloqueo de edición
        final MilkReceptionModel? settledLocalRec =
            await desktopHive.getReceptionById(morningOffline.recepcionId);
        expect(settledLocalRec?.liquidacionId, s.liquidacionId);
        expect(
          () => desktopRecService.editReceptionLitros(
            existing: settledLocalRec!,
            nuevosLitros: 50.0,
            motivo: 'Intento post liquidación',
            actor: admin,
          ),
          throwsA(isA<ReceptionServiceException>()),
        );

        // Confirmar pago y verificar PDF válido
        final SettlementModel paid = await desktopSettlementService.markAsPaid(
          actor: admin,
          settlement: s,
          observacionPago: 'Transferencia Bancolombia #8821',
        );
        expect(paid.isPagada, isTrue);

        final Uint8List pdfBytes =
            await SettlementPdfService.buildVoucherPdfBytes(
          settlement: paid,
          receptions: cloudDb.receptions.values.toList(),
          producer: producer,
        );
        expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
        expect(pdfBytes.length, greaterThan(1000));

        // 3) Verificación en Portal Móvil del Productor y Alertas Push FCM (CHK-05)
        final NotificationService notifService = NotificationService(
          hiveService: mobileHive,
          remoteDataSource: _CloudNotificationRemote(cloudDb),
        );
        await notifService.sendInstitutionalBroadcast(
          actor: admin,
          titulo: 'Jornada de mantenimiento tanque frío',
          mensaje: 'Entrega de tarde inicia a las 16:00 en planta Susa.',
        );

        final ProducerPortalController mobilePortal = ProducerPortalController(
          hiveService: mobileHive,
          producerService: ProducerService(
            hiveService: mobileHive,
            remoteDataSource: _CloudProducerRemote(cloudDb),
          ),
          receptionService: ReceptionService(
            hiveService: mobileHive,
            remoteDataSource: _CloudReceptionRemote(cloudDb),
          ),
          rateService: RateService(
            hiveService: mobileHive,
            remoteDataSource: _CloudRateRemote(cloudDb),
          ),
          settlementService: SettlementService(
            hiveService: mobileHive,
            remoteDataSource: _CloudSettlementRemote(cloudDb),
          ),
          notificationService: notifService,
          fcmService: FcmService(),
        );

        await mobilePortal.loadPortalForUser(
          producerUser,
          referenceDate: DateTime(2026, 11, 18, 18, 0),
        );

        expect(mobilePortal.activeProducer?.codigoAsociado, 'ASO-014');
        expect(mobilePortal.quincenaLiters, 71.65);
        expect(mobilePortal.settlements.length, 1);
        expect(mobilePortal.settlements.first.isPagada, isTrue);
        expect(mobilePortal.settlements.first.valorTotalPagar, 132581.16);
        expect(
          mobilePortal.allNotifications.any((n) => n.tipo == 'CIERRE_QUINCENA'),
          isTrue,
        );
        expect(
          mobilePortal.allNotifications.any((n) => n.tipo == 'PAGO'),
          isTrue,
        );
        expect(
          mobilePortal.allNotifications.any((n) => n.tipo == 'COMUNICADO'),
          isTrue,
        );

        // Validar parseo FCM para los eventos clave en primer/segundo plano
        for (final String fcmType in <String>[
          'ENTREGA',
          'CIERRE_QUINCENA',
          'LIQUIDACION',
          'PAGO',
        ]) {
          final AppNotificationModel? msg = FcmService.parseRemoteMessageData(
            <String, dynamic>{
              'notificacionId': 'push-$fcmType',
              'tipo': fcmType,
              'destinoProductorId': producer.productorId,
            },
            title: 'Evento $fcmType',
            body: 'Notificación verificada CHK-05',
          );
          expect(msg, isNotNull);
          expect(msg!.tipo, fcmType);
        }
      },
    );
  });
}
