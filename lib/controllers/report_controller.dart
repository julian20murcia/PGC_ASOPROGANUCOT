import 'package:flutter/foundation.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_rate_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../core/services/producer_service.dart';
import '../core/services/rate_service.dart';
import '../core/services/reception_service.dart';
import '../core/services/report_service.dart';
import '../core/services/settlement_calculator.dart';
import '../core/services/settlement_service.dart';

/// Controlador MVC para reportes analíticos por productor, consolidados y bitácora (`RF-17`, `RF-18`, `RNF-07`).
class ReportController extends ChangeNotifier {
  ReportController({
    ReportService? reportService,
    ReceptionService? receptionService,
    ProducerService? producerService,
    RateService? rateService,
    SettlementService? settlementService,
  })  : _reportService = reportService ?? ReportService(),
        _receptionService = receptionService ?? ReceptionService(),
        _producerService = producerService ?? ProducerService(),
        _rateService = rateService ?? RateService(),
        _settlementService = settlementService ?? SettlementService();

  final ReportService _reportService;
  final ReceptionService _receptionService;
  final ProducerService _producerService;
  final RateService _rateService;
  final SettlementService _settlementService;

  ReportRangeType _rangeType = ReportRangeType.quincenal;
  QuincenaPeriod _selectedPeriod =
      QuincenaPeriod.currentForDate(DateTime.now());
  String? _selectedProducerId;

  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
  List<ProducerModel> _producers = <ProducerModel>[];
  List<SettlementModel> _settlements = <SettlementModel>[];
  MilkRateModel? _activeRate;
  List<AuditLogModel> _auditLogs = <AuditLogModel>[];

  String _auditEntityFilter = 'TODOS';
  String _auditSearchQuery = '';
  bool _isLoading = false;
  bool _isExporting = false;
  String? _errorMessage;

  ReportRangeType get rangeType => _rangeType;
  QuincenaPeriod get selectedPeriod => _selectedPeriod;
  String? get selectedProducerId => _selectedProducerId;
  List<ProducerModel> get producers => _producers;
  MilkRateModel? get activeRate => _activeRate;
  String get auditEntityFilter => _auditEntityFilter;
  String get auditSearchQuery => _auditSearchQuery;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;

  double get effectivePricePerLiter => _activeRate?.precioPorLitro ?? 0;

  List<ProducerProductionSummary> get producerSummaries =>
      ReportService.buildProducerSummaries(
        period: _selectedPeriod,
        receptions: _receptions,
        producers: _producers,
        settlements: _settlements,
        activePricePerLiter: effectivePricePerLiter,
        filterProducerId: _selectedProducerId,
      );

  List<MilkReceptionModel> get filteredReceptions =>
      ReportService.filterReceptionsForReport(
        period: _selectedPeriod,
        receptions: _receptions,
        filterProducerId: _selectedProducerId,
      );

  List<SettlementModel> get filteredSettlements =>
      ReportService.filterSettlementsForReport(
        period: _selectedPeriod,
        settlements: _settlements,
        filterProducerId: _selectedProducerId,
      );

  double get totalRangeLiters => SettlementCalculator.roundToThousandths(
        producerSummaries.fold<double>(
          0,
          (double sum, ProducerProductionSummary p) => sum + p.totalLiters,
        ),
      );

  double get totalRangeValue => SettlementCalculator.roundToCents(
        producerSummaries.fold<double>(
          0,
          (double sum, ProducerProductionSummary p) =>
              sum + p.totalEconomicValue,
        ),
      );

  int get totalRangeDeliveries => producerSummaries.fold<int>(
        0,
        (int sum, ProducerProductionSummary p) => sum + p.deliveryCount,
      );

  double get averageDailyPerProducer {
    final List<ProducerProductionSummary> list = producerSummaries;
    if (list.isEmpty) return 0;
    final double sumAverages = list.fold<double>(
      0,
      (double s, ProducerProductionSummary p) => s + p.dailyAverageLiters,
    );
    return SettlementCalculator.roundToThousandths(sumAverages / list.length);
  }

  List<AuditLogModel> get filteredAuditLogs {
    final String q = _auditSearchQuery.trim().toLowerCase();
    return _auditLogs.where((AuditLogModel log) {
      if (_auditEntityFilter != 'TODOS' &&
          log.entidadAfectada.toLowerCase() !=
              _auditEntityFilter.toLowerCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      return log.entidadAfectada.toLowerCase().contains(q) ||
          log.accion.toLowerCase().contains(q) ||
          log.registroId.toLowerCase().contains(q) ||
          log.usuarioUid.toLowerCase().contains(q) ||
          (log.motivo ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> loadAll() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final recRes = await _receptionService.listReceptions();
      final prodRes = await _producerService.listProducers();
      final rateRes = await _rateService.listRates();
      final setRes = await _settlementService.listSettlements();
      final List<AuditLogModel> logs = await _reportService.listAuditLogs();

      _receptions = recRes.receptions;
      _producers = prodRes.producers;
      _activeRate = RateService.resolveRateForDate(
        rateRes.rates,
        DateTime.now(),
      );
      _settlements = setRes.settlements;
      _auditLogs = logs;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setRangeType(ReportRangeType type) {
    _rangeType = type;
    if (type != ReportRangeType.custom) {
      _selectedPeriod = ReportService.buildPeriodForType(type);
    }
    notifyListeners();
  }

  void setCustomPeriod(DateTime start, DateTime end) {
    _rangeType = ReportRangeType.custom;
    _selectedPeriod = QuincenaPeriod.custom(start, end);
    notifyListeners();
  }

  void setSelectedProducer(String? producerId) {
    _selectedProducerId =
        (producerId == null || producerId.isEmpty) ? null : producerId;
    notifyListeners();
  }

  void setAuditEntityFilter(String entity) {
    _auditEntityFilter = entity;
    notifyListeners();
  }

  void setAuditSearchQuery(String query) {
    _auditSearchQuery = query;
    notifyListeners();
  }

  void setExporting(bool value) {
    _isExporting = value;
    notifyListeners();
  }
}
