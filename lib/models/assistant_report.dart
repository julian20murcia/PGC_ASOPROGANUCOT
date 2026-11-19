/// Informe generado por el asistente IA (herramienta `generar_informe`).
///
/// La Cloud Function ya sanea la estructura; aquí se vuelve a validar para
/// que la app nunca falle por datos inesperados.
library;

enum ReportSectionType { text, kpis, table, chart }

enum ReportChartType { bar, horizontalBar, line, pie }

enum ReportCellType { text, integer, number, liters, money, percent }

enum ReportPreferredFormat { pdf, excel }

class ReportKpiItem {
  const ReportKpiItem(this.label, this.value);
  final String label;
  final String value;
}

class ReportSeries {
  const ReportSeries(this.name, this.values);
  final String name;
  final List<double> values;
}

class ReportChart {
  const ReportChart({required this.type, required this.labels, required this.series, this.axisLabel});
  final ReportChartType type;
  final List<String> labels;
  final List<ReportSeries> series;
  final String? axisLabel;

  double get maxValue {
    double m = 0;
    for (final ReportSeries s in series) {
      for (final double v in s.values) {
        if (v > m) m = v;
      }
    }
    return m;
  }
}

class ReportSection {
  const ReportSection._({
    required this.type,
    this.title,
    this.text,
    this.kpis = const <ReportKpiItem>[],
    this.columns = const <String>[],
    this.columnTypes = const <ReportCellType>[],
    this.rows = const <List<String>>[],
    this.chart,
  });

  final ReportSectionType type;
  final String? title;
  final String? text;
  final List<ReportKpiItem> kpis;
  final List<String> columns;
  final List<ReportCellType> columnTypes;
  final List<List<String>> rows;
  final ReportChart? chart;

  /// Valor de la celda convertido a número cuando la columna es numérica.
  Object? cellValue(int row, int col) {
    final String raw = rows[row][col];
    final ReportCellType t = columnTypes[col];
    if (t == ReportCellType.text) return raw;
    final double? n = AssistantReport.parseNumber(raw);
    if (n == null) return raw.isEmpty ? null : raw;
    if (t == ReportCellType.percent && n > 1.0001) return n / 100; // 45 → 0,45
    return n;
  }
}

class AssistantReport {
  const AssistantReport({
    required this.title,
    required this.sections,
    this.subtitle,
    this.preferred = ReportPreferredFormat.pdf,
  });

  final String title;
  final String? subtitle;
  final ReportPreferredFormat preferred;
  final List<ReportSection> sections;

  Iterable<ReportChart> get charts =>
      sections.where((ReportSection s) => s.chart != null).map((ReportSection s) => s.chart!);

  int get tableCount => sections.where((ReportSection s) => s.type == ReportSectionType.table).length;

  /// Acepta "1250.5", "1.250,5", "$ 1.850", "45%"; null si no es un número.
  static double? parseNumber(String raw) {
    String s = raw.trim().replaceAll(RegExp(r'[\s$%L]'), '');
    if (s.isEmpty) return null;
    final bool hasComma = s.contains(',');
    final bool hasDot = s.contains('.');
    if (hasComma && hasDot) {
      // El último separador es el decimal.
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (hasComma) {
      s = s.replaceAll(',', '.');
    } else if (hasDot && RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', ''); // 1.250 = mil doscientos cincuenta
    }
    return double.tryParse(s);
  }

  static String? _str(Object? v, int max) {
    if (v is! String) return null;
    final String t = v.trim();
    if (t.isEmpty) return null;
    return t.length > max ? t.substring(0, max) : t;
  }

  static List<Object?> _list(Object? v) => v is List ? v : const <Object?>[];

  static ReportCellType _cellType(Object? v) => switch (v) {
        'entero' => ReportCellType.integer,
        'numero' => ReportCellType.number,
        'litros' => ReportCellType.liters,
        'dinero' => ReportCellType.money,
        'porcentaje' => ReportCellType.percent,
        _ => ReportCellType.text,
      };

  static ReportChartType? _chartType(Object? v) => switch (v) {
        'barras' => ReportChartType.bar,
        'barras_horizontales' => ReportChartType.horizontalBar,
        'lineas' => ReportChartType.line,
        'torta' => ReportChartType.pie,
        _ => null,
      };

  static ReportSection? _section(Map<String, dynamic> m) {
    final String? title = _str(m['titulo'], 140);
    switch (m['tipo']) {
      case 'texto':
        final String? text = _str(m['texto'], 6000);
        return text == null ? null : ReportSection._(type: ReportSectionType.text, title: title, text: text);
      case 'indicadores':
        final List<ReportKpiItem> kpis = <ReportKpiItem>[
          for (final Object? k in _list(m['indicadores']).take(8))
            if (k is Map) ReportKpiItem(_str(k['etiqueta'], 60) ?? '', _str(k['valor'], 40) ?? ''),
        ];
        return kpis.isEmpty ? null : ReportSection._(type: ReportSectionType.kpis, title: title, kpis: kpis);
      case 'tabla':
        final List<String> cols = <String>[for (final Object? c in _list(m['columnas']).take(12)) _str(c, 60) ?? ''];
        if (cols.isEmpty) return null;
        final List<Object?> rawTypes = _list(m['tipos_columna']);
        final List<ReportCellType> types = <ReportCellType>[
          for (int i = 0; i < cols.length; i++) _cellType(i < rawTypes.length ? rawTypes[i] : null),
        ];
        final List<List<String>> rows = <List<String>>[
          for (final Object? r in _list(m['filas']).take(1000))
            <String>[
              for (int i = 0; i < cols.length; i++) r is List && i < r.length ? (r[i]?.toString() ?? '') : '',
            ],
        ];
        return ReportSection._(type: ReportSectionType.table, title: title, columns: cols, columnTypes: types, rows: rows);
      case 'grafica':
        final Object? g = m['grafica'];
        if (g is! Map) return null;
        final ReportChartType? type = _chartType(g['tipo']);
        final List<String> labels = <String>[for (final Object? l in _list(g['etiquetas']).take(60)) l?.toString() ?? ''];
        if (type == null || labels.isEmpty) return null;
        final List<ReportSeries> series = <ReportSeries>[
          for (final Object? s in _list(g['series']).take(type == ReportChartType.pie ? 1 : 6))
            if (s is Map)
              ReportSeries(
                _str(s['nombre'], 60) ?? 'Serie',
                <double>[
                  for (int i = 0; i < labels.length; i++)
                    () {
                      final List<Object?> vals = _list(s['valores']);
                      final Object? v = i < vals.length ? vals[i] : null;
                      final double d = v is num ? v.toDouble() : 0;
                      return d.isFinite ? d : 0.0;
                    }(),
                ],
              ),
        ];
        if (series.isEmpty) return null;
        return ReportSection._(
          type: ReportSectionType.chart,
          title: title,
          chart: ReportChart(type: type, labels: labels, series: series, axisLabel: _str(g['eje_y'], 30)),
        );
    }
    return null;
  }

  static AssistantReport? tryParse(Map<String, dynamic> json) {
    try {
      final List<ReportSection> sections = <ReportSection>[
        for (final Object? s in _list(json['secciones']).take(30))
          if (s is Map) ?_section(Map<String, dynamic>.from(s)),
      ];
      if (sections.isEmpty) return null;
      return AssistantReport(
        title: _str(json['titulo'], 140) ?? 'Informe',
        subtitle: _str(json['subtitulo'], 200),
        preferred: json['formato'] == 'excel' ? ReportPreferredFormat.excel : ReportPreferredFormat.pdf,
        sections: sections,
      );
    } catch (_) {
      return null;
    }
  }
}
