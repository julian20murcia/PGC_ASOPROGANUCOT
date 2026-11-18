import 'package:flutter/foundation.dart';

import '../../models/milk_rate_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../core/services/producer_service.dart';
import '../core/services/rate_service.dart';
import '../core/services/reception_service.dart';
import '../core/services/settlement_calculator.dart';
import '../core/services/settlement_service.dart';

/// Controlador MVC para cálculo, cierre quincenal, comprobantes y pagos (`RF-13` a `RF-15`).
class SettlementController extends ChangeNotifier {
  SettlementController({
    SettlementService? settlementService,
    ReceptionService? receptionService,
    ProducerService? producerService,
    RateService? rateService,
  })  : _settlementService = settlementService ?? SettlementService(),
        _receptionService = receptionService ?? ReceptionService(),
        _producerService = producerService ?? ProducerService(),
        _rateService = rateService ?? RateService();

  final SettlementService _settlementService;
  final ReceptionService _receptionService;
  final ProducerService _producerService;
  final RateService _rateService;

  QuincenaPeriod _selectedPeriod =
      QuincenaPeriod.currentForDate(DateTime.now());
  List<SettlementModel> _settlements = <SettlementModel>[];
  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
  List<ProducerModel> _producers = <ProducerModel>[];
  MilkRateModel? _activeRate;
  SettlementPreviewResult? _preview;

  String _searchQuery = '';
  String _statusFilter = 'TODOS'; // TODOS | PENDIENTE | PAGADA
  bool _isLoading = false;
  bool _isClosing = false;
  bool _isUpdatingPayment = false;
  bool _fromCache = false;
  String? _errorMessage;
  String? _feedbackMessage;

  QuincenaPeriod get selectedPeriod => _selectedPeriod;
  List<SettlementModel> get allSettlements => _settlements;
  List<MilkReceptionModel> get allReceptions => _receptions;
  List<ProducerModel> get allProducers => _producers;
  MilkRateModel? get activeRate => _activeRate;
  SettlementPreviewResult? get preview => _preview;
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  bool get isLoading => _isLoading;
  bool get isClosing => _isClosing;
  bool get isUpdatingPayment => _isUpdatingPayment;
  bool get fromCache => _fromCache;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;

  List<SettlementModel> get filteredSettlements {
    final String q = _searchQuery.trim().toLowerCase();
    return _settlements.where((SettlementModel s) {
      if (_statusFilter != 'TODOS' &&
          s.estadoPago.toUpperCase() != _statusFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return s.nombreProductorSnap.toLowerCase().contains(q) ||
          s.cedulaProductorSnap.toLowerCase().contains(q) ||
          s.numeroComprobante.toLowerCase().contains(q) ||
          s.quincenaLabel.toLowerCase().contains(q);
    }).toList();
  }

  int get pendingCount =>
      _settlements.where((SettlementModel s) => !s.isPagada).length;

  int get paidCount =>
      _settlements.where((SettlementModel s) => s.isPagada).length;

  double get totalPendingAmount => SettlementCalculator.roundToCents(
        _settlements
            .where((SettlementModel s) => !s.isPagada)
            .fold<double>(
              0,
              (double sum, SettlementModel s) => sum + s.valorTotalPagar,
            ),
      );

  double get totalPaidAmount => SettlementCalculator.roundToCents(
        _settlements
            .where((SettlementModel s) => s.isPagada)
            .fold<double>(
              0,
              (double sum, SettlementModel s) => sum + s.valorTotalPagar,
            ),
      );

  Future<void> loadData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final settlementsRes = await _settlementService.listSettlements();
      final receptionsRes = await _receptionService.listReceptions();
      final producersRes = await _producerService.listProducers();
      final ratesRes = await _rateService.listRates();

      _settlements = settlementsRes.settlements;
      _receptions = receptionsRes.receptions;
      _producers = producersRes.producers;
      _activeRate = RateService.resolveRateForDate(
        ratesRes.rates,
        DateTime.now(),
      );
      _fromCache = settlementsRes.fromCache;
      _rebuildPreview();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setPeriod(QuincenaPeriod period) {
    _selectedPeriod = period;
    _errorMessage = null;
    _rebuildPreview();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(String filter) {
    _statusFilter = filter.toUpperCase();
    notifyListeners();
  }

  void _rebuildPreview() {
    final double price = _activeRate?.precioPorLitro ?? 0;
    _preview = _settlementService.buildPreview(
      period: _selectedPeriod,
      pricePerLiter: price,
      receptions: _receptions,
      producers: _producers,
      existingSettlements: _settlements,
    );
  }

  List<MilkReceptionModel> receptionsForSettlement(SettlementModel settlement) {
    final List<MilkReceptionModel> items = _receptions
        .where(
          (MilkReceptionModel r) =>
              r.liquidacionId == settlement.liquidacionId && !r.anulado,
        )
        .toList();
    items.sort((MilkReceptionModel a, MilkReceptionModel b) {
      final int d = a.fechaEntrega.compareTo(b.fechaEntrega);
      if (d != 0) return d;
      return a.horaEntrega.compareTo(b.horaEntrega);
    });
    return items;
  }

  ProducerModel? producerForSettlement(SettlementModel settlement) {
    for (final ProducerModel p in _producers) {
      if (p.productorId == settlement.productorId) return p;
    }
    return null;
  }

  Future<bool> executeQuincenaClose({
    required UserModel actor,
    bool blockIfUnsynced = true,
  }) async {
    _isClosing = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final double price = _activeRate?.precioPorLitro ?? 0;
      final List<SettlementModel> created =
          await _settlementService.closeQuincena(
        actor: actor,
        period: _selectedPeriod,
        pricePerLiter: price,
        receptions: _receptions,
        producers: _producers,
        existingSettlements: _settlements,
        blockIfUnsynced: blockIfUnsynced,
      );

      final settlementsRes = await _settlementService.listSettlements();
      final receptionsRes = await _receptionService.listReceptions();
      _settlements = settlementsRes.settlements;
      _receptions = receptionsRes.receptions;
      _rebuildPreview();

      _feedbackMessage =
          'Cierre quincenal completado: ${created.length} comprobante(s) emitido(s).';
      return true;
    } on SettlementServiceException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'No se pudo completar el cierre quincenal.';
      return false;
    } finally {
      _isClosing = false;
      notifyListeners();
    }
  }

  Future<bool> confirmPayment({
    required UserModel actor,
    required SettlementModel settlement,
    required String observacionPago,
  }) async {
    _isUpdatingPayment = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final SettlementModel updated = await _settlementService.markAsPaid(
        actor: actor,
        settlement: settlement,
        observacionPago: observacionPago,
      );
      _settlements = _settlements
          .map(
            (SettlementModel s) =>
                s.liquidacionId == updated.liquidacionId ? updated : s,
          )
          .toList();
      _feedbackMessage =
          'Pago confirmado para el comprobante ${updated.numeroComprobante}.';
      return true;
    } on SettlementServiceException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'No fue posible registrar la confirmación de pago.';
      return false;
    } finally {
      _isUpdatingPayment = false;
      notifyListeners();
    }
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();
  }
}
