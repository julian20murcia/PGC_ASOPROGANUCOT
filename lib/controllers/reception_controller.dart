import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/services/hive_service.dart';
import '../core/services/producer_service.dart';
import '../core/services/reception_service.dart';
import '../models/milk_reception_model.dart';
import '../models/producer_model.dart';
import '../models/user_model.dart';

enum ReceptionDateFilterMode { today, quincena, all }

/// Controlador MVC para captura rápida de leche en planta, alertas de duplicados y corrección auditada.
class ReceptionController extends ChangeNotifier {
  ReceptionController({
    HiveService? hiveService,
    ReceptionService? receptionService,
    ProducerService? producerService,
  })  : _hiveService = hiveService ?? HiveService(),
        _receptionService = receptionService ??
            ReceptionService(hiveService: hiveService ?? HiveService()),
        _producerService = producerService ??
            ProducerService(hiveService: hiveService ?? HiveService());

  final HiveService _hiveService;
  final ReceptionService _receptionService;
  final ProducerService _producerService;

  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
  List<ProducerModel> _activeProducers = <ProducerModel>[];
  ProducerModel? _selectedProducer;
  String _selectedShift =
      ReceptionService.defaultShiftForTime(DateTime.now());

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isOnline = true;
  bool _isFromOfflineCache = false;
  int _pendingSyncCount = 0;
  String? _errorMessage;
  String? _feedbackMessage;

  ReceptionDateFilterMode _dateFilterMode = ReceptionDateFilterMode.today;
  String _shiftFilter = 'ALL'; // ALL | MANANA | TARDE
  String _statusFilter = 'ACTIVE'; // ACTIVE | ANNULLED | ALL
  String _searchQuery = '';
  int _currentPage = 1;
  int _itemsPerPage = 12;

  List<MilkReceptionModel> get allReceptions => _receptions;
  List<ProducerModel> get activeProducers => _activeProducers;
  ProducerModel? get selectedProducer => _selectedProducer;
  String get selectedShift => _selectedShift;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  bool get isFromOfflineCache => _isFromOfflineCache;
  int get pendingSyncCount => _pendingSyncCount;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;

  ReceptionDateFilterMode get dateFilterMode => _dateFilterMode;
  String get shiftFilter => _shiftFilter;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;

  String get _todayDateStr => ReceptionService.formatDate(DateTime.now());

  double get todayTotalLiters => _receptions
      .where(
        (MilkReceptionModel r) => !r.anulado && r.fechaEntrega == _todayDateStr,
      )
      .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);

  double get todayMorningLiters => _receptions
      .where(
        (MilkReceptionModel r) =>
            !r.anulado &&
            r.fechaEntrega == _todayDateStr &&
            r.jornada == AppConstants.shiftMorning,
      )
      .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);

  double get todayAfternoonLiters => _receptions
      .where(
        (MilkReceptionModel r) =>
            !r.anulado &&
            r.fechaEntrega == _todayDateStr &&
            r.jornada == AppConstants.shiftAfternoon,
      )
      .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);

  int get todayDeliveriesCount => _receptions
      .where(
        (MilkReceptionModel r) => !r.anulado && r.fechaEntrega == _todayDateStr,
      )
      .length;

  double get quincenaTotalLiters {
    final range = ReceptionService.currentQuincenaRange(DateTime.now());
    return _receptions
        .where(
          (MilkReceptionModel r) =>
              !r.anulado &&
              r.fechaEntrega.compareTo(range.start) >= 0 &&
              r.fechaEntrega.compareTo(range.end) <= 0,
        )
        .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);
  }

  String get currentQuincenaLabel =>
      ReceptionService.currentQuincenaRange(DateTime.now()).label;

  List<MilkReceptionModel> get filteredReceptions {
    final String q = _searchQuery.trim().toLowerCase();
    final range = ReceptionService.currentQuincenaRange(DateTime.now());
    final String today = _todayDateStr;

    return _receptions.where((MilkReceptionModel r) {
      if (_dateFilterMode == ReceptionDateFilterMode.today &&
          r.fechaEntrega != today) {
        return false;
      }
      if (_dateFilterMode == ReceptionDateFilterMode.quincena &&
          (r.fechaEntrega.compareTo(range.start) < 0 ||
              r.fechaEntrega.compareTo(range.end) > 0)) {
        return false;
      }
      if (_shiftFilter != 'ALL' && r.jornada != _shiftFilter) {
        return false;
      }
      if (_statusFilter == 'ACTIVE' && r.anulado) {
        return false;
      }
      if (_statusFilter == 'ANNULLED' && !r.anulado) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      return r.nombreProductorSnap.toLowerCase().contains(q) ||
          r.codigoAsociadoSnap.toLowerCase().contains(q) ||
          r.fechaEntrega.contains(q);
    }).toList();
  }

  int get totalPages {
    final int total = filteredReceptions.length;
    return total == 0 ? 1 : (total / _itemsPerPage).ceil();
  }

  List<MilkReceptionModel> get paginatedReceptions {
    final List<MilkReceptionModel> list = filteredReceptions;
    final int safePage = _currentPage.clamp(1, totalPages);
    final int start = (safePage - 1) * _itemsPerPage;
    if (start >= list.length) {
      return const <MilkReceptionModel>[];
    }
    final int end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  List<ProducerModel> matchProducersByCodeOrQuery(String rawInput) {
    final String q = rawInput.trim().toLowerCase();
    if (q.isEmpty) {
      return _activeProducers.take(6).toList();
    }

    final List<ProducerModel> exact = <ProducerModel>[];
    final List<ProducerModel> partial = <ProducerModel>[];

    for (final ProducerModel p in _activeProducers) {
      final String code = p.codigoAsociado.toLowerCase();
      final String cedula = p.cedula.toLowerCase();
      final String name = p.nombreCompleto.toLowerCase();

      if (code == q || cedula == q) {
        exact.add(p);
      } else if (code.contains(q) ||
          cedula.contains(q) ||
          name.contains(q) ||
          p.nombreFinca.toLowerCase().contains(q)) {
        partial.add(p);
      }
    }
    return <ProducerModel>[...exact, ...partial].take(6).toList();
  }

  ProducerModel? findExactProducer(String rawInput) {
    final String q = rawInput.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final ProducerModel p in _activeProducers) {
      if (p.codigoAsociado.toLowerCase() == q || p.cedula.toLowerCase() == q) {
        return p;
      }
    }
    return null;
  }

  Future<void> loadReceptions({bool? isOnlineOverride}) async {
    _isLoading = true;
    _errorMessage = null;
    if (isOnlineOverride != null) {
      _isOnline = isOnlineOverride;
    }
    notifyListeners();

    try {
      final prodResult = await _producerService.listProducers();
      _activeProducers = prodResult.producers
          .where((ProducerModel p) => p.isActivo)
          .toList()
        ..sort(
          (ProducerModel a, ProducerModel b) =>
              a.codigoAsociado.compareTo(b.codigoAsociado),
        );

      final recResult = await _receptionService.listReceptions();
      _receptions = recResult.receptions;
      _isFromOfflineCache = recResult.fromCache;
      _pendingSyncCount = (await _hiveService.getPendingReceptions()).length;

      if (_selectedProducer != null) {
        _selectedProducer = _activeProducers.cast<ProducerModel?>().firstWhere(
              (ProducerModel? p) =>
                  p?.productorId == _selectedProducer!.productorId,
              orElse: () => null,
            );
      }
    } catch (e) {
      _errorMessage = 'No fue posible cargar las entregas: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setOnlineStatus(bool isOnline) {
    if (_isOnline != isOnline) {
      _isOnline = isOnline;
      notifyListeners();
    }
  }

  void selectProducer(ProducerModel? producer) {
    _selectedProducer = producer;
    _errorMessage = null;
    notifyListeners();
  }

  void setSelectedShift(String shift) {
    _selectedShift = shift;
    notifyListeners();
  }

  Future<({bool saved, MilkReceptionModel? duplicateFound})> registerDelivery({
    required double litros,
    required String operarioUid,
    DateTime? timestamp,
    bool allowDuplicate = false,
  }) async {
    final ProducerModel? producer = _selectedProducer;
    if (producer == null) {
      _errorMessage = 'Selecciona un productor activo antes de registrar litros.';
      notifyListeners();
      return (saved: false, duplicateFound: null);
    }

    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final MilkReceptionModel saved =
          await _receptionService.registerReception(
        producer: producer,
        litros: litros,
        jornada: _selectedShift,
        operarioUid: operarioUid,
        timestamp: timestamp,
        allowDuplicate: allowDuplicate,
        isOnline: _isOnline,
      );
      _receptions = <MilkReceptionModel>[saved, ..._receptions];
      _pendingSyncCount = (await _hiveService.getPendingReceptions()).length;
      _feedbackMessage =
          'Entrega registrada: ${saved.litros.toStringAsFixed(1)} L para ${saved.nombreProductorSnap}.';
      _selectedProducer = null;
      _isSaving = false;
      notifyListeners();
      return (saved: true, duplicateFound: null);
    } on DuplicateReceptionException catch (dup) {
      _isSaving = false;
      notifyListeners();
      return (saved: false, duplicateFound: dup.existingReception);
    } on ReceptionServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return (saved: false, duplicateFound: null);
    } catch (e) {
      _errorMessage = 'No fue posible registrar la entrega: $e';
      _isSaving = false;
      notifyListeners();
      return (saved: false, duplicateFound: null);
    }
  }

  Future<bool> editDeliveryLitros({
    required MilkReceptionModel existing,
    required double nuevosLitros,
    required String motivo,
    required UserModel actor,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final MilkReceptionModel updated =
          await _receptionService.editReceptionLitros(
        existing: existing,
        nuevosLitros: nuevosLitros,
        motivo: motivo,
        actor: actor,
      );
      _receptions = _receptions
          .map(
            (MilkReceptionModel r) =>
                r.recepcionId == updated.recepcionId ? updated : r,
          )
          .toList();
      _pendingSyncCount = (await _hiveService.getPendingReceptions()).length;
      _feedbackMessage =
          'Entrega corregida a ${updated.litros.toStringAsFixed(1)} L.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on ReceptionServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible corregir la entrega: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> annulDelivery({
    required MilkReceptionModel existing,
    required String motivo,
    required UserModel actor,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final MilkReceptionModel updated = await _receptionService.annulReception(
        existing: existing,
        motivo: motivo,
        actor: actor,
      );
      _receptions = _receptions
          .map(
            (MilkReceptionModel r) =>
                r.recepcionId == updated.recepcionId ? updated : r,
          )
          .toList();
      _pendingSyncCount = (await _hiveService.getPendingReceptions()).length;
      _feedbackMessage = 'Entrega anulada y registrada en auditoría.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on ReceptionServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible anular la entrega: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> syncPendingNow() async {
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _receptionService.syncPending();
    _pendingSyncCount = result.remainingPendingCount;
    if (result.syncedCount > 0) {
      _receptions = await _hiveService.getReceptions();
      _feedbackMessage =
          'Se sincronizaron ${result.syncedCount} entregas pendientes.';
    } else if (result.hasError) {
      _errorMessage =
          'No fue posible completar el envío. Los registros permanecen seguros en el equipo.';
    }
    _isSyncing = false;
    notifyListeners();
  }

  void setDateFilterMode(ReceptionDateFilterMode mode) {
    _dateFilterMode = mode;
    _currentPage = 1;
    notifyListeners();
  }

  void setShiftFilter(String shift) {
    _shiftFilter = shift;
    _currentPage = 1;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    _currentPage = 1;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 1;
    notifyListeners();
  }

  void setItemsPerPage(int value) {
    _itemsPerPage = value;
    _currentPage = 1;
    notifyListeners();
  }

  void setPage(int page) {
    _currentPage = page.clamp(1, totalPages);
    notifyListeners();
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
  }
}
