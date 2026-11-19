import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/settlement_pdf_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';
import 'delivery_calendar.dart';
import 'mobile_kit.dart';

/// Genera los bytes del desprendible de una quincena.
Future<Uint8List> buildSettlementVoucher(ProducerPortalController portal, SettlementModel s) {
  return SettlementPdfService.buildVoucherPdfBytes(
    settlement: s,
    receptions: portal.receptionsForSettlement(s),
    producer: portal.activeProducer,
  );
}

String voucherFileName(SettlementModel s) {
  final String raw = s.numeroComprobante.trim().isEmpty ? s.liquidacionId : s.numeroComprobante;
  final String clean = raw.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-');
  return 'Desprendible_$clean.pdf';
}

/// Comparte / descarga el desprendible con el diálogo nativo del sistema.
Future<void> shareSettlementVoucher(BuildContext context, ProducerPortalController portal, SettlementModel s) async {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final Uint8List bytes = await buildSettlementVoucher(portal, s);
    await FileExportService.share(
      bytes,
      voucherFileName(s),
      mimeType: 'application/pdf',
      subject: 'Desprendible de pago ${s.numeroComprobante}',
      text: 'Desprendible de pago · ${s.quincenaLabel}',
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.danger,
        content: Text('No fue posible generar el desprendible: $e'),
      ),
    );
  }
}

/// Detalle de una quincena: totales, calendario del período y desprendible.
class SettlementDetailPage extends StatefulWidget {
  const SettlementDetailPage({super.key, required this.portal, required this.settlement});

  final ProducerPortalController portal;
  final SettlementModel settlement;

  @override
  State<SettlementDetailPage> createState() => _SettlementDetailPageState();
}

class _SettlementDetailPageState extends State<SettlementDetailPage> {
  String? _selected;
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await shareSettlementVoucher(context, widget.portal, widget.settlement);
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final SettlementModel s = widget.settlement;
    final List<MilkReceptionModel> recs = widget.portal.receptionsForSettlement(s);
    final Map<String, DayDeliverySummary> summaries = ProducerPortalController.buildDaySummaries(recs);
    final DateTime month = MobileDates.parseIso(s.periodoInicio) ?? DateTime.now();
    final double morning = summaries.values.fold<double>(0, (double a, DayDeliverySummary d) => a + d.morningLiters);
    final double afternoon = summaries.values.fold<double>(0, (double a, DayDeliverySummary d) => a + d.afternoonLiters);
    final double top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              gradient: MobileTokens.headerGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(8, top + 6, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Volver',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        s.quincenaLabel.isEmpty ? 'Liquidación' : s.quincenaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileTokens.title(size: 17, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Total a pagar', style: MobileTokens.body(size: 14, color: Colors.white.withValues(alpha: 0.75))),
                      AnimatedNumber(
                        value: s.valorTotalPagar,
                        format: (double v) => AppFormatters.formatCurrency(v.roundToDouble()),
                        style: MobileTokens.display(size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: <Widget>[
                          TonePill(
                            s.isPagada ? 'Pagada' : 'Pendiente de pago',
                            onDark: true,
                            icon: s.isPagada ? Icons.check_circle_rounded : Icons.schedule_rounded,
                          ),
                          TonePill(MobileDates.period(s.periodoInicio, s.periodoFin), onDark: true, icon: Icons.date_range_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 16, MobileTokens.gutter, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FadeSlideIn(
                  child: SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                    child: Row(
                      children: <Widget>[
                        _Metric(label: 'Litros', value: AppFormatters.formatLiters(s.totalLitros)),
                        _Metric(label: 'Entregas', value: '${s.cantidadEntregas}'),
                        _Metric(label: 'Precio / L', value: AppFormatters.formatCurrency(s.precioLitroAplicado)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  index: 1,
                  child: SoftCard(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text('Lo que se hizo cada día', style: MobileTokens.title(size: 16))),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 12),
                          child: Text(
                            'Mañana ${AppFormatters.formatLiters(morning)} · Tarde ${AppFormatters.formatLiters(afternoon)}',
                            style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                          ),
                        ),
                        const WeekdayHeader(),
                        const SizedBox(height: 4),
                        DeliveryMonthGrid(
                          key: const ValueKey<String>('settlement-calendar'),
                          month: DateTime(month.year, month.month, 1),
                          summaries: summaries,
                          selectedIso: _selected,
                          rangeStart: s.periodoInicio,
                          rangeEnd: s.periodoFin,
                          onDayTap: (String iso) {
                            setState(() => _selected = iso);
                            showDayDetailSheet(
                              context,
                              portal: widget.portal,
                              isoDate: iso,
                              summary: summaries[iso] ?? DayDeliverySummary(isoDate: iso),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: ShiftLegend()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  index: 2,
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text('Datos del pago', style: MobileTokens.title(size: 16)),
                        const SizedBox(height: 4),
                        InfoRow(label: 'Comprobante', value: s.numeroComprobante, mono: true),
                        InfoRow(label: 'Liquidada el', value: AppFormatters.formatDate(s.fechaLiquidacion)),
                        InfoRow(
                          label: 'Pagada el',
                          value: s.fechaPago == null ? 'Pendiente' : AppFormatters.formatDate(s.fechaPago!),
                        ),
                        if ((s.observacionPago ?? '').isNotEmpty) InfoRow(label: 'Referencia', value: s.observacionPago!),
                        InfoRow(
                          label: 'Código de integridad',
                          value: s.hashIntegridad.length > 12 ? '${s.hashIntegridad.substring(0, 12)}…' : s.hashIntegridad,
                          mono: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 10, MobileTokens.gutter, 10),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const ValueKey<String>('btn-view-voucher'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => VoucherPreviewPage(portal: widget.portal, settlement: s),
                    ),
                  ),
                  icon: const Icon(Icons.description_rounded, size: 20),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ver desprendible')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share_rounded, size: 20),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Descargar')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: <Widget>[
            Text(label, style: MobileTokens.label()),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: MobileTokens.number(size: 16))),
          ],
        ),
      ),
    );
  }
}

/// Vista previa del desprendible dentro de la app, con descarga / compartir.
class VoucherPreviewPage extends StatefulWidget {
  const VoucherPreviewPage({super.key, required this.portal, required this.settlement});

  final ProducerPortalController portal;
  final SettlementModel settlement;

  @override
  State<VoucherPreviewPage> createState() => _VoucherPreviewPageState();
}

class _VoucherPreviewPageState extends State<VoucherPreviewPage> {
  late final Future<Uint8List> _bytes = buildSettlementVoucher(widget.portal, widget.settlement);

  @override
  Widget build(BuildContext context) {
    final SettlementModel s = widget.settlement;
    return Scaffold(
      backgroundColor: AppTheme.canvasAlt,
      appBar: AppBar(
        backgroundColor: AppTheme.brandDeep,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Desprendible de pago', style: MobileTokens.title(size: 17, color: Colors.white)),
            Text(
              s.numeroComprobante,
              style: MobileTokens.body(size: 13, color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Descargar o compartir',
            onPressed: () => shareSettlementVoucher(context, widget.portal, s),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => _bytes,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        pdfFileName: voucherFileName(s),
        maxPageWidth: 720,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (BuildContext context, Object error) => Center(
          child: MobileEmpty(
            icon: Icons.picture_as_pdf_rounded,
            title: 'No se pudo mostrar el desprendible',
            message: '$error',
          ),
        ),
        scrollViewDecoration: const BoxDecoration(color: AppTheme.canvasAlt),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 8, MobileTokens.gutter, 10),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => shareSettlementVoucher(context, widget.portal, s),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Descargar / Compartir PDF'),
          ),
        ),
      ),
    );
  }
}
