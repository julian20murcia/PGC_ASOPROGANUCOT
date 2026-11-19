import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';
import '../../../models/user_model.dart';
import 'delivery_calendar.dart';
import 'mobile_kit.dart';
import 'producer_tour.dart';

/// Pestaña Inicio: saludo, carrusel de KPIs, gráfica, jornadas y quincena.
class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.portal,
    required this.user,
    required this.tourKeys,
    required this.onOpenTab,
    required this.onOpenProfile,
    required this.onOpenSettlement,
    required this.onRefresh,
  });

  final ProducerPortalController portal;
  final UserModel user;
  final ProducerTourKeys tourKeys;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onOpenProfile;
  final ValueChanged<SettlementModel> onOpenSettlement;
  final Future<void> Function() onRefresh;

  String get _firstName {
    final String full = (portal.activeProducer?.nombres ?? user.nombreCompleto).trim();
    if (full.isEmpty) return 'productor';
    return full.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final bool skeleton = portal.isLoading && !portal.hasLoaded;
    final DateTime now = DateTime.now();

    return RefreshIndicator(
      color: AppTheme.brand,
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('home-list'),
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _HomeHeader(
            greeting: '${MobileDates.greeting(now)}, $_firstName',
            dateLabel: MobileDates.longDay(now),
            initials: _initials(portal.activeProducer?.nombreCompleto ?? user.nombreCompleto),
            unread: portal.unreadNotificationsCount,
            onProfile: onOpenProfile,
            onNotices: () => onOpenTab(3),
            child: skeleton
                ? const Shimmer(child: SkeletonBox(height: 150, radius: MobileTokens.radius))
                : KpiCarousel(key: tourKeys.carousel, slides: _slides()),
          ),
          if (skeleton)
            const TabSkeleton(rows: 3, hero: true)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 16, MobileTokens.gutter, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (portal.fromCache) ...<Widget>[const OfflineBanner(), const SizedBox(height: 12)],
                  if (portal.errorMessage != null) ...<Widget>[
                    ErrorBanner(message: portal.errorMessage!, onRetry: onRefresh),
                    const SizedBox(height: 12),
                  ],
                  if (portal.activeProducer == null && portal.hasLoaded) ...<Widget>[
                    const SoftCard(
                      child: MobileEmpty(
                        icon: Icons.link_off_rounded,
                        title: 'Tu cuenta aún no está vinculada',
                        message: 'Pide en la asociación que vinculen tu ficha de productor para ver tus entregas.',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FadeSlideIn(
                    index: 0,
                    child: ProductionChartCard(key: tourKeys.chart, portal: portal),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(index: 1, child: _ShiftSplitCard(portal: portal)),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    index: 2,
                    child: _QuincenaCard(portal: portal, onOpenSettlement: onOpenSettlement, onOpenTab: onOpenTab),
                  ),
                  const SizedBox(height: 20),
                  FadeSlideIn(
                    index: 3,
                    child: _RecentDeliveries(portal: portal, onSeeAll: () => onOpenTab(1)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<KpiSlide> _slides() {
    final double? delta = portal.quincenaDeltaPercent;
    final ({String isoDate, double liters})? best = portal.bestDayLast30;
    final int streak = portal.deliveryStreakDays;
    return <KpiSlide>[
      KpiSlide(
        icon: Icons.water_drop_rounded,
        label: 'Leche esta quincena',
        value: portal.quincenaLiters,
        format: (double v) => AppFormatters.formatLiters(v),
        footnote: '${portal.quincenaDeliveriesCount} entregas · ${portal.currentQuincena.label}',
        tone: MTone.brand,
      ),
      KpiSlide(
        icon: Icons.payments_rounded,
        label: 'Valor estimado a recibir',
        value: portal.quincenaEstimatedAmount,
        format: (double v) => AppFormatters.formatCurrency(v.roundToDouble()),
        footnote: portal.activePricePerLiter > 0
            ? 'Tarifa vigente ${AppFormatters.formatCurrency(portal.activePricePerLiter)}/L'
            : 'Sin tarifa vigente registrada',
        tone: MTone.accent,
      ),
      KpiSlide(
        icon: Icons.insights_rounded,
        label: 'Promedio diario',
        value: portal.quincenaAverageDailyLiters,
        format: (double v) => AppFormatters.formatLiters(v),
        footnote: 'Por día con entrega en la quincena',
        tone: MTone.info,
      ),
      KpiSlide(
        icon: delta == null || delta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        label: 'Frente a la quincena anterior',
        value: delta ?? 0,
        format: (double v) => delta == null
            ? 'Sin comparación'
            : '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1).replaceAll('.', ',')} %',
        footnote: 'Anterior: ${AppFormatters.formatLiters(portal.previousQuincenaLiters)} en total',
        tone: delta == null ? MTone.neutral : (delta >= 0 ? MTone.success : MTone.danger),
      ),
      KpiSlide(
        icon: Icons.local_fire_department_rounded,
        label: 'Racha de entregas',
        value: streak.toDouble(),
        format: (double v) => '${v.round()} ${v.round() == 1 ? 'día' : 'días'}',
        footnote: streak > 0 ? 'Días seguidos entregando leche' : 'Tu racha empieza con la próxima entrega',
        tone: MTone.warning,
      ),
      KpiSlide(
        icon: Icons.emoji_events_rounded,
        label: 'Mejor día (30 días)',
        value: best?.liters ?? 0,
        format: (double v) => AppFormatters.formatLiters(v),
        footnote: best == null ? 'Aún sin entregas recientes' : MobileDates.longIso(best.isoDate),
        tone: MTone.brand,
      ),
    ];
  }
}

String _initials(String name) {
  final List<String> parts = name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'P';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

String initialsOf(String name) => _initials(name);

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.dateLabel,
    required this.initials,
    required this.unread,
    required this.onProfile,
    required this.onNotices,
    required this.child,
  });

  final String greeting;
  final String dateLabel;
  final String initials;
  final int unread;
  final VoidCallback onProfile;
  final VoidCallback onNotices;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(
        gradient: MobileTokens.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(0, top + 14, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileTokens.body(size: 13.5, color: Colors.white.withValues(alpha: 0.75), weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        greeting,
                        key: const ValueKey<String>('home-greeting'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileTokens.title(size: 22, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                HeaderIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Avisos',
                  badge: unread,
                  onPressed: onNotices,
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Mi perfil',
                  child: InkWell(
                    onTap: onProfile,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
                      ),
                      child: Text(initials, style: MobileTokens.body(size: 15, color: AppTheme.brandInk, weight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ── Carrusel de KPIs ────────────────────────────────────────────────────────

class KpiSlide {
  const KpiSlide({
    required this.icon,
    required this.label,
    required this.value,
    required this.format,
    required this.footnote,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final double value;
  final String Function(double) format;
  final String footnote;
  final MTone tone;
}

/// Carrusel auto-desplazable (pausa al tocar) con indicadores animados.
class KpiCarousel extends StatefulWidget {
  const KpiCarousel({super.key, required this.slides, this.interval = const Duration(seconds: 4)});

  final List<KpiSlide> slides;
  final Duration interval;

  @override
  State<KpiCarousel> createState() => _KpiCarouselState();
}

class _KpiCarouselState extends State<KpiCarousel> {
  final PageController _page = PageController(viewportFraction: 0.86);
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _tick());
  }

  void _tick() {
    if (!mounted || _paused || !_page.hasClients || widget.slides.length < 2) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    final int next = (_index + 1) % widget.slides.length;
    _page.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Listener(
          onPointerDown: (_) {
            _paused = true;
            _timer?.cancel();
          },
          onPointerUp: (_) {
            _paused = false;
            if (mounted) _start();
          },
          onPointerCancel: (_) {
            _paused = false;
            if (mounted) _start();
          },
          child: SizedBox(
            height: 150,
            child: PageView.builder(
              key: const ValueKey<String>('home-kpi-carousel'),
              controller: _page,
              padEnds: true,
              itemCount: widget.slides.length,
              onPageChanged: (int i) => setState(() => _index = i),
              itemBuilder: (BuildContext context, int i) => AnimatedBuilder(
                animation: _page,
                builder: (BuildContext context, Widget? child) {
                  double scale = 1;
                  if (_page.hasClients && _page.position.haveDimensions) {
                    final double d = ((_page.page ?? 0) - i).abs();
                    scale = 1 - math.min(d, 1) * 0.06;
                  } else if (i != _index) {
                    scale = 0.94;
                  }
                  return Transform.scale(scale: scale, child: child);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _KpiCard(slide: widget.slides[i]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < widget.slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _index ? AppTheme.accent : Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.slide});

  final KpiSlide slide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x33082826), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconChip(slide.icon, tone: slide.tone, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  slide.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileTokens.body(size: 14, color: AppTheme.textSecondary, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: AnimatedNumber(
              value: slide.value,
              format: slide.format,
              style: MobileTokens.display(size: 30, color: slide.tone == MTone.neutral ? AppTheme.textPrimary : AppTheme.brandInk),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            slide.footnote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── Gráfica de producción ───────────────────────────────────────────────────

class ProductionChartCard extends StatefulWidget {
  const ProductionChartCard({super.key, required this.portal});

  final ProducerPortalController portal;

  @override
  State<ProductionChartCard> createState() => _ProductionChartCardState();
}

class _ProductionChartCardState extends State<ProductionChartCard> {
  int _days = 7;
  bool _grown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _grown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ProducerDailySeriesPoint> series = widget.portal.lastDaysSeries(_days);
    final double total = series.fold<double>(0, (double s, ProducerDailySeriesPoint p) => s + p.totalLiters);
    final double maxY = series.fold<double>(0, (double m, ProducerDailySeriesPoint p) => math.max(m, p.totalLiters));
    final double top = maxY <= 0 ? 10 : maxY * 1.18;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Tu producción', style: MobileTokens.title(size: 16.5)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${AppFormatters.formatLiters(total)} en $_days días',
                        style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              _RangeToggle(
                value: _days,
                onChanged: (int v) => setState(() => _days = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: top,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: top / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.dividerLight, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: top / 4,
                      getTitlesWidget: (double v, TitleMeta meta) {
                        if (v == 0 || v >= top) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(compactLiters(v), style: MobileTokens.body(size: 11.5, color: AppTheme.textMuted)),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (double v, TitleMeta meta) {
                        final int i = v.toInt();
                        if (i < 0 || i >= series.length) return const SizedBox.shrink();
                        final bool show = _days == 7 || i % 5 == 4 || i == series.length - 1;
                        if (!show) return const SizedBox.shrink();
                        final DateTime? d = MobileDates.parseIso(series[i].isoDate);
                        final String label = d == null
                            ? ''
                            : _days == 7
                                ? MobileDates.weekdayInitials[d.weekday - 1]
                                : '${d.day}';
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(label, style: MobileTokens.body(size: 12, color: AppTheme.textMuted, weight: FontWeight.w600)),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.brandInk,
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipItem: (BarChartGroupData g, int gi, BarChartRodData rod, int ri) {
                      final ProducerDailySeriesPoint p = series[g.x];
                      return BarTooltipItem(
                        '${MobileDates.shortIso(p.isoDate)}\n',
                        MobileTokens.body(size: 12.5, color: Colors.white70),
                        children: <TextSpan>[
                          TextSpan(
                            text: AppFormatters.formatLiters(p.totalLiters),
                            style: MobileTokens.number(size: 14, color: Colors.white),
                          ),
                        ],
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
                          toY: _grown ? series[i].totalLiters : 0,
                          width: _days == 7 ? 18 : 6,
                          borderRadius: BorderRadius.circular(_days == 7 ? 6 : 3),
                          color: Colors.transparent,
                          rodStackItems: <BarChartRodStackItem>[
                            BarChartRodStackItem(0, _grown ? series[i].morningLiters : 0, MobileTokens.morning),
                            BarChartRodStackItem(
                              _grown ? series[i].morningLiters : 0,
                              _grown ? series[i].totalLiters : 0,
                              MobileTokens.afternoon,
                            ),
                          ],
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: top,
                            color: AppTheme.surfaceMuted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
            ),
          ),
          const SizedBox(height: 10),
          const ShiftLegend(),
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(int v, String label) {
      final bool active = v == value;
      return GestureDetector(
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            boxShadow: active ? AppTheme.shadowSm : null,
          ),
          child: Text(
            label,
            style: MobileTokens.body(size: 13.5, color: active ? AppTheme.brand : AppTheme.textMuted, weight: FontWeight.w700),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surfaceSunken, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[item(7, '7 días'), item(30, '30 días')],
      ),
    );
  }
}

// ── Mañana vs tarde ─────────────────────────────────────────────────────────

class _ShiftSplitCard extends StatelessWidget {
  const _ShiftSplitCard({required this.portal});

  final ProducerPortalController portal;

  @override
  Widget build(BuildContext context) {
    final double m = portal.quincenaMorningLiters;
    final double t = portal.quincenaAfternoonLiters;
    final double total = m + t;
    final double mp = total <= 0 ? 0.5 : m / total;

    Widget side(String label, double liters, double pct, Color color, IconData icon, CrossAxisAlignment align) => Expanded(
          child: Column(
            crossAxisAlignment: align,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: MobileTokens.body(size: 14, color: AppTheme.textSecondary, weight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(AppFormatters.formatLiters(liters), style: MobileTokens.number(size: 18)),
              ),
              Text(
                total <= 0 ? '—' : '${(pct * 100).round()} %',
                style: MobileTokens.body(size: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        );

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Mañana vs. tarde', style: MobileTokens.title(size: 16.5)),
          Text('En la quincena actual', style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted)),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              side('Mañana', m, mp, MobileTokens.morning, Icons.wb_sunny_rounded, CrossAxisAlignment.start),
              side('Tarde', t, 1 - mp, MobileTokens.afternoon, Icons.wb_twilight_rounded, CrossAxisAlignment.end),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.5, end: mp),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: math.max(1, (v * 1000).round()),
                      child: Container(color: total <= 0 ? AppTheme.border : MobileTokens.morning),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      flex: math.max(1, ((1 - v) * 1000).round()),
                      child: Container(color: total <= 0 ? AppTheme.border : MobileTokens.afternoon),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quincena en curso y última liquidación ─────────────────────────────────

class _QuincenaCard extends StatelessWidget {
  const _QuincenaCard({required this.portal, required this.onOpenSettlement, required this.onOpenTab});

  final ProducerPortalController portal;
  final ValueChanged<SettlementModel> onOpenSettlement;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final int elapsed = portal.quincenaElapsedDays;
    final int total = portal.quincenaTotalDays;
    final int left = portal.daysToQuincenaClose;
    final SettlementModel? last = portal.latestSettlement;
    final String closeLabel = MobileDates.shortIso(portal.currentQuincena.end);

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const IconChip(Icons.event_available_rounded, tone: MTone.accent, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Quincena en curso', style: MobileTokens.title(size: 16)),
                          Text(
                            left == 0 ? 'Cierra hoy, $closeLabel' : 'Cierra el $closeLabel · faltan $left días',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: total <= 0 ? 0 : elapsed / total),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double v, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      backgroundColor: AppTheme.surfaceSunken,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Día $elapsed de $total. El pago se programa después del cierre.',
                  style: MobileTokens.body(size: 13.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.dividerLight),
          InkWell(
            onTap: last == null ? () => onOpenTab(2) : () => onOpenSettlement(last),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Última liquidación', style: MobileTokens.label()),
                        const SizedBox(height: 2),
                        Text(
                          last == null ? 'Aún no tienes quincenas cerradas' : MobileDates.period(last.periodoInicio, last.periodoFin),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MobileTokens.body(size: 14, color: AppTheme.textPrimary, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (last != null) ...<Widget>[
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(AppFormatters.formatCurrency(last.valorTotalPagar), style: MobileTokens.number(size: 15.5)),
                          ),
                          const SizedBox(height: 2),
                          TonePill(last.isPagada ? 'Pagada' : 'Pendiente', tone: last.isPagada ? MTone.success : MTone.warning),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Últimas entregas ───────────────────────────────────────────────────────

class _RecentDeliveries extends StatelessWidget {
  const _RecentDeliveries({required this.portal, required this.onSeeAll});

  final ProducerPortalController portal;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final List<MilkReceptionModel> recent = portal.allReceptions.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: 'Últimas entregas',
          trailing: TextButton(onPressed: onSeeAll, child: const Text('Ver calendario')),
        ),
        if (recent.isEmpty)
          const SoftCard(
            child: MobileEmpty(
              icon: Icons.water_drop_outlined,
              title: 'Sin entregas todavía',
              message: 'Cuando entregues leche en el centro de acopio la verás aquí.',
            ),
          )
        else
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < recent.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 64, color: AppTheme.dividerLight),
                  InkWell(
                    onTap: () => showDayDetailSheet(context, portal: portal, isoDate: recent[i].fechaEntrega),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: <Widget>[
                          IconChip(
                            DayDeliverySummary.isAfternoon(recent[i]) ? Icons.wb_twilight_rounded : Icons.wb_sunny_rounded,
                            tone: DayDeliverySummary.isAfternoon(recent[i]) ? MTone.accent : MTone.brand,
                            size: 38,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  MobileDates.longIso(recent[i].fechaEntrega),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MobileTokens.body(size: 14.5, color: AppTheme.textPrimary, weight: FontWeight.w600),
                                ),
                                Text(
                                  '${DayDeliverySummary.isAfternoon(recent[i]) ? 'Tarde' : 'Mañana'} · ${MobileDates.hhmm(recent[i].horaEntrega)}',
                                  style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(AppFormatters.formatLiters(recent[i].litros), style: MobileTokens.number(size: 15.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
