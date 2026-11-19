import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../controllers/rate_controller.dart';
import '../../controllers/reception_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/security/permissions.dart';
import '../../core/services/finance_config_service.dart';
import '../../core/services/forecast_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_date_range_picker.dart';
import '../shared/widgets/pro_ui.dart';
import 'dashboard/dashboard_charts.dart';
import 'dashboard/dashboard_metrics.dart';
import 'dashboard/dashboard_sections.dart';

/// Inicio: indicadores del rango elegido, comparación con el período anterior
/// y predicciones estadísticas a 5 meses (`RF-16`).
class DashboardModuleView extends StatefulWidget {
  const DashboardModuleView({super.key, this.onNavigateSection, this.financeLoader});

  /// Callback opcional con llave String ('recepcion', 'productores', 'liquidaciones', 'reportes', 'tarifas')
  /// para mantener desacoplado el widget de `AdminSection`.
  final ValueChanged<String>? onNavigateSection;

  /// Cargador de la configuración financiera (inyectable en pruebas).
  final Future<FinanceConfig> Function()? financeLoader;

  /// Solo pruebas: calcula la proyección en el mismo hilo (sin isolate).
  static bool debugSyncForecast = false;

  @override
  State<DashboardModuleView> createState() => _DashboardModuleViewState();
}

class _DashboardModuleViewState extends State<DashboardModuleView> {
  static const ForecastService _forecastService = ForecastService();

  DateRangeValue _range = DateRangePresets.quincenaOf(DateTime.now());
  FinanceConfig _finance = FinanceConfig.empty;
  bool _financeLoaded = false;

  // Memorización: los cálculos solo se rehacen si cambian los datos.
  Object? _metricsKey;
  DashboardMetrics? _metrics;
  Object? _forecastKey;
  ForecastResult? _forecast;
  Object? _forecastPendingKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshAll();
    });
    _loadFinance();
  }

  Future<void> _loadFinance() async {
    FinanceConfig cfg = FinanceConfig.empty;
    try {
      cfg = await (widget.financeLoader ?? () => FinanceConfigService().load())();
    } catch (_) {
      cfg = FinanceConfig.empty;
    }
    if (!mounted) return;
    setState(() {
      _finance = cfg;
      _financeLoaded = true;
    });
  }

  Future<void> _refreshAll() async {
    final bool isOnline = context.read<UserController>().isOnline;
    await Future.wait<void>(<Future<void>>[
      context.read<ReceptionController>().loadReceptions(isOnlineOverride: isOnline),
      context.read<ProducerController>().loadProducers(),
      context.read<RateController>().loadRates(),
      context.read<SettlementController>().loadData(),
      context.read<SyncController>().refreshPendingCount(),
    ]);
  }

  Future<void> _syncAndRefresh() async {
    final SyncController syncCtrl = context.read<SyncController>();
    await syncCtrl.syncNow(refreshMasters: true);
    if (!mounted) return;
    await Future.wait<void>(<Future<void>>[_refreshAll(), _loadFinance()]);
    if (!mounted) return;
    showAppToast(context, 'Indicadores del tablero actualizados.', tone: Tone.success);
  }

  DashboardMetrics _metricsFor(List<MilkReceptionModel> receptions, List<ProducerModel> producers, DateTime today) {
    final Object key = Object.hash(identityHashCode(receptions), receptions.length,
        identityHashCode(producers), producers.length, _range, AppFormatters.toIsoDate(today));
    if (_metrics == null || key != _metricsKey) {
      _metricsKey = key;
      _metrics = DashboardMetrics.compute(receptions: receptions, producers: producers, range: _range, today: today);
    }
    return _metrics!;
  }

  static ForecastResult _runForecast(List<DailyValue> series, DateTime today, FinanceInputs finance) {
    try {
      return _forecastService.forecast(series, today: today, finance: finance);
    } catch (_) {
      return const ForecastResult(
        status: ForecastStatus.insufficient,
        historyDays: 0,
        minDays: ForecastService.minHistoryDays,
        message: 'No fue posible calcular la proyección con los datos actuales.',
      );
    }
  }

  // Estático: el cierre enviado al isolate no debe capturar el State.
  static Future<ForecastResult> _forecastInBackground(
    List<DailyValue> series,
    DateTime today,
    FinanceInputs finance,
  ) =>
      Isolate.run(() => _runForecast(series, today, finance));

  /// La proyección (búsqueda de parámetros Holt-Winters + validación) es costosa:
  /// se calcula en un isolate para no congelar la interfaz. Mientras tanto se
  /// muestra la última proyección o un indicador de "calculando".
  ForecastResult _forecastFor(List<MilkReceptionModel> receptions, double price, DateTime today) {
    final Object key = Object.hash(identityHashCode(receptions), receptions.length, price,
        _finance.precioVentaLitro, _finance.costoOperativoMensual, AppFormatters.toIsoDate(today));
    if (_forecast != null && key == _forecastKey) return _forecast!;
    if (key != _forecastPendingKey) {
      _forecastPendingKey = key;
      final List<DailyValue> series = DashboardMetrics.dailySeries(receptions);
      final FinanceInputs finance = FinanceInputs(
        purchasePricePerLiter: price,
        salePricePerLiter: _finance.precioVentaLitro,
        monthlyOperatingCost: _finance.costoOperativoMensual,
      );
      if (DashboardModuleView.debugSyncForecast) {
        _forecast = _runForecast(series, today, finance);
        _forecastKey = key;
        return _forecast!;
      }
      _forecastInBackground(series, today, finance).then((ForecastResult r) {
        if (!mounted || _forecastPendingKey != key) return;
        setState(() {
          _forecast = r;
          _forecastKey = key;
        });
      }, onError: (Object _) {
        if (!mounted || _forecastPendingKey != key) return;
        setState(() {
          _forecast = _runForecast(series, today, finance);
          _forecastKey = key;
        });
      });
    }
    return _forecast ??
        const ForecastResult(
          status: ForecastStatus.computing,
          historyDays: 0,
          minDays: ForecastService.minHistoryDays,
        );
  }

  void _go(String section) => widget.onNavigateSection?.call(section);

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final ReceptionController recCtrl = context.watch<ReceptionController>();
    final ProducerController prodCtrl = context.watch<ProducerController>();
    final RateController rateCtrl = context.watch<RateController>();
    final SettlementController setCtrl = context.watch<SettlementController>();
    final SyncController syncCtrl = context.watch<SyncController>();
    final UserController userCtrl = context.watch<UserController>();

    final UserModel? user = auth.currentUser;
    bool can(String module, [String action = PermAction.ver]) => user?.can(module, action) ?? false;
    final bool showMoney = can(Permissions.liquidaciones) || can(Permissions.tarifas) || can(Permissions.reportes);

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String todayIso = AppFormatters.toIsoDate(today);
    final List<MilkReceptionModel> receptions = recCtrl.allReceptions;
    final List<ProducerModel> producers =
        prodCtrl.allProducers.isNotEmpty ? prodCtrl.allProducers : recCtrl.activeProducers;
    final DashboardMetrics m = _metricsFor(receptions, producers, today);
    final double price = rateCtrl.effectivePricePerLiter;
    final ForecastResult forecast = _forecastFor(receptions, price, today);
    final List<ForecastInsight> insights = ForecastService.buildInsights(
      showMoney ? forecast : _withoutFinance(forecast),
      drops: m.drops,
    );

    final int activeProducers = producers.where((ProducerModel p) => p.isActivo).length;
    final int producersToday = receptions
        .where((MilkReceptionModel r) => !r.anulado && r.fechaEntrega == todayIso)
        .map((MilkReceptionModel r) => r.productorId)
        .toSet()
        .length;
    final int pendingSync =
        syncCtrl.pendingCount > recCtrl.pendingSyncCount ? syncCtrl.pendingCount : recCtrl.pendingSyncCount;

    final List<QuickLink> links = <QuickLink>[
      if (can(Permissions.recepcion, PermAction.crear))
        const QuickLink('Registrar entrega', Icons.add_circle_outline_rounded, 'recepcion'),
      if (can(Permissions.productores)) const QuickLink('Productores', Icons.groups_2_outlined, 'productores'),
      if (can(Permissions.liquidaciones)) const QuickLink('Liquidaciones', Icons.receipt_long_outlined, 'liquidaciones'),
      if (can(Permissions.tarifas)) const QuickLink('Tarifas', Icons.sell_outlined, 'tarifas'),
      if (can(Permissions.reportes)) const QuickLink('Reportes', Icons.insights_outlined, 'reportes'),
    ];

    final double toPay = m.liters * price;
    final double prevToPay = m.prevLiters * price;
    final List<StatItem> stats = <StatItem>[
      StatItem(
        label: 'Litros del período',
        value: AppFormatters.formatLiters(m.liters),
        icon: Icons.water_drop_outlined,
        delta: DashboardMetrics.delta(m.liters, m.prevLiters),
        hint: m.elapsedDays < m.range.days ? 'vs. mismos días del período anterior' : 'vs. período anterior',
      ),
      StatItem(
        label: 'Promedio diario',
        value: AppFormatters.formatLiters(m.dailyAvg),
        icon: Icons.show_chart_rounded,
        tone: Tone.info,
        delta: DashboardMetrics.delta(m.dailyAvg, m.prevDailyAvg),
        hint: '${m.elapsedDays} ${m.elapsedDays == 1 ? 'día' : 'días'} transcurridos',
      ),
      StatItem(
        label: 'Entregas',
        value: '${m.deliveries}',
        icon: Icons.local_shipping_outlined,
        tone: Tone.neutral,
        delta: DashboardMetrics.delta(m.deliveries, m.prevDeliveries),
      ),
      StatItem(
        label: 'Productores que entregaron',
        value: '${m.producersDelivered}',
        icon: Icons.groups_2_outlined,
        tone: Tone.brand,
        delta: DashboardMetrics.delta(m.producersDelivered, m.prevProducersDelivered),
        hint: 'de $activeProducers activos',
      ),
      if (showMoney) ...<StatItem>[
        StatItem(
          label: 'Valor a pagar (estimado)',
          value: AppFormatters.formatCurrency(toPay.roundToDouble()),
          icon: Icons.payments_outlined,
          tone: Tone.accent,
          delta: DashboardMetrics.delta(toPay, prevToPay),
          deltaPositiveIsGood: true,
          hint: price > 0 ? null : 'sin tarifa vigente',
        ),
        StatItem(
          label: 'Precio vigente',
          value: price > 0 ? '${AppFormatters.formatCurrency(price)}/L' : 'Sin tarifa',
          icon: Icons.sell_outlined,
          tone: Tone.info,
          delta: rateCtrl.variationPercent == null ? null : rateCtrl.variationPercent! / 100,
          hint: rateCtrl.variationPercent == null ? null : 'vs. tarifa anterior',
        ),
        StatItem(
          label: 'Liquidaciones pendientes',
          value: '${setCtrl.pendingCount}',
          icon: Icons.receipt_long_outlined,
          tone: setCtrl.pendingCount > 0 ? Tone.warning : Tone.success,
          hint: AppFormatters.formatCurrency(setCtrl.totalPendingAmount),
        ),
      ],
      StatItem(
        label: 'Días sin entregas',
        value: '${m.zeroDays.length}',
        icon: Icons.event_busy_outlined,
        tone: m.zeroDays.isEmpty ? Tone.success : Tone.warning,
        hint: m.unsyncedInRange > 0 ? '${m.unsyncedInRange} sin sincronizar' : 'datos completos',
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = c.maxWidth;
        final bool narrow = width < 900;
        final bool wide = width >= 1100;
        final double pad = narrow ? 16 : 24;

        final Widget trendPanel = Panel(
          title: 'Tendencia diaria',
          subtitle: 'Litros por día · ${m.range.label}',
          icon: Icons.show_chart_rounded,
          trailing: const _ChartLegend(),
          child: DailyTrendChart(days: m.days, prevDays: m.prevDays, height: 230),
        );
        final Widget shiftPanel = Panel(
          title: 'Jornadas y veredas',
          subtitle: 'Distribución del período',
          icon: Icons.pie_chart_outline_rounded,
          child: ShiftVeredaBody(metrics: m),
        );
        final Widget topPanel = Panel(
          title: 'Top productores',
          subtitle: 'Ranking por litros del período',
          icon: Icons.leaderboard_outlined,
          child: TopProducersBody(metrics: m),
        );
        final Widget alertsPanel = Panel(
          title: 'Alertas y calidad de datos',
          subtitle: 'Caídas > 30 % frente al promedio de cada productor',
          icon: Icons.notifications_active_outlined,
          child: AlertsBody(
            metrics: m,
            pendingSync: pendingSync,
            pendingSettlements: setCtrl.pendingCount,
            pendingSettlementsAmount: setCtrl.totalPendingAmount,
            showMoney: showMoney,
            activeProducers: activeProducers,
          ),
        );
        final Widget forecastPanel = Panel(
          title: 'Predicción inteligente · próximos 5 meses',
          subtitle: forecast.isOk
              ? 'Modelo estadístico elegido por validación cruzada · confianza ${forecast.confidenceLabel}'
              : 'Se activa con suficiente historia de entregas',
          icon: Icons.auto_graph_rounded,
          trailing: ForecastBadges(result: forecast, compact: narrow),
          child: ForecastBody(
            result: showMoney ? forecast : _withoutFinance(forecast),
            insights: insights,
            showMoney: showMoney,
            financeLoaded: _financeLoaded,
            onConfigureFinance: can(Permissions.tarifas) && widget.onNavigateSection != null ? () => _go('tarifas') : null,
          ),
        );

        Widget pair(Widget a, Widget b, {int fa = 1, int fb = 1}) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: fa, child: a),
                  const SizedBox(width: 12),
                  Expanded(flex: fb, child: b),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[a, const SizedBox(height: 12), b],
              );

        final int perRow = width >= 1360 ? stats.length : (width >= 640 ? (stats.length / 2).ceil() : 2);

        return Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                PageHeader(
                  title: 'Resumen Operativo de Planta',
                  subtitle: 'Hola, ${user?.nombreCompleto.split(' ').first ?? 'equipo'} · '
                      'indicadores de ${m.range.label} comparados con el período anterior',
                  actions: <Widget>[
                    AppDateRangeField(
                      value: _range,
                      dense: true,
                      lastDate: DateTime(today.year + 1, 12, 31),
                      onChanged: (DateRangeValue r) => setState(() => _range = r),
                    ),
                    SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed: recCtrl.isLoading || syncCtrl.isSyncing ? null : _syncAndRefresh,
                        icon: recCtrl.isLoading || syncCtrl.isSyncing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: const Text('Actualizar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TodayPulseBar(
                  todayLiters: recCtrl.todayTotalLiters,
                  morning: recCtrl.todayMorningLiters,
                  afternoon: recCtrl.todayAfternoonLiters,
                  producersToday: producersToday,
                  activeProducers: activeProducers,
                  pendingSync: pendingSync,
                  isOnline: userCtrl.isOnline,
                ),
                if (links.isNotEmpty && widget.onNavigateSection != null) ...<Widget>[
                  const SizedBox(height: 10),
                  QuickLinksRow(links: links, onTap: _go),
                ],
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints sc) => StatStrip(
                    items: stats,
                    minItemWidth: sc.maxWidth / perRow - 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                pair(trendPanel, shiftPanel, fa: 3, fb: 2),
                const SizedBox(height: 12),
                forecastPanel,
                const SizedBox(height: 12),
                pair(topPanel, alertsPanel),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Copia del pronóstico sin datos financieros (usuarios sin permisos de dinero).
  static ForecastResult _withoutFinance(ForecastResult r) => ForecastResult(
        status: r.status,
        historyDays: r.historyDays,
        minDays: r.minDays,
        message: r.message,
        best: r.best,
        candidates: r.candidates,
        daily: r.daily,
        history: r.history,
        currentMonth: r.currentMonth,
        months: r.months,
        trend: r.trend,
        weekdayPattern: r.weekdayPattern,
        lastCompleteDay: r.lastCompleteDay,
      );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t, {bool dashed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 12,
              height: dashed ? 2 : 3,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 5),
            Text(t, style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        );
    return Wrap(
      spacing: 10,
      children: <Widget>[
        item(AppTheme.brand, 'Período'),
        item(AppTheme.textMuted, 'Anterior', dashed: true),
      ],
    );
  }
}
