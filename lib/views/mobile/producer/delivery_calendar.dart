import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';
import 'mobile_kit.dart';

const double _kRowHeight = 58;

int _rowsFor(DateTime month) {
  final int offset = DateTime(month.year, month.month, 1).weekday - 1;
  final int days = DateTime(month.year, month.month + 1, 0).day;
  return ((offset + days) / 7).ceil();
}

/// Calendario mensual propio con indicadores de jornada Mañana (M) / Tarde (T).
///
/// Cada día muestra el total entregado y dos mini barras cuya intensidad
/// depende de los litros de cada jornada frente al máximo del mes.
class DeliveryMonthGrid extends StatelessWidget {
  const DeliveryMonthGrid({
    super.key,
    required this.month,
    required this.summaries,
    required this.onDayTap,
    this.selectedIso,
    this.todayIso,
    this.rangeStart,
    this.rangeEnd,
  });

  final DateTime month;
  final Map<String, DayDeliverySummary> summaries;
  final ValueChanged<String> onDayTap;
  final String? selectedIso;
  final String? todayIso;
  final String? rangeStart;
  final String? rangeEnd;

  bool _inRange(String iso) {
    if (rangeStart != null && iso.compareTo(rangeStart!) < 0) return false;
    if (rangeEnd != null && iso.compareTo(rangeEnd!) > 0) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int offset = first.weekday - 1;
    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int rows = _rowsFor(month);

    double maxShift = 0;
    for (int d = 1; d <= days; d++) {
      final DayDeliverySummary? s = summaries[MobileDates.iso(DateTime(month.year, month.month, d))];
      if (s == null) continue;
      maxShift = math.max(maxShift, math.max(s.morningLiters, s.afternoonLiters));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int r = 0; r < rows; r++)
          SizedBox(
            height: _kRowHeight,
            child: Row(
              children: <Widget>[
                for (int c = 0; c < 7; c++)
                  Expanded(
                    child: () {
                      final int day = r * 7 + c - offset + 1;
                      if (day < 1 || day > days) return const SizedBox.shrink();
                      final String iso = MobileDates.iso(DateTime(month.year, month.month, day));
                      return _DayCell(
                        key: ValueKey<String>('cal-day-$iso'),
                        iso: iso,
                        day: day,
                        summary: summaries[iso],
                        maxShift: maxShift,
                        selected: iso == selectedIso,
                        today: iso == todayIso,
                        enabled: _inRange(iso),
                        onTap: () => onDayTap(iso),
                      );
                    }(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.iso,
    required this.day,
    required this.summary,
    required this.maxShift,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.onTap,
  });

  final String iso;
  final int day;
  final DayDeliverySummary? summary;
  final double maxShift;
  final bool selected;
  final bool today;
  final bool enabled;
  final VoidCallback onTap;

  double _intensity(double liters) {
    if (liters <= 0 || maxShift <= 0) return 0;
    return (0.35 + 0.65 * (liters / maxShift)).clamp(0.35, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final DayDeliverySummary? s = summary;
    final bool has = s != null && s.hasDeliveries;
    final Color numberColor = !enabled
        ? AppTheme.textMuted.withValues(alpha: 0.45)
        : selected
            ? Colors.white
            : AppTheme.textPrimary;
    final Color litersColor = selected ? Colors.white.withValues(alpha: 0.9) : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? AppTheme.brand
            : has && enabled
                ? AppTheme.surfaceMuted
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: today && !selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.brand, width: 1.5),
                  )
                : null,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '$day',
                  style: MobileTokens.number(size: 14, color: numberColor, weight: today ? FontWeight.w800 : FontWeight.w600),
                ),
                SizedBox(
                  height: 15,
                  child: has && enabled
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            compactLiters(s.totalLiters),
                            style: MobileTokens.number(size: 11.5, color: litersColor, weight: FontWeight.w600),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _ShiftBar(
                      key: s != null && s.hasMorning ? ValueKey<String>('cal-m-$iso') : null,
                      color: MobileTokens.morning,
                      intensity: enabled ? _intensity(s?.morningLiters ?? 0) : 0,
                      onDark: selected,
                    ),
                    const SizedBox(width: 3),
                    _ShiftBar(
                      key: s != null && s.hasAfternoon ? ValueKey<String>('cal-t-$iso') : null,
                      color: MobileTokens.afternoon,
                      intensity: enabled ? _intensity(s?.afternoonLiters ?? 0) : 0,
                      onDark: selected,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShiftBar extends StatelessWidget {
  const _ShiftBar({super.key, required this.color, required this.intensity, required this.onDark});

  final Color color;
  final double intensity;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color fill = intensity <= 0
        ? (onDark ? Colors.white.withValues(alpha: 0.22) : AppTheme.border)
        : onDark
            ? Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: intensity)
            : color.withValues(alpha: intensity);
    return Container(
      width: 12,
      height: 5,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(99)),
    );
  }
}

/// Fila de iniciales de los días de la semana.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final String w in MobileDates.weekdayInitials)
          Expanded(
            child: Center(child: Text(w, style: MobileTokens.label(size: 12.5))),
          ),
      ],
    );
  }
}

/// Leyenda M / T del calendario.
class ShiftLegend extends StatelessWidget {
  const ShiftLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(width: 14, height: 6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99))),
            const SizedBox(width: 6),
            Text(t, style: MobileTokens.body(size: 13, color: AppTheme.textSecondary)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: <Widget>[
        item(MobileTokens.morning, 'Mañana'),
        item(MobileTokens.afternoon, 'Tarde'),
        Text('Más intenso = más litros', style: MobileTokens.body(size: 13, color: AppTheme.textMuted)),
      ],
    );
  }
}

/// Calendario con navegación entre meses por deslizamiento y flechas.
class DeliveryMonthPager extends StatefulWidget {
  const DeliveryMonthPager({
    super.key,
    required this.summaries,
    required this.minMonth,
    required this.maxMonth,
    required this.onDayTap,
    this.initialMonth,
    this.onMonthChanged,
    this.selectedIso,
    this.todayIso,
  });

  final Map<String, DayDeliverySummary> summaries;
  final DateTime minMonth;
  final DateTime maxMonth;
  final DateTime? initialMonth;
  final ValueChanged<String> onDayTap;
  final ValueChanged<DateTime>? onMonthChanged;
  final String? selectedIso;
  final String? todayIso;

  @override
  State<DeliveryMonthPager> createState() => _DeliveryMonthPagerState();
}

class _DeliveryMonthPagerState extends State<DeliveryMonthPager> {
  late final PageController _page;
  late int _index;

  int get _count {
    final DateTime a = widget.minMonth;
    final DateTime b = widget.maxMonth;
    return math.max(1, (b.year - a.year) * 12 + b.month - a.month + 1);
  }

  DateTime _monthAt(int i) => DateTime(widget.minMonth.year, widget.minMonth.month + i, 1);

  @override
  void initState() {
    super.initState();
    final DateTime init = widget.initialMonth ?? widget.maxMonth;
    _index = ((init.year - widget.minMonth.year) * 12 + init.month - widget.minMonth.month).clamp(0, _count - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final int target = (_index + delta).clamp(0, _count - 1);
    if (target == _index || !_page.hasClients) return;
    _page.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime current = _monthAt(_index);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _ArrowButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Mes anterior',
              onTap: _index > 0 ? () => _go(-1) : null,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  MobileDates.monthYear(current),
                  key: ValueKey<int>(_index),
                  textAlign: TextAlign.center,
                  style: MobileTokens.title(size: 16.5),
                ),
              ),
            ),
            _ArrowButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Mes siguiente',
              onTap: _index < _count - 1 ? () => _go(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const WeekdayHeader(),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: _rowsFor(current) * _kRowHeight,
          child: PageView.builder(
            controller: _page,
            itemCount: _count,
            onPageChanged: (int i) {
              setState(() => _index = i);
              widget.onMonthChanged?.call(_monthAt(i));
            },
            itemBuilder: (BuildContext context, int i) => SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: DeliveryMonthGrid(
                month: _monthAt(i),
                summaries: widget.summaries,
                selectedIso: widget.selectedIso,
                todayIso: widget.todayIso,
                onDayTap: widget.onDayTap,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.surfaceMuted,
        disabledBackgroundColor: Colors.transparent,
        fixedSize: const Size(40, 40),
      ),
      icon: Icon(icon, color: onTap == null ? AppTheme.border : AppTheme.textPrimary),
    );
  }
}

// ── Detalle de día ──────────────────────────────────────────────────────────

({String text, MTone tone, IconData icon}) receptionStatus(MilkReceptionModel r) {
  if (r.anulado) return (text: 'Anulada', tone: MTone.danger, icon: Icons.block_rounded);
  if (r.isLiquidada) return (text: 'Liquidada', tone: MTone.success, icon: Icons.verified_rounded);
  if (r.isSynced || r.syncStatus == AppConstants.syncSynced) {
    return (text: 'Sincronizada', tone: MTone.brand, icon: Icons.cloud_done_rounded);
  }
  return (text: 'Por sincronizar', tone: MTone.warning, icon: Icons.cloud_upload_rounded);
}

/// Muestra el detalle de un día en una hoja inferior.
Future<void> showDayDetailSheet(
  BuildContext context, {
  required ProducerPortalController portal,
  required String isoDate,
  DayDeliverySummary? summary,
}) {
  final DayDeliverySummary s = summary ?? portal.daySummaries[isoDate] ?? DayDeliverySummary(isoDate: isoDate);
  return showMobileSheet<void>(
    context,
    builder: (BuildContext ctx) => DayDetailContent(portal: portal, summary: s),
  );
}

class DayDetailContent extends StatelessWidget {
  const DayDetailContent({super.key, required this.portal, required this.summary});

  final ProducerPortalController portal;
  final DayDeliverySummary summary;

  @override
  Widget build(BuildContext context) {
    final List<MilkReceptionModel> all = <MilkReceptionModel>[...summary.receptions, ...summary.annulled]
      ..sort((MilkReceptionModel a, MilkReceptionModel b) => a.horaEntrega.compareTo(b.horaEntrega));
    final double value = summary.receptions.fold<double>(
      0,
      (double acc, MilkReceptionModel r) => acc + r.litros * portal.priceForReception(r),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(MobileDates.longIso(summary.isoDate), style: MobileTokens.title(size: 19)),
          const SizedBox(height: 4),
          Text(
            summary.hasDeliveries
                ? '${summary.receptions.length} entrega(s) registradas'
                : 'Sin entregas registradas este día',
            style: MobileTokens.body(size: 14, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _ShiftTotal(label: 'Mañana', liters: summary.morningLiters, color: MobileTokens.morning, icon: Icons.wb_sunny_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _ShiftTotal(label: 'Tarde', liters: summary.afternoonLiters, color: MobileTokens.afternoon, icon: Icons.wb_twilight_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppTheme.brandSoft, borderRadius: BorderRadius.circular(MobileTokens.radiusSm)),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Total del día', style: MobileTokens.label(color: AppTheme.brand)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(AppFormatters.formatLiters(summary.totalLiters), style: MobileTokens.number(size: 18, color: AppTheme.brandDeep)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text('Valor estimado', style: MobileTokens.label(color: AppTheme.brand)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(AppFormatters.formatCurrency(value), style: MobileTokens.number(size: 18, color: AppTheme.brandDeep)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (all.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text('Registros', style: MobileTokens.title(size: 15.5)),
            const SizedBox(height: 8),
            for (final MilkReceptionModel r in all) _ReceptionLine(portal: portal, reception: r),
          ],
        ],
      ),
    );
  }
}

class _ShiftTotal extends StatelessWidget {
  const _ShiftTotal({required this.label, required this.liters, required this.color, required this.icon});

  final String label;
  final double liters;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: MobileTokens.body(size: 13.5, color: AppTheme.textSecondary, weight: FontWeight.w600)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    liters > 0 ? AppFormatters.formatLiters(liters) : '—',
                    style: MobileTokens.number(size: 16.5),
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

class _ReceptionLine extends StatelessWidget {
  const _ReceptionLine({required this.portal, required this.reception});

  final ProducerPortalController portal;
  final MilkReceptionModel reception;

  @override
  Widget build(BuildContext context) {
    final MilkReceptionModel r = reception;
    final bool afternoon = DayDeliverySummary.isAfternoon(r);
    final ({String text, MTone tone, IconData icon}) st = receptionStatus(r);
    final SettlementModel? settlement = portal.settlementForReception(r);
    final double price = portal.priceForReception(r);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconChip(
                afternoon ? Icons.wb_twilight_rounded : Icons.wb_sunny_rounded,
                tone: afternoon ? MTone.accent : MTone.brand,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      afternoon ? 'Jornada tarde' : 'Jornada mañana',
                      style: MobileTokens.body(size: 14.5, color: AppTheme.textPrimary, weight: FontWeight.w700),
                    ),
                    Text(MobileDates.hhmm(r.horaEntrega), style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppFormatters.formatLiters(r.litros),
                    style: MobileTokens.number(
                      size: 16.5,
                      color: r.anulado ? AppTheme.textMuted : AppTheme.textPrimary,
                    ).copyWith(decoration: r.anulado ? TextDecoration.lineThrough : null),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TonePill(st.text, tone: st.tone, icon: st.icon),
              if (!r.anulado)
                Text(
                  '≈ ${AppFormatters.formatCurrency(r.litros * price)}  ·  ${AppFormatters.formatCurrency(price)}/L',
                  style: MobileTokens.body(size: 13, color: AppTheme.textSecondary),
                ),
            ],
          ),
          if (settlement != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Comprobante ${settlement.numeroComprobante}',
              style: MobileTokens.body(size: 13, color: AppTheme.successText, weight: FontWeight.w600),
            ),
          ],
          if (r.anulado && (r.motivoAnulacion ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text('Motivo: ${r.motivoAnulacion}', style: MobileTokens.body(size: 13, color: AppTheme.dangerText)),
          ],
        ],
      ),
    );
  }
}
