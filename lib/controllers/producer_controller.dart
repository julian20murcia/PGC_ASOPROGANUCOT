import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/services/producer_service.dart';
import '../models/milk_reception_model.dart';
import '../models/privacy_notice.dart';
import '../models/producer_model.dart';
import '../views/shared/widgets/app_date_range_picker.dart';

/// Criterios de orden del padrón.
enum ProducerSortOption {
  recientes,
  antiguos,
  masLeche,
  menosLeche,
  nombre,
  codigo,
}

extension ProducerSortOptionX on ProducerSortOption {
  String get label => switch (this) {
    ProducerSortOption.recientes => 'Más recientes',
    ProducerSortOption.antiguos => 'Más antiguos',
    ProducerSortOption.masLeche => 'Más leche entregada',
    ProducerSortOption.menosLeche => 'Menos leche entregada',
    ProducerSortOption.nombre => 'Nombre A–Z',
    ProducerSortOption.codigo => 'Código',
  };

  /// Indica si el orden depende de las entregas del período.
  bool get usesDeliveries =>
      this == ProducerSortOption.masLeche ||
      this == ProducerSortOption.menosLeche;
}

/// Resumen de entregas de un productor en el período seleccionado.
@immutable
class ProducerDeliveryStats {
  const ProducerDeliveryStats({
    this.liters = 0,
    this.deliveries = 0,
    this.morningLiters = 0,
    this.afternoonLiters = 0,
    this.lastDeliveryIso,
  });

  static const ProducerDeliveryStats empty = ProducerDeliveryStats();

  /// Litros dentro del período.
  final double liters;
  final int deliveries;
  final double morningLiters;
  final double afternoonLiters;

  /// Última entrega conocida dentro de la ventana consultada (período ∪ últimos 30 días).
  final String? lastDeliveryIso;

  double get averagePerDelivery => deliveries == 0 ? 0 : liters / deliveries;
}

/// Punto diario para la mini gráfica del panel de detalle.
@immutable
class DailyLiters {
  const DailyLiters(this.day, this.liters);
  final DateTime day;
  final double liters;
}

/// Estadísticas completas de un productor para el panel de detalle.
@immutable
class ProducerDetailStats {
  const ProducerDetailStats({
    required this.period,
    required this.last30Days,
    required this.recent,
  });

  final ProducerDeliveryStats period;
  final List<DailyLiters> last30Days;
  final List<MilkReceptionModel> recent;

  double get last30Total =>
      last30Days.fold<double>(0, (double s, DailyLiters d) => s + d.liters);
}

/// Controlador MVC para la gestión administrativa de productores y Habeas Data.
class ProducerController extends ChangeNotifier {
  ProducerController({
    ProducerService? producerService,
    Future<PrivacyNotice> Function()? privacyNoticeLoader,
    DateTime Function()? clock,
  }) : _service = producerService ?? ProducerService(),
       loadPrivacyNotice = privacyNoticeLoader ?? PrivacyNotice.load,
       _clock = clock ?? DateTime.now {
    _period = DateRangePresets.monthOf(_clock());
  }

  final ProducerService _service;
  final Future<PrivacyNotice> Function() loadPrivacyNotice;
  final DateTime Function() _clock;

  List<ProducerModel> _producers = <ProducerModel>[];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isFromOfflineCache = false;
  String? _errorMessage;
  String? _feedbackMessage;
  ProducerModel? _lastSaved;

  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL | ACTIVO | INACTIVO
  String _veredaFilter = 'ALL';
  ProducerSortOption _sort = ProducerSortOption.recientes;

  late DateRangeValue _period;
  List<MilkReceptionModel> _deliveries = <MilkReceptionModel>[];
  Map<String, ProducerDeliveryStats> _stats = <String, ProducerDeliveryStats>{};
  bool _isLoadingDeliveries = false;
  bool _deliveriesFromCache = false;
  bool _deliveriesLoaded = false;
  int _deliveriesRequest = 0;

  List<ProducerModel> get allProducers => _producers;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isFromOfflineCache => _isFromOfflineCache;
  String? get errorMessage => _errorMessage;
  String? get feedbackMessage => _feedbackMessage;
  ProducerModel? get lastSavedProducer => _lastSaved;

  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  String get veredaFilter => _veredaFilter;
  ProducerSortOption get sort => _sort;

  /// Cambia cada vez que se limpian los filtros (para reiniciar el buscador).
  int get filtersVersion => _filtersVersion;
  int _filtersVersion = 0;

  DateRangeValue get period => _period;
  bool get isLoadingDeliveries => _isLoadingDeliveries;
  bool get deliveriesFromCache => _deliveriesFromCache;
  bool get deliveriesLoaded => _deliveriesLoaded;

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _statusFilter != 'ALL' ||
      _veredaFilter != 'ALL';

  int get totalCount => _producers.length;
  int get activeCount =>
      _producers.where((ProducerModel p) => p.isActivo).length;
  int get inactiveCount =>
      _producers.where((ProducerModel p) => !p.isActivo).length;
  int get linkedMobileCount =>
      _producers.where((ProducerModel p) => hasAppAccess(p)).length;

  static bool hasAppAccess(ProducerModel p) =>
      p.uidUsuario != null && p.uidUsuario!.trim().isNotEmpty;

  List<String> get availableVeredas {
    final Map<String, String> unique = <String, String>{};
    for (final ProducerModel p in _producers) {
      final String v = p.vereda.trim();
      if (v.isEmpty) continue;
      unique.putIfAbsent(v.toLowerCase(), () => v);
    }
    final List<String> list = unique.values.toList()
      ..sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    return list;
  }

  int get veredasCount => availableVeredas.length;

  /// Veredas existentes que coinciden con lo escrito (para autocompletar).
  List<String> veredaSuggestions(String query) {
    final String q = _fold(query.trim());
    final List<String> all = availableVeredas;
    if (q.isEmpty) return all;
    return all.where((String v) => _fold(v).contains(q)).toList();
  }

  ProducerDeliveryStats statsFor(String productorId) =>
      _stats[productorId] ?? ProducerDeliveryStats.empty;

  double get periodLiters => _stats.values.fold<double>(
    0,
    (double s, ProducerDeliveryStats e) => s + e.liters,
  );

  int get periodDeliveries => _stats.values.fold<int>(
    0,
    (int s, ProducerDeliveryStats e) => s + e.deliveries,
  );

  /// Productores activos sin entregas en el período.
  int get activeWithoutDeliveries => _producers
      .where(
        (ProducerModel p) =>
            p.isActivo && statsFor(p.productorId).deliveries == 0,
      )
      .length;

  List<ProducerModel> get filteredProducers {
    final String q = _fold(_searchQuery.trim());
    final List<ProducerModel> filtered = _producers.where((ProducerModel p) {
      if (_statusFilter != 'ALL' && p.estado != _statusFilter) return false;
      if (_veredaFilter != 'ALL' &&
          p.vereda.trim().toLowerCase() != _veredaFilter.toLowerCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      return _fold(p.nombreCompleto).contains(q) ||
          p.cedula.contains(q) ||
          p.telefono.contains(q) ||
          _fold(p.codigoAsociado).contains(q) ||
          _fold(p.nombreFinca).contains(q) ||
          _fold(p.vereda).contains(q);
    }).toList();
    return sortProducers(filtered, _sort, _stats);
  }

  /// Ordena una lista de productores según [option]. Función pura (testeable).
  static List<ProducerModel> sortProducers(
    List<ProducerModel> input,
    ProducerSortOption option,
    Map<String, ProducerDeliveryStats> stats,
  ) {
    final List<ProducerModel> list = List<ProducerModel>.of(input);
    int byName(ProducerModel a, ProducerModel b) =>
        _fold(a.nombreCompleto).compareTo(_fold(b.nombreCompleto));
    double liters(ProducerModel p) => stats[p.productorId]?.liters ?? 0;

    list.sort((ProducerModel a, ProducerModel b) {
      final int cmp = switch (option) {
        ProducerSortOption.recientes => b.fechaCreacion.compareTo(
          a.fechaCreacion,
        ),
        ProducerSortOption.antiguos => a.fechaCreacion.compareTo(
          b.fechaCreacion,
        ),
        ProducerSortOption.masLeche => liters(b).compareTo(liters(a)),
        ProducerSortOption.menosLeche => liters(a).compareTo(liters(b)),
        ProducerSortOption.nombre => byName(a, b),
        ProducerSortOption.codigo => compareCodes(
          a.codigoAsociado,
          b.codigoAsociado,
        ),
      };
      return cmp != 0 ? cmp : byName(a, b);
    });
    return list;
  }

  /// Compara códigos de forma natural: ASO-2 < ASO-10.
  static int compareCodes(String a, String b) {
    final RegExp re = RegExp(r'^(.*?)(\d+)$');
    final RegExpMatch? ma = re.firstMatch(a.trim().toUpperCase());
    final RegExpMatch? mb = re.firstMatch(b.trim().toUpperCase());
    if (ma != null && mb != null) {
      final int prefix = ma.group(1)!.compareTo(mb.group(1)!);
      if (prefix != 0) return prefix;
      final BigInt na = BigInt.parse(ma.group(2)!);
      final BigInt nb = BigInt.parse(mb.group(2)!);
      return na.compareTo(nb);
    }
    return a.toUpperCase().compareTo(b.toUpperCase());
  }

  /// Agrega entregas por productor. Solo suma litros dentro de
  /// [startIso]..[endIso]; la última entrega considera todas las recibidas.
  static Map<String, ProducerDeliveryStats> aggregateDeliveries(
    Iterable<MilkReceptionModel> deliveries, {
    required String startIso,
    required String endIso,
  }) {
    final Map<String, _StatsAccumulator> acc = <String, _StatsAccumulator>{};
    for (final MilkReceptionModel r in deliveries) {
      if (r.anulado) continue;
      final _StatsAccumulator a = acc.putIfAbsent(
        r.productorId,
        () => _StatsAccumulator(),
      );
      if (a.last == null || r.fechaEntrega.compareTo(a.last!) > 0) {
        a.last = r.fechaEntrega;
      }
      final bool inPeriod =
          r.fechaEntrega.compareTo(startIso) >= 0 &&
          r.fechaEntrega.compareTo(endIso) <= 0;
      if (!inPeriod) continue;
      final double l = r.litros.isFinite ? r.litros : 0;
      a.liters += l;
      a.count++;
      if (r.jornada.toUpperCase() == AppConstants.shiftAfternoon) {
        a.afternoon += l;
      } else {
        a.morning += l;
      }
    }
    return acc.map(
      (String id, _StatsAccumulator a) =>
          MapEntry<String, ProducerDeliveryStats>(
            id,
            ProducerDeliveryStats(
              liters: a.liters,
              deliveries: a.count,
              morningLiters: a.morning,
              afternoonLiters: a.afternoon,
              lastDeliveryIso: a.last,
            ),
          ),
    );
  }

  /// Estadísticas para el panel lateral del productor.
  ProducerDetailStats detailFor(String productorId) {
    final DateTime today = _dateOnly(_clock());
    final List<MilkReceptionModel> mine =
        _deliveries
            .where(
              (MilkReceptionModel r) =>
                  r.productorId == productorId && !r.anulado,
            )
            .toList()
          ..sort((MilkReceptionModel a, MilkReceptionModel b) {
            final int d = b.fechaEntrega.compareTo(a.fechaEntrega);
            return d != 0 ? d : b.horaEntrega.compareTo(a.horaEntrega);
          });
    final Map<String, double> byDay = <String, double>{};
    for (final MilkReceptionModel r in mine) {
      byDay[r.fechaEntrega] = (byDay[r.fechaEntrega] ?? 0) + r.litros;
    }
    final List<DailyLiters> series = <DailyLiters>[
      for (int i = 29; i >= 0; i--)
        () {
          final DateTime d = today.subtract(Duration(days: i));
          return DailyLiters(d, byDay[DateRangeValue.single(d).startIso] ?? 0);
        }(),
    ];
    return ProducerDetailStats(
      period: statsFor(productorId),
      last30Days: series,
      recent: mine.take(8).toList(),
    );
  }

  String suggestedNextCode() => _service.suggestNextCodigoAsociado(_producers);

  /// Devuelve el productor que ya usa la cédula (excluyendo [excludeId]).
  ProducerModel? findByCedula(String cedula, {String? excludeId}) {
    final String c = ProducerRules.digitsOnly(cedula);
    if (c.isEmpty) return null;
    for (final ProducerModel p in _producers) {
      if (p.productorId != excludeId && p.cedula.trim() == c) return p;
    }
    return null;
  }

  /// Devuelve el productor que ya usa el código (excluyendo [excludeId]).
  ProducerModel? findByCode(String code, {String? excludeId}) {
    final String c = ProducerRules.collapse(code).toUpperCase();
    if (c.isEmpty) return null;
    for (final ProducerModel p in _producers) {
      if (p.productorId != excludeId &&
          p.codigoAsociado.trim().toUpperCase() == c) {
        return p;
      }
    }
    return null;
  }

  ProducerModel? byId(String productorId) {
    for (final ProducerModel p in _producers) {
      if (p.productorId == productorId) return p;
    }
    return null;
  }

  Future<void> loadProducers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _service.listProducers();
      _producers = result.producers;
      _isFromOfflineCache = result.fromCache;
      if (_veredaFilter != 'ALL' &&
          !availableVeredas
              .map((String v) => v.toLowerCase())
              .contains(_veredaFilter.toLowerCase())) {
        _veredaFilter = 'ALL';
      }
    } catch (e) {
      _errorMessage = 'No fue posible cargar el padrón de productores: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga las entregas del período (más los últimos 30 días para la gráfica
  /// y la columna "Última entrega").
  Future<void> loadDeliveries() async {
    final int request = ++_deliveriesRequest;
    _isLoadingDeliveries = true;
    notifyListeners();

    final DateTime today = _dateOnly(_clock());
    final DateTime last30 = today.subtract(const Duration(days: 29));
    final DateTime start = _period.start.isBefore(last30)
        ? _period.start
        : last30;
    final DateTime end = _period.end.isAfter(today) ? _period.end : today;
    final DateRangeValue window = DateRangeValue(start, end);

    try {
      final result = await _service.listDeliveries(
        startIso: window.startIso,
        endIso: window.endIso,
      );
      if (request != _deliveriesRequest) return;
      _deliveries = result.deliveries;
      _deliveriesFromCache = result.fromCache;
      _deliveriesLoaded = true;
      _recomputeStats();
    } catch (_) {
      if (request != _deliveriesRequest) return;
      _deliveriesFromCache = true;
    } finally {
      if (request == _deliveriesRequest) {
        _isLoadingDeliveries = false;
        notifyListeners();
      }
    }
  }

  void _recomputeStats() {
    _stats = aggregateDeliveries(
      _deliveries,
      startIso: _period.startIso,
      endIso: _period.endIso,
    );
  }

  Future<void> setPeriod(DateRangeValue value) async {
    if (value == _period) return;
    _period = value;
    _recomputeStats();
    notifyListeners();
    await loadDeliveries();
  }

  /// Carga padrón y entregas en paralelo.
  Future<void> refreshAll() async {
    await Future.wait<void>(<Future<void>>[loadProducers(), loadDeliveries()]);
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
    PrivacyNotice? privacyNotice,
    String? authorizationReference,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    _feedbackMessage = null;
    _lastSaved = null;
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
        privacyNotice: privacyNotice,
        authorizationReference: authorizationReference,
        createMobileAccount: createMobileAccount,
        mobileEmail: mobileEmail,
        mobilePassword: mobilePassword,
      );
      _producers = <ProducerModel>[created, ..._producers];
      _lastSaved = created;
      _feedbackMessage =
          'Productor "${created.nombreCompleto}" registrado correctamente.';
      return true;
    } on ProducerServiceException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible registrar el productor: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
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
    _lastSaved = null;
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
      _replace(updated);
      _lastSaved = updated;
      _feedbackMessage = 'Productor "${updated.nombreCompleto}" actualizado.';
      return true;
    } on ProducerServiceException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'No fue posible actualizar el productor: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
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
      _replace(updated);
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

  void _replace(ProducerModel updated) {
    _producers = _producers
        .map(
          (ProducerModel p) =>
              p.productorId == updated.productorId ? updated : p,
        )
        .toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    notifyListeners();
  }

  void setVeredaFilter(String vereda) {
    _veredaFilter = vereda;
    notifyListeners();
  }

  void setSort(ProducerSortOption option) {
    if (option == _sort) return;
    _sort = option;
    notifyListeners();
  }

  void clearFilters() {
    _filtersVersion++;
    _searchQuery = '';
    _statusFilter = 'ALL';
    _veredaFilter = 'ALL';
    notifyListeners();
  }

  void clearFeedback() {
    _errorMessage = null;
    _feedbackMessage = null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Minúsculas sin tildes para búsquedas y orden alfabético estable.
  static String _fold(String s) {
    const String from = 'áéíóúüÁÉÍÓÚÜñÑ';
    const String to = 'aeiouuAEIOUUnN';
    final StringBuffer out = StringBuffer();
    for (final int rune in s.runes) {
      final String ch = String.fromCharCode(rune);
      final int i = from.indexOf(ch);
      out.write(i >= 0 ? to[i] : ch);
    }
    return out.toString().toLowerCase();
  }
}

class _StatsAccumulator {
  double liters = 0;
  int count = 0;
  double morning = 0;
  double afternoon = 0;
  String? last;
}
