import 'package:flutter/foundation.dart';

import '../../../core/services/activity_presenter.dart';
import '../../../core/services/audit_query_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/audit_log_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';

/// Estado de una línea de tiempo de actividad (pestaña de reportes o panel
/// lateral de un usuario). Pagina contra `auditoria_logs` y traduce cada
/// registro con [ActivityPresenter].
class ActivityFeedController extends ChangeNotifier {
  ActivityFeedController({
    required this.service,
    DateRangeValue? range,
    String? initialUserUid,
    ActivityDirectory? directory,
    this.pageSize = 120,
  })  : _range = range ?? DateRangeValue(DateTime.now().subtract(const Duration(days: 6)), DateTime.now()),
        _userUid = initialUserUid,
        _presenter = ActivityPresenter(directory);

  final AuditQueryService service;
  final int pageSize;

  ActivityPresenter _presenter;
  DateRangeValue _range;
  String? _userUid;
  ActivityKind? _kind;
  ActivityModule? _module;
  String _search = '';

  List<AuditLogModel> _logs = <AuditLogModel>[];
  AuditCursor? _cursor;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;
  List<ActivityEntry>? _cache;

  DateRangeValue get range => _range;
  String? get userUid => _userUid;
  ActivityKind? get kind => _kind;
  ActivityModule? get module => _module;
  String get search => _search;
  bool get hasMore => _hasMore;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  String? get error => _error;
  int get loadedCount => _logs.length;
  bool get hasFilters => _kind != null || _module != null || _search.trim().isNotEmpty;

  AuditQuery get _query => AuditQuery.forDays(_range.start, _range.end, usuarioUid: _userUid, limit: pageSize);

  /// Actividades agrupadas y filtradas (más recientes primero).
  List<ActivityEntry> get entries => _cache ??= _filter(ActivityPresenter.group(_presenter.presentAll(_logs)));

  List<ActivityEntry> _filter(List<ActivityEntry> list) {
    final String q = _search.trim().toLowerCase();
    return list.where((ActivityEntry e) {
      if (_kind != null && e.kind != _kind) return false;
      if (_module != null && e.module != _module) return false;
      if (q.isNotEmpty &&
          !e.sentence.toLowerCase().contains(q) &&
          !e.title.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  void updateDirectory(ActivityDirectory directory) {
    _presenter = ActivityPresenter(directory);
    _cache = null;
    notifyListeners();
  }

  void setRange(DateRangeValue r) {
    if (r == _range) return;
    _range = r;
    reload();
  }

  void setUser(String? uid) {
    final String? clean = (uid == null || uid.isEmpty) ? null : uid;
    if (clean == _userUid) return;
    _userUid = clean;
    reload();
  }

  void setKind(ActivityKind? k) {
    _kind = k;
    _cache = null;
    notifyListeners();
    _autoFill();
  }

  void setModule(ActivityModule? m) {
    _module = m;
    _cache = null;
    notifyListeners();
    _autoFill();
  }

  void setSearch(String q) {
    _search = q;
    _cache = null;
    notifyListeners();
  }

  void clearFilters() {
    _kind = null;
    _module = null;
    _search = '';
    _cache = null;
    notifyListeners();
  }

  Future<void> reload() async {
    final int gen = ++_generation;
    _loading = true;
    _error = null;
    _logs = <AuditLogModel>[];
    _cursor = null;
    _hasMore = false;
    _cache = null;
    notifyListeners();
    try {
      final AuditPage page = await service.fetchPage(_query);
      if (gen != _generation) return;
      _logs = page.logs;
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } catch (e) {
      if (gen != _generation) return;
      _error = describeError(e);
    } finally {
      if (gen == _generation) {
        _loading = false;
        _cache = null;
        notifyListeners();
      }
    }
    if (gen == _generation) await _autoFill();
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    final int gen = _generation;
    _loadingMore = true;
    notifyListeners();
    try {
      final AuditPage page = await service.fetchPage(_query, cursor: _cursor);
      if (gen != _generation) return;
      _logs = <AuditLogModel>[..._logs, ...page.logs];
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } catch (e) {
      if (gen != _generation) return;
      _error = describeError(e);
    } finally {
      if (gen == _generation) {
        _loadingMore = false;
        _cache = null;
        notifyListeners();
      }
    }
  }

  /// Con filtros locales activos, carga algunas páginas más para que la
  /// lista no quede casi vacía.
  Future<void> _autoFill() async {
    int guard = 0;
    while (hasFilters && _hasMore && entries.length < 25 && guard < 4 && !_loading) {
      guard++;
      await loadMore();
    }
  }

  /// Todas las actividades del rango con los filtros actuales (para exportar).
  Future<List<ActivityEntry>> entriesForExport({int max = 3000}) async {
    final List<AuditLogModel> all = await service.fetchAll(_query, max: max);
    return _filter(ActivityPresenter.group(_presenter.presentAll(all)));
  }

  static String describeError(Object e) {
    final String s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('permiso')) {
      return 'Tu cuenta no tiene acceso a la bitácora. Pide a un administrador el permiso "Reportes y auditoría · Ver".';
    }
    if (s.contains('index') || s.contains('índice') || s.contains('failed-precondition')) {
      return 'Falta un índice de Firestore para esta consulta (auditoria_logs: usuarioUid ↑, timestamp ↓). '
          'Pide al administrador del sistema que lo cree.';
    }
    if (s.contains('unavailable') || s.contains('network') || s.contains('socket')) {
      return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
    }
    return 'No fue posible cargar la actividad. Intenta de nuevo.';
  }

  /// Tabla exportable de actividades (PDF, Excel o CSV).
  static ReportDataset toDataset(
    List<ActivityEntry> entries, {
    required String periodLabel,
    String title = 'Actividad de usuarios',
    String? subtitle,
  }) {
    final Map<ActivityKind, int> byKind = <ActivityKind, int>{};
    for (final ActivityEntry e in entries) {
      byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;
    }
    final Set<String> actors = entries.map((ActivityEntry e) => e.log.usuarioUid).toSet();
    final List<MapEntry<ActivityKind, int>> top = byKind.entries.toList()
      ..sort((MapEntry<ActivityKind, int> a, MapEntry<ActivityKind, int> b) => b.value.compareTo(a.value));
    return ReportDataset(
      title: title,
      subtitle: subtitle,
      periodLabel: periodLabel,
      emptyMessage: 'No hay actividad registrada con los filtros seleccionados.',
      columns: const <ReportColumn>[
        ReportColumn('Fecha', type: ReportColumnType.date),
        ReportColumn('Hora', type: ReportColumnType.date, flex: 1),
        ReportColumn('Usuario', flex: 3),
        ReportColumn('Módulo'),
        ReportColumn('Acción'),
        ReportColumn('Descripción', flex: 7),
        ReportColumn('Motivo', flex: 3),
        ReportColumn('Cambios', flex: 5),
      ],
      rows: <List<Object?>>[
        for (final ActivityEntry e in entries)
          <Object?>[
            AppFormatters.formatDate(e.timestamp),
            _time(e.timestamp.toLocal()),
            e.actorName,
            e.module.label,
            e.title,
            e.related.isEmpty ? e.description : '${e.description} (+${e.related.length} registros relacionados)',
            e.motivo ?? '',
            e.changes
                .where((ActivityChange c) => c.before != null)
                .map((ActivityChange c) => '${c.label}: ${c.before} → ${c.after ?? '—'}')
                .join(' | '),
          ],
      ],
      kpis: <ReportKpi>[
        ReportKpi('Actividades', '${entries.length}'),
        ReportKpi('Usuarios', '${actors.length}'),
        ReportKpi('Más frecuente', top.isEmpty ? '—' : top.first.key.label, hint: top.isEmpty ? null : '${top.first.value}'),
      ],
    );
  }

  static String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
