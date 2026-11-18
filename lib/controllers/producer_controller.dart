import 'package:flutter/foundation.dart';

import '../core/services/producer_service.dart';
import '../models/producer_model.dart';

enum ProducerSortColumn {
  codigo,
  nombre,
  cedula,
  finca,
  vereda,
  estado,
}

/// Controlador MVC para la gestión administrativa de productores y Habeas Data.
class ProducerController extends ChangeNotifier {
  ProducerController({ProducerService? producerService})
      : _service = producerService ?? ProducerService();

  final ProducerService _service;

  List<ProducerModel> _producers = <ProducerModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isFromOfflineCache = false;
  String? _errorMessage;
  String? _feedbackMessage;

  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL | ACTIVO | INACTIVO
  String _veredaFilter = 'ALL';
  ProducerSortColumn _sortColumn = ProducerSortColumn.codigo;
  bool _sortAscending = true;
  int _currentPage = 1;
  int _itemsPerPage = 10;

  List<ProducerModel> get allProducers => _producers;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isFromOfflineCache => _isFromOfflineCache;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;

  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  String get veredaFilter => _veredaFilter;
  ProducerSortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _statusFilter != 'ALL' ||
      _veredaFilter != 'ALL';

  int get totalCount => _producers.length;
  int get activeCount =>
      _producers.where((ProducerModel p) => p.isActivo).length;
  int get inactiveCount =>
      _producers.where((ProducerModel p) => !p.isActivo).length;
  int get linkedMobileCount => _producers
      .where(
        (ProducerModel p) => p.uidUsuario != null && p.uidUsuario!.isNotEmpty,
      )
      .length;

  List<String> get availableVeredas {
    final Set<String> set = _producers
        .map((ProducerModel p) => p.vereda.trim())
        .where((String v) => v.isNotEmpty)
        .toSet();
    final List<String> list = set.toList()..sort();
    return list;
  }

  int get veredasCount => availableVeredas.length;

  List<ProducerModel> get filteredProducers {
    final String q = _searchQuery.trim().toLowerCase();
    final List<ProducerModel> filtered = _producers.where((ProducerModel p) {
      if (_statusFilter != 'ALL' && p.estado != _statusFilter) {
        return false;
      }
      if (_veredaFilter != 'ALL' && p.vereda.trim() != _veredaFilter) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      return p.nombreCompleto.toLowerCase().contains(q) ||
          p.cedula.toLowerCase().contains(q) ||
          p.codigoAsociado.toLowerCase().contains(q) ||
          p.nombreFinca.toLowerCase().contains(q) ||
          p.vereda.toLowerCase().contains(q);
    }).toList();

    filtered.sort((ProducerModel a, ProducerModel b) {
      int cmp = 0;
      switch (_sortColumn) {
        case ProducerSortColumn.codigo:
          cmp = a.codigoAsociado
              .toLowerCase()
              .compareTo(b.codigoAsociado.toLowerCase());
          break;
        case ProducerSortColumn.nombre:
          cmp = a.nombreCompleto
              .toLowerCase()
              .compareTo(b.nombreCompleto.toLowerCase());
          break;
        case ProducerSortColumn.cedula:
          cmp = a.cedula.compareTo(b.cedula);
          break;
        case ProducerSortColumn.finca:
          cmp = a.nombreFinca
              .toLowerCase()
              .compareTo(b.nombreFinca.toLowerCase());
          break;
        case ProducerSortColumn.vereda:
          cmp = a.vereda.toLowerCase().compareTo(b.vereda.toLowerCase());
          break;
        case ProducerSortColumn.estado:
          cmp = (a.isActivo ? 0 : 1).compareTo(b.isActivo ? 0 : 1);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  int get totalPages {
    final int total = filteredProducers.length;
    if (total == 0) {
      return 1;
    }
    return (total / _itemsPerPage).ceil();
  }

  List<ProducerModel> get paginatedProducers {
    final List<ProducerModel> list = filteredProducers;
    final int safePage = _currentPage.clamp(1, totalPages);
    final int start = (safePage - 1) * _itemsPerPage;
    if (start >= list.length) {
      return const <ProducerModel>[];
    }
    final int end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  String suggestedNextCode() => _service.suggestNextCodigoAsociado(_producers);

  Future<void> loadProducers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.listProducers();
      _producers = result.producers;
      _isFromOfflineCache = result.fromCache;
      if (_veredaFilter != 'ALL' && !availableVeredas.contains(_veredaFilter)) {
        _veredaFilter = 'ALL';
      }
      _currentPage = 1;
    } catch (e) {
      _errorMessage = 'No fue posible cargar el padrón de productores: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createProducer({
    required String codigoAsociado,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String nombreFinca,
    required String vereda,
    required String estado,
    required bool aceptoHabeasData,
    required String actorUid,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final ProducerModel created = await _service.createProducer(
        codigoAsociado: codigoAsociado,
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        telefono: telefono,
        nombreFinca: nombreFinca,
        vereda: vereda,
        estado: estado,
        aceptoHabeasData: aceptoHabeasData,
        actorUid: actorUid,
        createMobileAccount: createMobileAccount,
        mobileEmail: mobileEmail,
        mobilePassword: mobilePassword,
      );
      _producers = <ProducerModel>[created, ..._producers];
      _feedbackMessage =
          'Productor "${created.nombreCompleto}" registrado correctamente.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on ProducerServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible registrar el productor: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProducer({
    required ProducerModel previous,
    required String codigoAsociado,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String nombreFinca,
    required String vereda,
    required String estado,
    required bool aceptoHabeasData,
    required String actorUid,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    notifyListeners();

    try {
      final ProducerModel updated = await _service.updateProducer(
        previous: previous,
        codigoAsociado: codigoAsociado,
        cedula: cedula,
        nombres: nombres,
        apellidos: apellidos,
        telefono: telefono,
        nombreFinca: nombreFinca,
        vereda: vereda,
        estado: estado,
        aceptoHabeasData: aceptoHabeasData,
        actorUid: actorUid,
        createMobileAccount: createMobileAccount,
        mobileEmail: mobileEmail,
        mobilePassword: mobilePassword,
      );
      _producers = _producers
          .map(
            (ProducerModel p) =>
                p.productorId == updated.productorId ? updated : p,
          )
          .toList();
      _feedbackMessage = 'Productor "${updated.nombreCompleto}" actualizado.';
      _isSaving = false;
      notifyListeners();
      return true;
    } on ProducerServiceException catch (e) {
      _errorMessage = e.message;
      _isSaving = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible actualizar el productor: $e';
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleProducerStatus({
    required ProducerModel producer,
    required String actorUid,
  }) async {
    _errorMessage = null;
    _feedbackMessage = null;
    try {
      final ProducerModel updated = await _service.toggleProducerStatus(
        producer: producer,
        actorUid: actorUid,
      );
      _producers = _producers
          .map(
            (ProducerModel p) =>
                p.productorId == updated.productorId ? updated : p,
          )
          .toList();
      _feedbackMessage = updated.isActivo
          ? 'Productor "${updated.nombreCompleto}" activado.'
          : 'Productor "${updated.nombreCompleto}" marcado como inactivo.';
      notifyListeners();
      return true;
    } on ProducerServiceException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible cambiar el estado del productor: $e';
      notifyListeners();
      return false;
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _currentPage = 1;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    _currentPage = 1;
    notifyListeners();
  }

  void setVeredaFilter(String vereda) {
    _veredaFilter = vereda;
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

  void toggleSort(ProducerSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _statusFilter = 'ALL';
    _veredaFilter = 'ALL';
    _currentPage = 1;
    notifyListeners();
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
  }
}
