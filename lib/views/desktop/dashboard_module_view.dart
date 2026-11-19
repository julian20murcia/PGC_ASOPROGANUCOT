import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../controllers/rate_controller.dart';
import '../../controllers/reception_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/reception_service.dart';
import '../../core/services/settlement_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/milk_reception_model.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';

/// Dashboard operativo en tiempo real de ASOPROGANUCOTT (`RF-16`).
class DashboardModuleView extends StatefulWidget {
  const DashboardModuleView({super.key, this.onNavigateSection});

  /// Callback opcional con llave String ('recepcion', 'productores', 'liquidaciones', 'reportes', 'tarifas')
  /// para mantener desacoplado el widget de `AdminSection`.
  final ValueChanged<String>? onNavigateSection;

  @override
  State<DashboardModuleView> createState() => _DashboardModuleViewState();
}

class _DashboardModuleViewState extends State<DashboardModuleView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    final bool isOnline = context.read<UserController>().isOnline;
    await Future.wait<void>(<Future<void>>[
      context.read<ReceptionController>().loadReceptions(
        isOnlineOverride: isOnline,
      ),
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
    await _refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Indicadores del tablero actualizados.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final ReceptionController recCtrl = context.watch<ReceptionController>();
    final ProducerController prodCtrl = context.watch<ProducerController>();
    final RateController rateCtrl = context.watch<RateController>();
    final SettlementController setCtrl = context.watch<SettlementController>();
    final SyncController syncCtrl = context.watch<SyncController>();
    final UserController userCtrl = context.watch<UserController>();

    final bool isAdmin = auth.currentUser?.isAdmin == true;
    final bool isNarrow = MediaQuery.of(context).size.width < 960;

    final String todayIso = ReceptionService.formatDate(DateTime.now());
    final List<MilkReceptionModel> todayDeliveries = recCtrl.allReceptions
        .where(
          (MilkReceptionModel r) => !r.anulado && r.fechaEntrega == todayIso,
        )
        .toList();

    final int todayUniqueProducers = todayDeliveries
        .map((MilkReceptionModel r) => r.productorId)
        .toSet()
        .length;
    final int activeProducersCount = prodCtrl.allProducers
        .where((p) => p.isActivo)
        .length;

    final int pendingSync = syncCtrl.pendingCount > recCtrl.pendingSyncCount
        ? syncCtrl.pendingCount
        : recCtrl.pendingSyncCount;

    final double quincenaLiters = recCtrl.quincenaTotalLiters;
    final double activePrice = rateCtrl.effectivePricePerLiter;
    final double quincenaEstimated = activePrice > 0
        ? SettlementCalculator.calculateTotalAmount(
            totalLiters: quincenaLiters,
            pricePerLiter: activePrice,
          )
        : 0;

    final Widget quickCard = _QuickOperationsCard(
      isAdmin: isAdmin,
      activePrice: activePrice,
      pendingSettlements: setCtrl.pendingCount,
      pendingSettlementsAmount: setCtrl.totalPendingAmount,
      todayUniqueProducers: todayUniqueProducers,
      activeProducersCount: activeProducersCount,
      onNavigateSection: widget.onNavigateSection,
    );

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 24,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _WelcomeBanner(
              isNarrow: isNarrow,
              isBusy: recCtrl.isLoading || syncCtrl.isSyncing,
              isOnline: userCtrl.isOnline,
              pendingSync: pendingSync,
              onRefresh: _syncAndRefresh,
              userName: auth.currentUser?.nombreCompleto ?? 'Planta Susa',
              quincenaLabel: recCtrl.currentQuincenaLabel,
            ),
            const SizedBox(height: 16),
            _buildKpiRow(
              isNarrow: isNarrow,
              recCtrl: recCtrl,
              quincenaLiters: quincenaLiters,
              quincenaEstimated: quincenaEstimated,
              activePrice: activePrice,
              todayUniqueProducers: todayUniqueProducers,
              activeProducersCount: activeProducersCount,
              pendingSync: pendingSync,
              isOnline: userCtrl.isOnline,
            ),
            const SizedBox(height: 16),
            if (isNarrow) ...<Widget>[
              _SevenDayChartCard(receptions: recCtrl.allReceptions),
              const SizedBox(height: 14),
              quickCard,
            ] else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      flex: 6,
                      child: _SevenDayChartCard(
                        receptions: recCtrl.allReceptions,
                        chartHeight: isAdmin ? 290 : 200,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: quickCard),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _buildTodayDeliveriesCard(todayDeliveries),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow({
    required bool isNarrow,
    required ReceptionController recCtrl,
    required double quincenaLiters,
    required double quincenaEstimated,
    required double activePrice,
    required int todayUniqueProducers,
    required int activeProducersCount,
    required int pendingSync,
    required bool isOnline,
  }) {
    final List<Widget> cards = <Widget>[
      AppMetricTile(
        title: 'Litros acopiados hoy',
        value: AppFormatters.formatLiters(recCtrl.todayTotalLiters),
        subtitle:
            'Mañana: ${AppFormatters.formatLiters(recCtrl.todayMorningLiters)} · Tarde: ${AppFormatters.formatLiters(recCtrl.todayAfternoonLiters)}',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppMetricTile(
        title: 'Acumulado quincena actual',
        value: AppFormatters.formatLiters(quincenaLiters),
        subtitle: activePrice > 0
            ? 'Estimado: ${AppFormatters.formatCurrency(quincenaEstimated)}'
            : recCtrl.currentQuincenaLabel,
        icon: Icons.date_range_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
        title: 'Productores que entregaron hoy',
        value: '$todayUniqueProducers',
        subtitle:
            'De $activeProducersCount activos · ${recCtrl.todayDeliveriesCount} entrega(s) hoy',
        icon: Icons.agriculture_outlined,
        accentColor: AppTheme.warmGold,
      ),
      AppMetricTile(
        title: 'Estado de sincronización',
        value: pendingSync == 0 ? 'Al día' : '$pendingSync pend.',
        subtitle: isOnline
            ? (pendingSync == 0
                  ? 'Conectado y respaldado en la nube'
                  : 'En línea · listo para enviar pendientes')
            : 'Sin conexión · guardando en equipo',
        icon: pendingSync == 0
            ? Icons.cloud_done_outlined
            : Icons.cloud_upload_outlined,
        accentColor: pendingSync == 0
            ? AppTheme.tealAccent
            : AppTheme.warningText,
      ),
    ];

    if (isNarrow) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          Expanded(child: cards[i]),
          if (i < cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildTodayDeliveriesCard(List<MilkReceptionModel> todayDeliveries) {
    final List<MilkReceptionModel> latest = todayDeliveries.take(6).toList();

    return _DashCard(
      icon: Icons.local_shipping_outlined,
      iconColor: AppTheme.skyBlue,
      title: 'Últimas entregas registradas hoy',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppCountPill(text: '${todayDeliveries.length}'),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: () => widget.onNavigateSection?.call('recepcion'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Ir a Recepción'),
          ),
        ],
      ),
      child: latest.isEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                color: AppTheme.canvasAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Column(
                children: <Widget>[
                  AppIconBadge(
                    icon: Icons.water_drop_outlined,
                    color: AppTheme.skyBlue,
                    size: 44,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Aún no se registran entregas de leche en la jornada de hoy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : CleanDataTable(
              columns: const <CleanTableColumn>[
                CleanTableColumn(label: 'Hora'),
                CleanTableColumn(label: 'Productor'),
                CleanTableColumn(label: 'Jornada'),
                CleanTableColumn(label: 'Litros', numeric: true),
                CleanTableColumn(label: 'Respaldo'),
              ],
              rows: latest.map((MilkReceptionModel r) {
                final bool isMorning = r.jornada == AppConstants.shiftMorning;
                return <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        r.horaEntrega,
                        style: AppTheme.monoStyle(fontSize: 12.5),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _InitialsAvatar(name: r.nombreProductorSnap),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            r.nombreProductorSnap,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            r.codigoAsociadoSnap,
                            style: AppTheme.monoStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _ShiftBadge(isMorning: isMorning),
                  Text(
                    AppFormatters.formatLiters(r.litros),
                    style: AppTheme.monoStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                  SyncStatusBadge(
                    isSynced: r.isSynced,
                    syncedLabel: 'Sincronizado',
                    pendingLabel: 'En cola local',
                  ),
                ];
              }).toList(),
            ),
    );
  }
}

/// Banner de bienvenida con saludo, fecha, estado de conexión y sincronización.
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({
    required this.isNarrow,
    required this.isBusy,
    required this.isOnline,
    required this.pendingSync,
    required this.onRefresh,
    required this.userName,
    required this.quincenaLabel,
  });

  final bool isNarrow;
  final bool isBusy;
  final bool isOnline;
  final int pendingSync;
  final VoidCallback onRefresh;
  final String userName;
  final String quincenaLabel;

  static const List<String> _weekdays = <String>[
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const List<String> _months = <String>[
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String greeting = now.hour < 12
        ? 'Buenos días'
        : now.hour < 19
        ? 'Buenas tardes'
        : 'Buenas noches';
    final String firstName = userName.trim().split(RegExp(r'\s+')).first;
    final String dateLabel =
        '${_weekdays[now.weekday - 1]}, ${now.day} de ${_months[now.month - 1]} de ${now.year}';

    final Widget syncButton = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.inkBlack,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
        disabledForegroundColor: AppTheme.inkBlack,
        minimumSize: const Size(0, 40),
      ),
      onPressed: isBusy ? null : onRefresh,
      icon: isBusy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryGreen,
              ),
            )
          : const Icon(Icons.sync_rounded, size: 17),
      label: Text(isBusy ? 'Sincronizando…' : 'Sincronizar y actualizar'),
    );

    final Widget info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$greeting, $firstName',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCFE9D8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Resumen Operativo de Planta',
          style: AppTheme.titleStyle(isMobile: isNarrow, color: Colors.white),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _BannerChip(icon: Icons.today_rounded, label: dateLabel),
            _BannerChip(icon: Icons.date_range_outlined, label: quincenaLabel),
            _BannerChip(
              icon: isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              label: isOnline
                  ? (pendingSync == 0
                        ? 'En línea · todo respaldado'
                        : 'En línea · $pendingSync pendiente(s)')
                  : 'Sin conexión · modo local',
              dotColor: isOnline
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFFFBBF24),
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.inkBlack, Color(0xFF14663A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F0C3B24),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            right: isNarrow ? -20 : 230,
            top: -30,
            child: Icon(
              Icons.water_drop_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          if (isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                info,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: syncButton),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(child: info),
                const SizedBox(width: 16),
                syncButton,
              ],
            ),
        ],
      ),
    );
  }
}

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.icon, required this.label, this.dotColor});

  final IconData icon;
  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dotColor != null) ...<Widget>[
            Icon(Icons.circle, size: 7, color: dotColor),
            const SizedBox(width: 6),
          ],
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenedor estándar de tarjetas del tablero con cabecera de ícono.
class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080C3B24),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconBadge(icon: icon, color: iconColor, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTheme.subtitleStyle()),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SevenDayChartCard extends StatelessWidget {
  const _SevenDayChartCard({required this.receptions, this.chartHeight = 180});

  final List<MilkReceptionModel> receptions;
  final double chartHeight;

  static const List<String> _weekdayShort = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<
      ({
        String iso,
        String label,
        String weekday,
        double morning,
        double afternoon,
      })
    >
    days =
        <
          ({
            String iso,
            String label,
            String weekday,
            double morning,
            double afternoon,
          })
        >[];

    double maxTotal = 1.0;
    double sum = 0;
    for (int offset = 6; offset >= 0; offset--) {
      final DateTime day = now.subtract(Duration(days: offset));
      final String iso = AppFormatters.toIsoDate(day);
      final String shortLabel =
          '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';

      double m = 0;
      double a = 0;
      for (final MilkReceptionModel r in receptions) {
        if (r.anulado || r.fechaEntrega != iso) continue;
        if (r.jornada == AppConstants.shiftMorning) {
          m += r.litros;
        } else {
          a += r.litros;
        }
      }
      final double total = m + a;
      sum += total;
      if (total > maxTotal) maxTotal = total;
      days.add((
        iso: iso,
        label: shortLabel,
        weekday: offset == 0 ? 'Hoy' : _weekdayShort[day.weekday - 1],
        morning: m,
        afternoon: a,
      ));
    }
    final double average = sum / 7;

    return _DashCard(
      icon: Icons.bar_chart_rounded,
      iconColor: AppTheme.primaryGreen,
      title: 'Acopio últimos 7 días',
      subtitle: 'Comparativo diario entre jornada Mañana y Tarde',
      trailing: const Wrap(
        spacing: 10,
        children: <Widget>[
          _LegendDot(color: AppTheme.skyBlue, label: 'Mañana'),
          _LegendDot(color: AppTheme.primaryGreen, label: 'Tarde'),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _StatChip(
                label: 'Total 7 días',
                value: AppFormatters.formatLiters(sum),
              ),
              _StatChip(
                label: 'Promedio diario',
                value: AppFormatters.formatLiters(average),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: chartHeight,
            child: Stack(
              children: <Widget>[
                // Líneas guía horizontales.
                Positioned.fill(
                  bottom: 34,
                  top: 18,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List<Widget>.generate(
                      4,
                      (_) => Container(height: 1, color: AppTheme.dividerLight),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.map((d) {
                    final double total = d.morning + d.afternoon;
                    final bool isToday = d.weekday == 'Hoy';
                    final double factor = total <= 0
                        ? 0.03
                        : (total / maxTotal).clamp(0.03, 1.0);

                    return Expanded(
                      child: Tooltip(
                        message: total <= 0
                            ? '${d.label}: sin entregas'
                            : '${d.label}\nMañana: ${AppFormatters.formatLiters(d.morning)}\nTarde: ${AppFormatters.formatLiters(d.afternoon)}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                total > 0
                                    ? AppFormatters.formatLiters(
                                        total,
                                        withUnit: false,
                                      )
                                    : '0',
                                style: AppTheme.monoStyle(
                                  fontSize: 10.5,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isToday
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: factor,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 34,
                                      ),
                                      decoration: BoxDecoration(
                                        color: total <= 0
                                            ? AppTheme.border
                                            : Colors.transparent,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(6),
                                              bottom: Radius.circular(2),
                                            ),
                                        boxShadow: isToday && total > 0
                                            ? const <BoxShadow>[
                                                BoxShadow(
                                                  color: Color(0x33168A3E),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: total <= 0
                                          ? null
                                          : Column(
                                              children: <Widget>[
                                                if (d.afternoon > 0)
                                                  Expanded(
                                                    flex: (d.afternoon * 100)
                                                        .round()
                                                        .clamp(1, 100000),
                                                    child: Container(
                                                      color:
                                                          AppTheme.primaryGreen,
                                                    ),
                                                  ),
                                                if (d.morning > 0)
                                                  Expanded(
                                                    flex: (d.morning * 100)
                                                        .round()
                                                        .clamp(1, 100000),
                                                    child: Container(
                                                      color: AppTheme.skyBlue,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? AppTheme.inkBlack
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill,
                                  ),
                                ),
                                child: Text(
                                  d.weekday,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isToday
                                        ? Colors.white
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                d.label,
                                style: AppTheme.monoStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            TextSpan(
              text: value,
              style: AppTheme.monoStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _QuickOperationsCard extends StatelessWidget {
  const _QuickOperationsCard({
    required this.isAdmin,
    required this.activePrice,
    required this.pendingSettlements,
    required this.pendingSettlementsAmount,
    required this.todayUniqueProducers,
    required this.activeProducersCount,
    this.onNavigateSection,
  });

  final bool isAdmin;
  final double activePrice;
  final int pendingSettlements;
  final double pendingSettlementsAmount;
  final int todayUniqueProducers;
  final int activeProducersCount;
  final ValueChanged<String>? onNavigateSection;

  @override
  Widget build(BuildContext context) {
    final double coverage = activeProducersCount <= 0
        ? 0
        : (todayUniqueProducers / activeProducersCount).clamp(0.0, 1.0);

    return _DashCard(
      icon: Icons.bolt_rounded,
      iconColor: AppTheme.warmGold,
      title: 'Operación y accesos directos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppInfoPanel(
            children: <Widget>[
              AppInfoRow(
                label: 'Tarifa vigente / litro',
                value: activePrice > 0
                    ? AppFormatters.formatCurrency(activePrice)
                    : 'Sin definir',
                mono: true,
                emphasize: true,
              ),
              if (isAdmin)
                AppInfoRow(
                  label: 'Pagos pendientes',
                  value:
                      '$pendingSettlements (${AppFormatters.formatCurrency(pendingSettlementsAmount)})',
                  mono: true,
                ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  const Text(
                    'Cobertura de entregas hoy',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                  const Spacer(),
                  Text(
                    '$todayUniqueProducers / $activeProducersCount',
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                child: LinearProgressIndicator(
                  value: coverage,
                  minHeight: 7,
                  backgroundColor: AppTheme.border,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
          const SizedBox(height: 12),
          PrimaryActionButton(
            label: 'Registrar recepción de leche',
            icon: Icons.water_drop_outlined,
            onPressed: () => onNavigateSection?.call('recepcion'),
          ),
          const SizedBox(height: 8),
          _ShortcutTile(
            icon: Icons.agriculture_outlined,
            color: AppTheme.primaryGreen,
            title: 'Consultar productores',
            subtitle: 'Padrón, fincas y acceso móvil',
            onTap: () => onNavigateSection?.call('productores'),
          ),
          if (isAdmin) ...<Widget>[
            _ShortcutTile(
              icon: Icons.receipt_long_outlined,
              color: AppTheme.warmGold,
              title: 'Cerrar quincena y comprobantes',
              subtitle: 'Liquidación y control de pagos',
              onTap: () => onNavigateSection?.call('liquidaciones'),
            ),
            _ShortcutTile(
              icon: Icons.assessment_outlined,
              color: AppTheme.indigoAccent,
              title: 'Reportes PDF / CSV y Auditoría',
              subtitle: 'Consolidados y bitácora',
              onTap: () => onNavigateSection?.call('reportes'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatefulWidget {
  const _ShortcutTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ShortcutTile> createState() => _ShortcutTileState();
}

class _ShortcutTileState extends State<_ShortcutTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? AppTheme.canvasAlt : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: _hover
                  ? widget.color.withValues(alpha: 0.35)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              AppIconBadge(icon: widget.icon, color: widget.color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(_hover ? 0.15 : 0, 0),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: _hover ? widget.color : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    final String initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenLight,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryGreen,
        ),
      ),
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  const _ShiftBadge({required this.isMorning});

  final bool isMorning;

  @override
  Widget build(BuildContext context) {
    final Color fg = isMorning ? AppTheme.warningText : AppTheme.indigoAccent;
    final Color bg = isMorning ? AppTheme.warningBg : AppTheme.indigoLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isMorning ? Icons.wb_sunny_outlined : Icons.wb_twilight_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            isMorning ? 'Mañana' : 'Tarde',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
