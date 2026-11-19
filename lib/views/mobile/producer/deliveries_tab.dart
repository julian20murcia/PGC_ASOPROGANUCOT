import 'package:flutter/material.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'delivery_calendar.dart';
import 'mobile_kit.dart';

/// Pestaña "Mis entregas": calendario mensual con jornadas M/T y detalle por día.
class DeliveriesTab extends StatefulWidget {
  const DeliveriesTab({super.key, required this.portal, required this.onRefresh});

  final ProducerPortalController portal;
  final Future<void> Function() onRefresh;

  @override
  State<DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends State<DeliveriesTab> {
  DateTime? _month;
  String? _selectedIso;

  DateTime get _maxMonth {
    final DateTime ref = widget.portal.referenceDate;
    return DateTime(ref.year, ref.month, 1);
  }

  DateTime get _minMonth {
    final DateTime? earliest = MobileDates.parseIso(widget.portal.earliestDeliveryDate ?? '');
    final DateTime fallback = DateTime(_maxMonth.year, _maxMonth.month - 2, 1);
    if (earliest == null) return fallback;
    final DateTime e = DateTime(earliest.year, earliest.month, 1);
    return e.isBefore(fallback) ? e : fallback;
  }

  void _openDay(String iso, Map<String, DayDeliverySummary> summaries) {
    setState(() => _selectedIso = iso);
    showDayDetailSheet(context, portal: widget.portal, isoDate: iso, summary: summaries[iso]);
  }

  @override
  Widget build(BuildContext context) {
    final ProducerPortalController portal = widget.portal;
    final Map<String, DayDeliverySummary> summaries = portal.daySummaries;
    final DateTime month = _month ?? _maxMonth;
    final String prefix = '${month.year}-${month.month.toString().padLeft(2, '0')}-';
    final List<DayDeliverySummary> monthDays = summaries.values
        .where((DayDeliverySummary s) => s.isoDate.startsWith(prefix) && s.hasDeliveries)
        .toList()
      ..sort((DayDeliverySummary a, DayDeliverySummary b) => b.isoDate.compareTo(a.isoDate));
    final double liters = monthDays.fold<double>(0, (double s, DayDeliverySummary d) => s + d.totalLiters);
    final int deliveries = monthDays.fold<int>(0, (int s, DayDeliverySummary d) => s + d.receptions.length);
    final bool skeleton = portal.isLoading && !portal.hasLoaded;

    return RefreshIndicator(
      color: AppTheme.brand,
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('deliveries-list'),
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          GradientHeader(
            title: 'Mis entregas',
            subtitle: 'Lo que te registraron, día por día',
            bottom: _MonthSummary(
              monthLabel: MobileDates.monthYear(month),
              liters: liters,
              deliveries: deliveries,
              days: monthDays.length,
            ),
          ),
          if (skeleton)
            const TabSkeleton(rows: 4)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 16, MobileTokens.gutter, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (portal.fromCache) ...<Widget>[const OfflineBanner(), const SizedBox(height: 12)],
                  FadeSlideIn(
                    child: SoftCard(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          DeliveryMonthPager(
                            key: const ValueKey<String>('deliveries-calendar'),
                            summaries: summaries,
                            minMonth: _minMonth,
                            maxMonth: _maxMonth,
                            initialMonth: month,
                            selectedIso: _selectedIso,
                            todayIso: MobileDates.iso(portal.referenceDate),
                            onMonthChanged: (DateTime m) => setState(() => _month = m),
                            onDayTap: (String iso) => _openDay(iso, summaries),
                          ),
                          const SizedBox(height: 10),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: ShiftLegend(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: 'Días con entrega',
                    subtitle: monthDays.isEmpty ? null : 'Toca un día para ver el detalle',
                  ),
                  if (monthDays.isEmpty)
                    const SoftCard(
                      child: MobileEmpty(
                        icon: Icons.calendar_month_rounded,
                        title: 'Sin entregas en este mes',
                        message: 'Desliza el calendario para ver otros meses.',
                      ),
                    )
                  else
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < monthDays.length; i++) ...<Widget>[
                            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.dividerLight),
                            _DayRow(summary: monthDays[i], onTap: () => _openDay(monthDays[i].isoDate, summaries)),
                          ],
                        ],
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

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.monthLabel, required this.liters, required this.deliveries, required this.days});

  final String monthLabel;
  final double liters;
  final int deliveries;
  final int days;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MobileTokens.label(color: Colors.white.withValues(alpha: 0.72))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: MobileTokens.number(size: 18, color: Colors.white)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Resumen de $monthLabel',
            style: MobileTokens.body(size: 13.5, color: Colors.white, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              cell('Litros', AppFormatters.formatLiters(liters)),
              cell('Entregas', '$deliveries'),
              cell('Días', '$days'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.summary, required this.onTap});

  final DayDeliverySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? d = MobileDates.parseIso(summary.isoDate);
    Widget shift(String tag, double liters, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: liters > 0 ? 0.14 : 0.05), borderRadius: BorderRadius.circular(6)),
              child: Text(tag, style: MobileTokens.body(size: 11.5, color: liters > 0 ? color : AppTheme.textMuted, weight: FontWeight.w800)),
            ),
            const SizedBox(width: 4),
            Text(
              liters > 0 ? compactLiters(liters) : '—',
              style: MobileTokens.number(size: 13.5, color: AppTheme.textSecondary, weight: FontWeight.w600),
            ),
          ],
        );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppTheme.brandSoft, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text('${d?.day ?? ''}', style: MobileTokens.number(size: 16, color: AppTheme.brandDeep, weight: FontWeight.w800)),
                  Text(
                    d == null ? '' : MobileDates.weekdays[d.weekday - 1].substring(0, 3),
                    style: MobileTokens.body(size: 11.5, color: AppTheme.brand, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  shift('M', summary.morningLiters, MobileTokens.morning),
                  shift('T', summary.afternoonLiters, MobileTokens.afternoon),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(AppFormatters.formatLiters(summary.totalLiters), style: MobileTokens.number(size: 15.5)),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
