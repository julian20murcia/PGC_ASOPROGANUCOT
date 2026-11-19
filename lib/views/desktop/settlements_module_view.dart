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
import '../shared/widgets/ui_kit.dart';

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
      builder: (_) =>
          _ConfirmPaymentDialog(actor: actor, settlement: settlement),
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
    final List<MilkReceptionModel> items = ctrl.receptionsForSettlement(
      settlement,
    );
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

  Widget _buildHeader(SettlementController ctrl, {required bool isNarrow}) {
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
      AppMetricTile(
        title: 'Por liquidar en período',
        value: AppFormatters.formatCurrency(preview?.totalAmountToPay ?? 0),
        subtitle:
            '${AppFormatters.formatLiters(preview?.totalLiters ?? 0)} · ${preview?.candidates.length ?? 0} productor(es)',
        icon: Icons.calculate_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
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
      AppMetricTile(
        title: 'Comprobantes pendientes',
        value: '${ctrl.pendingCount}',
        subtitle:
            '${AppFormatters.formatCurrency(ctrl.totalPendingAmount)} por pagar',
        icon: Icons.schedule_rounded,
        accentColor: AppTheme.warning,
      ),
      AppMetricTile(
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

  Widget _buildQuincenaCloseCard(
    SettlementController ctrl, {
    required UserModel actor,
    required bool isNarrow,
  }) {
    final SettlementPreviewResult? preview = ctrl.preview;
    final QuincenaPeriod period = ctrl.selectedPeriod;
    final bool canClose =
        actor.isAdmin &&
        preview != null &&
        preview.hasEligibleCandidates &&
        !preview.hasPendingSync &&
        (ctrl.activeRate?.precioPorLitro ?? 0) > 0;

    final Widget closeButton = PrimaryActionButton(
      label: 'Ejecutar cierre quincenal',
      icon: Icons.lock_outline_rounded,
      isLoading: ctrl.isClosing,
      fullWidth: isNarrow,
      isMobile: isNarrow,
      onPressed: canClose ? () => _confirmAndCloseQuincena(ctrl, actor) : null,
    );

    final Widget titleBlock = Row(
      children: <Widget>[
        const AppIconBadge(
          icon: Icons.lock_clock_outlined,
          color: AppTheme.warmGold,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Cierre de quincena: ${period.label}',
                style: AppTheme.subtitleStyle().copyWith(fontSize: 16),
              ),
              const SizedBox(height: 3),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.date_range_outlined,
                    size: 13,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${AppFormatters.formatIsoDate(period.startDate)} → ${AppFormatters.formatIsoDate(period.endDate)}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final Widget periodSelector = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppSegmentedControl<int>(
          selected: _quickRangeIndex,
          onChanged: _selectQuickPeriod,
          segments: const <AppSegment<int>>[
            AppSegment<int>(
              value: 0,
              label: 'Quincena actual',
              icon: Icons.today_rounded,
            ),
            AppSegment<int>(value: 1, label: 'Quincena anterior'),
            AppSegment<int>(value: 2, label: 'Días 1 al 15 del mes'),
            AppSegment<int>(value: 3, label: 'Días 16 a fin de mes'),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _pickCustomRange,
          style: _quickRangeIndex == 4
              ? OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.inkBlack,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.inkBlack),
                )
              : null,
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: Text(
            _quickRangeIndex == 4 ? period.label : 'Rango personalizado',
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D0C3B24),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[AppTheme.warmGoldLight, AppTheme.surface],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border(bottom: BorderSide(color: AppTheme.dividerLight)),
            ),
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      titleBlock,
                      const SizedBox(height: 12),
                      closeButton,
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: titleBlock),
                      const SizedBox(width: 12),
                      closeButton,
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                periodSelector,
                if (preview != null && preview.hasPendingSync) ...<Widget>[
                  const SizedBox(height: 12),
                  AppInlineNotice(
                    icon: Icons.sync_problem_rounded,
                    message:
                        'Hay ${preview.pendingSyncReceptions.length} entrega(s) en este rango pendientes por subir a la nube. Sincroniza en Recepción antes de cerrar el período.',
                  ),
                ],
                if ((ctrl.activeRate?.precioPorLitro ?? 0) <= 0) ...<Widget>[
                  const SizedBox(height: 12),
                  const AppInlineNotice.danger(
                    icon: Icons.money_off_rounded,
                    message:
                        'No existe una tarifa vigente configurada. Regístrala en "Tarifas por Litro" para calcular liquidaciones.',
                  ),
                ],
                const SizedBox(height: 14),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 26,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.canvasAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      children: <Widget>[
                        AppIconBadge(
                          icon:
                              preview != null &&
                                  preview.alreadySettledDeliveriesCount > 0
                              ? Icons.task_alt_rounded
                              : Icons.inventory_2_outlined,
                          color:
                              preview != null &&
                                  preview.alreadySettledDeliveriesCount > 0
                              ? AppTheme.primaryGreen
                              : AppTheme.textMuted,
                          size: 44,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          preview != null &&
                                  preview.alreadySettledDeliveriesCount > 0
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
                else ...<Widget>[
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _InitialsAvatar(name: c.nombreProductor),
                            const SizedBox(width: 10),
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
                                  style: AppTheme.monoStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AppCountPill(text: '${c.deliveryCount}'),
                        _ShiftLiters(
                          liters: c.morningLiters,
                          icon: Icons.wb_sunny_outlined,
                          color: AppTheme.warningText,
                        ),
                        _ShiftLiters(
                          liters: c.afternoonLiters,
                          icon: Icons.wb_twilight_rounded,
                          color: AppTheme.indigoAccent,
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
                          style: AppTheme.monoStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
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
                  const SizedBox(height: 10),
                  _PreviewTotalBar(preview: preview),
                ],
              ],
            ),
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
            const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Comprobantes de liquidación emitidos',
                style: AppTheme.subtitleStyle(),
              ),
            ),
            const SizedBox(width: 10),
            AppCountPill(text: '${items.length}'),
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
            child: const Column(
              children: <Widget>[
                AppIconBadge(
                  icon: Icons.receipt_long_outlined,
                  color: AppTheme.skyBlue,
                  size: 48,
                ),
                SizedBox(height: 10),
                Text(
                  'No hay comprobantes emitidos con el filtro seleccionado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
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
                    _PaymentBadge(paid: s.isPagada),
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
                    AppRowActionButton(
                      tooltip: 'Ver / Imprimir comprobante PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      color: AppTheme.danger,
                      onPressed: () =>
                          _openVoucherPdf(ctrl, s, shareOnly: false),
                    ),
                    const SizedBox(width: 6),
                    AppRowActionButton(
                      tooltip: 'Descargar / Compartir PDF',
                      icon: Icons.download_outlined,
                      color: AppTheme.skyBlue,
                      onPressed: () =>
                          _openVoucherPdf(ctrl, s, shareOnly: true),
                    ),
                    if (!s.isPagada && actor.isAdmin) ...<Widget>[
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 30,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: ctrl.isUpdatingPayment
                              ? null
                              : () => _openConfirmPaymentDialog(ctrl, actor, s),
                          icon: const Icon(Icons.payments_outlined, size: 15),
                          label: const Text('Pagar'),
                        ),
                      ),
                    ],
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
    return AppSegmentedControl<String>(
      height: 40,
      selected: ctrl.statusFilter,
      onChanged: ctrl.setStatusFilter,
      segments: const <AppSegment<String>>[
        AppSegment<String>(value: 'TODOS', label: 'Todos'),
        AppSegment<String>(
          value: 'PENDIENTE',
          label: 'Pendientes',
          icon: Icons.schedule_rounded,
        ),
        AppSegment<String>(
          value: 'PAGADA',
          label: 'Pagadas',
          icon: Icons.task_alt_rounded,
        ),
      ],
    );
  }
}

/// Avatar circular con iniciales del productor.
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

class _ShiftLiters extends StatelessWidget {
  const _ShiftLiters({
    required this.liters,
    required this.icon,
    required this.color,
  });

  final double liters;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: liters > 0 ? color : AppTheme.textMuted),
        const SizedBox(width: 5),
        Text(
          AppFormatters.formatLiters(liters),
          style: AppTheme.monoStyle(
            fontSize: 12.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Barra de totales del corte previo al cierre.
class _PreviewTotalBar extends StatelessWidget {
  const _PreviewTotalBar({required this.preview});

  final SettlementPreviewResult preview;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, {bool strong = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFCFE9D8)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.monoStyle(
              fontSize: strong ? 17 : 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.inkBlack, Color(0xFF14663A)],
        ),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: <Widget>[
          item('Productores', '${preview.candidates.length}'),
          item('Entregas', '${preview.totalDeliveries}'),
          item('Total litros', AppFormatters.formatLiters(preview.totalLiters)),
          item(
            'Total neto a emitir',
            AppFormatters.formatCurrency(
              preview.totalAmountToPay,
              alwaysShowDecimals: true,
            ),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    final Color fg = paid ? AppTheme.successText : AppTheme.warningText;
    final Color bg = paid ? AppTheme.successBg : AppTheme.warningBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            paid ? Icons.task_alt_rounded : Icons.schedule_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            paid ? 'Pagada' : 'Pendiente',
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

class _CloseQuincenaConfirmDialog extends StatelessWidget {
  const _CloseQuincenaConfirmDialog({required this.preview});

  final SettlementPreviewResult preview;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDialogHeader(
                icon: Icons.lock_clock_outlined,
                color: AppTheme.warmGold,
                title: 'Confirmar cierre quincenal',
                subtitle: preview.period.label,
                onClose: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 16),
              AppInfoPanel(
                children: <Widget>[
                  AppInfoRow(
                    label: 'Productores a liquidar',
                    value: '${preview.candidates.length}',
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Entregas incluidas',
                    value: '${preview.totalDeliveries}',
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Total de litros',
                    value: AppFormatters.formatLiters(preview.totalLiters),
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Tarifa por litro',
                    value: AppFormatters.formatCurrency(preview.precioPorLitro),
                    mono: true,
                  ),
                  const Divider(height: 14),
                  AppInfoRow(
                    label: 'Total neto a emitir',
                    value: AppFormatters.formatCurrency(
                      preview.totalAmountToPay,
                      alwaysShowDecimals: true,
                    ),
                    mono: true,
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppInlineNotice(
                icon: Icons.lock_outline_rounded,
                message:
                    'Una vez cerradas las entregas de ${preview.period.label}, quedarán bloqueadas contra futuras modificaciones.',
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    autofocus: true,
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

class _ConfirmPaymentDialog extends StatefulWidget {
  const _ConfirmPaymentDialog({required this.actor, required this.settlement});

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

    final SettlementModel st = widget.settlement;

    Widget quick(IconData icon, String label, String text) {
      final bool active = _obsCtrl.text == text;
      return ActionChip(
        avatar: Icon(
          icon,
          size: 15,
          color: active ? Colors.white : AppTheme.textSecondary,
        ),
        label: Text(label),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppTheme.textPrimary,
        ),
        backgroundColor: active ? AppTheme.inkBlack : AppTheme.surface,
        side: BorderSide(
          color: active ? AppTheme.inkBlack : AppTheme.inputBorder,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        onPressed: ctrl.isUpdatingPayment
            ? null
            : () => setState(() => _obsCtrl.text = text),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDialogHeader(
                icon: Icons.payments_outlined,
                title: 'Confirmar pago al productor',
                subtitle: 'Registra el desembolso del comprobante.',
                onClose: ctrl.isUpdatingPayment
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 16),
              AppInfoPanel(
                children: <Widget>[
                  AppInfoRow(
                    label: 'Comprobante',
                    value: st.numeroComprobante,
                    mono: true,
                  ),
                  AppInfoRow(label: 'Productor', value: st.nombreProductorSnap),
                  AppInfoRow(label: 'Período', value: st.quincenaLabel),
                  AppInfoRow(
                    label: 'Litros',
                    value:
                        '${AppFormatters.formatLiters(st.totalLitros)} · ${st.cantidadEntregas} ent.',
                    mono: true,
                  ),
                  const Divider(height: 14),
                  AppInfoRow(
                    label: 'Valor a pagar',
                    value: AppFormatters.formatCurrency(
                      st.valorTotalPagar,
                      alwaysShowDecimals: true,
                    ),
                    mono: true,
                    emphasize: true,
                  ),
                ],
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
                enabled: !ctrl.isUpdatingPayment,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText:
                      'Ej: Transferencia Bancolombia #84920 o pago en caja',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  quick(
                    Icons.account_balance_outlined,
                    'Transferencia',
                    'Pago confirmado por transferencia',
                  ),
                  quick(
                    Icons.point_of_sale_outlined,
                    'Efectivo en planta',
                    'Desembolso en efectivo en tesorería',
                  ),
                ],
              ),
              if (error != null && error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                AppInlineNotice.danger(message: error),
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
