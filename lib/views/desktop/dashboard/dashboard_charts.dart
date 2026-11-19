import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/services/forecast_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'dashboard_metrics.dart';

/// Formato compacto para ejes: 950, 12 k, 1,2 M.
String compactNumber(double v) {
  final double a = v.abs();
  String fmt(double x) {
    final String s = x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s.replaceAll('.', ',');
  }

  if (a >= 1e9) return '${fmt(v / 1e9)} B';
  if (a >= 1e6) return '${fmt(v / 1e6)} M';
  if (a >= 1e3) return '${fmt(v / 1e3)} k';
  return v.toStringAsFixed(0);
}

double _niceMax(double v) {
  if (!(v > 0) || !v.isFinite) return 1;
  final double exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final double m in <double>[1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
    if (v <= m * exp) return m * exp;
  }
  return 10 * exp;
}

FlTitlesData _titles({
  required double interval,
  required Widget Function(double value, TitleMeta meta) bottom,
  double bottomInterval = 1,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 40,
        interval: interval,
        getTitlesWidget: (double value, TitleMeta meta) {
          if (value == meta.max && value != meta.min) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(compactNumber(value), style: AppTheme.monoStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: bottomInterval,
        getTitlesWidget: bottom,
      ),
    ),
  );
}

FlGridData get _grid => FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (double v) => const FlLine(color: AppTheme.dividerLight, strokeWidth: 1),
    );

/// Tendencia diaria del rango con el período anterior superpuesto (punteado).
class DailyTrendChart extends StatelessWidget {
  const DailyTrendChart({super.key, required this.days, required this.prevDays, this.height = 220});

  final List<DayTotal> days;
  final List<DayTotal> prevDays;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (days.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Selecciona un rango de varios días para ver la tendencia diaria.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }
    double maxY = 0;
    for (final DayTotal d in days) {
      maxY = math.max(maxY, d.total);
    }
    for (final DayTotal d in prevDays) {
      maxY = math.max(maxY, d.total);
    }
    final double top = _niceMax(maxY * 1.08);
    final int n = days.length;
    final double labelEvery = math.max(1, (n / 7).ceil()).toDouble();
    final List<FlSpot> cur = <FlSpot>[for (int i = 0; i < n; i++) FlSpot(i.toDouble(), days[i].total)];
    final List<FlSpot> prev = <FlSpot>[
      for (int i = 0; i < math.min(n, prevDays.length); i++) FlSpot(i.toDouble(), prevDays[i].total),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (n - 1).toDouble(),
          minY: 0,
          maxY: top,
          gridData: _grid,
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            interval: top / 4,
            bottomInterval: labelEvery,
            bottom: (double value, TitleMeta meta) {
              final int i = value.round();
              if (i < 0 || i >= n || value != i.toDouble()) return const SizedBox.shrink();
              final DateTime d = days[i].day;
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                  style: AppTheme.monoStyle(fontSize: 10.5, color: AppTheme.textMuted),
                ),
              );
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot _) => AppTheme.brandInk,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 220,
              getTooltipItems: (List<LineBarSpot> spots) => spots.map((LineBarSpot s) {
                final int i = s.x.round().clamp(0, n - 1);
                if (s.barIndex == 0) {
                  final DayTotal d = days[i];
                  return LineTooltipItem(
                    '${AppFormatters.formatDate(d.day)}\n',
                    AppTheme.bodyStyle(fontSize: 11, color: Colors.white70),
                    children: <TextSpan>[
                      TextSpan(
                        text: AppFormatters.formatLiters(d.total),
                        style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      TextSpan(
                        text: '\nMañana ${AppFormatters.formatLiters(d.morning)} · Tarde ${AppFormatters.formatLiters(d.afternoon)}',
                        style: AppTheme.bodyStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  );
                }
                return LineTooltipItem(
                  'Período anterior: ${AppFormatters.formatLiters(s.y)}',
                  AppTheme.bodyStyle(fontSize: 11, color: AppTheme.brandMuted),
                );
              }).toList(),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: cur,
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: AppTheme.brand,
              barWidth: 2.2,
              dotData: FlDotData(show: n <= 16),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[AppTheme.brand.withValues(alpha: 0.22), AppTheme.brand.withValues(alpha: 0.0)],
                ),
              ),
            ),
            if (prev.length >= 2)
              LineChartBarData(
                spots: prev,
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: AppTheme.textMuted,
                barWidth: 1.4,
                dashArray: const <int>[4, 4],
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      ),
    );
  }
}

/// Histórico mensual + proyección con banda de predicción al 80 %.
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.result, this.height = 230});

  final ForecastResult result;
  final double height;

  @override
  Widget build(BuildContext context) {
    final List<MonthActual> actual = result.history.where((MonthActual m) => !m.partial).toList();
    final List<MonthProjection> proj = <MonthProjection>[?result.currentMonth, ...result.months];
    final List<String> labels = <String>[
      for (final MonthActual m in actual) ForecastService.monthLabel(m.month),
      for (final MonthProjection p in proj) p.label,
    ];
    final int k = actual.length;
    final List<FlSpot> actualSpots = <FlSpot>[
      for (int i = 0; i < k; i++) FlSpot(i.toDouble(), actual[i].liters),
    ];
    final List<FlSpot> fc = <FlSpot>[
      if (k > 0) FlSpot((k - 1).toDouble(), actual.last.liters),
      for (int i = 0; i < proj.length; i++) FlSpot((k + i).toDouble(), proj[i].liters),
    ];
    final List<FlSpot> low = <FlSpot>[
      if (k > 0) FlSpot((k - 1).toDouble(), actual.last.liters),
      for (int i = 0; i < proj.length; i++) FlSpot((k + i).toDouble(), proj[i].litersLow),
    ];
    final List<FlSpot> high = <FlSpot>[
      if (k > 0) FlSpot((k - 1).toDouble(), actual.last.liters),
      for (int i = 0; i < proj.length; i++) FlSpot((k + i).toDouble(), proj[i].litersHigh),
    ];
    double maxY = 0;
    for (final FlSpot s in <FlSpot>[...actualSpots, ...high]) {
      maxY = math.max(maxY, s.y);
    }
    final double top = _niceMax(maxY * 1.05);
    final int total = labels.length;
    if (total < 2) return SizedBox(height: height);

    LineChartBarData invisible(List<FlSpot> spots) => LineChartBarData(
          spots: spots,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        );

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (total - 1).toDouble(),
          minY: 0,
          maxY: top,
          gridData: _grid,
          borderData: FlBorderData(show: false),
          extraLinesData: k > 0
              ? ExtraLinesData(verticalLines: <VerticalLine>[
                  VerticalLine(
                    x: (k - 1).toDouble(),
                    color: AppTheme.borderStrong,
                    strokeWidth: 1,
                    dashArray: const <int>[3, 3],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: AppTheme.overlineStyle(),
                      labelResolver: (_) => 'PROYECCIÓN',
                    ),
                  ),
                ])
              : const ExtraLinesData(),
          betweenBarsData: <BetweenBarsData>[
            BetweenBarsData(fromIndex: 2, toIndex: 3, color: AppTheme.accent.withValues(alpha: 0.16)),
          ],
          titlesData: _titles(
            interval: top / 4,
            bottom: (double value, TitleMeta meta) {
              final int i = value.round();
              if (i < 0 || i >= total || value != i.toDouble()) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  labels[i].split(' ').first,
                  style: AppTheme.bodyStyle(
                    fontSize: 10.5,
                    color: i >= k ? AppTheme.accentDeep : AppTheme.textMuted,
                    fontWeight: i >= k ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              );
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot _) => AppTheme.brandInk,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 240,
              getTooltipItems: (List<LineBarSpot> spots) => spots.map((LineBarSpot s) {
                final int i = s.x.round();
                if (s.barIndex == 0 && i < k) {
                  return LineTooltipItem(
                    '${labels[i]} · real\n',
                    AppTheme.bodyStyle(fontSize: 11, color: Colors.white70),
                    children: <TextSpan>[
                      TextSpan(
                        text: AppFormatters.formatLiters(s.y.roundToDouble()),
                        style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  );
                }
                if (s.barIndex == 1 && i >= k) {
                  final MonthProjection p = proj[i - k];
                  return LineTooltipItem(
                    '${p.label} · ${p.isCurrent ? 'cierre estimado' : 'proyección'}\n',
                    AppTheme.bodyStyle(fontSize: 11, color: Colors.white70),
                    children: <TextSpan>[
                      TextSpan(
                        text: AppFormatters.formatLiters(p.liters.roundToDouble()),
                        style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      TextSpan(
                        text: '\n80 %: ${compactNumber(p.litersLow)} – ${compactNumber(p.litersHigh)} L',
                        style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.accentSoft),
                      ),
                    ],
                  );
                }
                return null;
              }).toList(),
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: actualSpots,
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: AppTheme.brand,
              barWidth: 2.4,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: AppTheme.brand.withValues(alpha: 0.08)),
            ),
            LineChartBarData(
              spots: fc,
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: AppTheme.accent,
              barWidth: 2.4,
              dashArray: const <int>[6, 4],
              dotData: FlDotData(
                show: true,
                getDotPainter: (FlSpot s, double p, LineChartBarData b, int i) => FlDotCirclePainter(
                  radius: 3,
                  color: AppTheme.surface,
                  strokeWidth: 2,
                  strokeColor: AppTheme.accent,
                ),
              ),
            ),
            invisible(low),
            invisible(high),
          ],
        ),
        duration: const Duration(milliseconds: 250),
      ),
    );
  }
}
