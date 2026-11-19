import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/assistant_report.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'file_export_service.dart';

/// Convierte un [AssistantReport] (generado por la IA) en PDF con gráficas o
/// en un libro de Excel con gráficas nativas.
class AssistantReportExport {
  AssistantReportExport._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF0B3B37);
  static const PdfColor _emerald = PdfColor.fromInt(0xFF0F766E);
  static const PdfColor _soft = PdfColor.fromInt(0xFFCDEAE4);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E7EA);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF4B5B61);
  static const PdfColor _textPrimary = PdfColor.fromInt(0xFF0F1B1E);
  static const PdfColor _zebra = PdfColor.fromInt(0xFFF7F9FA);

  /// Paleta de las gráficas (coincide con la de la app y la de Excel).
  static const List<int> palette = <int>[
    0xFF0F766E, 0xFFE59E0B, 0xFF4F6BED, 0xFFE15D7A, 0xFF7C8B91, 0xFF14B8A6, 0xFF9A5B00, 0xFF1E40AF,
  ];

  static PdfColor _color(int i) => PdfColor.fromInt(palette[i % palette.length]);

  // ── Formato de celdas ────────────────────────────────────────────────────

  static String formatCell(ReportSection s, int row, int col) {
    final Object? v = s.cellValue(row, col);
    if (v is! num) return v?.toString() ?? '';
    final double d = v.toDouble();
    return switch (s.columnTypes[col]) {
      ReportCellType.liters => AppFormatters.formatLiters(d),
      ReportCellType.money => AppFormatters.formatCurrency(d),
      ReportCellType.integer => AppFormatters.formatCurrency(d.roundToDouble(), symbol: ''),
      ReportCellType.number => formatNumber(d),
      ReportCellType.percent => '${(d * 100).toStringAsFixed(1).replaceAll('.', ',')} %',
      ReportCellType.text => s.rows[row][col],
    };
  }

  /// 1250.5 → "1.250,5"; enteros sin decimales.
  static String formatNumber(double v) {
    if (v == v.roundToDouble()) return AppFormatters.formatCurrency(v, symbol: '');
    return AppFormatters.formatLiters(v, withUnit: false);
  }

  static String fileBaseName(AssistantReport r) {
    String clean(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final DateTime now = DateTime.now();
    final String stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    String base = clean(r.title);
    if (base.isEmpty) base = 'informe';
    if (base.length > 70) base = base.substring(0, 70);
    return 'ia_${base}_$stamp';
  }

  static Future<Uint8List> build(AssistantReport r, ExportFormat format, {String? generatedBy}) async {
    switch (format) {
      case ExportFormat.xlsx:
        return buildXlsx(r, generatedBy: generatedBy);
      case ExportFormat.pdf:
      case ExportFormat.csv:
        return buildPdf(r, generatedBy: generatedBy);
    }
  }

  // ── Excel ────────────────────────────────────────────────────────────────

  static XlsxCellType _xlsxType(ReportCellType t) => switch (t) {
        ReportCellType.text => XlsxCellType.text,
        ReportCellType.integer => XlsxCellType.integer,
        ReportCellType.number => XlsxCellType.number,
        ReportCellType.liters => XlsxCellType.liters,
        ReportCellType.money => XlsxCellType.money,
        ReportCellType.percent => XlsxCellType.number,
      };

  static XlsxChartType _xlsxChart(ReportChartType t) => switch (t) {
        ReportChartType.bar => XlsxChartType.bar,
        ReportChartType.horizontalBar => XlsxChartType.horizontalBar,
        ReportChartType.line => XlsxChartType.line,
        ReportChartType.pie => XlsxChartType.pie,
      };

  static Uint8List buildXlsx(AssistantReport r, {String? generatedBy}) {
    final String header = '${AppConstants.appName} · ${r.title}';
    final String generated = <String>[
      if (r.subtitle != null) r.subtitle!,
      'Generado con el Asistente IA: ${AppFormatters.formatDateTime(DateTime.now())}',
      if (generatedBy != null && generatedBy.isNotEmpty) generatedBy,
    ].join(' · ');

    // Hoja 1: resumen con indicadores y textos de análisis.
    final List<List<Object?>> summary = <List<Object?>>[];
    for (final ReportSection s in r.sections) {
      if (s.type == ReportSectionType.kpis) {
        if (s.title != null) summary.add(<Object?>[s.title!.toUpperCase(), null]);
        for (final ReportKpiItem k in s.kpis) {
          summary.add(<Object?>[k.label, k.value]);
        }
        summary.add(<Object?>[null, null]);
      } else if (s.type == ReportSectionType.text) {
        if (s.title != null) summary.add(<Object?>[s.title!.toUpperCase(), null]);
        for (final String line in s.text!.split('\n')) {
          if (line.trim().isNotEmpty) summary.add(<Object?>[line.trim(), null]);
        }
        summary.add(<Object?>[null, null]);
      }
    }
    while (summary.isNotEmpty && summary.last.every((Object? v) => v == null)) {
      summary.removeLast();
    }

    final List<TableSheet> sheets = <TableSheet>[
      if (summary.isNotEmpty)
        TableSheet(
          name: 'Resumen',
          title: header,
          subtitle: generated,
          columns: const <XlsxColumn>[XlsxColumn('Concepto', width: 70), XlsxColumn('Valor', width: 24)],
          rows: summary,
        ),
    ];

    int tableN = 0;
    int chartN = 0;
    for (final ReportSection s in r.sections) {
      if (s.type == ReportSectionType.table) {
        tableN++;
        final List<List<Object?>> rows = <List<Object?>>[
          for (int i = 0; i < s.rows.length; i++)
            <Object?>[
              for (int c = 0; c < s.columns.length; c++)
                () {
                  final Object? v = s.cellValue(i, c);
                  if (v is num && s.columnTypes[c] == ReportCellType.percent) {
                    return double.parse((v * 100).toStringAsFixed(2));
                  }
                  return v;
                }(),
            ],
        ];
        sheets.add(TableSheet(
          name: s.title ?? 'Tabla $tableN',
          title: s.title ?? header,
          subtitle: generated,
          columns: <XlsxColumn>[
            for (int c = 0; c < s.columns.length; c++)
              XlsxColumn(
                s.columnTypes[c] == ReportCellType.percent ? '${s.columns[c]} (%)' : s.columns[c],
                type: _xlsxType(s.columnTypes[c]),
                width: s.columnTypes[c] == ReportCellType.text ? 30 : 16,
              ),
          ],
          rows: rows,
        ));
      } else if (s.type == ReportSectionType.chart) {
        chartN++;
        final ReportChart ch = s.chart!;
        final String title = s.title ?? 'Gráfica $chartN';
        sheets.add(TableSheet(
          name: 'Gráfica $chartN',
          title: title,
          subtitle: ch.axisLabel == null ? null : 'Valores en ${ch.axisLabel}',
          columns: <XlsxColumn>[
            const XlsxColumn('Categoría', width: 30),
            for (final ReportSeries se in ch.series) XlsxColumn(se.name, type: XlsxCellType.number, width: 16),
          ],
          rows: <List<Object?>>[
            for (int i = 0; i < ch.labels.length; i++)
              <Object?>[ch.labels[i], for (final ReportSeries se in ch.series) se.values[i]],
          ],
          charts: <XlsxChart>[
            XlsxChart(
              type: _xlsxChart(ch.type),
              title: title,
              seriesColumns: <int>[for (int k = 0; k < ch.series.length; k++) k + 1],
            ),
          ],
        ));
      }
    }
    if (sheets.isEmpty) {
      sheets.add(TableSheet(
        name: 'Resumen',
        title: header,
        subtitle: generated,
        columns: const <XlsxColumn>[XlsxColumn('Concepto', width: 60)],
        rows: const <List<Object?>>[],
      ));
    }
    return XlsxBuilder.build(sheets);
  }

  // ── PDF ──────────────────────────────────────────────────────────────────

  static pw.ThemeData? _theme;
  static bool _themeTried = false;

  static Future<pw.ThemeData?> _pdfTheme() async {
    if (_themeTried) return _theme;
    _themeTried = true;
    try {
      final ByteData regular = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final ByteData bold = await rootBundle.load('assets/fonts/Inter-SemiBold.ttf');
      _theme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
    } catch (_) {
      _theme = null;
    }
    return _theme;
  }

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final ByteData data = await rootBundle.load(AppConstants.darkLogoAssetPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> buildPdf(AssistantReport r, {String? generatedBy}) async {
    final pw.ThemeData? theme = await _pdfTheme();
    final pw.MemoryImage? logo = await _logo();
    final bool landscape = r.sections.any((ReportSection s) => s.columns.length > 7);
    final pw.Document pdf = pw.Document(title: r.title, author: AppConstants.appName, theme: theme);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: landscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        footer: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text('${AppConstants.appName} · ${r.title} · Generado con el Asistente IA',
                  style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
              pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
            ],
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          _header(r, generatedBy, logo),
          for (final ReportSection s in r.sections) ...<pw.Widget>[
            pw.SizedBox(height: 14),
            ..._section(s),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'Informe generado con inteligencia artificial a partir de los datos de la plataforma. Verifica las cifras críticas.',
            style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _header(AssistantReport r, String? generatedBy, pw.MemoryImage? logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Row(
        children: <pw.Widget>[
          if (logo != null) ...<pw.Widget>[
            pw.SizedBox(width: 40, height: 40, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text('${AppConstants.appName} · ${AppConstants.appTagline}',
                    style: const pw.TextStyle(fontSize: 7.5, color: _soft)),
                pw.SizedBox(height: 2),
                pw.Text(r.title,
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                if (r.subtitle != null) ...<pw.Widget>[
                  pw.SizedBox(height: 3),
                  pw.Text(r.subtitle!, style: const pw.TextStyle(fontSize: 8.5, color: _soft)),
                ],
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text('Generado', style: const pw.TextStyle(fontSize: 7.5, color: _soft)),
              pw.Text(AppFormatters.formatDateTime(DateTime.now()),
                  style: pw.TextStyle(fontSize: 8.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
              if (generatedBy != null && generatedBy.isNotEmpty)
                pw.Text(generatedBy, style: const pw.TextStyle(fontSize: 7.5, color: _soft)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t.toUpperCase(),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
      );

  static List<pw.Widget> _section(ReportSection s) {
    final List<pw.Widget> out = <pw.Widget>[if (s.title != null) _sectionTitle(s.title!)];
    switch (s.type) {
      case ReportSectionType.text:
        for (final String raw in s.text!.split('\n')) {
          final String line = raw.trim();
          if (line.isEmpty) {
            out.add(pw.SizedBox(height: 4));
            continue;
          }
          final bool bullet = line.startsWith('- ') || line.startsWith('• ') || line.startsWith('* ');
          final String body = (bullet ? line.substring(2) : line).replaceAll('**', '');
          out.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: bullet ? 8 : 0, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                if (bullet)
                  pw.Container(
                    width: 4,
                    height: 4,
                    margin: const pw.EdgeInsets.only(top: 4.5, right: 7),
                    decoration: const pw.BoxDecoration(color: _emerald, shape: pw.BoxShape.circle),
                  ),
                pw.Expanded(
                  child: pw.Text(body, style: const pw.TextStyle(fontSize: 9.5, color: _textPrimary, lineSpacing: 2)),
                ),
              ],
            ),
          ));
        }
      case ReportSectionType.kpis:
        out.add(_kpis(s.kpis));
      case ReportSectionType.table:
        out.add(_table(s));
      case ReportSectionType.chart:
        out.add(_chartBox(s.chart!));
    }
    return out;
  }

  static pw.Widget _kpis(List<ReportKpiItem> kpis) {
    final List<pw.Widget> rows = <pw.Widget>[];
    for (int start = 0; start < kpis.length; start += 4) {
      final List<ReportKpiItem> chunk = kpis.sublist(start, math.min(start + 4, kpis.length));
      rows.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _border), borderRadius: pw.BorderRadius.circular(5)),
        child: pw.Row(
          children: <pw.Widget>[
            for (int i = 0; i < chunk.length; i++)
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: i == 0
                      ? null
                      : const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: _border, width: 0.6))),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(chunk[i].label, style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
                      pw.SizedBox(height: 3),
                      pw.Text(chunk[i].value,
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    return pw.Column(children: rows);
  }

  static pw.Widget _table(ReportSection s) {
    if (s.rows.isEmpty) {
      return pw.Text('Sin datos para mostrar.', style: const pw.TextStyle(fontSize: 9, color: _textSecondary));
    }
    final Map<int, pw.Alignment> aligns = <int, pw.Alignment>{
      for (int c = 0; c < s.columns.length; c++)
        c: s.columnTypes[c] == ReportCellType.text ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
    };
    final Map<int, pw.TableColumnWidth> widths = <int, pw.TableColumnWidth>{
      for (int c = 0; c < s.columns.length; c++)
        c: pw.FlexColumnWidth(s.columnTypes[c] == ReportCellType.text ? 2.2 : 1.2),
    };
    return pw.TableHelper.fromTextArray(
      headers: s.columns.map((String c) => c.toUpperCase()).toList(),
      data: <List<String>>[
        for (int i = 0; i < s.rows.length; i++)
          <String>[for (int c = 0; c < s.columns.length; c++) formatCell(s, i, c)],
      ],
      columnWidths: widths,
      headerAlignments: aligns,
      cellAlignments: aligns,
      headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _emerald),
      cellStyle: const pw.TextStyle(fontSize: 7.8, color: _textPrimary),
      oddRowDecoration: const pw.BoxDecoration(color: _zebra),
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.5),
        bottom: pw.BorderSide(color: _border, width: 0.5),
      ),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    );
  }

  /// Escala "bonita" del eje de valores: 0, paso, 2·paso… ≥ máximo.
  static List<double> niceTicks(double max, {int target = 5}) {
    if (!(max > 0)) return <double>[0, 1];
    final double raw = max / target;
    final double mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final double norm = raw / mag;
    final double step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
    final List<double> ticks = <double>[];
    for (double v = 0; v < max + step * 0.999; v += step) {
      ticks.add(double.parse(v.toStringAsFixed(6)));
    }
    if (ticks.length < 2) ticks.add(step);
    return ticks;
  }

  static String _short(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String _axisNumber(num v) {
    final double d = v.toDouble();
    if (d.abs() >= 1000000) return '${formatNumber(double.parse((d / 1000000).toStringAsFixed(1)))} M';
    if (d.abs() >= 10000) return '${formatNumber(double.parse((d / 1000).toStringAsFixed(1)))} k';
    return formatNumber(double.parse(d.toStringAsFixed(2)));
  }

  static pw.Widget _legend(List<String> names, {List<String>? values}) => pw.Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <pw.Widget>[
          for (int i = 0; i < names.length; i++)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: <pw.Widget>[
                pw.Container(width: 8, height: 8, color: _color(i)),
                pw.SizedBox(width: 4),
                pw.Text(values == null ? names[i] : '${names[i]}: ${values[i]}',
                    style: const pw.TextStyle(fontSize: 7.5, color: _textPrimary)),
              ],
            ),
        ],
      );

  static pw.Widget _chartBox(ReportChart ch) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _border), borderRadius: pw.BorderRadius.circular(5)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          if (ch.axisLabel != null && ch.type != ReportChartType.pie)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(ch.axisLabel!, style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
            ),
          _chart(ch),
          if (ch.series.length > 1 && ch.type != ReportChartType.pie) ...<pw.Widget>[
            pw.SizedBox(height: 6),
            _legend(ch.series.map((ReportSeries s) => s.name).toList()),
          ],
        ],
      ),
    );
  }

  static pw.Widget _chart(ReportChart ch) {
    final int n = ch.labels.length;
    // Muchas categorías en barras verticales se leen mejor en horizontal.
    final ReportChartType type =
        ch.type == ReportChartType.bar && n > 12 ? ReportChartType.horizontalBar : ch.type;

    if (type == ReportChartType.pie) {
      final List<double> values = ch.series.first.values.map((double v) => v < 0 ? 0.0 : v).toList();
      final double total = values.fold<double>(0, (double a, double b) => a + b);
      if (total <= 0) {
        return pw.Text('Sin valores para graficar.', style: const pw.TextStyle(fontSize: 9, color: _textSecondary));
      }
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 190,
            height: 190,
            child: pw.Chart(
              grid: pw.PieGrid(),
              datasets: <pw.Dataset>[
                for (int i = 0; i < n; i++)
                  if (values[i] > 0)
                    pw.PieDataSet(
                      value: values[i],
                      color: _color(i),
                      legendPosition: pw.PieLegendPosition.none,
                    ),
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                for (int i = 0; i < n; i++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      children: <pw.Widget>[
                        pw.Container(width: 9, height: 9, color: _color(i)),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: pw.Text(ch.labels[i], style: const pw.TextStyle(fontSize: 8.5, color: _textPrimary)),
                        ),
                        pw.Text(
                          '${formatNumber(values[i])}  (${(values[i] / total * 100).toStringAsFixed(1).replaceAll('.', ',')} %)',
                          style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final List<double> ticks = niceTicks(ch.maxValue);
    final pw.TextStyle axisStyle = const pw.TextStyle(fontSize: 6.8, color: _textSecondary);
    final int k = ch.series.length;

    if (type == ReportChartType.horizontalBar) {
      final double rowH = 16;
      final double barW = math.max(3, (rowH * 0.7) / k);
      return pw.SizedBox(
        height: math.max(120, n * rowH + 30),
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis<double>(ticks, format: _axisNumber, textStyle: axisStyle, divisions: true,
                divisionsColor: _border, color: _border),
            // Primera categoría arriba: el eje vertical crece hacia arriba.
            yAxis: pw.FixedAxis.fromStrings(
              <String>[for (final String l in ch.labels.reversed) _short(l, 26)],
              marginStart: rowH / 2,
              marginEnd: rowH / 2,
              textStyle: axisStyle,
              color: _border,
            ),
          ),
          datasets: <pw.Dataset>[
            for (int s = 0; s < k; s++)
              pw.BarDataSet<pw.PointChartValue>(
                color: _color(s),
                width: barW,
                offset: ((k - 1) / 2 - s) * barW, // primera serie arriba
                axis: pw.Axis.vertical,
                borderColor: _color(s),
                data: <pw.PointChartValue>[
                  for (int i = 0; i < n; i++) pw.PointChartValue(ch.series[s].values[i], (n - 1 - i).toDouble()),
                ],
              ),
          ],
        ),
      );
    }

    // Etiquetas del eje X: si son muchas, se muestra una de cada "step".
    final int step = n <= 12 ? 1 : (n / 12).ceil();
    final int maxChars = n <= 6 ? 18 : n <= 10 ? 11 : 9;
    final List<String> labels = <String>[
      for (int i = 0; i < n; i++) i % step == 0 ? _short(ch.labels[i], maxChars) : '',
    ];
    final double slot = 460 / math.max(1, n);
    final double barW = math.max(2, math.min(26, slot * 0.7 / k));

    return pw.SizedBox(
      height: 210,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(
            labels,
            marginStart: slot / 2,
            marginEnd: slot / 2,
            ticks: true,
            textStyle: axisStyle,
            color: _border,
          ),
          yAxis: pw.FixedAxis<double>(ticks, format: _axisNumber, textStyle: axisStyle, divisions: true,
              divisionsColor: _border, color: _border),
        ),
        datasets: <pw.Dataset>[
          for (int s = 0; s < k; s++)
            if (type == ReportChartType.line)
              pw.LineDataSet<pw.PointChartValue>(
                color: _color(s),
                lineColor: _color(s),
                lineWidth: 1.6,
                pointSize: n > 31 ? 0 : 2.2,
                drawPoints: n <= 31,
                data: <pw.PointChartValue>[
                  for (int i = 0; i < n; i++) pw.PointChartValue(i.toDouble(), ch.series[s].values[i]),
                ],
              )
            else
              pw.BarDataSet<pw.PointChartValue>(
                color: _color(s),
                borderColor: _color(s),
                width: barW,
                offset: (s - (k - 1) / 2) * barW,
                data: <pw.PointChartValue>[
                  for (int i = 0; i < n; i++) pw.PointChartValue(i.toDouble(), ch.series[s].values[i]),
                ],
              ),
        ],
      ),
    );
  }
}
