import 'package:flutter/foundation.dart';

import '../../models/milk_rate_model.dart';
import '../../models/user_model.dart';
import '../core/services/rate_service.dart';

/// Controlador MVC para administración de tarifa histórica por litro (`RF-12`).
class RateController extends ChangeNotifier {
  RateController({
    RateService? rateService,
  }) : _rateService = rateService ?? RateService();

  final RateService _rateService;

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

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();
  }
}
