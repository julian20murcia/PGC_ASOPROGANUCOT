import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../controllers/rate_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_rate_model.dart';
import '../../shared/widgets/pro_ui.dart';

String _pct(double v) =>
    '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1).replaceAll('.', ',')} %';

String _ago(DateTime d) {
  final int days = DateTime.now().difference(d.toLocal()).inDays;
  if (days < 0) return 'empieza en ${-days} día(s)';
  if (days == 0) return 'desde hoy';
  if (days == 1) return 'hace 1 día';
  if (days < 60) return 'hace $days días';
  return 'hace ${(days / 30).floor()} meses';
}

/// Precio vigente destacado, variación frente al anterior y desde cuándo rige.
class RateHeroPanel extends StatelessWidget {
  const RateHeroPanel({super.key, required this.ctrl});
  final RateController ctrl;

  @override
  Widget build(BuildContext context) {
    final MilkRateModel? active = ctrl.activeRate;
    final MilkRateModel? prev = ctrl.previousRate;
    final double? diff = ctrl.variationAmount;
    final double? pct = ctrl.variationPercent;

    if (active == null) {
      return const Panel(
        title: 'Tarifa vigente actual',
        icon: Icons.price_change_outlined,
        child: EmptyState(
          title: 'Sin tarifa registrada',
          message:
              'Publica la primera tarifa por litro para poder liquidar quincenas.',
          icon: Icons.price_change_outlined,
        ),
      );
    }

    final Tone tone = diff == null || diff == 0
        ? Tone.neutral
        : (diff > 0 ? Tone.warning : Tone.success);
    return Panel(
      title: 'Tarifa vigente actual',
      subtitle: 'Precio que se paga al productor por cada litro entregado',
      icon: Icons.price_change_outlined,
      trailing: const StatusBadge('Vigente', tone: Tone.success, dot: true),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final Widget price = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      AppFormatters.formatCurrency(active.precioPorLitro),
                      style: AppTheme.monoStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.brandDeep,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'por litro',
                      style: AppTheme.bodyStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (diff != null)
                    StatusBadge(
                      '${diff >= 0 ? '+' : '−'}${AppFormatters.formatCurrency(diff.abs())}${pct == null ? '' : ' (${_pct(pct)})'}',
                      tone: tone,
                      icon: diff > 0
                          ? Icons.arrow_upward_rounded
                          : (diff < 0
                                ? Icons.arrow_downward_rounded
                                : Icons.drag_handle_rounded),
                    ),
                  Text(
                    prev == null
                        ? 'Primera tarifa registrada'
                        : 'vs. anterior ${AppFormatters.formatCurrency(prev.precioPorLitro)}',
                    style: AppTheme.bodyStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ],
          );
          final Widget facts = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _fact(
                Icons.event_available_rounded,
                'Rige desde',
                '${AppFormatters.formatDate(active.fechaInicioVigencia)} · ${_ago(active.fechaInicioVigencia)}',
              ),
              const SizedBox(height: 8),
              _fact(
                Icons.notes_rounded,
                'Motivo',
                active.observacion.isEmpty
                    ? 'Sin observación'
                    : active.observacion,
              ),
              const SizedBox(height: 8),
              _fact(
                Icons.history_rounded,
                'Historial',
                '${ctrl.rates.length} tarifa(s) registradas',
              ),
            ],
          );
          if (c.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[price, const SizedBox(height: 14), facts],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 5, child: price),
              Container(
                width: 1,
                height: 84,
                color: AppTheme.dividerLight,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(flex: 6, child: facts),
            ],
          );
        },
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: AppTheme.bodyStyle(
              fontSize: 12.5,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyStyle(
              fontSize: 12.5,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Línea de tiempo de tarifas: gráfica escalonada + tabla compacta.
class RateHistoryPanel extends StatelessWidget {
  const RateHistoryPanel({super.key, required this.ctrl});
  final RateController ctrl;

  @override
  Widget build(BuildContext context) {
    final List<MilkRateModel> chrono = ctrl.chronological;
    return Panel(
      title: 'Historial de tarifas',
      subtitle:
          'Cada cambio queda registrado; los cierres usan la tarifa vigente al momento del cierre',
      icon: Icons.timeline_rounded,
      padding: EdgeInsets.zero,
      child: chrono.isEmpty
          ? const EmptyState(
              title: 'Sin historial',
              message: 'Aún no hay tarifas registradas.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 18, 8),
                  child: SizedBox(
                    height: 190,
                    child: _StepChart(rates: chrono),
                  ),
                ),
                const Divider(height: 1),
                _HistoryTable(ctrl: ctrl, rates: chrono.reversed.toList()),
              ],
            ),
    );
  }
}

class _StepChart extends StatelessWidget {
  const _StepChart({required this.rates});
  final List<MilkRateModel> rates;

  static double _x(DateTime d) =>
      d.toUtc().millisecondsSinceEpoch / Duration.millisecondsPerDay;

  @override
  Widget build(BuildContext context) {
    final List<FlSpot> spots = <FlSpot>[
      for (final MilkRateModel r in rates)
        FlSpot(_x(r.fechaInicioVigencia), r.precioPorLitro),
    ];
    final double todayX = _x(DateTime.now());
    if (spots.last.x < todayX) spots.add(FlSpot(todayX, spots.last.y));
    if (spots.length == 1) spots.add(FlSpot(spots.first.x + 1, spots.first.y));

    final double minY = spots.map((FlSpot s) => s.y).reduce(math.min);
    final double maxY = spots.map((FlSpot s) => s.y).reduce(math.max);
    final double pad = math.max((maxY - minY) * 0.25, maxY * 0.05 + 1);
    final double minX = spots.first.x;
    final double maxX = spots.last.x;
    final double xInterval = math.max((maxX - minX) / 4, 1);

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: math.max(0, minY - pad),
        maxY: maxY + pad,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.dividerLight, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 62,
              getTitlesWidget: (double v, TitleMeta meta) {
                if (v == meta.min || v == meta.max) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    AppFormatters.formatCurrency(v.roundToDouble()),
                    textAlign: TextAlign.right,
                    style: AppTheme.monoStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: xInterval,
              getTitlesWidget: (double v, TitleMeta meta) {
                if (v != meta.min &&
                    (v == meta.max ||
                        meta.max - v < xInterval * 0.6 ||
                        v - meta.min < xInterval * 0.6)) {
                  return const SizedBox.shrink();
                }
                final DateTime d = DateTime.fromMillisecondsSinceEpoch(
                  (v * Duration.millisecondsPerDay).round(),
                  isUtc: true,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    AppFormatters.formatDate(d),
                    style: AppTheme.monoStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.brandDeep,
            getTooltipItems: (List<LineBarSpot> items) => items.map((
              LineBarSpot s,
            ) {
              final DateTime d = DateTime.fromMillisecondsSinceEpoch(
                (s.x * Duration.millisecondsPerDay).round(),
                isUtc: true,
              );
              return LineTooltipItem(
                '${AppFormatters.formatCurrency(s.y)}/L\n${AppFormatters.formatDate(d)}',
                AppTheme.monoStyle(
                  fontSize: 11.5,
                  color: AppTheme.surface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: spots,
            isStepLineChart: true,
            lineChartStepData: const LineChartStepData(
              stepDirection: LineChartStepData.stepDirectionForward,
            ),
            color: AppTheme.brand,
            barWidth: 2.2,
            dotData: FlDotData(
              getDotPainter: (FlSpot s, double p, LineChartBarData b, int i) =>
                  FlDotCirclePainter(
                    radius: i == spots.length - 1 ? 0 : 3.5,
                    color: AppTheme.surface,
                    strokeWidth: 2,
                    strokeColor: AppTheme.brand,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.brand.withValues(alpha: 0.07),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTable extends StatelessWidget {
  const _HistoryTable({required this.ctrl, required this.rates});
  final RateController ctrl;
  final List<MilkRateModel> rates;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minHeight: 36),
          color: AppTheme.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: const Row(
            children: <Widget>[
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: DataHeaderCell('Precio/L'),
                ),
              ),
              SizedBox(width: 16),
              SizedBox(width: 120, child: DataHeaderCell('Variación')),
              SizedBox(width: 96, child: DataHeaderCell('Desde')),
              SizedBox(width: 96, child: DataHeaderCell('Hasta')),
              Expanded(child: DataHeaderCell('Motivo')),
              SizedBox(width: 84, child: DataHeaderCell('Estado')),
            ],
          ),
        ),
        const Divider(height: 1),
        for (int i = 0; i < rates.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, color: AppTheme.dividerLight),
          _row(rates[i]),
        ],
      ],
    );
  }

  Widget _row(MilkRateModel r) {
    final MilkRateModel? prev = ctrl.predecessorOf(r);
    final double? diff = prev == null
        ? null
        : r.precioPorLitro - prev.precioPorLitro;
    final double? pct = (prev == null || prev.precioPorLitro <= 0)
        ? null
        : diff! / prev.precioPorLitro * 100;
    final bool isActive = ctrl.activeRate?.tarifaId == r.tarifaId;
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Text(
                AppFormatters.formatCurrency(r.precioPorLitro),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.monoStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: Text(
                diff == null
                    ? '—'
                    : '${diff >= 0 ? '+' : '−'}${AppFormatters.formatCurrency(diff.abs())}${pct == null ? '' : ' · ${_pct(pct)}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.monoStyle(
                  fontSize: 12,
                  color: diff == null || diff == 0
                      ? AppTheme.textMuted
                      : (diff > 0
                            ? AppTheme.warningText
                            : AppTheme.successText),
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                AppFormatters.formatDate(r.fechaInicioVigencia),
                style: AppTheme.monoStyle(fontSize: 12.5),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                r.fechaFinVigencia == null
                    ? 'Actual'
                    : AppFormatters.formatDate(r.fechaFinVigencia!),
                style: AppTheme.monoStyle(
                  fontSize: 12.5,
                  color: r.fechaFinVigencia == null
                      ? AppTheme.brand
                      : AppTheme.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Tooltip(
                message: r.observacion,
                child: Text(
                  r.observacion.isEmpty ? '—' : r.observacion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(fontSize: 12.5),
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Align(
                alignment: Alignment.centerLeft,
                child: isActive
                    ? const StatusBadge(
                        'Vigente',
                        tone: Tone.success,
                        dot: true,
                      )
                    : const StatusBadge('Histórica', tone: Tone.neutral),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
