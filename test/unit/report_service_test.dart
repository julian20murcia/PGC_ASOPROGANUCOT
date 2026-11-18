import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/controllers/report_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/report_export_service.dart';
import 'package:pgc_asoproganucot/core/services/report_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';

class _InMemoryAuditSource implements RemoteAuditDataSource {
  _InMemoryAuditSource(this.logs);
  final List<AuditLogModel> logs;

  @override
  Future<List<AuditLogModel>> fetchAuditLogs({int limit = 250}) async => logs;
}

class _InMemoryReceptionSource implements RemoteReceptionDataSource {
  _InMemoryReceptionSource(this.items);
  final List<MilkReceptionModel> items;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async => items;

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemoryProducerSource implements RemoteProducerDataSource {
  _InMemoryProducerSource(this.items);
  final List<ProducerModel> items;

  @override
  Future<List<ProducerModel>> fetchProducers() async => items;

  @override
  Future<void> upsertProducer(ProducerModel producer) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemoryRateSource implements RemoteRateDataSource {
  _InMemoryRateSource(this.items);
  final List<MilkRateModel> items;

  @override
  Future<List<MilkRateModel>> fetchRates() async => items;

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class _InMemorySettlementSource implements RemoteSettlementDataSource {
  _InMemorySettlementSource(this.items);
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

void main() {
  final DateTime refNow = DateTime.utc(2026, 11, 18, 10, 0);

  final ProducerModel prod1 = ProducerModel(
    productorId: 'p-1',
    codigoAsociado: 'ASO-001',
    cedula: '1073500111',
    nombres: 'Carlos',
    apellidos: 'Rojas',
    telefono: '3101112233',
    nombreFinca: 'El Mirador',
    vereda: 'La Glorieta',
    estado: 'ACTIVO',
    aceptoHabeasData: true,
    fechaAutorizacionDatos: refNow,
    fechaCreacion: refNow,
  );

  final ProducerModel prod2 = ProducerModel(
    productorId: 'p-2',
    codigoAsociado: 'ASO-002',
    cedula: '1073500222',
    nombres: 'Lucía',
    apellidos: 'Becerra',
    telefono: '3104445566',
    nombreFinca: 'San Isidro',
    vereda: 'El Tablón',
    estado: 'ACTIVO',
    aceptoHabeasData: true,
    fechaAutorizacionDatos: refNow,
    fechaCreacion: refNow,
  );

  final MilkRateModel rate = MilkRateModel(
    tarifaId: 'rate-1',
    precioPorLitro: 1900,
    fechaInicioVigencia: DateTime.utc(2026, 11, 1),
    observacion: 'Tarifa noviembre',
    registradoPorUid: 'admin',
    activa: true,
  );

  final SettlementModel settlement1 = SettlementModel(
    liquidacionId: 'liq-1',
    productorId: 'p-1',
    nombreProductorSnap: 'Carlos Rojas',
    cedulaProductorSnap: '1073500111',
    periodoInicio: '2026-11-01',
    periodoFin: '2026-11-15',
    quincenaLabel: '1ra Quincena Nov 2026',
    totalLitros: 30.0,
    cantidadEntregas: 2,
    precioLitroAplicado: 1850,
    valorTotalPagar: 55500,
    fechaLiquidacion: refNow,
    numeroComprobante: 'COMP-2026-0001',
    hashIntegridad: 'hash-1',
    creadoPorUid: 'admin',
  );

  final List<MilkReceptionModel> sampleDeliveries = <MilkReceptionModel>[
    MilkReceptionModel(
      recepcionId: 'r1',
      productorId: 'p-1',
      codigoAsociadoSnap: 'ASO-001',
      nombreProductorSnap: 'Carlos Rojas',
      litros: 18.0,
      fechaEntrega: '2026-11-05',
      horaEntrega: '06:30:00',
      jornada: AppConstants.shiftMorning,
      operarioUid: 'op-1',
      syncStatus: AppConstants.syncSynced,
      isSynced: true,
      liquidacionId: 'liq-1',
      createdAt: refNow,
    ),
    MilkReceptionModel(
      recepcionId: 'r2',
      productorId: 'p-1',
      codigoAsociadoSnap: 'ASO-001',
      nombreProductorSnap: 'Carlos Rojas',
      litros: 12.0,
      fechaEntrega: '2026-11-06',
      horaEntrega: '16:20:00',
      jornada: AppConstants.shiftAfternoon,
      operarioUid: 'op-1',
      syncStatus: AppConstants.syncSynced,
      isSynced: true,
      liquidacionId: 'liq-1',
      createdAt: refNow,
    ),
    MilkReceptionModel(
      recepcionId: 'r3',
      productorId: 'p-2',
      codigoAsociadoSnap: 'ASO-002',
      nombreProductorSnap: 'Lucía Becerra',
      litros: 25.0,
      fechaEntrega: '2026-11-16',
      horaEntrega: '06:45:00',
      jornada: AppConstants.shiftMorning,
      operarioUid: 'op-1',
      syncStatus: AppConstants.syncSynced,
      isSynced: true,
      createdAt: refNow,
    ),
    MilkReceptionModel(
      recepcionId: 'r4-anulada',
      productorId: 'p-2',
      codigoAsociadoSnap: 'ASO-002',
      nombreProductorSnap: 'Lucía Becerra',
      litros: 100.0,
      fechaEntrega: '2026-11-16',
      horaEntrega: '17:00:00',
      jornada: AppConstants.shiftAfternoon,
      operarioUid: 'op-1',
      anulado: true,
      createdAt: refNow,
    ),
  ];

  final List<AuditLogModel> sampleLogs = <AuditLogModel>[
    AuditLogModel(
      logId: 'log-1',
      entidadAfectada: AppConstants.receptionsCollection,
      registroId: 'r4-anulada',
      accion: 'ANULAR',
      motivo: 'Error en marcación de cantina',
      usuarioUid: 'admin',
      timestamp: refNow,
    ),
    AuditLogModel(
      logId: 'log-2',
      entidadAfectada: AppConstants.settlementsCollection,
      registroId: '2026-11-01_2026-11-15',
      accion: 'LIQUIDAR',
      motivo: 'Cierre quincenal 1ra Quincena Nov 2026',
      usuarioUid: 'admin',
      timestamp: refNow.subtract(const Duration(hours: 2)),
    ),
  ];

  group('ReportService, ReportController, CSV y PDF consolidado', () {
    test(
        'Calcula producción individual por ganadero, promedio diario, filtros de auditoría y exporta CSV/PDF válidos',
        () async {
      final HiveService memoryHive = HiveService(enablePersistence: false);
      final ReportController controller = ReportController(
        reportService: ReportService(
          remoteAuditDataSource: _InMemoryAuditSource(sampleLogs),
        ),
        receptionService: ReceptionService(
          hiveService: memoryHive,
          remoteDataSource: _InMemoryReceptionSource(sampleDeliveries),
        ),
        producerService: ProducerService(
          hiveService: memoryHive,
          remoteDataSource: _InMemoryProducerSource(
            <ProducerModel>[prod1, prod2],
          ),
        ),
        rateService: RateService(
          hiveService: memoryHive,
          remoteDataSource: _InMemoryRateSource(<MilkRateModel>[rate]),
        ),
        settlementService: SettlementService(
          hiveService: memoryHive,
          remoteDataSource: _InMemorySettlementSource(
            <SettlementModel>[settlement1],
          ),
        ),
      );

      await controller.loadAll();
      controller.setCustomPeriod(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      );

      expect(controller.producerSummaries.length, 2);
      expect(controller.totalRangeLiters, 55.0);
      expect(controller.totalRangeDeliveries, 3);
      // prod1: 30 L * 1850 = 55.500 (liquidado); prod2: 25 L * 1900 = 47.500 (estimado) => 103.000
      expect(controller.totalRangeValue, 103000.0);

      // Filtrar individualmente por Carlos Rojas (prod1: 30 L en 2 días => 15.0 L/día)
      controller.setSelectedProducer(prod1.productorId);
      expect(controller.producerSummaries.length, 1);
      final ProducerProductionSummary p1Summary =
          controller.producerSummaries.first;
      expect(p1Summary.morningLiters, 18.0);
      expect(p1Summary.afternoonLiters, 12.0);
      expect(p1Summary.totalLiters, 30.0);
      expect(p1Summary.activeDaysCount, 2);
      expect(p1Summary.dailyAverageLiters, 15.0);
      expect(p1Summary.settledAmount, 55500.0);

      // Auditoría solo lectura y filtro por entidad
      expect(controller.filteredAuditLogs.length, 2);
      controller.setAuditEntityFilter(AppConstants.receptionsCollection);
      expect(controller.filteredAuditLogs.length, 1);
      expect(controller.filteredAuditLogs.first.accion, 'ANULAR');

      // Exportación CSV con BOM UTF-8 para Excel
      controller.setSelectedProducer(null);
      final String prodCsv = ReportExportService.buildProducerSummaryCsv(
        controller.producerSummaries,
      );
      expect(prodCsv.startsWith('\ufeff'), isTrue);
      expect(prodCsv, contains('ASO-001'));
      expect(prodCsv, contains('Carlos Rojas'));
      expect(prodCsv, contains('55500.00'));

      final String settCsv = ReportExportService.buildSettlementsCsv(
        controller.filteredSettlements,
      );
      expect(settCsv, contains('COMP-2026-0001'));

      // Exportación PDF consolidado
      final Uint8List pdfBytes =
          await ReportExportService.buildConsolidatedReportPdfBytes(
        period: controller.selectedPeriod,
        summaries: controller.producerSummaries,
        settlements: controller.filteredSettlements,
        activePricePerLiter: controller.effectivePricePerLiter,
      );
      expect(pdfBytes.length, greaterThan(1500));
      expect(pdfBytes.sublist(0, 4), <int>[0x25, 0x50, 0x44, 0x46]);
    });
  });
}
