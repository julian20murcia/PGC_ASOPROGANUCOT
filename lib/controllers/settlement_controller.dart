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
  List<MilkRateModel> _rates = <MilkRateModel>[];
  SettlementPreviewResult? _preview;
  int _lastClosedCount = 0;
  bool _loadedOnce = false;

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
  List<MilkRateModel> get rates => _rates;

  /// Comprobantes emitidos en el último cierre exitoso.
  int get lastClosedCount => _lastClosedCount;

  /// true después de la primera carga (aunque haya fallado).
  bool get loadedOnce => _loadedOnce;
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
      // Las cuatro consultas son independientes: en paralelo.
      final settlementsF = _settlementService.listSettlements();
      final receptionsF = _receptionService.listReceptions();
      final producersF = _producerService.listProducers();
      final ratesF = _rateService.listRates();
      final settlementsRes = await settlementsF;
      final receptionsRes = await receptionsF;
      final producersRes = await producersF;
      final ratesRes = await ratesF;

      _settlements = settlementsRes.settlements;
      _receptions = receptionsRes.receptions;
      _producers = producersRes.producers;
      _rates = ratesRes.rates;
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
      _loadedOnce = true;
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

  /// Ejecuta el cierre del período seleccionado (o de [period] si se indica).
  ///
  /// [excludedProducerIds] deja fuera del cierre a esos productores: sus
  /// entregas permanecen abiertas para un cierre posterior.
  Future<bool> executeQuincenaClose({
    required UserModel actor,
    bool blockIfUnsynced = true,
    QuincenaPeriod? period,
    Set<String> excludedProducerIds = const <String>{},
  }) async {
    if (period != null) _selectedPeriod = period;
    _isClosing = true;
    _errorMessage = null;
    _feedbackMessage = null;
    _lastClosedCount = 0;
    notifyListeners();

    try {
      final double price = _activeRate?.precioPorLitro ?? 0;
      final List<MilkReceptionModel> scoped = excludedProducerIds.isEmpty
          ? _receptions
          : _receptions
              .where((MilkReceptionModel r) =>
                  !excludedProducerIds.contains(r.productorId))
              .toList();
      final List<SettlementModel> created =
          await _settlementService.closeQuincena(
        actor: actor,
        period: _selectedPeriod,
        pricePerLiter: price,
        receptions: scoped,
        producers: _producers,
        existingSettlements: _settlements,
        blockIfUnsynced: blockIfUnsynced,
      );

      final settlementsRes = await _settlementService.listSettlements();
      final receptionsRes = await _receptionService.listReceptions();
      _settlements = settlementsRes.settlements;
      _receptions = receptionsRes.receptions;
      _rebuildPreview();

      _lastClosedCount = created.length;
      _feedbackMessage =
          'Cierre quincenal completado: ${created.length} comprobante(s) emitido(s).';
      return true;
    } on SettlementServiceException catch (e) {
      try {
        _settlements = (await _settlementService.listSettlements()).settlements;
        _receptions = (await _receptionService.listReceptions()).receptions;
        _rebuildPreview();
      } catch (_) {}
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
    DateTime? fechaPago,
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
        fechaPago: fechaPago,
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

  // ── Consultas para la vista de quincenas ────────────────────────────────

  /// Previsualización de cierre para un período arbitrario (no altera el
  /// período seleccionado). Usa la tarifa vigente actual, igual que el cierre.
  SettlementPreviewResult previewForPeriod(
    QuincenaPeriod period, {
    Set<String> excludedProducerIds = const <String>{},
  }) {
    return _settlementService.buildPreview(
      period: period,
      pricePerLiter: _activeRate?.precioPorLitro ?? 0,
      receptions: excludedProducerIds.isEmpty
          ? _receptions
          : _receptions
              .where((MilkReceptionModel r) =>
                  !excludedProducerIds.contains(r.productorId))
              .toList(),
      producers: _producers,
      existingSettlements: _settlements,
    );
  }

  /// Quincenas cerradas agrupadas por período, de la más reciente a la más antigua.
  // Memo: agrupar todas las liquidaciones en cada build era costoso.
  List<SettlementModel>? _groupsSource;
  List<SettlementPeriodGroup> _groupsCache = const <SettlementPeriodGroup>[];

  List<SettlementPeriodGroup> get periodGroups {
    if (!identical(_groupsSource, _settlements)) {
      _groupsSource = _settlements;
      _groupsCache = SettlementPeriodGroup.groupAll(_settlements);
    }
    return _groupsCache;
  }

  /// Liquidaciones ya emitidas que se cruzan con [period].
  List<SettlementModel> settlementsOverlapping(QuincenaPeriod period) => _settlements
      .where((SettlementModel s) => period.overlapsWith(s.periodoInicio, s.periodoFin))
      .toList();

  /// Recepciones (no anuladas) amarradas a las liquidaciones del grupo.
  List<MilkReceptionModel> receptionsForGroup(SettlementPeriodGroup group) {
    final Set<String> ids =
        group.settlements.map((SettlementModel s) => s.liquidacionId).toSet();
    return _receptions
        .where((MilkReceptionModel r) =>
            !r.anulado && r.liquidacionId != null && ids.contains(r.liquidacionId))
        .toList();
  }

  /// Recepciones válidas (no anuladas) dentro de [period], liquidadas o no.
  List<MilkReceptionModel> receptionsInPeriod(QuincenaPeriod period) => _receptions
      .where((MilkReceptionModel r) => !r.anulado && period.containsIsoDate(r.fechaEntrega))
      .toList();

  /// Litros válidos registrados en la quincena en curso (para simular tarifas).
  double get currentPeriodLiters {
    final QuincenaPeriod p = QuincenaPeriod.currentForDate(DateTime.now());
    final int thousandths = receptionsInPeriod(p)
        .fold<int>(0, (int s, MilkReceptionModel r) => s + (r.litros * 1000).round());
    return thousandths / 1000.0;
  }

  /// Tarifas distintas a la vigente que rigieron durante [period].
  List<MilkRateModel> otherRatesDuring(QuincenaPeriod period) {
    final DateTime? start = DateTime.tryParse(period.startDate);
    final DateTime? end = DateTime.tryParse(period.endDate);
    if (start == null || end == null) return const <MilkRateModel>[];
    final DateTime endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return _rates.where((MilkRateModel r) {
      if (r.tarifaId == _activeRate?.tarifaId) return false;
      if ((r.precioPorLitro - (_activeRate?.precioPorLitro ?? 0)).abs() < 0.005) {
        return false;
      }
      final DateTime rs = r.fechaInicioVigencia.toLocal();
      final DateTime? re = r.fechaFinVigencia?.toLocal();
      return !rs.isAfter(endOfDay) && (re == null || !re.isBefore(start));
    }).toList();
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();
  }
}
