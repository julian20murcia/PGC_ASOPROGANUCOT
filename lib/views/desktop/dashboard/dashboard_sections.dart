import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/forecast_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shared/widgets/pro_ui.dart';
import 'dashboard_charts.dart';
import 'dashboard_metrics.dart';

/// Acceso directo compacto a un módulo.
class QuickLink {
  const QuickLink(this.label, this.icon, this.section);
  final String label;
  final IconData icon;
  final String section;
}

/// Fila delgada de accesos directos (sin tarjetas).
class QuickLinksRow extends StatelessWidget {
  const QuickLinksRow({super.key, required this.links, required this.onTap});
  final List<QuickLink> links;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('ACCESOS RÁPIDOS', style: AppTheme.overlineStyle()),
        ),
        for (final QuickLink l in links)
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              onPressed: () => onTap(l.section),
              icon: Icon(l.icon, size: 15),
              label: Text(l.label, style: const TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: AppTheme.textPrimary,
                backgroundColor: AppTheme.surface,
                side: const BorderSide(color: AppTheme.border),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }
}

/// Pulso del día: una sola línea con lo que pasa hoy en planta.
class TodayPulseBar extends StatelessWidget {
  const TodayPulseBar({
    super.key,
    required this.todayLiters,
    required this.morning,
    required this.afternoon,
    required this.producersToday,
    required this.activeProducers,
    required this.pendingSync,
    required this.isOnline,
  });

  final double todayLiters;
  final double morning;
  final double afternoon;
  final int producersToday;
  final int activeProducers;
  final int pendingSync;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, {Color? color}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$label ', style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
            Text(value, style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color ?? AppTheme.textPrimary)),
          ],
        );
    final Widget sep = Container(width: 1, height: 14, color: AppTheme.border);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.brandSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.brandMuted),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.today_rounded, size: 15, color: AppTheme.brand),
              const SizedBox(width: 6),
              Text('Litros acopiados hoy', style: AppTheme.bodyStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.brandDeep)),
              const SizedBox(width: 8),
              Text(
                AppFormatters.formatLiters(todayLiters),
                style: AppTheme.monoStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.brandDeep),
              ),
            ],
          ),
          sep,
          item('Mañana', AppFormatters.formatLiters(morning)),
          item('Tarde', AppFormatters.formatLiters(afternoon)),
          sep,
          item('Productores hoy', '$producersToday de $activeProducers'),
          sep,
          StatusBadge(
            isOnline ? 'En línea' : 'Sin conexión',
            tone: isOnline ? Tone.success : Tone.warning,
            dot: true,
          ),
          if (pendingSync > 0)
            StatusBadge('$pendingSync pendientes de sincronizar', tone: Tone.warning, icon: Icons.cloud_upload_outlined)
          else
            const StatusBadge('Todo sincronizado', tone: Tone.neutral, icon: Icons.cloud_done_outlined),
        ],
      ),
    );
  }
}

/// Barra horizontal fina con valor (para rankings y distribuciones).
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.leading,
    required this.label,
    required this.value,
    required this.fraction,
    this.sub,
    this.color = AppTheme.brand,
  });

  final Widget? leading;
  final String label;
  final String? sub;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: label,
                          style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                          children: <InlineSpan>[
                            if (sub != null)
                              TextSpan(text: '  $sub', style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(value, style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0,
                    minHeight: 5,
                    backgroundColor: AppTheme.surfaceSunken,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenido: mañana vs tarde + distribución por vereda.
class ShiftVeredaBody extends StatelessWidget {
  const ShiftVeredaBody({super.key, required this.metrics});
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final double total = metrics.morning + metrics.afternoon;
    final double mFrac = total > 0 ? metrics.morning / total : 0.5;
    final List<VeredaShare> veredas = metrics.veredas.take(6).toList();
    final double vMax = veredas.isEmpty ? 1 : veredas.first.liters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('MAÑANA VS TARDE', style: AppTheme.overlineStyle()),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: total <= 0
                ? Container(color: AppTheme.surfaceSunken)
                : Row(
                    children: <Widget>[
                      Expanded(flex: math.max(1, (mFrac * 1000).round()), child: Container(color: AppTheme.brand)),
                      Expanded(flex: math.max(1, ((1 - mFrac) * 1000).round()), child: Container(color: AppTheme.accent)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(child: _shiftLegend('Mañana', metrics.morning, total, AppTheme.brand)),
            Expanded(child: _shiftLegend('Tarde', metrics.afternoon, total, AppTheme.accent)),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text('LITROS POR VEREDA', style: AppTheme.overlineStyle()),
        const SizedBox(height: 4),
        if (veredas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Sin entregas en el período.', style: AppTheme.bodyStyle(color: AppTheme.textMuted)),
          )
        else
          for (final VeredaShare v in veredas)
            _BarRow(
              leading: null,
              label: v.name,
              sub: '${v.producers} prod.',
              value: '${AppFormatters.formatLiters(v.liters.roundToDouble(), withUnit: false)} L · '
                  '${total > 0 ? (v.liters / total * 100).toStringAsFixed(0) : 0} %',
              fraction: vMax > 0 ? v.liters / vMax : 0,
              color: AppTheme.chart3,
            ),
      ],
    );
  }

  Widget _shiftLegend(String label, double liters, double total, Color color) {
    return Row(
      children: <Widget>[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: '$label ',
              style: AppTheme.bodyStyle(fontSize: 12),
              children: <InlineSpan>[
                TextSpan(
                  text: AppFormatters.formatLiters(liters),
                  style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: total > 0 ? '  ${(liters / total * 100).toStringAsFixed(0)} %' : '',
                  style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Ranking de productores con barras.
class TopProducersBody extends StatelessWidget {
  const TopProducersBody({super.key, required this.metrics});
  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.top.isEmpty) {
      return const EmptyState(
        title: 'Sin entregas en el período',
        message: 'Cambia el rango de fechas para ver el ranking.',
        icon: Icons.leaderboard_outlined,
      );
    }
    final double max = metrics.top.first.liters;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < metrics.top.length; i++)
          _BarRow(
            leading: SizedBox(
              width: 18,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                style: AppTheme.monoStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i < 3 ? AppTheme.accentDeep : AppTheme.textMuted),
              ),
            ),
            label: metrics.top[i].name,
            sub: '${metrics.top[i].code} · ${metrics.top[i].deliveries} entregas',
            value: AppFormatters.formatLiters(metrics.top[i].liters),
            fraction: max > 0 ? metrics.top[i].liters / max : 0,
            color: i == 0 ? AppTheme.brand : AppTheme.brand.withValues(alpha: 0.65),
          ),
      ],
    );
  }
}

/// Una fila de alerta.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.tone, required this.icon, required this.title, this.detail});
  final Tone tone;
  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 14, color: tone.solid),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                if (detail != null)
                  Text(detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alertas: anomalías por productor, días sin entregas y calidad de datos.
class AlertsBody extends StatelessWidget {
  const AlertsBody({
    super.key,
    required this.metrics,
    required this.pendingSync,
    required this.pendingSettlements,
    required this.pendingSettlementsAmount,
    required this.showMoney,
    required this.activeProducers,
  });

  final DashboardMetrics metrics;
  final int pendingSync;
  final int pendingSettlements;
  final double pendingSettlementsAmount;
  final bool showMoney;
  final int activeProducers;

  String _days(List<DateTime> d) {
    final Iterable<String> s = d.take(6).map((DateTime x) => '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}');
    return s.join(', ') + (d.length > 6 ? ' y ${d.length - 6} más' : '');
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (final ProducerDrop d in metrics.drops.take(4)) {
      rows.add(_AlertRow(
        tone: d.recentDaily <= 0 ? Tone.danger : Tone.warning,
        icon: Icons.trending_down_rounded,
        title: d.recentDaily <= 0
            ? '${d.name} no ha entregado en el período'
            : '${d.name} bajó ${(d.change.abs() * 100).toStringAsFixed(0)} % sus entregas',
        detail: 'Promedio habitual ${AppFormatters.formatLiters(d.baselineDaily)}/día · ahora ${AppFormatters.formatLiters(d.recentDaily)}/día'
            '${d.daysSinceLast != null && d.daysSinceLast! > 1 ? ' · última entrega hace ${d.daysSinceLast} días' : ''}',
      ));
    }
    if (metrics.drops.length > 4) {
      rows.add(_AlertRow(
        tone: Tone.neutral,
        icon: Icons.more_horiz_rounded,
        title: '${metrics.drops.length - 4} productores más con caídas superiores al 30 %',
      ));
    }
    if (metrics.zeroDays.isNotEmpty) {
      rows.add(_AlertRow(
        tone: Tone.warning,
        icon: Icons.event_busy_outlined,
        title: '${metrics.zeroDays.length} ${metrics.zeroDays.length == 1 ? 'día' : 'días'} sin entregas en el período',
        detail: _days(metrics.zeroDays),
      ));
    }
    final int notDelivered = math.max(0, activeProducers - metrics.producersDelivered);
    if (metrics.elapsedDays > 0 && notDelivered > 0) {
      rows.add(_AlertRow(
        tone: Tone.info,
        icon: Icons.person_off_outlined,
        title: '$notDelivered productores activos sin entregas en el período',
      ));
    }
    if (pendingSync > 0 || metrics.unsyncedInRange > 0) {
      rows.add(_AlertRow(
        tone: Tone.warning,
        icon: Icons.cloud_off_outlined,
        title: '${math.max(pendingSync, metrics.unsyncedInRange)} registros pendientes de sincronizar',
        detail: 'Sincroniza para que reportes y liquidaciones usen datos completos.',
      ));
    }
    if (pendingSettlements > 0) {
      rows.add(_AlertRow(
        tone: Tone.accent,
        icon: Icons.receipt_long_outlined,
        title: '$pendingSettlements liquidaciones pendientes de pago',
        detail: showMoney ? 'Total por pagar ${AppFormatters.formatCurrency(pendingSettlementsAmount)}' : null,
      ));
    }
    if (rows.isEmpty) {
      return const EmptyState(
        title: 'Sin alertas',
        message: 'Entregas constantes y datos sincronizados.',
        icon: Icons.verified_outlined,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Predicciones
// ─────────────────────────────────────────────────────────────────────────────

Tone _insightTone(InsightTone t) => switch (t) {
      InsightTone.positive => Tone.success,
      InsightTone.negative => Tone.danger,
      InsightTone.warning => Tone.warning,
      InsightTone.neutral => Tone.info,
    };

IconData _insightIcon(InsightTone t) => switch (t) {
      InsightTone.positive => Icons.trending_up_rounded,
      InsightTone.negative => Icons.trending_down_rounded,
      InsightTone.warning => Icons.warning_amber_rounded,
      InsightTone.neutral => Icons.auto_awesome_outlined,
    };

/// Insignias de cabecera del panel de predicción (precisión y modelo).
class ForecastBadges extends StatelessWidget {
  const ForecastBadges({super.key, required this.result, this.compact = false});
  final ForecastResult result;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ModelScore? best = result.best;
    if (!result.isOk || best == null) return const SizedBox.shrink();
    final int acc = (best.accuracy * 100).round();
    final String detail = <String>[
      'Modelo elegido: ${best.label}${best.params.isEmpty ? '' : ' (${best.params})'}',
      'Validación de origen rodante: ${best.folds} cortes, ${result.historyDays} días de historia.',
      '',
      'Candidatos (sMAPE):',
      for (final ModelScore c in result.candidates) '• ${c.label}: ${(c.smape * 100).toStringAsFixed(1)} %',
    ].join('\n');
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Tooltip(
          message: detail,
          child: StatusBadge(
            'Precisión histórica $acc %',
            tone: acc >= 90 ? Tone.success : (acc >= 80 ? Tone.warning : Tone.danger),
            icon: Icons.verified_outlined,
          ),
        ),
        if (!compact) Tooltip(message: detail, child: StatusBadge(best.label, tone: Tone.brand, icon: Icons.functions_rounded)),
      ],
    );
  }
}

/// Cuerpo del panel de predicciones.
class ForecastBody extends StatelessWidget {
  const ForecastBody({
    super.key,
    required this.result,
    required this.insights,
    required this.showMoney,
    required this.financeLoaded,
    this.onConfigureFinance,
  });

  final ForecastResult result;
  final List<ForecastInsight> insights;
  final bool showMoney;
  final bool financeLoaded;
  final VoidCallback? onConfigureFinance;

  static String money(double v) => AppFormatters.formatCurrency(v.roundToDouble());
  static String liters(double v) => AppFormatters.formatLiters(v.roundToDouble());

  @override
  Widget build(BuildContext context) {
    if (!result.isOk) {
      final double progress = result.minDays > 0 ? result.historyDays / result.minDays : 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.hourglass_bottom_rounded, size: 18, color: AppTheme.accentDeep),
                const SizedBox(width: 8),
                Expanded(child: Text('Datos insuficientes para proyectar', style: AppTheme.subtitleStyle())),
              ],
            ),
            const SizedBox(height: 6),
            Text(result.message ?? '', style: AppTheme.bodyStyle(height: 1.4)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppTheme.surfaceSunken,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${result.historyDays} de ${result.minDays} días',
              style: AppTheme.monoStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            if (insights.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _InsightList(insights: insights.where((ForecastInsight i) => i.text != result.message).toList()),
            ],
          ],
        ),
      );
    }

    final bool finance = showMoney && result.financeConfigured;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 980;
        final Widget left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Scenarios(result: result, finance: finance),
            const SizedBox(height: 12),
            ForecastChart(result: result, height: wide ? 210 : 200),
            const SizedBox(height: 6),
            const _Legend(),
          ],
        );
        final Widget table = _ProjectionTable(result: result, finance: finance, showMoney: showMoney);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showMoney && financeLoaded && !result.financeConfigured) ...<Widget>[
              _FinanceNotice(onConfigure: onConfigureFinance),
              const SizedBox(height: 12),
            ],
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: 16),
                  Container(width: 1, height: 300, color: AppTheme.dividerLight),
                  const SizedBox(width: 16),
                  Expanded(flex: 6, child: table),
                ],
              )
            else ...<Widget>[
              left,
              const SizedBox(height: 12),
              table,
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text('CONCLUSIONES', style: AppTheme.overlineStyle()),
            const SizedBox(height: 4),
            _InsightList(insights: insights),
          ],
        );
      },
    );
  }
}

class _FinanceNotice extends StatelessWidget {
  const _FinanceNotice({this.onConfigure});
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.warningText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Configura el precio de venta en Tarifas por litro para estimar ganancias',
              style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.warningText, fontWeight: FontWeight.w500),
            ),
          ),
          if (onConfigure != null)
            TextButton(
              onPressed: onConfigure,
              style: TextButton.styleFrom(foregroundColor: AppTheme.warningText, visualDensity: VisualDensity.compact),
              child: const Text('Ir a Tarifas'),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t, {bool band = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: band ? 14 : 10,
              height: band ? 8 : 3,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Text(t, style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        );
    return Wrap(
      spacing: 12,
      children: <Widget>[
        dot(AppTheme.brand, 'Real'),
        dot(AppTheme.accent, 'Proyección'),
        dot(AppTheme.accent.withValues(alpha: 0.25), 'Banda 80 %', band: true),
      ],
    );
  }
}

class _Scenarios extends StatelessWidget {
  const _Scenarios({required this.result, required this.finance});
  final ForecastResult result;
  final bool finance;

  @override
  Widget build(BuildContext context) {
    final String until = result.months.isEmpty ? '' : result.months.last.label;
    final List<({String label, double value, Tone tone, String hint})> s = finance
        ? <({String label, double value, Tone tone, String hint})>[
            (label: 'Pesimista', value: result.totalNetLow ?? 0, tone: Tone.danger, hint: 'banda baja 80 %'),
            (label: 'Esperado', value: result.totalNet ?? 0, tone: Tone.brand, hint: 'acumulado a $until'),
            (label: 'Optimista', value: result.totalNetHigh ?? 0, tone: Tone.success, hint: 'banda alta 80 %'),
          ]
        : <({String label, double value, Tone tone, String hint})>[
            (label: 'Pesimista', value: result.totalLitersLow, tone: Tone.danger, hint: 'litros a $until'),
            (label: 'Esperado', value: result.totalLiters, tone: Tone.brand, hint: 'litros a $until'),
            (label: 'Optimista', value: result.totalLitersHigh, tone: Tone.success, hint: 'litros a $until'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          finance ? 'RESULTADO NETO ACUMULADO (5 MESES)' : 'LITROS PROYECTADOS (5 MESES)',
          style: AppTheme.overlineStyle(),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            for (int i = 0; i < s.length; i++) ...<Widget>[
              if (i > 0) Container(width: 1, height: 40, color: AppTheme.dividerLight, margin: const EdgeInsets.symmetric(horizontal: 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: s[i].tone.solid, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(s[i].label, style: AppTheme.bodyStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        finance ? ForecastBody.money(s[i].value) : ForecastBody.liters(s[i].value),
                        style: AppTheme.monoStyle(
                          fontSize: i == 1 ? 18 : 15,
                          fontWeight: FontWeight.w700,
                          color: finance && s[i].value < 0 ? AppTheme.dangerText : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(s[i].hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

String _span(ForecastResult r) => r.months.isEmpty
    ? ''
    : '${r.months.first.label.split(' ').first}–${r.months.last.label.split(' ').first}';

class _ProjectionTable extends StatelessWidget {
  const _ProjectionTable({required this.result, required this.finance, required this.showMoney});
  final ForecastResult result;
  final bool finance;
  final bool showMoney;

  @override
  Widget build(BuildContext context) {
    final List<MonthProjection> rows = <MonthProjection>[?result.currentMonth, ...result.months];
    final List<({String title, int flex, TextAlign align})> cols = <({String title, int flex, TextAlign align})>[
      (title: 'MES', flex: 4, align: TextAlign.start),
      (title: 'LITROS', flex: 3, align: TextAlign.end),
      (title: 'RANGO 80 %', flex: 4, align: TextAlign.end),
      if (showMoney) (title: 'COSTO COMPRA', flex: 4, align: TextAlign.end),
      if (finance) (title: 'INGRESOS', flex: 4, align: TextAlign.end),
      if (finance) (title: 'RESULTADO', flex: 4, align: TextAlign.end),
    ];

    Widget cell(String text, int i, {TextStyle? style}) => Expanded(
          flex: cols[i].flex,
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(
                text,
                textAlign: cols[i].align,
                maxLines: 1,
                style: style ?? AppTheme.monoStyle(fontSize: 12.5),
              ),
            ),
          ),
        );

    Widget row(MonthProjection? m, {bool total = false}) {
      final double l = total ? result.totalLiters : m!.liters;
      final double lo = total ? result.totalLitersLow : m!.litersLow;
      final double hi = total ? result.totalLitersHigh : m!.litersHigh;
      final double cost = total ? result.totalPurchase : m!.purchaseCost;
      final double? rev = total ? result.totalRevenue : m!.revenue;
      final double? net = total ? result.totalNet : m!.net;
      final FontWeight w = total ? FontWeight.w700 : FontWeight.w500;
      int i = 0;
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: total ? AppTheme.surfaceMuted : (m!.isCurrent ? AppTheme.brandSoft.withValues(alpha: 0.5) : null),
          border: const Border(bottom: BorderSide(color: AppTheme.dividerLight)),
        ),
        child: Row(
          children: <Widget>[
            cell(
              total ? 'Total ${_span(result)}' : (m!.isCurrent ? '${m.label.split(' ').first} · cierre' : m.label),
              i++,
              style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: total ? FontWeight.w700 : FontWeight.w500),
            ),
            cell(ForecastBody.liters(l), i++, style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: w)),
            cell('${compactNumber(lo)} – ${compactNumber(hi)}', i++, style: AppTheme.monoStyle(fontSize: 11.5, color: AppTheme.textMuted)),
            if (showMoney) cell(ForecastBody.money(cost), i++, style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: w)),
            if (finance) cell(ForecastBody.money(rev ?? 0), i++, style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: w)),
            if (finance)
              cell(
                ForecastBody.money(net ?? 0),
                i++,
                style: AppTheme.monoStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: (net ?? 0) < 0 ? AppTheme.dangerText : AppTheme.successText,
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < cols.length; i++)
                Expanded(
                  flex: cols[i].flex,
                  child: Text(cols[i].title, textAlign: cols[i].align, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.overlineStyle()),
                ),
            ],
          ),
        ),
        for (final MonthProjection m in rows) row(m),
        row(null, total: true),
        const SizedBox(height: 6),
        Text(
          finance
              ? 'Resultado = litros × (precio de venta − tarifa vigente) − costos operativos del mes. '
                  'El total suma los 5 meses siguientes (sin el mes en curso).'
              : 'Costo de compra = litros proyectados × tarifa vigente. El total suma los 5 meses siguientes.',
          style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted, height: 1.35),
        ),
      ],
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({required this.insights});
  final List<ForecastInsight> insights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final ForecastInsight i in insights)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(_insightIcon(i.tone), size: 15, color: _insightTone(i.tone).solid),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(i.text, style: AppTheme.bodyStyle(fontSize: 12.8, color: AppTheme.textPrimary, height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
