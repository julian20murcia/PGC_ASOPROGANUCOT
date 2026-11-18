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

/// Dashboard operativo en tiempo real de ASOPROGANUCOTT (`RF-16`).
class DashboardModuleView extends StatefulWidget {
  const DashboardModuleView({
    super.key,
    this.onNavigateSection,
  });

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
    final int activeProducersCount =
        prodCtrl.allProducers.where((p) => p.isActivo).length;

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
            _buildHeader(
              isNarrow: isNarrow,
              isBusy: recCtrl.isLoading || syncCtrl.isSyncing,
              onRefresh: _syncAndRefresh,
              userName: auth.currentUser?.nombreCompleto ?? 'Planta Susa',
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
            const SizedBox(height: 18),
            if (isNarrow) ...<Widget>[
              _SevenDayChartCard(receptions: recCtrl.allReceptions),
              const SizedBox(height: 14),
              _QuickOperationsCard(
                isAdmin: isAdmin,
                activePrice: activePrice,
                pendingSettlements: setCtrl.pendingCount,
                pendingSettlementsAmount: setCtrl.totalPendingAmount,
                onNavigateSection: widget.onNavigateSection,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 6,
                    child: _SevenDayChartCard(receptions: recCtrl.allReceptions),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: _QuickOperationsCard(
                      isAdmin: isAdmin,
                      activePrice: activePrice,
                      pendingSettlements: setCtrl.pendingCount,
                      pendingSettlementsAmount: setCtrl.totalPendingAmount,
                      onNavigateSection: widget.onNavigateSection,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            _buildTodayDeliveriesCard(todayDeliveries),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required bool isNarrow,
    required bool isBusy,
    required VoidCallback onRefresh,
    required String userName,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Resumen Operativo de Planta',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
        const SizedBox(height: 4),
        Text(
          'Bienvenido, $userName · Seguimiento diario de acopio, quincena activa y sincronización.',
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actionBtn = PrimaryActionButton(
      label: isBusy ? 'Sincronizando…' : 'Sincronizar y actualizar',
      icon: Icons.sync_rounded,
      isLoading: isBusy,
      fullWidth: false,
      onPressed: onRefresh,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          titleBlock,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: actionBtn),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        actionBtn,
      ],
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
      AppKpiCard(
        title: 'Litros acopiados hoy',
        value: AppFormatters.formatLiters(recCtrl.todayTotalLiters),
        subtitle:
            'Mañana: ${AppFormatters.formatLiters(recCtrl.todayMorningLiters)} · Tarde: ${AppFormatters.formatLiters(recCtrl.todayAfternoonLiters)}',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppKpiCard(
        title: 'Acumulado quincena actual',
        value: AppFormatters.formatLiters(quincenaLiters),
        subtitle: activePrice > 0
            ? 'Estimado: ${AppFormatters.formatCurrency(quincenaEstimated)}'
            : recCtrl.currentQuincenaLabel,
        icon: Icons.date_range_outlined,
        accentColor: AppTheme.inkBlack,
      ),
      AppKpiCard(
        title: 'Productores que entregaron hoy',
        value: '$todayUniqueProducers',
        subtitle:
            'De $activeProducersCount activos · ${recCtrl.todayDeliveriesCount} entrega(s) hoy',
        icon: Icons.agriculture_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppKpiCard(
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
        accentColor: pendingSync == 0 ? AppTheme.primaryGreen : AppTheme.warning,
      ),
    ];

    if (isNarrow) {
      return Column(
        children: cards
            .map(
              (Widget card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card,
              ),
            )
            .toList(),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Últimas entregas registradas hoy',
                  style: AppTheme.serifStyle(fontSize: 18),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onNavigateSection?.call('recepcion'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ir a Recepción'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (latest.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: const Center(
                child: Text(
                  'Aún no se registran entregas de leche en la jornada de hoy.',
                  style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            CleanDataTable(
              columns: const <CleanTableColumn>[
                CleanTableColumn(label: 'Hora'),
                CleanTableColumn(label: 'Código'),
                CleanTableColumn(label: 'Productor'),
                CleanTableColumn(label: 'Jornada'),
                CleanTableColumn(label: 'Litros', numeric: true),
                CleanTableColumn(label: 'Respaldo'),
              ],
              rows: latest.map((MilkReceptionModel r) {
                final bool isMorning = r.jornada == AppConstants.shiftMorning;
                return <Widget>[
                  Text(
                    r.horaEntrega,
                    style: AppTheme.monoStyle(fontSize: 12.5),
                  ),
                  Text(
                    r.codigoAsociadoSnap,
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    r.nombreProductorSnap,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  HeaderPropertyChip(
                    label: isMorning ? 'Mañana' : 'Tarde',
                    value: '',
                    dotColor:
                        isMorning ? AppTheme.primaryGreen : AppTheme.inkBlack,
                  ),
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
        ],
      ),
    );
  }
}

class _SevenDayChartCard extends StatelessWidget {
  const _SevenDayChartCard({required this.receptions});

  final List<MilkReceptionModel> receptions;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<({String iso, String label, double morning, double afternoon})>
        days =
        <({String iso, String label, double morning, double afternoon})>[];

    double maxTotal = 1.0;
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
      if (total > maxTotal) maxTotal = total;
      days.add((iso: iso, label: shortLabel, morning: m, afternoon: a));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Acopio últimos 7 días',
                      style: AppTheme.serifStyle(fontSize: 18),
                    ),
                    const Text(
                      'Comparativo diario entre jornada Mañana y Tarde',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Wrap(
                spacing: 12,
                children: <Widget>[
                  _LegendDot(color: AppTheme.inkBlack, label: 'Mañana'),
                  _LegendDot(color: AppTheme.primaryGreen, label: 'Tarde'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((d) {
                final double total = d.morning + d.afternoon;
                final double mFactor = total <= 0 ? 0 : d.morning / maxTotal;
                final double aFactor = total <= 0 ? 0 : d.afternoon / maxTotal;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: (mFactor + aFactor).clamp(0.03, 1.0),
                              child: Container(
                                width: 26,
                                decoration: BoxDecoration(
                                  color: total <= 0
                                      ? AppTheme.border
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
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
                                                color: AppTheme.primaryGreen,
                                              ),
                                            ),
                                          if (d.morning > 0)
                                            Expanded(
                                              flex: (d.morning * 100)
                                                  .round()
                                                  .clamp(1, 100000),
                                              child: Container(
                                                color: AppTheme.inkBlack,
                                              ),
                                            ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d.label,
                          style: AppTheme.monoStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
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
    this.onNavigateSection,
  });

  final bool isAdmin;
  final double activePrice;
  final int pendingSettlements;
  final double pendingSettlementsAmount;
  final ValueChanged<String>? onNavigateSection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Operación y accesos directos',
            style: AppTheme.serifStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Tarifa vigente / litro',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        activePrice > 0
                            ? AppFormatters.formatCurrency(activePrice)
                            : 'Sin definir',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTheme.monoStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isAdmin) ...<Widget>[
                  const Divider(height: 16),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Pagos pendientes',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$pendingSettlements (${AppFormatters.formatCurrency(pendingSettlementsAmount)})',
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: AppTheme.monoStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          PrimaryActionButton(
            label: 'Registrar recepción de leche',
            icon: Icons.water_drop_outlined,
            onPressed: () => onNavigateSection?.call('recepcion'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => onNavigateSection?.call('productores'),
            icon: const Icon(Icons.agriculture_outlined, size: 17),
            label: const Text('Consultar productores'),
          ),
          if (isAdmin) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onNavigateSection?.call('liquidaciones'),
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Cerrar quincena y comprobantes'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onNavigateSection?.call('reportes'),
              icon: const Icon(Icons.assessment_outlined, size: 17),
              label: const Text('Reportes PDF / CSV y Auditoría'),
            ),
          ],
        ],
      ),
    );
  }
}
