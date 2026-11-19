import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/settlement_controller.dart';
import '../../../core/security/permissions.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/settlement_calculator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';
import '../../../models/settlement_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/pro_ui.dart';
import '../../shared/widgets/ui_kit.dart';
import 'daily_matrix_table.dart';
import 'settlement_actions.dart';
import 'settlement_exports.dart';
import 'settlement_widgets.dart';

enum _DetailTab { producers, daily }

/// Página interna con el detalle de una quincena cerrada.
class SettlementPeriodDetail extends StatefulWidget {
  const SettlementPeriodDetail({
    super.key,
    required this.group,
    required this.onBack,
  });

  final SettlementPeriodGroup group;
  final VoidCallback onBack;

  @override
  State<SettlementPeriodDetail> createState() => _SettlementPeriodDetailState();
}

class _SettlementPeriodDetailState extends State<SettlementPeriodDetail> {
  _DetailTab _tab = _DetailTab.producers;
  String _query = '';

  Map<String, String> _codes(SettlementController ctrl) {
    final Map<String, String> out = <String, String>{};
    for (final SettlementModel s in widget.group.settlements) {
      final ProducerModel? p = ctrl.producerForSettlement(s);
      if (p != null) out[s.productorId] = p.codigoAsociado;
    }
    for (final MilkReceptionModel r in ctrl.receptionsForGroup(widget.group)) {
      if (r.codigoAsociadoSnap.isNotEmpty) {
        out.putIfAbsent(r.productorId, () => r.codigoAsociadoSnap);
      }
    }
    return out;
  }

  DailyDeliveryMatrix _matrix(
    SettlementController ctrl,
    Map<String, String> codes,
  ) {
    return DailyDeliveryMatrix.build(
      startIso: widget.group.periodoInicio,
      endIso: widget.group.periodoFin,
      receptions: ctrl.receptionsForGroup(widget.group),
      producerOrder: <({String productorId, String codigo, String nombre})>[
        for (final SettlementModel s in widget.group.settlements)
          (
            productorId: s.productorId,
            codigo: codes[s.productorId] ?? 'SIN-COD',
            nombre: s.nombreProductorSnap,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final UserModel? user = context.watch<AuthController>().currentUser;
    final SettlementPeriodGroup g = widget.group;
    final Map<String, String> codes = _codes(ctrl);
    final DailyDeliveryMatrix matrix = _matrix(ctrl, codes);
    final bool canExport =
        user?.can(Permissions.liquidaciones, PermAction.exportar) ?? false;
    final bool canPay =
        user?.can(Permissions.liquidaciones, PermAction.editar) ?? false;

    final Widget header = PageHeader(
      leading: IconButton.outlined(
        tooltip: 'Volver a quincenas',
        onPressed: widget.onBack,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        style: IconButton.styleFrom(
          side: const BorderSide(color: AppTheme.inputBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
        ),
      ),
      title: g.label,
      subtitle:
          '${AppFormatters.formatIsoDate(g.periodoInicio)} al ${AppFormatters.formatIsoDate(g.periodoFin)} · cerrada el ${AppFormatters.formatDate(g.closedAt)}',
      actions: <Widget>[
        if (g.fullyPaid)
          const StatusBadge(
            'Pagada por completo',
            tone: Tone.success,
            icon: Icons.verified_rounded,
          )
        else
          StatusBadge(
            '${g.pendingCount} pago(s) pendiente(s)',
            tone: Tone.warning,
            dot: true,
          ),
        if (canExport)
          ExportButton(
            label: 'Descargar quincena',
            title: 'Descargar ${g.label}',
            subtitle:
                'PDF consolidado, Excel (Resumen, Registros diarios, Productores) o CSV',
            build: (ExportFormat f) => SettlementExports.build(
              format: f,
              group: g,
              matrix: matrix,
              receptions: ctrl.receptionsForGroup(g),
              codesByProducerId: codes,
            ),
          ),
      ],
    );

    final Widget stats = StatStrip(
      minItemWidth: 150,
      items: <StatItem>[
        StatItem(
          label: 'Productores',
          value: '${g.producerCount}',
          icon: Icons.groups_2_outlined,
        ),
        StatItem(
          label: 'Entregas',
          value: '${g.deliveries}',
          icon: Icons.local_shipping_outlined,
        ),
        StatItem(
          label: 'Litros',
          value: AppFormatters.formatLiters(g.totalLiters),
          icon: Icons.water_drop_outlined,
        ),
        StatItem(
          label: 'Valor liquidado',
          value: AppFormatters.formatCurrency(g.totalAmount),
          hint: 'Promedio ${AppFormatters.formatCurrency(g.averagePrice)}/L',
          icon: Icons.payments_outlined,
        ),
        StatItem(
          label: 'Pagado',
          value: AppFormatters.formatCurrency(g.paidAmount),
          hint: '${g.paidCount} de ${g.producerCount} comprobantes',
          icon: Icons.check_circle_outline_rounded,
          tone: Tone.success,
        ),
        StatItem(
          label: 'Pendiente',
          value: AppFormatters.formatCurrency(g.pendingAmount),
          hint: '${g.pendingCount} por pagar',
          icon: Icons.schedule_rounded,
          tone: g.pendingCount > 0 ? Tone.warning : Tone.neutral,
        ),
      ],
    );

    final Widget tabs = Row(
      children: <Widget>[
        AppSegmentedControl<_DetailTab>(
          selected: _tab,
          onChanged: (_DetailTab t) => setState(() => _tab = t),
          segments: <AppSegment<_DetailTab>>[
            AppSegment<_DetailTab>(
              value: _DetailTab.producers,
              label: 'Productores (${g.producerCount})',
              icon: Icons.people_alt_outlined,
            ),
            const AppSegment<_DetailTab>(
              value: _DetailTab.daily,
              label: 'Registros diarios',
              icon: Icons.grid_on_rounded,
            ),
          ],
        ),
        const Spacer(),
        if (_tab == _DetailTab.producers)
          Flexible(
            child: AppSearchField(
              width: 260,
              hint: 'Buscar productor o comprobante',
              onChanged: (String v) => setState(() => _query = v),
            ),
          )
        else
          Flexible(
            child: Text(
              '${matrix.days.length} días · ${matrix.emptyDays.length} sin registros · M = mañana, T = tarde',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ),
      ],
    );

    final Widget table = _tab == _DetailTab.producers
        ? _ProducersTable(
            settlements: _filter(g.settlements),
            codes: codes,
            canPay: canPay,
          )
        : DailyMatrixTable(matrix: matrix);

    final Widget panel = Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: table,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final EdgeInsets pad = EdgeInsets.all(c.maxWidth < 700 ? 16 : 24);
        if (c.maxHeight < 600) {
          return SingleChildScrollView(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                const SizedBox(height: 12),
                stats,
                const SizedBox(height: 12),
                tabs,
                const SizedBox(height: 10),
                SizedBox(height: 460, child: panel),
              ],
            ),
          );
        }
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              const SizedBox(height: 12),
              stats,
              const SizedBox(height: 12),
              tabs,
              const SizedBox(height: 10),
              Expanded(child: panel),
            ],
          ),
        );
      },
    );
  }

  List<SettlementModel> _filter(List<SettlementModel> items) {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (SettlementModel s) =>
              s.nombreProductorSnap.toLowerCase().contains(q) ||
              s.cedulaProductorSnap.toLowerCase().contains(q) ||
              s.numeroComprobante.toLowerCase().contains(q),
        )
        .toList();
  }
}

class _ProducersTable extends StatelessWidget {
  const _ProducersTable({
    required this.settlements,
    required this.codes,
    required this.canPay,
  });

  final List<SettlementModel> settlements;
  final Map<String, String> codes;
  final bool canPay;

  static const double _minWidth = 960;

  @override
  Widget build(BuildContext context) {
    if (settlements.isEmpty) {
      return const EmptyState(
        title: 'Sin resultados',
        message: 'Ningún productor coincide con la búsqueda.',
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = math.max(c.maxWidth, _minWidth);
        final Widget content = SizedBox(
          width: w,
          child: Column(
            children: <Widget>[
              Container(
                height: 40,
                color: AppTheme.surfaceMuted,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: const Row(
                  children: <Widget>[
                    SizedBox(width: 68, child: DataHeaderCell('Código')),
                    Expanded(child: DataHeaderCell('Productor')),
                    SizedBox(
                      width: 64,
                      child: HeaderCell('Entregas', right: true),
                    ),
                    SizedBox(
                      width: 92,
                      child: HeaderCell('Litros', right: true),
                    ),
                    SizedBox(
                      width: 80,
                      child: HeaderCell('Precio/L', right: true),
                    ),
                    SizedBox(
                      width: 110,
                      child: HeaderCell('Valor', right: true),
                    ),
                    SizedBox(width: 14),
                    SizedBox(width: 96, child: DataHeaderCell('Estado')),
                    SizedBox(width: 118, child: DataHeaderCell('Comprobante')),
                    SizedBox(
                      width: 144,
                      child: HeaderCell('Acciones', right: true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: settlements.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppTheme.dividerLight),
                  itemBuilder: (BuildContext context, int i) => _ProducerRow(
                    settlement: settlements[i],
                    code: codes[settlements[i].productorId],
                    canPay: canPay,
                  ),
                ),
              ),
            ],
          ),
        );
        if (w <= c.maxWidth) return content;
        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        );
      },
    );
  }
}

class _ProducerRow extends StatefulWidget {
  const _ProducerRow({
    required this.settlement,
    required this.code,
    required this.canPay,
  });

  final SettlementModel settlement;
  final String? code;
  final bool canPay;

  @override
  State<_ProducerRow> createState() => _ProducerRowState();
}

class _ProducerRowState extends State<_ProducerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final SettlementModel s = widget.settlement;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 46,
        color: _hover ? AppTheme.surfaceMuted : AppTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 68,
              child: CellText(
                widget.code ?? '—',
                mono: true,
                color: AppTheme.textSecondary,
                size: 12,
              ),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  InitialsAvatar(s.nombreProductorSnap, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        CellText(s.nombreProductorSnap, strong: true),
                        CellText(
                          RegExp(r'^\d+$').hasMatch(s.cedulaProductorSnap)
                              ? 'CC ${s.cedulaProductorSnap}'
                              : 'Sin documento registrado',
                          size: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 64,
              child: CellText(
                '${s.cantidadEntregas}',
                mono: true,
                align: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 92,
              child: CellText(
                AppFormatters.formatLiters(s.totalLitros),
                mono: true,
                align: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 80,
              child: CellText(
                AppFormatters.formatCurrency(s.precioLitroAplicado),
                mono: true,
                align: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 110,
              child: CellText(
                AppFormatters.formatCurrency(s.valorTotalPagar),
                mono: true,
                strong: true,
                align: TextAlign.right,
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 96,
              child: Tooltip(
                message: s.isPagada
                    ? 'Pagada el ${s.fechaPago != null ? AppFormatters.formatDate(s.fechaPago!) : 'N/D'}${(s.observacionPago ?? '').isEmpty ? '' : ' · ${s.observacionPago}'}'
                    : 'Pendiente de pago',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PaymentBadge(s),
                ),
              ),
            ),
            SizedBox(
              width: 118,
              child: InkWell(
                onTap: () => VoucherActions.preview(context, s),
                borderRadius: BorderRadius.circular(4),
                child: CellText(
                  s.numeroComprobante,
                  mono: true,
                  color: AppTheme.brand,
                  size: 12.5,
                ),
              ),
            ),
            SizedBox(
              width: 144,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _iconBtn(
                    Icons.visibility_outlined,
                    'Ver comprobante',
                    () => VoucherActions.preview(context, s),
                  ),
                  _iconBtn(
                    Icons.download_rounded,
                    'Descargar PDF',
                    () => VoucherActions.download(context, s),
                  ),
                  _iconBtn(
                    Icons.share_rounded,
                    'Compartir en…',
                    () => VoucherActions.share(context, s),
                  ),
                  if (widget.canPay && !s.isPagada)
                    _iconBtn(
                      Icons.payments_rounded,
                      'Registrar pago',
                      () async {
                        final bool ok = await showRegisterPaymentDialog(
                          context,
                          s,
                        );
                        if (ok && context.mounted) {
                          showAppToast(
                            context,
                            'Pago registrado para ${s.numeroComprobante}',
                            tone: Tone.success,
                          );
                        }
                      },
                      highlight: true,
                    )
                  else
                    const SizedBox(width: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool highlight = false,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        style: highlight
            ? IconButton.styleFrom(
                backgroundColor: AppTheme.brandSoft,
                foregroundColor: AppTheme.brand,
              )
            : null,
        icon: Icon(
          icon,
          size: 17,
          color: highlight ? AppTheme.brand : AppTheme.textSecondary,
        ),
      ),
    );
  }
}
