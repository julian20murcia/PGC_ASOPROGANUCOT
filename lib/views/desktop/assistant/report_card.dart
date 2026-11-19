import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/services/assistant_report_export.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/assistant_report.dart';

Color _paletteColor(int i) => Color(AssistantReportExport.palette[i % AssistantReportExport.palette.length]);

/// Tarjeta de un informe generado por la IA: resumen, vista previa de la
/// primera gráfica y botones para descargar en PDF o Excel.
class AssistantReportCard extends StatelessWidget {
  const AssistantReportCard({
    super.key,
    required this.report,
    required this.onDownload,
    this.busyFormat,
  });

  final AssistantReport report;
  final void Function(ExportFormat format) onDownload;

  /// Formato que se está generando (muestra un indicador en ese botón).
  final ExportFormat? busyFormat;

  @override
  Widget build(BuildContext context) {
    final List<ReportChart> charts = report.charts.toList();
    final int tables = report.tableCount;
    final bool excelFirst = report.preferred == ReportPreferredFormat.excel;
    final String? previewTitle = report.sections
        .firstWhere((ReportSection s) => s.chart != null, orElse: () => report.sections.first)
        .title;

    Widget button(ExportFormat f) {
      final bool primary = (f == ExportFormat.xlsx) == excelFirst;
      final bool busy = busyFormat == f;
      final Widget icon = busy
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: primary ? Colors.white : AppTheme.brand),
            )
          : Icon(f == ExportFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined, size: 16);
      final Widget label = Text('Descargar ${f.label}');
      final VoidCallback? onPressed = busyFormat == null ? () => onDownload(f) : null;
      return primary
          ? FilledButton.icon(
              key: Key('report-download-${f.extension}'),
              onPressed: onPressed,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(
              key: Key('report-download-${f.extension}'),
              onPressed: onPressed,
              icon: icon,
              label: label,
            );
    }

    return Container(
      key: const Key('assistant-report-card'),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            color: AppTheme.brandSoft,
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.insert_chart_outlined_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(report.title,
                          style: AppTheme.bodyStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          if (report.subtitle != null) report.subtitle!,
                          if (charts.isNotEmpty) '${charts.length} ${charts.length == 1 ? 'gráfica' : 'gráficas'}',
                          if (tables > 0) '$tables ${tables == 1 ? 'tabla' : 'tablas'}',
                        ].join(' · '),
                        style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (charts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (previewTitle != null)
                    Text(previewTitle,
                        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SizedBox(height: 190, child: ReportChartPreview(chart: charts.first)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: excelFirst
                  ? <Widget>[button(ExportFormat.xlsx), button(ExportFormat.pdf)]
                  : <Widget>[button(ExportFormat.pdf), button(ExportFormat.xlsx)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista previa (fl_chart) de una gráfica del informe.
class ReportChartPreview extends StatelessWidget {
  const ReportChartPreview({super.key, required this.chart});
  final ReportChart chart;

  static String _short(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String _compact(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(v.abs() >= 10000 ? 0 : 1)}k';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final int n = chart.labels.length;
    final TextStyle axis = AppTheme.monoStyle(fontSize: 10, color: AppTheme.textMuted);

    if (chart.type == ReportChartType.pie) {
      final List<double> values = chart.series.first.values;
      final double total = values.fold<double>(0, (double a, double b) => a + math.max(0, b));
      return Row(
        children: <Widget>[
          SizedBox(
            width: 170,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 34,
                sectionsSpace: 1.5,
                sections: <PieChartSectionData>[
                  for (int i = 0; i < n; i++)
                    if (values[i] > 0)
                      PieChartSectionData(value: values[i], color: _paletteColor(i), radius: 44, showTitle: false),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (int i = 0; i < n; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        Container(width: 9, height: 9, color: _paletteColor(i)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(chart.labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textPrimary)),
                        ),
                        Text(
                          total > 0 ? '${(values[i] / total * 100).toStringAsFixed(1).replaceAll('.', ',')} %' : '',
                          style: axis,
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

    final double maxY = chart.maxValue <= 0 ? 1 : chart.maxValue * 1.12;
    final int every = n <= 8 ? 1 : (n / 8).ceil();
    final FlTitlesData titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          getTitlesWidget: (double value, TitleMeta meta) {
            if (value == meta.max && value != meta.min) return const SizedBox.shrink();
            return SideTitleWidget(meta: meta, child: Text(_compact(value), style: axis));
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: 1,
          getTitlesWidget: (double value, TitleMeta meta) {
            final int i = value.round();
            if (i < 0 || i >= n || i % every != 0 || value != i.toDouble()) return const SizedBox.shrink();
            return SideTitleWidget(meta: meta, child: Text(_short(chart.labels[i], n <= 5 ? 14 : 8), style: axis));
          },
        ),
      ),
    );
    final FlGridData grid = FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (double v) => const FlLine(color: AppTheme.dividerLight, strokeWidth: 1),
    );

    if (chart.type == ReportChartType.line) {
      return LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          lineBarsData: <LineChartBarData>[
            for (int s = 0; s < chart.series.length; s++)
              LineChartBarData(
                spots: <FlSpot>[for (int i = 0; i < n; i++) FlSpot(i.toDouble(), chart.series[s].values[i])],
                color: _paletteColor(s),
                barWidth: 2.2,
                dotData: FlDotData(show: n <= 20),
              ),
          ],
        ),
      );
    }

    final int k = chart.series.length;
    final double rodWidth = math.max(3, math.min(22, 300 / math.max(1, n * k)));
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: grid,
        borderData: FlBorderData(show: false),
        titlesData: titles,
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < n; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: <BarChartRodData>[
                for (int s = 0; s < k; s++)
                  BarChartRodData(
                    toY: chart.series[s].values[i],
                    color: _paletteColor(s),
                    width: rodWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
