import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/producer_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/pro_ui.dart';

/// Panel lateral derecho con el detalle de un productor.
class ProducerDetailPanel extends StatelessWidget {
  const ProducerDetailPanel({
    super.key,
    required this.producer,
    required this.onClose,
    this.onEdit,
    this.onToggleStatus,
    this.onCreateAppAccess,
  });

  final ProducerModel producer;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleStatus;
  final VoidCallback? onCreateAppAccess;

  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();
    final ProducerModel p = ctrl.byId(producer.productorId) ?? producer;
    final ProducerDetailStats stats = ctrl.detailFor(p.productorId);
    final bool hasApp = ProducerController.hasAppAccess(p);

    return Material(
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Cabecera ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InitialsAvatar(p.nombreCompleto, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.nombreCompleto,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.subtitleStyle().copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${p.codigoAsociado} · CC ${p.cedula}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.monoStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          StatusBadge(
                            p.isActivo ? 'Activo' : 'Inactivo',
                            tone: p.isActivo ? Tone.success : Tone.neutral,
                            dot: true,
                          ),
                          StatusBadge(
                            hasApp ? 'Con app' : 'Sin app',
                            tone: hasApp ? Tone.brand : Tone.neutral,
                            icon: Icons.smartphone_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null ||
              onToggleStatus != null ||
              (onCreateAppAccess != null && !hasApp))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (onEdit != null)
                    FilledButton.tonalIcon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                    ),
                  if (onToggleStatus != null)
                    OutlinedButton.icon(
                      onPressed: onToggleStatus,
                      icon: Icon(
                        p.isActivo
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 16,
                      ),
                      label: Text(p.isActivo ? 'Inactivar' : 'Activar'),
                    ),
                  if (onCreateAppAccess != null && !hasApp)
                    OutlinedButton.icon(
                      onPressed: onCreateAppAccess,
                      icon: const Icon(Icons.smartphone_rounded, size: 16),
                      label: const Text('Crear acceso app'),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: <Widget>[
                _SectionTitle('Entregas · ${ctrl.period.label}'),
                const SizedBox(height: 8),
                _StatsGrid(
                  stats: stats.period,
                  loading: ctrl.isLoadingDeliveries,
                ),
                const SizedBox(height: 10),
                _ShiftSplit(stats: stats.period),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    const Expanded(child: _SectionTitle('Últimos 30 días')),
                    Text(
                      AppFormatters.formatLiters(stats.last30Total),
                      style: AppTheme.monoStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: _MiniBarChart(series: stats.last30Days),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Últimas entregas'),
                const SizedBox(height: 4),
                if (stats.recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Sin entregas en los últimos 30 días.',
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  )
                else
                  for (final MilkReceptionModel r in stats.recent)
                    _DeliveryRow(r),
                const SizedBox(height: 16),
                const _SectionTitle('Datos del productor'),
                const SizedBox(height: 6),
                _KeyValue(
                  'Celular',
                  p.telefono.isEmpty ? '—' : p.telefono,
                  mono: true,
                ),
                _KeyValue('Finca', p.nombreFinca),
                _KeyValue('Vereda', p.vereda),
                _KeyValue(
                  'Registrado',
                  AppFormatters.formatDate(p.fechaCreacion),
                ),
                _KeyValue('App móvil', hasApp ? 'Acceso activo' : 'Sin acceso'),
                const SizedBox(height: 16),
                const _SectionTitle('Autorización de datos · Ley 1581'),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    StatusBadge(
                      p.hasValidHabeasData
                          ? 'Autorizado'
                          : 'Pendiente de soporte',
                      tone: p.hasValidHabeasData ? Tone.success : Tone.warning,
                      icon: p.hasValidHabeasData
                          ? Icons.verified_user_outlined
                          : Icons.history_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (p.fechaAutorizacionDatos != null)
                  _KeyValue(
                    'Fecha',
                    AppFormatters.formatDate(p.fechaAutorizacionDatos!),
                  ),
                _KeyValue(
                  'Soporte',
                  p.soporteAutorizacion ?? 'Sin referencia registrada',
                ),
                if (p.avisoPrivacidad?['version'] != null)
                  _KeyValue(
                    'Aviso',
                    'Versión ${p.avisoPrivacidad!['version']}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTheme.overlineStyle(),
  );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value, {this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
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
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? AppTheme.monoStyle(fontSize: 12.5)
                  : AppTheme.bodyStyle(
                      fontSize: 12.5,
                      color: AppTheme.textPrimary,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.loading});
  final ProducerDeliveryStats stats;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(fontSize: 11.5),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                loading ? '…' : value,
                style: AppTheme.monoStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            cell('Litros', AppFormatters.formatLiters(stats.liters)),
            const VerticalDivider(width: 1, color: AppTheme.border),
            cell('Entregas', '${stats.deliveries}'),
            const VerticalDivider(width: 1, color: AppTheme.border),
            cell(
              'Promedio',
              AppFormatters.formatLiters(stats.averagePerDelivery),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra horizontal mañana vs tarde.
class _ShiftSplit extends StatelessWidget {
  const _ShiftSplit({required this.stats});
  final ProducerDeliveryStats stats;

  @override
  Widget build(BuildContext context) {
    final double total = stats.morningLiters + stats.afternoonLiters;
    final double ratio = total <= 0 ? 0.5 : stats.morningLiters / total;
    final int morningFlex = math.max(1, (ratio * 1000).round());
    final int afternoonFlex = math.max(1, 1000 - morningFlex);
    Widget legend(Color c, String label, double liters) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ', style: AppTheme.bodyStyle(fontSize: 12)),
        Text(
          AppFormatters.formatLiters(liters),
          style: AppTheme.monoStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: total <= 0
                ? const ColoredBox(color: AppTheme.surfaceSunken)
                : Row(
                    children: <Widget>[
                      Expanded(
                        flex: morningFlex,
                        child: const ColoredBox(color: AppTheme.brand),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: afternoonFlex,
                        child: const ColoredBox(color: AppTheme.accent),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: <Widget>[
            legend(AppTheme.brand, 'Mañana', stats.morningLiters),
            legend(AppTheme.accent, 'Tarde', stats.afternoonLiters),
          ],
        ),
      ],
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({required this.series});
  final List<DailyLiters> series;

  @override
  Widget build(BuildContext context) {
    final double maxY = series.fold<double>(
      0,
      (double m, DailyLiters d) => math.max(m, d.liters),
    );
    if (maxY <= 0) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
        child: Text(
          'Sin entregas en este lapso',
          style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }
    return BarChart(
      BarChartData(
        maxY: maxY * 1.15,
        alignment: BarChartAlignment.spaceBetween,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(
          show: true,
          border: const Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int i = value.toInt();
                if (i != 0 &&
                    i != series.length - 1 &&
                    i != series.length ~/ 2) {
                  return const SizedBox.shrink();
                }
                final DateTime d = series[i].day;
                return Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${d.day}/${d.month}',
                    style: AppTheme.bodyStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppTheme.brandDeep,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            getTooltipItem:
                (
                  BarChartGroupData group,
                  int groupIndex,
                  BarChartRodData rod,
                  int rodIndex,
                ) {
                  final DateTime d = series[group.x].day;
                  return BarTooltipItem(
                    '${AppFormatters.formatDate(d)}\n${AppFormatters.formatLiters(rod.toY)}',
                    AppTheme.bodyStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < series.length; i++)
            BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: series[i].liters,
                  width: 6,
                  color: series[i].liters > 0
                      ? AppTheme.brand
                      : AppTheme.surfaceSunken,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow(this.r);
  final MilkReceptionModel r;

  @override
  Widget build(BuildContext context) {
    final bool morning = r.jornada.toUpperCase() != AppConstants.shiftAfternoon;
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            morning ? Icons.wb_sunny_outlined : Icons.wb_twilight_rounded,
            size: 14,
            color: morning ? AppTheme.brand : AppTheme.accentDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${AppFormatters.formatIsoDate(r.fechaEntrega)} · ${morning ? 'Mañana' : 'Tarde'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (r.isLiquidada)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Liquidada',
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          Text(
            AppFormatters.formatLiters(r.litros),
            style: AppTheme.monoStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
