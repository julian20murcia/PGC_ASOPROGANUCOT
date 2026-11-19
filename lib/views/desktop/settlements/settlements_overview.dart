import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/settlement_controller.dart';
import '../../../core/services/settlement_calculator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';
import 'settlement_widgets.dart';

/// Panel "Quincena en curso / por cerrar".
class CurrentPeriodPanel extends StatelessWidget {
  const CurrentPeriodPanel({
    super.key,
    required this.canClose,
    required this.onClose,
  });

  final bool canClose;
  final void Function(QuincenaPeriod period) onClose;

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final DateTime now = DateTime.now();
    final String todayIso = AppFormatters.toIsoDate(now);
    final QuincenaPeriod current = QuincenaPeriod.currentForDate(now);
    final QuincenaPeriod previous = QuincenaPeriod.previousForDate(now);

    final List<MilkReceptionModel> recs = ctrl.receptionsInPeriod(current);
    final int thousandths = recs.fold<int>(
      0,
      (int s, MilkReceptionModel r) => s + (r.litros * 1000).round(),
    );
    final double liters = thousandths / 1000.0;
    final int producers = recs
        .map((MilkReceptionModel r) => r.productorId)
        .toSet()
        .length;
    final double price = ctrl.activeRate?.precioPorLitro ?? 0;
    final double estimate = SettlementCalculator.calculateTotalAmount(
      totalLiters: liters,
      pricePerLiter: price,
    );
    final List<String> days = DailyDeliveryMatrix.daysBetween(
      current.startDate,
      current.endDate,
    );
    final int elapsed = days
        .where((String d) => d.compareTo(todayIso) <= 0)
        .length;
    final Set<String> daysWithRecords = recs
        .map((MilkReceptionModel r) => r.fechaEntrega)
        .toSet();
    final int recordedDays = days.where(daysWithRecords.contains).length;

    final List<SettlementModel> closedCurrent = ctrl.settlementsOverlapping(
      current,
    );
    final SettlementPreviewResult currentPreview = ctrl.previewForPeriod(
      current,
    );
    final bool currentClosed =
        closedCurrent.isNotEmpty && !currentPreview.hasEligibleCandidates;

    final SettlementPreviewResult prevPreview = ctrl.previewForPeriod(previous);
    final bool previousPending =
        prevPreview.hasEligibleCandidates || prevPreview.hasPendingSync;

    final (String, Tone) status = currentClosed
        ? ('Cerrada', Tone.success)
        : (closedCurrent.isNotEmpty
              ? ('Cerrada parcialmente', Tone.info)
              : ('En curso', Tone.brand));

    return Panel(
      title: 'Quincena en curso · ${current.label}',
      subtitle:
          '${AppFormatters.formatIsoDate(current.startDate)} al ${AppFormatters.formatIsoDate(current.endDate)} · tarifa ${price > 0 ? '${AppFormatters.formatCurrency(price)}/L' : 'sin definir'}',
      icon: Icons.event_note_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatusBadge(status.$1, tone: status.$2, dot: true),
          const SizedBox(width: 10),
          if (canClose)
            FilledButton.icon(
              onPressed: () => onClose(previousPending ? previous : current),
              icon: const Icon(Icons.lock_clock_rounded, size: 17),
              label: const Text('Cerrar quincena'),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InlineMetricRow(
            items: <InlineMetric>[
              InlineMetric(
                'Días transcurridos',
                '$elapsed de ${days.length}',
                hint: '$recordedDays día(s) con registros',
              ),
              InlineMetric(
                'Litros acumulados',
                AppFormatters.formatLiters(liters),
                hint: '${recs.length} entregas',
              ),
              InlineMetric(
                'Productores',
                '$producers',
                hint: 'con entregas en el período',
              ),
              InlineMetric(
                'Valor estimado',
                AppFormatters.formatCurrency(estimate),
                hint: price > 0 ? 'con la tarifa vigente' : 'define una tarifa',
                valueColor: AppTheme.brandDeep,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: days.isEmpty ? 0 : elapsed / days.length,
              minHeight: 4,
              backgroundColor: AppTheme.surfaceSunken,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          if (previousPending) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warningBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.pending_actions_rounded,
                    size: 18,
                    color: AppTheme.warningText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${previous.label} está por cerrar: ${prevPreview.candidates.length} productor(es) · '
                      '${AppFormatters.formatLiters(prevPreview.totalLiters)} · '
                      '${AppFormatters.formatCurrency(prevPreview.totalAmountToPay)}'
                      '${prevPreview.hasPendingSync ? ' · ${prevPreview.pendingSyncReceptions.length} entrega(s) sin sincronizar' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        color: AppTheme.warningText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (canClose)
                    TextButton(
                      onPressed: () => onClose(previous),
                      child: const Text('Cerrar ahora'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppTheme.dividerLight),
          const SizedBox(height: 10),
          const _HowItWorks(),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String title, String detail) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: AppTheme.monoStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.brand,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTheme.bodyStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final List<Widget> steps = <Widget>[
          step(
            1,
            'Elige la quincena',
            'Actual, anterior u otro rango; verificamos que no falte nada.',
          ),
          step(
            2,
            'Revisa productores',
            'Litros, precio y valor de cada uno; puedes excluir alguno.',
          ),
          step(
            3,
            'Confirma',
            'Se bloquean entregas, se emiten comprobantes y se notifica.',
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Ejecutar cierre quincenal',
              style: AppTheme.overlineStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (c.maxWidth < 640)
              Column(
                children: <Widget>[
                  for (final Widget s in steps) Row(children: <Widget>[s]),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  steps[0],
                  const SizedBox(width: 16),
                  steps[1],
                  const SizedBox(width: 16),
                  steps[2],
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Lista compacta de quincenas cerradas con filtro por rango y búsqueda.
class ClosedPeriodsPanel extends StatelessWidget {
  const ClosedPeriodsPanel({
    super.key,
    required this.groups,
    required this.range,
    required this.onRangeChanged,
    required this.onClearRange,
    required this.onQueryChanged,
    required this.onOpen,
    this.emptyAction,
  });

  final List<SettlementPeriodGroup> groups;
  final DateRangeValue? range;
  final ValueChanged<DateRangeValue> onRangeChanged;
  final VoidCallback onClearRange;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SettlementPeriodGroup> onOpen;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final double total =
        groups.fold<int>(
          0,
          (int s, SettlementPeriodGroup g) => s + (g.totalAmount * 100).round(),
        ) /
        100.0;
    final double pending =
        groups.fold<int>(
          0,
          (int s, SettlementPeriodGroup g) =>
              s + (g.pendingAmount * 100).round(),
        ) /
        100.0;

    final Widget filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 230,
          child: AppDateRangeField(
            value: range ?? DateRangeValue(DateTime(now.year, 1, 1), now),
            onChanged: onRangeChanged,
            dense: true,
            expand: true,
          ),
        ),
        if (range != null)
          IconButton(
            tooltip: 'Quitar filtro de fechas',
            onPressed: onClearRange,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
          ),
        AppSearchField(
          width: 240,
          hint: 'Buscar período, productor o comprobante',
          onChanged: onQueryChanged,
        ),
      ],
    );

    return Panel(
      title: 'Quincenas cerradas',
      subtitle: groups.isEmpty
          ? 'Toca una quincena para ver productores, registros diarios y comprobantes'
          : '${groups.length} período(s) · ${AppFormatters.formatCurrency(total)} liquidados · ${AppFormatters.formatCurrency(pending)} por pagar',
      icon: Icons.history_rounded,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: filters,
          ),
          const Divider(height: 1),
          if (groups.isEmpty)
            EmptyState(
              title: range == null
                  ? 'Aún no hay quincenas cerradas'
                  : 'No hay quincenas en este filtro',
              message: range == null
                  ? 'Cuando cierres tu primera quincena aparecerá aquí con sus productores y comprobantes.'
                  : 'Prueba con otro rango de fechas o quita el filtro.',
              icon: Icons.receipt_long_outlined,
              action: emptyAction,
            )
          else ...<Widget>[
            Container(
              height: 36,
              color: AppTheme.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const Row(
                children: <Widget>[
                  Expanded(flex: 5, child: DataHeaderCell('Período')),
                  Expanded(
                    flex: 2,
                    child: HeaderCell('Productores', right: true),
                  ),
                  Expanded(flex: 3, child: HeaderCell('Litros', right: true)),
                  Expanded(flex: 3, child: HeaderCell('Valor', right: true)),
                  SizedBox(width: 24),
                  Expanded(flex: 4, child: DataHeaderCell('Pagos')),
                  SizedBox(width: 16),
                  SizedBox(width: 120, child: DataHeaderCell('Estado')),
                  SizedBox(width: 24),
                ],
              ),
            ),
            const Divider(height: 1),
            for (int i = 0; i < groups.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1, color: AppTheme.dividerLight),
              _PeriodRow(group: groups[i], onTap: () => onOpen(groups[i])),
            ],
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends StatefulWidget {
  const _PeriodRow({required this.group, required this.onTap});
  final SettlementPeriodGroup group;
  final VoidCallback onTap;

  @override
  State<_PeriodRow> createState() => _PeriodRowState();
}

class _PeriodRowState extends State<_PeriodRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final SettlementPeriodGroup g = widget.group;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 54,
          color: _hover ? AppTheme.surfaceMuted : AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 5,
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.brandSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        size: 17,
                        color: AppTheme.brand,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CellText(g.label, strong: true),
                          CellText(
                            '${AppFormatters.formatIsoDate(g.periodoInicio)} – ${AppFormatters.formatIsoDate(g.periodoFin)} · cerrada ${AppFormatters.formatDate(g.closedAt)}',
                            size: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: CellText(
                  '${g.producerCount}',
                  mono: true,
                  align: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 3,
                child: CellText(
                  AppFormatters.formatLiters(g.totalLiters),
                  mono: true,
                  align: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 3,
                child: CellText(
                  AppFormatters.formatCurrency(g.totalAmount),
                  mono: true,
                  strong: true,
                  align: TextAlign.right,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 4,
                child: PaymentProgress(
                  paid: g.paidCount,
                  total: g.producerCount,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: g.fullyPaid
                      ? const StatusBadge(
                          'Pagada',
                          tone: Tone.success,
                          dot: true,
                        )
                      : StatusBadge(
                          '${g.pendingCount} pendiente(s)',
                          tone: Tone.warning,
                          dot: true,
                        ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: _hover ? AppTheme.brand : AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
