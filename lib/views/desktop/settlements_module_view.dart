import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../core/services/settlement_calculator.dart';
import '../../core/services/settlement_pdf_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/milk_rate_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';

/// Módulo administrativo de liquidación quincenal, comprobantes PDF y control de pagos (`RF-13` a `RF-15`).
class SettlementsModuleView extends StatefulWidget {
  const SettlementsModuleView({super.key});

  @override
  State<SettlementsModuleView> createState() => _SettlementsModuleViewState();
}

class _SettlementsModuleViewState extends State<SettlementsModuleView> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _quickRangeIndex = 0; // 0: actual, 1: anterior, 2: 1ra, 3: 2da, 4: custom

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettlementController>().loadData();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectQuickPeriod(int index) {
    final DateTime now = DateTime.now();
    late final QuincenaPeriod period;
    switch (index) {
      case 0:
        period = QuincenaPeriod.currentForDate(now);
      case 1:
        period = QuincenaPeriod.previousForDate(now);
      case 2:
        period = QuincenaPeriod.forHalfMonth(
          year: now.year,
          month: now.month,
          firstHalf: true,
        );
      case 3:
      default:
        period = QuincenaPeriod.forHalfMonth(
          year: now.year,
          month: now.month,
          firstHalf: false,
        );
    }
    setState(() => _quickRangeIndex = index);
    context.read<SettlementController>().setPeriod(period);
  }

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, now.day <= 15 ? 1 : 16),
        end: now,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _quickRangeIndex = 4);
    context.read<SettlementController>().setPeriod(
          QuincenaPeriod.custom(picked.start, picked.end),
        );
  }

  Future<void> _confirmAndCloseQuincena(
    SettlementController ctrl,
    UserModel actor,
  ) async {
    final SettlementPreviewResult? preview = ctrl.preview;
    if (preview == null || !preview.hasEligibleCandidates) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloseQuincenaConfirmDialog(preview: preview),
    );
    if (confirmed != true || !mounted) return;

    final bool ok = await ctrl.executeQuincenaClose(actor: actor);
    if (!mounted) return;
    _showToast(
      ok
          ? (ctrl.feedbackMessage ?? 'Cierre quincenal completado.')
          : (ctrl.errorMessage ?? 'No se pudo ejecutar el cierre quincenal.'),
      isError: !ok,
    );
  }

  Future<void> _openConfirmPaymentDialog(
    SettlementController ctrl,
    UserModel actor,
    SettlementModel settlement,
  ) async {
    ctrl.clearFeedback();
    final bool? paid = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmPaymentDialog(
        actor: actor,
        settlement: settlement,
      ),
    );
    if (paid == true && mounted) {
      _showToast(ctrl.feedbackMessage ?? 'Pago confirmado.');
    }
  }

  Future<void> _openVoucherPdf(
    SettlementController ctrl,
    SettlementModel settlement, {
    required bool shareOnly,
  }) async {
    final List<MilkReceptionModel> items =
        ctrl.receptionsForSettlement(settlement);
    final producer = ctrl.producerForSettlement(settlement);
    try {
      if (shareOnly) {
        await SettlementPdfService.shareOrDownloadVoucher(
          settlement: settlement,
          receptions: items,
          producer: producer,
        );
      } else {
        await SettlementPdfService.printOrPreviewVoucher(
          settlement: settlement,
          receptions: items,
          producer: producer,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showToast(
        'No fue posible generar el archivo PDF en este equipo.',
        isError: true,
      );
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.inkBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final AuthController auth = context.watch<AuthController>();
    final UserModel actor = auth.currentUser ?? UserModel.bootstrapAdmin();
    final bool isNarrow = MediaQuery.of(context).size.width < 940;

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
            _buildHeader(ctrl, isNarrow: isNarrow),
            const SizedBox(height: 16),
            _buildKpiStrip(ctrl, isNarrow),
            const SizedBox(height: 18),
            _buildQuincenaCloseCard(ctrl, actor: actor, isNarrow: isNarrow),
            const SizedBox(height: 20),
            _buildHistorySection(ctrl, actor: actor, isNarrow: isNarrow),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    SettlementController ctrl, {
    required bool isNarrow,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Liquidaciones Quincenales',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cálculo quincenal automático por productor, emisión de comprobantes en PDF y control de desembolsos.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget refreshBtn = OutlinedButton.icon(
      onPressed: ctrl.isLoading ? null : ctrl.loadData,
      icon: const Icon(Icons.refresh_rounded, size: 17),
      label: const Text('Actualizar'),
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          titleBlock,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: refreshBtn),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        refreshBtn,
      ],
    );
  }

  Widget _buildKpiStrip(SettlementController ctrl, bool isNarrow) {
    final SettlementPreviewResult? preview = ctrl.preview;
    final MilkRateModel? rate = ctrl.activeRate;

    final List<Widget> cards = <Widget>[
      AppKpiCard(
        title: 'Por liquidar en período',
        value: AppFormatters.formatCurrency(preview?.totalAmountToPay ?? 0),
        subtitle:
            '${AppFormatters.formatLiters(preview?.totalLiters ?? 0)} · ${preview?.candidates.length ?? 0} productor(es)',
        icon: Icons.calculate_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppKpiCard(
        title: 'Tarifa aplicable',
        value: rate != null
            ? AppFormatters.formatCurrency(rate.precioPorLitro)
            : 'Sin definir',
        subtitle: rate != null
            ? 'Vigente desde ${AppFormatters.formatDate(rate.fechaInicioVigencia)}'
            : 'Configura una tarifa primero',
        icon: Icons.payments_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppKpiCard(
        title: 'Comprobantes pendientes',
        value: '${ctrl.pendingCount}',
        subtitle:
            '${AppFormatters.formatCurrency(ctrl.totalPendingAmount)} por pagar',
        icon: Icons.schedule_rounded,
        accentColor: AppTheme.warning,
      ),
      AppKpiCard(
        title: 'Comprobantes pagados',
        value: '${ctrl.paidCount}',
        subtitle:
            '${AppFormatters.formatCurrency(ctrl.totalPaidAmount)} desembolsados',
        icon: Icons.task_alt_rounded,
        accentColor: AppTheme.primaryGreen,
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

  Widget _buildQuincenaCloseCard(
    SettlementController ctrl, {
    required UserModel actor,
    required bool isNarrow,
  }) {
    final SettlementPreviewResult? preview = ctrl.preview;
    final QuincenaPeriod period = ctrl.selectedPeriod;
    final bool canClose = actor.isAdmin &&
        preview != null &&
        preview.hasEligibleCandidates &&
        !preview.hasPendingSync &&
        (ctrl.activeRate?.precioPorLitro ?? 0) > 0;

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
          if (isNarrow) ...<Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Cierre de quincena: ${period.label}',
                  style: AppTheme.serifStyle(fontSize: 19),
                ),
                const SizedBox(height: 2),
                Text(
                  'Del ${AppFormatters.formatIsoDate(period.startDate)} al ${AppFormatters.formatIsoDate(period.endDate)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryActionButton(
              label: 'Ejecutar cierre quincenal',
              icon: Icons.lock_outline_rounded,
              isLoading: ctrl.isClosing,
              fullWidth: true,
              onPressed: canClose
                  ? () => _confirmAndCloseQuincena(ctrl, actor)
                  : null,
            ),
          ] else
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Cierre de quincena: ${period.label}',
                        style: AppTheme.serifStyle(fontSize: 19),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rango seleccionado: ${AppFormatters.formatIsoDate(period.startDate)} al ${AppFormatters.formatIsoDate(period.endDate)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                PrimaryActionButton(
                  label: 'Ejecutar cierre quincenal',
                  icon: Icons.lock_outline_rounded,
                  isLoading: ctrl.isClosing,
                  fullWidth: false,
                  onPressed: canClose
                      ? () => _confirmAndCloseQuincena(ctrl, actor)
                      : null,
                ),
              ],
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _PeriodChip(
                label: 'Quincena actual',
                selected: _quickRangeIndex == 0,
                onTap: () => _selectQuickPeriod(0),
              ),
              _PeriodChip(
                label: 'Quincena anterior',
                selected: _quickRangeIndex == 1,
                onTap: () => _selectQuickPeriod(1),
              ),
              _PeriodChip(
                label: 'Días 1 al 15 del mes',
                selected: _quickRangeIndex == 2,
                onTap: () => _selectQuickPeriod(2),
              ),
              _PeriodChip(
                label: 'Días 16 a fin de mes',
                selected: _quickRangeIndex == 3,
                onTap: () => _selectQuickPeriod(3),
              ),
              OutlinedButton.icon(
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: Text(
                  _quickRangeIndex == 4 ? period.label : 'Rango personalizado',
                ),
              ),
            ],
          ),
          if (preview != null && preview.hasPendingSync) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.sync_problem_rounded,
                    size: 18,
                    color: AppTheme.warningText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hay ${preview.pendingSyncReceptions.length} entrega(s) en este rango pendientes por subir a la nube. Sincroniza en Recepción antes de cerrar el período.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if ((ctrl.activeRate?.precioPorLitro ?? 0) <= 0) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.dangerBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'No existe una tarifa vigente configurada. Regístrala en "Tarifas por Litro" para calcular liquidaciones.',
                style: TextStyle(fontSize: 13, color: AppTheme.dangerText),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (ctrl.isLoading && preview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: DairyLoader(
                  size: DairyLoaderSize.md,
                  label: 'Calculando entregas del corte…',
                ),
              ),
            )
          else if (preview == null || preview.candidates.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: <Widget>[
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 32,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview != null && preview.alreadySettledDeliveriesCount > 0
                        ? 'Las entregas registradas en este corte ya fueron liquidadas.'
                        : 'No hay entregas sincronizadas pendientes por liquidar en este rango.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            CleanDataTable(
              columns: const <CleanTableColumn>[
                CleanTableColumn(label: 'Productor'),
                CleanTableColumn(label: 'Entregas', numeric: true),
                CleanTableColumn(label: 'Mañana', numeric: true),
                CleanTableColumn(label: 'Tarde', numeric: true),
                CleanTableColumn(label: 'Total litros', numeric: true),
                CleanTableColumn(label: 'Tarifa / L', numeric: true),
                CleanTableColumn(label: 'Neto a pagar', numeric: true),
              ],
              rows: preview.candidates.map((SettlementCandidate c) {
                return <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        c.nombreProductor,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${c.codigoAsociado} · C.C. ${c.cedula}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${c.deliveryCount}',
                    style: AppTheme.monoStyle(fontSize: 13),
                  ),
                  Text(
                    AppFormatters.formatLiters(c.morningLiters),
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    AppFormatters.formatLiters(c.afternoonLiters),
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    AppFormatters.formatLiters(c.totalLiters),
                    style: AppTheme.monoStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    AppFormatters.formatCurrency(c.precioPorLitro),
                    style: AppTheme.monoStyle(fontSize: 12.5),
                  ),
                  Text(
                    AppFormatters.formatCurrency(
                      c.valorTotalPagar,
                      alwaysShowDecimals: true,
                    ),
                    style: AppTheme.monoStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    SettlementController ctrl, {
    required UserModel actor,
    required bool isNarrow,
  }) {
    final List<SettlementModel> items = ctrl.filteredSettlements;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Comprobantes de liquidación emitidos',
                style: AppTheme.serifStyle(fontSize: 19),
              ),
            ),
            Text(
              '${items.length} registro(s)',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isNarrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildSearchField(ctrl),
              const SizedBox(height: 10),
              _buildStatusFilters(ctrl),
            ],
          )
        else
          Row(
            children: <Widget>[
              Expanded(child: _buildSearchField(ctrl)),
              const SizedBox(width: 12),
              _buildStatusFilters(ctrl),
            ],
          ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Center(
              child: Text(
                'No hay comprobantes emitidos con el filtro seleccionado.',
                style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          CleanDataTable(
            columns: const <CleanTableColumn>[
              CleanTableColumn(label: 'Comprobante'),
              CleanTableColumn(label: 'Productor'),
              CleanTableColumn(label: 'Período'),
              CleanTableColumn(label: 'Litros / Tarifa', numeric: true),
              CleanTableColumn(label: 'Valor neto', numeric: true),
              CleanTableColumn(label: 'Estado'),
              CleanTableColumn(label: 'Acciones'),
            ],
            rows: items.map((SettlementModel s) {
              return <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      s.numeroComprobante,
                      style: AppTheme.monoStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppFormatters.formatDate(s.fechaLiquidacion),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      s.nombreProductorSnap,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'C.C. ${s.cedulaProductorSnap}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      s.quincenaLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${AppFormatters.formatIsoDate(s.periodoInicio)} – ${AppFormatters.formatIsoDate(s.periodoFin)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      AppFormatters.formatLiters(s.totalLitros),
                      style: AppTheme.monoStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${AppFormatters.formatCurrency(s.precioLitroAplicado)}/L · ${s.cantidadEntregas} ent.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  AppFormatters.formatCurrency(
                    s.valorTotalPagar,
                    alwaysShowDecimals: true,
                  ),
                  style: AppTheme.monoStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: s.isPagada
                        ? AppTheme.primaryGreen
                        : AppTheme.textPrimary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SyncStatusBadge(
                      isSynced: s.isPagada,
                      syncedLabel: 'Pagada',
                      pendingLabel: 'Pendiente',
                    ),
                    if (s.isPagada && s.fechaPago != null)
                      Text(
                        AppFormatters.formatDate(s.fechaPago!),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Ver / Imprimir comprobante PDF',
                      onPressed: () =>
                          _openVoucherPdf(ctrl, s, shareOnly: false),
                      icon: const Icon(
                        Icons.picture_as_pdf_outlined,
                        size: 19,
                        color: AppTheme.inkBlack,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Descargar / Compartir PDF',
                      onPressed: () => _openVoucherPdf(ctrl, s, shareOnly: true),
                      icon: const Icon(
                        Icons.download_outlined,
                        size: 19,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (!s.isPagada && actor.isAdmin)
                      TextButton.icon(
                        onPressed: ctrl.isUpdatingPayment
                            ? null
                            : () => _openConfirmPaymentDialog(ctrl, actor, s),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Pagar'),
                      ),
                  ],
                ),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSearchField(SettlementController ctrl) {
    return TextField(
      controller: _searchCtrl,
      onChanged: ctrl.setSearchQuery,
      decoration: InputDecoration(
        hintText: 'Buscar por comprobante, productor, cédula o quincena…',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchCtrl.clear();
                  ctrl.setSearchQuery('');
                },
                icon: const Icon(Icons.close_rounded, size: 17),
              )
            : null,
      ),
    );
  }

  Widget _buildStatusFilters(SettlementController ctrl) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _PeriodChip(
          label: 'Todos',
          selected: ctrl.statusFilter == 'TODOS',
          onTap: () => ctrl.setStatusFilter('TODOS'),
        ),
        _PeriodChip(
          label: 'Pendientes',
          selected: ctrl.statusFilter == 'PENDIENTE',
          onTap: () => ctrl.setStatusFilter('PENDIENTE'),
        ),
        _PeriodChip(
          label: 'Pagadas',
          selected: ctrl.statusFilter == 'PAGADA',
          onTap: () => ctrl.setStatusFilter('PAGADA'),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textSecondary,
        ),
      ),
      selected: selected,
      selectedColor: AppTheme.inkBlack,
      backgroundColor: AppTheme.surfaceMuted,
      side: BorderSide(
        color: selected ? AppTheme.inkBlack : AppTheme.border,
      ),
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}

class _CloseQuincenaConfirmDialog extends StatelessWidget {
  const _CloseQuincenaConfirmDialog({required this.preview});

  final SettlementPreviewResult preview;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Confirmar cierre quincenal',
                style: AppTheme.serifStyle(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Una vez cerradas las entregas de ${preview.period.label}, quedarán bloqueadas contra futuras modificaciones.',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: <Widget>[
                    _SummaryRow(
                      label: 'Productores a liquidar',
                      value: '${preview.candidates.length}',
                    ),
                    _SummaryRow(
                      label: 'Entregas incluidas',
                      value: '${preview.totalDeliveries}',
                    ),
                    _SummaryRow(
                      label: 'Total de litros',
                      value: AppFormatters.formatLiters(preview.totalLiters),
                    ),
                    _SummaryRow(
                      label: 'Tarifa por litro',
                      value: AppFormatters.formatCurrency(preview.precioPorLitro),
                    ),
                    const Divider(height: 16),
                    _SummaryRow(
                      label: 'Total neto a emitir',
                      value: AppFormatters.formatCurrency(
                        preview.totalAmountToPay,
                        alwaysShowDecimals: true,
                      ),
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  PrimaryActionButton(
                    label: 'Confirmar y emitir',
                    icon: Icons.check_rounded,
                    fullWidth: false,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTheme.monoStyle(
              fontSize: highlight ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: highlight ? AppTheme.primaryGreen : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmPaymentDialog extends StatefulWidget {
  const _ConfirmPaymentDialog({
    required this.actor,
    required this.settlement,
  });

  final UserModel actor;
  final SettlementModel settlement;

  @override
  State<_ConfirmPaymentDialog> createState() => _ConfirmPaymentDialogState();
}

class _ConfirmPaymentDialogState extends State<_ConfirmPaymentDialog> {
  final TextEditingController _obsCtrl = TextEditingController(
    text: 'Pago confirmado mediante transferencia bancaria',
  );

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bool ok = await context.read<SettlementController>().confirmPayment(
          actor: widget.actor,
          settlement: widget.settlement,
          observacionPago: _obsCtrl.text,
        );
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final String? error = ctrl.errorMessage;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Confirmar pago al productor',
                style: AppTheme.serifStyle(fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.settlement.numeroComprobante} · ${widget.settlement.nombreProductorSnap} · ${AppFormatters.formatCurrency(widget.settlement.valorTotalPagar, alwaysShowDecimals: true)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Observación o referencia del desembolso',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Ej: Transferencia Bancolombia #84920 o pago en caja',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: <Widget>[
                  ActionChip(
                    label: const Text('Transferencia'),
                    onPressed: () {
                      _obsCtrl.text = 'Pago confirmado por transferencia';
                    },
                  ),
                  ActionChip(
                    label: const Text('Efectivo en planta'),
                    onPressed: () {
                      _obsCtrl.text = 'Desembolso en efectivo en tesorería';
                    },
                  ),
                ],
              ),
              if (error != null && error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.dangerText,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: ctrl.isUpdatingPayment
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  PrimaryActionButton(
                    label: 'Marcar como pagada',
                    icon: Icons.task_alt_rounded,
                    isLoading: ctrl.isUpdatingPayment,
                    fullWidth: false,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
