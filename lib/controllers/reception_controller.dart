import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/services/hive_service.dart';
import '../core/services/producer_service.dart';
import '../core/services/reception_service.dart';
import '../models/milk_reception_model.dart';
import '../models/producer_model.dart';
import '../models/user_model.dart';

enum ReceptionDateFilterMode { today, quincena, all }

enum ReceptionViewMode { matrix, list }

/// Fila agrupada por productor para la planilla estilo EvolMilk por días de la quincena.
class ReceptionMatrixRow {
  const ReceptionMatrixRow({
    required this.producer,
    required this.receptionsByDate,
    required this.allReceptionsByDate,
  });

  final ProducerModel producer;
  final Map<String, List<MilkReceptionModel>> receptionsByDate;
  final Map<String, List<MilkReceptionModel>> allReceptionsByDate;

  double litersForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null || items.isEmpty) return 0.0;
    return items.fold<double>(
      0.0,
      (double acc, MilkReceptionModel r) => acc + r.litros,
    );
  }

  double morningLitersForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null || items.isEmpty) return 0.0;
    return items
        .where((MilkReceptionModel r) => r.jornada == AppConstants.shiftMorning)
        .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);
  }

  double afternoonLitersForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null || items.isEmpty) return 0.0;
    return items
        .where(
          (MilkReceptionModel r) => r.jornada == AppConstants.shiftAfternoon,
        )
        .fold<double>(0.0, (double acc, MilkReceptionModel r) => acc + r.litros);
  }

  double get totalLiters {
    double sum = 0.0;
    for (final List<MilkReceptionModel> dayItems in receptionsByDate.values) {
      for (final MilkReceptionModel r in dayItems) {
        sum += r.litros;
      }
    }
    return sum;
  }

  int get deliveryCount {
    int count = 0;
    for (final List<MilkReceptionModel> dayItems in receptionsByDate.values) {
      count += dayItems.length;
    }
    return count;
  }

  bool hasPendingSyncForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null) return false;
    return items.any((MilkReceptionModel r) => !r.isSynced);
  }

  bool hasLiquidatedForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null) return false;
    return items.any((MilkReceptionModel r) => r.isLiquidada);
  }

  bool hasEditedForDate(String date) {
    final List<MilkReceptionModel>? items = receptionsByDate[date];
    if (items == null) return false;
    return items.any((MilkReceptionModel r) => r.updatedAt != null);
  }

  List<MilkReceptionModel> entriesForDate(String date) =>
      allReceptionsByDate[date] ?? const <MilkReceptionModel>[];
}

/// Controlador MVC para captura rápida de leche en planta, planilla por días y corrección auditada.
class ReceptionController extends ChangeNotifier {
  ReceptionController({
    HiveService? hiveService,
    ReceptionService? receptionService,
    ProducerService? producerService,
  })  : _hiveService = hiveService ?? HiveService(),
        _receptionService = receptionService ??
            ReceptionService(hiveService: hiveService ?? HiveService()),
        _producerService = producerService ??
            ProducerService(hiveService: hiveService ?? HiveService()) {
    final DateTime now = DateTime.now().toLocal();
    _matrixYear = now.year;
    _matrixMonth = now.month;
    _matrixFirstHalf = now.day <= 15;
  }

  final HiveService _hiveService;
  final ReceptionService _receptionService;
  final ProducerService _producerService;

  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
  List<ProducerModel> _activeProducers = <ProducerModel>[];
  Map<String, ProducerModel> _producersById = <String, ProducerModel>{};
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

  ReceptionViewMode _viewMode = ReceptionViewMode.matrix;
  late int _matrixYear;
  late int _matrixMonth;
  late bool _matrixFirstHalf;
  int _matrixPage = 1;
  int _matrixRowsPerPage = 25;

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

  ReceptionViewMode get viewMode => _viewMode;
  int get matrixYear => _matrixYear;
  int get matrixMonth => _matrixMonth;
  bool get matrixFirstHalf => _matrixFirstHalf;
  int get matrixPage => _matrixPage;
  int get matrixRowsPerPage => _matrixRowsPerPage;

  ReceptionDateFilterMode get dateFilterMode => _dateFilterMode;
  String get shiftFilter => _shiftFilter;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;

  String get _todayDateStr => ReceptionService.formatDate(DateTime.now());

  static String formatDate(DateTime dt) => ReceptionService.formatDate(dt);
  static String shortMonthName(int month) =>
      ReceptionService.shortMonthName(month);

  ({
    String start,
    String end,
    String label,
    String rangeLabel,
    List<DateTime> days,
  }) get _matrixQuincena => ReceptionService.quincenaRangeFor(
        _matrixYear,
        _matrixMonth,
        _matrixFirstHalf,
      );

  List<DateTime> get matrixDays => _matrixQuincena.days;
  String get matrixQuincenaLabel => _matrixQuincena.label;
  String get matrixRangeLabel => _matrixQuincena.rangeLabel;

  bool get isCurrentMatrixQuincena {
    final DateTime now = DateTime.now().toLocal();
    return _matrixYear == now.year &&
        _matrixMonth == now.month &&
        _matrixFirstHalf == (now.day <= 15);
  }

  bool get canGoNextMatrixQuincena {
    final DateTime now = DateTime.now().toLocal();
    final bool nowFirstHalf = now.day <= 15;
    if (_matrixYear < now.year) return true;
    if (_matrixYear > now.year) return false;
    if (_matrixMonth < now.month) return true;
    if (_matrixMonth > now.month) return false;
    return _matrixFirstHalf && !nowFirstHalf;
  }

  List<ReceptionMatrixRow> get matrixRows {
    final range = _matrixQuincena;
    final Map<String, Map<String, List<MilkReceptionModel>>> activeByProducer =
        <String, Map<String, List<MilkReceptionModel>>>{};
    final Map<String, Map<String, List<MilkReceptionModel>>> allByProducer =
        <String, Map<String, List<MilkReceptionModel>>>{};
    final Map<String, MilkReceptionModel> sampleByProducer =
        <String, MilkReceptionModel>{};

    for (final MilkReceptionModel r in _receptions) {
      if (r.fechaEntrega.compareTo(range.start) < 0 ||
          r.fechaEntrega.compareTo(range.end) > 0) {
        continue;
      }

      allByProducer
          .putIfAbsent(
            r.productorId,
            () => <String, List<MilkReceptionModel>>{},
          )
          .putIfAbsent(r.fechaEntrega, () => <MilkReceptionModel>[])
          .add(r);

      if (r.anulado) continue;

      sampleByProducer.putIfAbsent(r.productorId, () => r);
      if (_shiftFilter != 'ALL' && r.jornada != _shiftFilter) {
        continue;
      }

      activeByProducer
          .putIfAbsent(
            r.productorId,
            () => <String, List<MilkReceptionModel>>{},
          )
          .putIfAbsent(r.fechaEntrega, () => <MilkReceptionModel>[])
          .add(r);
    }

    final Map<String, ProducerModel> pool = <String, ProducerModel>{};
    for (final ProducerModel p in _activeProducers) {
      pool[p.productorId] = p;
    }

    // Incluir también productores inactivos que tuvieron entregas activas en esa quincena.
    for (final MapEntry<String, MilkReceptionModel> entry
        in sampleByProducer.entries) {
      if (pool.containsKey(entry.key)) continue;
      final ProducerModel? known = _producersById[entry.key];
      if (known != null) {
        pool[entry.key] = known;
      } else {
        final MilkReceptionModel snap = entry.value;
        final List<String> parts = snap.nombreProductorSnap
            .trim()
            .split(RegExp(r'\s+'))
            .where((String s) => s.isNotEmpty)
            .toList();
        final String nombres = parts.isEmpty ? snap.codigoAsociadoSnap : parts.first;
        final String apellidos =
            parts.length > 1 ? parts.sublist(1).join(' ') : '';
        pool[entry.key] = ProducerModel(
          productorId: entry.key,
          codigoAsociado: snap.codigoAsociadoSnap,
          cedula: '',
          nombres: nombres,
          apellidos: apellidos,
          telefono: '',
          nombreFinca: 'Finca asociada',
          vereda: 'Susa',
          estado: 'INACTIVO',
          aceptoHabeasData: true,
          fechaCreacion: snap.createdAt,
        );
      }
    }

    final String q = _searchQuery.trim().toLowerCase();
    final List<ProducerModel> producers = pool.values.where((ProducerModel p) {
      if (q.isEmpty) return true;
      return p.codigoAsociado.toLowerCase().contains(q) ||
          p.nombreCompleto.toLowerCase().contains(q) ||
          p.cedula.toLowerCase().contains(q) ||
          p.nombreFinca.toLowerCase().contains(q) ||
          p.vereda.toLowerCase().contains(q);
    }).toList()
      ..sort(
        (ProducerModel a, ProducerModel b) => a.codigoAsociado
            .toLowerCase()
            .compareTo(b.codigoAsociado.toLowerCase()),
      );

    return producers.map((ProducerModel p) {
      final Map<String, List<MilkReceptionModel>> filteredMap =
          activeByProducer[p.productorId] ??
              const <String, List<MilkReceptionModel>>{};
      final Map<String, List<MilkReceptionModel>> fullMap =
          allByProducer[p.productorId] ??
              const <String, List<MilkReceptionModel>>{};
      return ReceptionMatrixRow(
        producer: p,
        receptionsByDate: filteredMap,
        allReceptionsByDate: fullMap,
      );
    }).toList();
  }

  int get matrixTotalPages {
    final int total = matrixRows.length;
    return total == 0 ? 1 : (total / _matrixRowsPerPage).ceil();
  }

  List<ReceptionMatrixRow> get paginatedMatrixRows {
    final List<ReceptionMatrixRow> list = matrixRows;
    final int safePage = _matrixPage.clamp(1, matrixTotalPages);
    final int start = (safePage - 1) * _matrixRowsPerPage;
    if (start >= list.length) {
      return const <ReceptionMatrixRow>[];
    }
    final int end = (start + _matrixRowsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  Map<String, double> get matrixDayTotals {
    final Map<String, double> totals = <String, double>{
      for (final DateTime day in matrixDays)
        ReceptionService.formatDate(day): 0.0,
    };
    for (final ReceptionMatrixRow row in matrixRows) {
      for (final String dateKey in totals.keys) {
        totals[dateKey] = (totals[dateKey] ?? 0.0) + row.litersForDate(dateKey);
      }
    }
    return totals;
  }

  double get matrixGrandTotal => matrixRows.fold<double>(
        0.0,
        (double acc, ReceptionMatrixRow row) => acc + row.totalLiters,
      );

  int get matrixTotalDeliveries => matrixRows.fold<int>(
        0,
        (int acc, ReceptionMatrixRow row) => acc + row.deliveryCount,
      );

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
      _producersById = <String, ProducerModel>{
        for (final ProducerModel p in prodResult.producers) p.productorId: p,
      };
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

  /// Registra una entrega desde una celda específica de la planilla sin alterar la captura superior.
  Future<({bool saved, MilkReceptionModel? duplicateFound})>
      registerDeliveryForProducer({
    required ProducerModel producer,
    required double litros,
    required String jornada,
    required String operarioUid,
    required String fechaEntrega,
    DateTime? timestamp,
    bool allowDuplicate = false,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final MilkReceptionModel saved =
          await _receptionService.registerReception(
        producer: producer,
        litros: litros,
        jornada: jornada,
        operarioUid: operarioUid,
        timestamp: timestamp,
        fechaEntregaOverride: fechaEntrega,
        allowDuplicate: allowDuplicate,
        isOnline: _isOnline,
      );
      _receptions = <MilkReceptionModel>[saved, ..._receptions];
      _pendingSyncCount = (await _hiveService.getPendingReceptions()).length;
      _feedbackMessage =
          'Entrega registrada ($fechaEntrega): ${saved.litros.toStringAsFixed(1)} L para ${saved.nombreProductorSnap}.';
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

  void setViewMode(ReceptionViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
  }

  void previousMatrixQuincena() {
    if (_matrixFirstHalf) {
      if (_matrixMonth == 1) {
        _matrixMonth = 12;
        _matrixYear--;
      } else {
        _matrixMonth--;
      }
      _matrixFirstHalf = false;
    } else {
      _matrixFirstHalf = true;
    }
    _matrixPage = 1;
    notifyListeners();
  }

  void nextMatrixQuincena() {
    if (!canGoNextMatrixQuincena) return;
    if (!_matrixFirstHalf) {
      if (_matrixMonth == 12) {
        _matrixMonth = 1;
        _matrixYear++;
      } else {
        _matrixMonth++;
      }
      _matrixFirstHalf = true;
    } else {
      _matrixFirstHalf = false;
    }
    _matrixPage = 1;
    notifyListeners();
  }

  void goToCurrentMatrixQuincena() {
    final DateTime now = DateTime.now().toLocal();
    _matrixYear = now.year;
    _matrixMonth = now.month;
    _matrixFirstHalf = now.day <= 15;
    _matrixPage = 1;
    notifyListeners();
  }

  void setMatrixPage(int page) {
    _matrixPage = page.clamp(1, matrixTotalPages);
    notifyListeners();
  }

  void setMatrixRowsPerPage(int rows) {
    _matrixRowsPerPage = rows;
    _matrixPage = 1;
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
    _matrixPage = 1;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    _currentPage = 1;
    _matrixPage = 1;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 1;
    _matrixPage = 1;
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
