import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/settlement_controller.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/settlement_pdf_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/settlement_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';

/// Acciones sobre el comprobante de un productor: ver, descargar y compartir.
class VoucherActions {
  VoucherActions._();

  static Future<Uint8List> _bytes(BuildContext context, SettlementModel s) {
    final SettlementController ctrl = context.read<SettlementController>();
    return SettlementPdfService.buildVoucherPdfBytes(
      settlement: s,
      receptions: ctrl.receptionsForSettlement(s),
      producer: ctrl.producerForSettlement(s),
    );
  }

  /// Guarda el PDF en Descargas/ASOPROGANUCOTT (escritorio) o lo comparte (móvil).
  static Future<void> download(
    BuildContext context,
    SettlementModel s, {
    Uint8List? bytes,
  }) async {
    try {
      final Uint8List data = bytes ?? await _bytes(context, s);
      final String name = SettlementPdfService.voucherFileName(s);
      if (FileExportService.isDesktop) {
        final SavedFile saved = await FileExportService.save(data, name);
        if (!context.mounted) return;
        showAppToast(
          context,
          'Comprobante ${s.numeroComprobante} guardado en Descargas',
          tone: Tone.success,
          action: SnackBarAction(
            label: 'Abrir carpeta',
            textColor: AppTheme.brandMuted,
            onPressed: () => FileExportService.reveal(saved),
          ),
        );
      } else {
        await FileExportService.share(data, name, mimeType: 'application/pdf');
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          'No se pudo generar el comprobante: $e',
          tone: Tone.danger,
        );
      }
    }
  }

  /// Abre el diálogo nativo "Compartir en…" (correo, WhatsApp, Drive…).
  static Future<void> share(
    BuildContext context,
    SettlementModel s, {
    Uint8List? bytes,
  }) async {
    try {
      final Uint8List data = bytes ?? await _bytes(context, s);
      await SettlementPdfService.shareVoucher(
        settlement: s,
        receptions: const [],
        bytes: data,
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          'No se pudo compartir el comprobante: $e',
          tone: Tone.danger,
        );
      }
    }
  }

  /// Vista previa a pantalla amplia con acciones de descarga, compartir e impresión.
  static Future<void> preview(BuildContext context, SettlementModel s) async {
    final SettlementController ctrl = context.read<SettlementController>();
    final Future<Uint8List> bytesFuture =
        SettlementPdfService.buildVoucherPdfBytes(
          settlement: s,
          receptions: ctrl.receptionsForSettlement(s),
          producer: ctrl.producerForSettlement(s),
        );
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final Size size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: size.width.clamp(320, 980).toDouble(),
            height: size.height * 0.9,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.receipt_long_rounded,
                        color: AppTheme.brand,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Comprobante ${s.numeroComprobante}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.subtitleStyle(),
                            ),
                            Text(
                              '${s.nombreProductorSnap} · ${s.quincenaLabel} · ${AppFormatters.formatCurrency(s.valorTotalPagar)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final Uint8List b = await bytesFuture;
                          if (ctx.mounted) await download(ctx, s, bytes: b);
                        },
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text('Descargar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final Uint8List b = await bytesFuture;
                          if (ctx.mounted) await share(ctx, s, bytes: b);
                        },
                        icon: const Icon(Icons.share_rounded, size: 17),
                        label: const Text('Compartir'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (_) => bytesFuture,
                    pdfFileName: SettlementPdfService.voucherFileName(s),
                    allowSharing: false,
                    allowPrinting: true,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    useActions: true,
                    scrollViewDecoration: const BoxDecoration(
                      color: AppTheme.canvasAlt,
                    ),
                    loadingWidget: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Diálogo para registrar el pago de un comprobante (fecha + referencia).
Future<bool> showRegisterPaymentDialog(
  BuildContext context,
  SettlementModel settlement,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (_) => RegisterPaymentDialog(settlement: settlement),
  );
  return ok ?? false;
}

class RegisterPaymentDialog extends StatefulWidget {
  const RegisterPaymentDialog({super.key, required this.settlement});
  final SettlementModel settlement;

  @override
  State<RegisterPaymentDialog> createState() => _RegisterPaymentDialogState();
}

class _RegisterPaymentDialogState extends State<RegisterPaymentDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _obs = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final UserModel? actor = context.read<AuthController>().currentUser;
    if (actor == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final DateTime now = DateTime.now();
    final DateTime when = DateTime(
      _date.year,
      _date.month,
      _date.day,
      now.hour,
      now.minute,
    );
    final SettlementController ctrl = context.read<SettlementController>();
    final bool ok = await ctrl.confirmPayment(
      actor: actor,
      settlement: widget.settlement,
      observacionPago: _obs.text.trim(),
      fechaPago: when,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = ctrl.errorMessage ?? 'No se pudo registrar el pago.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettlementModel s = widget.settlement;
    final DateTime closed = s.fechaLiquidacion.toLocal();
    return AppDialog(
      title: 'Registrar pago',
      subtitle: '${s.numeroComprobante} · ${s.nombreProductorSnap}',
      icon: Icons.payments_rounded,
      width: 480,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.brandSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${s.quincenaLabel} · ${AppFormatters.formatLiters(s.totalLitros)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        color: AppTheme.brandDeep,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppFormatters.formatCurrency(s.valorTotalPagar),
                        style: AppTheme.monoStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandDeep,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Fecha del pago',
              required: true,
              child: AppDateField(
                value: _date,
                firstDate: DateTime(closed.year, closed.month, closed.day),
                lastDate: DateTime.now(),
                onChanged: (DateTime d) => setState(() => _date = d),
              ),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Referencia u observación',
              controller: _obs,
              required: true,
              hint: 'Ej. Transferencia Bancolombia 0045, efectivo en planta',
              helper:
                  'Mínimo 3 caracteres. Quedará en la auditoría y en el comprobante.',
              inputFormatters: AppInputs.text(max: FieldLimits.shortText),
              validator: (String? v) => AppValidators.text(
                v,
                label: 'La referencia',
                min: 3,
                max: FieldLimits.shortText,
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppTheme.bodyStyle(
                  fontSize: 12.5,
                  color: AppTheme.dangerText,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.surface,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 17),
          label: const Text('Registrar pago'),
        ),
      ],
    );
  }
}
