import 'package:flutter/material.dart';

import '../../../controllers/rate_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_rules.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';

/// Formulario "Nueva tarifa vigente" con vista previa del impacto.
///
/// Es independiente de los controladores para poder probarlo aislado:
/// [onSubmit] recibe precio, fecha de inicio y observación y devuelve
/// `true` si se guardó.
class NewRateForm extends StatefulWidget {
  const NewRateForm({
    super.key,
    required this.currentPrice,
    required this.currentPeriodLiters,
    required this.currentPeriodLabel,
    required this.onSubmit,
    this.saving = false,
    this.firstDate,
  });

  final double currentPrice;
  final double currentPeriodLiters;
  final String currentPeriodLabel;
  final bool saving;
  final DateTime? firstDate;
  final Future<bool> Function(double price, DateTime start, String observation)
  onSubmit;

  static const double maxPrice = 99999;

  @override
  State<NewRateForm> createState() => NewRateFormState();
}

class NewRateFormState extends State<NewRateForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _obs = TextEditingController();
  DateTime _start = DateTime.now();

  @override
  void dispose() {
    _price.dispose();
    _obs.dispose();
    super.dispose();
  }

  double? get _parsedPrice => ThousandsInputFormatter.parse(_price.text);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final double price = _parsedPrice!;
    final bool confirmed = await confirmAction(
      context,
      title: 'Publicar nueva tarifa',
      message:
          'Desde el ${AppFormatters.formatDate(_start)} se pagará ${AppFormatters.formatCurrency(price)} por litro. '
          'La tarifa anterior queda en el historial y los cierres ya emitidos no cambian.',
      confirmLabel: 'Publicar tarifa',
    );
    if (!confirmed || !mounted) return;
    final bool ok = await widget.onSubmit(price, _start, _obs.text.trim());
    if (ok && mounted) {
      _price.clear();
      _obs.clear();
      setState(() => _start = DateTime.now());
      _formKey.currentState?.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final double? price = _parsedPrice;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Widget priceField = AppTextField(
                key: const ValueKey<String>('rate-price-field'),
                label: 'Precio por litro',
                controller: _price,
                required: true,
                hint: 'Ej. 1.850',
                prefixIcon: Icons.attach_money_rounded,
                monospace: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: AppInputs.money(maxIntegerDigits: 5),
                validator: (String? v) =>
                    AppValidators.money(v, min: 1, max: NewRateForm.maxPrice),
                onChanged: (_) => setState(() {}),
              );
              final Widget dateField = LabeledField(
                label: 'Rige desde',
                required: true,
                child: AppDateField(
                  value: _start,
                  firstDate:
                      widget.firstDate ??
                      DateTime(now.year - 1, now.month, now.day),
                  lastDate: DateTime(now.year + 1, now.month, now.day),
                  onChanged: (DateTime d) => setState(() => _start = d),
                ),
              );
              if (c.maxWidth < 420) {
                return Column(
                  children: <Widget>[
                    priceField,
                    const SizedBox(height: 12),
                    dateField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: priceField),
                  const SizedBox(width: 12),
                  Expanded(child: dateField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          AppTextField(
            key: const ValueKey<String>('rate-obs-field'),
            label: 'Motivo del cambio',
            controller: _obs,
            required: true,
            hint: 'Ej. Ajuste acordado en asamblea de noviembre',
            helper:
                'Entre 5 y ${FieldLimits.shortText} caracteres. Queda en la auditoría.',
            inputFormatters: AppInputs.text(max: FieldLimits.shortText),
            validator: (String? v) => AppValidators.text(
              v,
              label: 'El motivo',
              min: 5,
              max: FieldLimits.shortText,
            ),
          ),
          const SizedBox(height: 12),
          _ImpactPreview(
            price: price,
            currentPrice: widget.currentPrice,
            liters: widget.currentPeriodLiters,
            periodLabel: widget.currentPeriodLabel,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey<String>('rate-submit'),
              onPressed: widget.saving ? null : _submit,
              icon: widget.saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.surface,
                      ),
                    )
                  : const Icon(Icons.publish_rounded, size: 17),
              label: const Text('Publicar tarifa'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpactPreview extends StatelessWidget {
  const _ImpactPreview({
    required this.price,
    required this.currentPrice,
    required this.liters,
    required this.periodLabel,
  });

  final double? price;
  final double currentPrice;
  final double liters;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    if (price == null || price! <= 0 || price! > NewRateForm.maxPrice) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.calculate_outlined,
              size: 18,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Escribe un precio para ver cuánto costaría la quincena actual ($periodLabel, '
                '${AppFormatters.formatLiters(liters)} hasta hoy).',
                style: AppTheme.bodyStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    // Sin litros aún en la quincena: se simula sobre 1.000 L de referencia.
    final bool reference = liters <= 0;
    final double base = reference ? 1000 : liters;
    final String baseLabel = reference
        ? 'cada 1.000 L (aún no hay entregas en $periodLabel)'
        : '${AppFormatters.formatLiters(liters)} de $periodLabel';
    final ({double cost, double currentCost, double diff, double? percent}) r =
        RateController.impact(
          liters: base,
          newPrice: price!,
          currentPrice: currentPrice,
        );
    final bool up = price! > currentPrice;
    final bool same = (price! - currentPrice).abs() < 0.005;
    final Tone tone = same ? Tone.neutral : (up ? Tone.warning : Tone.success);
    final String pct = r.percent == null
        ? ''
        : '${r.percent! >= 0 ? '+' : ''}${r.percent!.toStringAsFixed(1).replaceAll('.', ',')} %';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            same
                ? Icons.drag_handle_rounded
                : (up
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded),
            size: 20,
            color: tone.fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reference
                      ? 'Con este precio, cada 1.000 L costarían ${AppFormatters.formatCurrency(r.cost)}'
                      : 'Con este precio, la quincena actual costaría ${AppFormatters.formatCurrency(r.cost)}',
                  style: AppTheme.bodyStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  currentPrice <= 0
                      ? 'No hay tarifa vigente para comparar. Base: $baseLabel.'
                      : same
                      ? 'Igual que con la tarifa vigente (${AppFormatters.formatCurrency(currentPrice)}/L).'
                      : '${up ? '+' : '−'}${AppFormatters.formatCurrency(r.diff.abs())} ($pct) frente a la tarifa vigente '
                            'de ${AppFormatters.formatCurrency(currentPrice)}/L · base $baseLabel.',
                  style: AppTheme.bodyStyle(fontSize: 12, color: tone.fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
