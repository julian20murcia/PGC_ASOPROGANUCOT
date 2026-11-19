import 'package:flutter/material.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/settlement_model.dart';
import 'mobile_kit.dart';
import 'settlement_detail_page.dart';

/// Pestaña "Liquidaciones": quincenas cerradas en tarjetas compactas.
class SettlementsTab extends StatelessWidget {
  const SettlementsTab({super.key, required this.portal, required this.onRefresh});

  final ProducerPortalController portal;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final List<SettlementModel> items = portal.settlements;
    final double paid = items.where((SettlementModel s) => s.isPagada).fold<double>(0, (double a, SettlementModel s) => a + s.valorTotalPagar);
    final double pending = items.where((SettlementModel s) => !s.isPagada).fold<double>(0, (double a, SettlementModel s) => a + s.valorTotalPagar);
    final bool skeleton = portal.isLoading && !portal.hasLoaded;

    return RefreshIndicator(
      color: AppTheme.brand,
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('settlements-list'),
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          GradientHeader(
            title: 'Liquidaciones',
            subtitle: 'Tus quincenas cerradas y desprendibles',
            bottom: _Totals(paid: paid, pending: pending, count: items.length),
          ),
          if (skeleton)
            const TabSkeleton(rows: 4, hero: false)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 16, MobileTokens.gutter, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (portal.fromCache) ...<Widget>[const OfflineBanner(), const SizedBox(height: 12)],
                  if (items.isEmpty)
                    const SoftCard(
                      child: MobileEmpty(
                        icon: Icons.receipt_long_rounded,
                        title: 'Aún no hay quincenas cerradas',
                        message: 'Cuando la asociación cierre una quincena, verás aquí tu liquidación y el desprendible de pago.',
                      ),
                    )
                  else
                    for (int i = 0; i < items.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 10),
                      FadeSlideIn(
                        index: i,
                        child: SettlementTile(
                          settlement: items[i],
                          onTap: () => openSettlementDetail(context, portal, items[i]),
                        ),
                      ),
                    ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Abre la pantalla de detalle de una quincena.
Future<void> openSettlementDetail(BuildContext context, ProducerPortalController portal, SettlementModel s) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => SettlementDetailPage(portal: portal, settlement: s),
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.paid, required this.pending, required this.count});

  final double paid;
  final double pending;
  final int count;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, {int flex = 3}) => Expanded(
          flex: flex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MobileTokens.label(color: Colors.white.withValues(alpha: 0.72))),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: MobileTokens.number(size: 17, color: Colors.white)),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: <Widget>[
          cell('Pagado', AppFormatters.formatCurrency(paid)),
          const SizedBox(width: 10),
          cell('Pendiente', AppFormatters.formatCurrency(pending)),
          const SizedBox(width: 10),
          cell('Quincenas', '$count', flex: 2),
        ],
      ),
    );
  }
}

/// Tarjeta compacta de quincena: período, litros, valor y estado.
class SettlementTile extends StatelessWidget {
  const SettlementTile({super.key, required this.settlement, required this.onTap});

  final SettlementModel settlement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SettlementModel s = settlement;
    final DateTime? start = MobileDates.parseIso(s.periodoInicio);
    final DateTime? end = MobileDates.parseIso(s.periodoFin);
    return SoftCard(
      key: ValueKey<String>('settlement-${s.liquidacionId}'),
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 60,
            decoration: BoxDecoration(
              gradient: MobileTokens.headerGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    start == null || end == null ? '—' : '${start.day}–${end.day}',
                    style: MobileTokens.number(size: 15, color: Colors.white, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  end == null ? '' : MobileDates.monthShort(end.month).toUpperCase(),
                  style: MobileTokens.body(size: 12, color: Colors.white.withValues(alpha: 0.8), weight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.quincenaLabel.isEmpty ? MobileDates.period(s.periodoInicio, s.periodoFin) : s.quincenaLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileTokens.body(size: 15, color: AppTheme.textPrimary, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppFormatters.formatLiters(s.totalLitros)} · ${s.cantidadEntregas} entregas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 6),
                TonePill(
                  s.isPagada ? 'Pagada' : 'Pendiente de pago',
                  tone: s.isPagada ? MTone.success : MTone.warning,
                  icon: s.isPagada ? Icons.check_circle_rounded : Icons.schedule_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(AppFormatters.formatCurrency(s.valorTotalPagar), style: MobileTokens.number(size: 16)),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
