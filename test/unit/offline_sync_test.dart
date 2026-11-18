import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/sync_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/master_cache_service.dart';
import 'package:pgc_asoproganucot/core/services/sync_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:uuid/uuid.dart';

class _InMemoryRemoteReceptionGateway implements RemoteReceptionGateway {
  final Map<String, MilkReceptionModel> remoteDocs =
      <String, MilkReceptionModel>{};
  int batchCallsCount = 0;
  bool shouldFail = false;

  @override
  Future<void> uploadReceptionsBatch(List<MilkReceptionModel> receptions) async {
    batchCallsCount++;
    if (shouldFail) {
      throw Exception('Sin conexión a internet.');
    }
    for (final MilkReceptionModel item in receptions) {
      // Comportamiento idempotente equivalente a doc(recepcionId).set(..., merge: true).
      remoteDocs[item.recepcionId] = item.copyWith(
        isSynced: true,
        syncStatus: AppConstants.syncSynced,
      );
    }
  }
}

class _InMemoryMasterDataSource implements RemoteMasterDataSource {
  _InMemoryMasterDataSource({
    required this.producers,
    required this.rates,
  });

  final List<ProducerModel> producers;
  final List<MilkRateModel> rates;
  bool shouldFail = false;

  @override
  Future<List<ProducerModel>> fetchProducers() async {
    if (shouldFail) {
      throw Exception('Red no disponible');
    }
    return producers;
  }

  @override
  Future<List<MilkRateModel>> fetchRates() async {
    if (shouldFail) {
      throw Exception('Red no disponible');
    }
    return rates;
  }
}

void main() {
  const Uuid uuid = Uuid();

  group('Modelos de dominio Fase 2 (serialización completa)', () {
    final DateTime now = DateTime.utc(2026, 11, 18, 12, 30);

    test('Round-trip toMap/fromMap para los 6 modelos del dominio lácteo', () {
      final ProducerModel producer = ProducerModel(
        productorId: 'prod-1',
        uidUsuario: 'user-prod-1',
        codigoAsociado: 'ASO-001',
        cedula: '1073500999',
        nombres: 'José',
        apellidos: 'Rodríguez',
        telefono: '3112223344',
        nombreFinca: 'El Hato',
        vereda: 'La Glorieta',
        estado: 'ACTIVO',
        aceptoHabeasData: true,
        fechaAutorizacionDatos: now,
        autorizadoPorUid: 'admin-1',
        fechaCreacion: now,
      );
      final ProducerModel producerRt = ProducerModel.fromMap(producer.toMap());
      expect(producerRt.nombreCompleto, 'José Rodríguez');
      expect(producerRt.hasValidHabeasData, isTrue);
      expect(producerRt.isActivo, isTrue);

      final MilkRateModel rate = MilkRateModel(
        tarifaId: 'rate-1',
        precioPorLitro: 2150.0,
        fechaInicioVigencia: now.subtract(const Duration(days: 5)),
        observacion: 'Tarifa noviembre',
        registradoPorUid: 'admin-1',
      );
      final MilkRateModel rateRt = MilkRateModel.fromMap(rate.toMap());
      expect(rateRt.precioPorLitro, 2150.0);
      expect(rateRt.isVigenteEn(now), isTrue);

      final MilkReceptionModel reception = MilkReceptionModel(
        recepcionId: uuid.v4(),
        productorId: 'prod-1',
        codigoAsociadoSnap: 'ASO-001',
        nombreProductorSnap: 'José Rodríguez',
        litros: 42.5,
        fechaEntrega: '2026-11-18',
        horaEntrega: '06:15:00',
        jornada: AppConstants.shiftMorning,
        operarioUid: 'op-1',
        createdAt: now,
      );
      final MilkReceptionModel receptionRt =
          MilkReceptionModel.fromMap(reception.toMap());
      expect(receptionRt.recepcionId, reception.recepcionId);
      expect(receptionRt.litros, 42.5);
      expect(receptionRt.canBeModified, isTrue);
      expect(receptionRt.isLiquidada, isFalse);

      final SettlementModel settlement = SettlementModel(
        liquidacionId: 'liq-1',
        productorId: 'prod-1',
        nombreProductorSnap: 'José Rodríguez',
        cedulaProductorSnap: '1073500999',
        periodoInicio: '2026-11-01',
        periodoFin: '2026-11-15',
        quincenaLabel: 'Quincena 1 · Nov 2026',
        totalLitros: 510.5,
        cantidadEntregas: 14,
        precioLitroAplicado: 2150.0,
        valorTotalPagar: 1097575.0,
        fechaLiquidacion: now,
        numeroComprobante: 'COMP-2026-0001',
        hashIntegridad: 'sha256-abc',
        creadoPorUid: 'admin-1',
      );
      final SettlementModel settlementRt =
          SettlementModel.fromMap(settlement.toMap());
      expect(settlementRt.valorTotalPagar, 1097575.0);
      expect(settlementRt.isPagada, isFalse);

      final AppNotificationModel notif = AppNotificationModel(
        notificacionId: 'not-1',
        titulo: 'Liquidación emitida',
        mensaje: 'Se cerró tu quincena por 510.5 L.',
        tipo: 'CIERRE_QUINCENA',
        destinoProductorId: 'prod-1',
        fechaEnvio: now,
      );
      final AppNotificationModel notifRt =
          AppNotificationModel.fromMap(notif.toMap());
      expect(notifRt.titulo, 'Liquidación emitida');
      expect(notifRt.leida, isFalse);

      final AuditLogModel audit = AuditLogModel(
        logId: 'log-1',
        entidadAfectada: 'recepciones_leche',
        registroId: reception.recepcionId,
        accion: 'CREAR',
        valorNuevo: reception.toMap(),
        usuarioUid: 'op-1',
        timestamp: now,
      );
      final AuditLogModel auditRt = AuditLogModel.fromMap(audit.toMap());
      expect(auditRt.accion, 'CREAR');
      expect(auditRt.registroId, reception.recepcionId);
    });
  });

  group('Motor Offline-First Hive e idempotencia (offline_sync_test)', () {
    late HiveService memoryHive;
    late _InMemoryRemoteReceptionGateway remoteGateway;
    late SyncService syncService;

    setUp(() {
      memoryHive = HiveService(enablePersistence: false);
      remoteGateway = _InMemoryRemoteReceptionGateway();
      syncService = SyncService(
        hiveService: memoryHive,
        remoteGateway: remoteGateway,
      );
    });

    test(
      'Guarda entrega offline conservando UUID, pasa a isSynced=true al sincronizar y es idempotente al reejecutarse',
      () async {
        final String id1 = uuid.v4();
        final String id2 = uuid.v4();

        final MilkReceptionModel delivery1 = MilkReceptionModel(
          recepcionId: id1,
          productorId: 'prod-1',
          codigoAsociadoSnap: 'ASO-001',
          nombreProductorSnap: 'Ana López',
          litros: 35.5,
          fechaEntrega: '2026-11-18',
          horaEntrega: '06:30:00',
          jornada: AppConstants.shiftMorning,
          operarioUid: 'op-1',
          createdAt: DateTime.utc(2026, 11, 18, 6, 30),
        );
        final MilkReceptionModel delivery2 = MilkReceptionModel(
          recepcionId: id2,
          productorId: 'prod-2',
          codigoAsociadoSnap: 'ASO-002',
          nombreProductorSnap: 'Carlos Pérez',
          litros: 48.0,
          fechaEntrega: '2026-11-18',
          horaEntrega: '06:45:00',
          jornada: AppConstants.shiftMorning,
          operarioUid: 'op-1',
          createdAt: DateTime.utc(2026, 11, 18, 6, 45),
        );

        final MilkReceptionModel saved1 =
            await syncService.registerReceptionOfflineFirst(delivery1);
        final MilkReceptionModel saved2 =
            await syncService.registerReceptionOfflineFirst(delivery2);

        expect(saved1.recepcionId, id1);
        expect(saved1.isSynced, isFalse);
        expect(saved1.syncStatus, AppConstants.syncPending);
        expect(saved2.isSynced, isFalse);
        expect(remoteGateway.remoteDocs, isEmpty);

        final List<MilkReceptionModel> pendingBefore =
            await memoryHive.getPendingReceptions();
        expect(pendingBefore.length, 2);
        // Orden cronológico ascendente para envío a la nube
        expect(pendingBefore.first.recepcionId, id1);
        expect(pendingBefore.last.recepcionId, id2);

        // Primera sincronización tras recuperar conectividad
        final SyncExecutionResult firstRun =
            await syncService.syncPendingReceptions();
        expect(firstRun.hasError, isFalse);
        expect(firstRun.syncedCount, 2);
        expect(firstRun.remainingPendingCount, 0);
        expect(remoteGateway.remoteDocs.length, 2);

        final MilkReceptionModel? syncedLocal1 =
            await memoryHive.getReceptionById(id1);
        expect(syncedLocal1?.isSynced, isTrue);
        expect(syncedLocal1?.syncStatus, AppConstants.syncSynced);
        expect(syncedLocal1?.recepcionId, id1);

        // Segunda sincronización inmediata: no debe duplicar ni volver a subir
        final SyncExecutionResult secondRun =
            await syncService.syncPendingReceptions();
        expect(secondRun.syncedCount, 0);
        expect(secondRun.remainingPendingCount, 0);
        expect(remoteGateway.batchCallsCount, 1);
        expect(remoteGateway.remoteDocs.length, 2);

        // Incluso ante un reintento manual del mismo UUID hacia el gateway remoto, no duplica litros
        await remoteGateway.uploadReceptionsBatch(
          <MilkReceptionModel>[delivery1, delivery2],
        );
        expect(remoteGateway.remoteDocs.length, 2);
        expect(remoteGateway.remoteDocs[id1]?.litros, 35.5);
      },
    );

    test(
      'Rechaza modificar localmente una entrega ya liquidada y conserva respaldo pendiente ante falla de red',
      () async {
        final String settledId = uuid.v4();
        final MilkReceptionModel settled = MilkReceptionModel(
          recepcionId: settledId,
          productorId: 'prod-1',
          codigoAsociadoSnap: 'ASO-001',
          nombreProductorSnap: 'Ana López',
          litros: 50.0,
          fechaEntrega: '2026-11-10',
          horaEntrega: '07:00:00',
          jornada: AppConstants.shiftMorning,
          operarioUid: 'op-1',
          isSynced: true,
          syncStatus: AppConstants.syncSynced,
          liquidacionId: 'liq-nov-01',
          createdAt: DateTime.utc(2026, 11, 10, 7, 0),
        );
        await memoryHive.saveReception(settled);

        expect(
          () => memoryHive.saveReception(settled.copyWith(litros: 99.0)),
          throwsStateError,
        );
        final MilkReceptionModel? persisted =
            await memoryHive.getReceptionById(settledId);
        expect(persisted?.litros, 50.0);

        // Falla de red al intentar sincronizar nueva entrega mantiene registro pendiente intacto
        remoteGateway.shouldFail = true;
        final MilkReceptionModel unsent = MilkReceptionModel(
          recepcionId: uuid.v4(),
          productorId: 'prod-1',
          codigoAsociadoSnap: 'ASO-001',
          nombreProductorSnap: 'Ana López',
          litros: 22.0,
          fechaEntrega: '2026-11-18',
          horaEntrega: '16:10:00',
          jornada: AppConstants.shiftAfternoon,
          operarioUid: 'op-1',
          createdAt: DateTime.utc(2026, 11, 18, 16, 10),
        );
        await syncService.registerReceptionOfflineFirst(unsent);
        final SyncExecutionResult failedRun =
            await syncService.syncPendingReceptions();

        expect(failedRun.hasError, isTrue);
        expect(failedRun.remainingPendingCount, 1);
      },
    );

    test(
      'MasterCacheService y SyncController respaldan operación 100% offline',
      () async {
        final DateTime now = DateTime.utc(2026, 11, 18, 8, 0);
        final _InMemoryMasterDataSource masterRemote = _InMemoryMasterDataSource(
          producers: <ProducerModel>[
            ProducerModel(
              productorId: 'p-1',
              codigoAsociado: 'ASO-010',
              cedula: '1073510001',
              nombres: 'Marta',
              apellidos: 'Sánchez',
              telefono: '3120001122',
              nombreFinca: 'La Pradera',
              vereda: 'El Crucero',
              estado: 'ACTIVO',
              aceptoHabeasData: true,
              fechaAutorizacionDatos: now,
              fechaCreacion: now,
            ),
          ],
          rates: <MilkRateModel>[
            MilkRateModel(
              tarifaId: 'tar-actual',
              precioPorLitro: 2200.0,
              fechaInicioVigencia: now.subtract(const Duration(days: 2)),
              observacion: 'Vigente',
              registradoPorUid: 'admin-1',
            ),
          ],
        );

        final MasterCacheService masterCache = MasterCacheService(
          hiveService: memoryHive,
          remoteDataSource: masterRemote,
        );

        final refreshRes = await masterCache.refreshAll();
        expect(refreshRes.fromCache, isFalse);
        expect(refreshRes.producersCount, 1);
        expect(refreshRes.ratesCount, 1);

        // Simular pérdida de internet: MasterCacheService sirve desde Hive sin fallar
        masterRemote.shouldFail = true;
        final offlineRefresh = await masterCache.refreshAll();
        expect(offlineRefresh.fromCache, isTrue);
        final List<ProducerModel> cachedProducers =
            await masterCache.getProducers();
        final MilkRateModel? activeRate = await masterCache.getActiveRate();
        expect(cachedProducers.first.codigoAsociado, 'ASO-010');
        expect(activeRate?.precioPorLitro, 2200.0);

        // SyncController registra y sincroniza actualizando pendingCount
        final SyncController controller = SyncController(
          hiveService: memoryHive,
          syncService: syncService,
          masterCacheService: masterCache,
        );
        await controller.initialize(startConnectivityWatch: false);
        expect(controller.pendingCount, 0);

        // Registrar con error temporal en la nube deja pendingCount en 1
        remoteGateway.shouldFail = true;
        await controller.registerReception(
          MilkReceptionModel(
            recepcionId: uuid.v4(),
            productorId: 'p-1',
            codigoAsociadoSnap: 'ASO-010',
            nombreProductorSnap: 'Marta Sánchez',
            litros: 19.5,
            fechaEntrega: '2026-11-18',
            horaEntrega: '06:50:00',
            jornada: AppConstants.shiftMorning,
            operarioUid: 'op-1',
            createdAt: now,
          ),
        );
        expect(controller.pendingCount, 1);

        // Al volver la red, syncNow sube la cola y limpia pendingCount
        remoteGateway.shouldFail = false;
        final SyncExecutionResult syncResult = await controller.syncNow();
        expect(syncResult.syncedCount, 1);
        expect(controller.pendingCount, 0);
        expect(controller.lastSyncCount, 1);
      },
    );
  });
}
