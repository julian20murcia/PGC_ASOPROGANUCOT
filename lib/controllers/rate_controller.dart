import 'package:flutter/foundation.dart';

import '../../models/milk_rate_model.dart';
import '../../models/user_model.dart';
import '../core/security/permissions.dart';
import '../core/services/finance_config_service.dart';
import '../core/services/rate_service.dart';

/// Controlador MVC para administración de tarifa histórica por litro (`RF-12`).
class RateController extends ChangeNotifier {
  RateController({
    RateService? rateService,
    FinanceConfigService? financeService,
  })  : _rateService = rateService ?? RateService(),
        _financeService = financeService ?? FinanceConfigService();

  final RateService _rateService;
  final FinanceConfigService _financeService;

  FinanceConfig _finance = FinanceConfig.empty;
  bool _financeLoaded = false;
  bool _isSavingFinance = false;

  /// Parámetros financieros (precio de venta a la industria y costo operativo).
  FinanceConfig get finance => _finance;
  bool get financeLoaded => _financeLoaded;
  bool get isSavingFinance => _isSavingFinance;

  List<MilkRateModel> _rates = <MilkRateModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _fromCache = false;
  String? _errorMessage;
  String? _feedbackMessage;

  List<MilkRateModel> get rates => _rates;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get fromCache => _fromCache;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;

  MilkRateModel? get activeRate {
    for (final MilkRateModel r in _rates) {
      if (r.activa) return r;
    }
    return _rates.isEmpty ? null : _rates.first;
  }

  MilkRateModel? get previousRate {
    final MilkRateModel? current = activeRate;
    if (current == null) return null;
    for (final MilkRateModel r in _rates) {
      if (r.tarifaId != current.tarifaId) return r;
    }
    return null;
  }

  double get effectivePricePerLiter => activeRate?.precioPorLitro ?? 0;

  double? get variationAmount {
    final MilkRateModel? current = activeRate;
    final MilkRateModel? prev = previousRate;
    if (current == null || prev == null) return null;
    return current.precioPorLitro - prev.precioPorLitro;
  }

  double? get variationPercent {
    final MilkRateModel? prev = previousRate;
    final double? diff = variationAmount;
    if (prev == null || diff == null || prev.precioPorLitro <= 0) return null;
    return (diff / prev.precioPorLitro) * 100;
  }

  Future<void> loadRates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _rateService.listRates();
      _rates = result.rates;
      _fromCache = result.fromCache;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createRate({
    required UserModel actor,
    required double precioPorLitro,
    required DateTime fechaInicioVigencia,
    required String observacion,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final MilkRateModel created = await _rateService.createNewRate(
        actor: actor,
        precioPorLitro: precioPorLitro,
        fechaInicioVigencia: fechaInicioVigencia,
        observacion: observacion,
      );
      final result = await _rateService.listRates();
      _rates = result.rates;
      _fromCache = result.fromCache;
      _feedbackMessage =
          'Nueva tarifa registrada vigente desde el ${created.fechaInicioVigencia.toLocal().day.toString().padLeft(2, '0')}/${created.fechaInicioVigencia.toLocal().month.toString().padLeft(2, '0')}/${created.fechaInicioVigencia.toLocal().year}.';
      return true;
    } on RateServiceException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'No se pudo actualizar la tarifa por litro.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Historial en orden cronológico ascendente (para la gráfica escalonada).
  List<MilkRateModel> get chronological {
    final List<MilkRateModel> copy = List<MilkRateModel>.from(_rates)
      ..sort((MilkRateModel a, MilkRateModel b) =>
          a.fechaInicioVigencia.compareTo(b.fechaInicioVigencia));
    return copy;
  }

  /// Tarifa inmediatamente anterior (cronológicamente) a [rate].
  MilkRateModel? predecessorOf(MilkRateModel rate) {
    MilkRateModel? prev;
    for (final MilkRateModel r in chronological) {
      if (r.tarifaId == rate.tarifaId) return prev;
      prev = r;
    }
    return null;
  }

  /// Impacto de un precio sobre una cantidad de litros frente a la tarifa vigente.
  static ({double cost, double currentCost, double diff, double? percent}) impact({
    required double liters,
    required double newPrice,
    required double currentPrice,
  }) {
    int cents(double price) => ((liters * 1000).round() * (price * 100).round() / 1000).round();
    final int a = cents(newPrice);
    final int b = cents(currentPrice);
    return (
      cost: a / 100.0,
      currentCost: b / 100.0,
      diff: (a - b) / 100.0,
      percent: currentPrice > 0 ? ((newPrice - currentPrice) / currentPrice) * 100 : null,
    );
  }

  Future<void> loadFinance() async {
    _finance = await _financeService.load();
    _financeLoaded = true;
    notifyListeners();
  }

  /// Guarda los parámetros financieros. Devuelve `null` si todo salió bien o
  /// el mensaje de error.
  Future<String?> saveFinance({
    required UserModel actor,
    required double precioVentaLitro,
    required double costoOperativoMensual,
  }) async {
    if (!actor.can(Permissions.tarifas, PermAction.crear)) {
      return 'Tu usuario no tiene permiso para cambiar los parámetros financieros.';
    }
    _isSavingFinance = true;
    notifyListeners();
    try {
      await _financeService.save(
        precioVentaLitro: precioVentaLitro,
        costoOperativoMensual: costoOperativoMensual,
        actorUid: actor.uid,
      );
      _finance = FinanceConfig(
        precioVentaLitro: precioVentaLitro,
        costoOperativoMensual: costoOperativoMensual,
        actualizadoEn: DateTime.now().toUtc(),
        actualizadoPorUid: actor.uid,
      );
      return null;
    } on ArgumentError catch (e) {
      return e.message?.toString() ?? 'Valores fuera de rango.';
    } catch (_) {
      return 'No se pudieron guardar los parámetros. Verifica la conexión y los permisos.';
    } finally {
      _isSavingFinance = false;
      notifyListeners();
    }
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();
  }
}
