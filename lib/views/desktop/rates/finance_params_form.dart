import 'package:flutter/material.dart';

import '../../../core/services/finance_config_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_rules.dart';
import '../../shared/widgets/pro_ui.dart';

/// Formulario de parámetros financieros usados por las predicciones del panel:
/// precio de venta por litro a la industria y costo operativo mensual.
class FinanceParamsForm extends StatefulWidget {
  const FinanceParamsForm({
    super.key,
    required this.config,
    required this.purchasePrice,
    required this.monthlyLiters,
    required this.onSave,
    this.canEdit = true,
    this.saving = false,
  });

  final FinanceConfig config;

  /// Tarifa vigente pagada al productor.
  final double purchasePrice;

  /// Litros acopiados en los últimos 30 días (base de la proyección).
  final double monthlyLiters;
  final bool canEdit;
  final bool saving;
  final Future<bool> Function(double salePrice, double monthlyCost) onSave;

  static const double maxSalePrice = 99999;
  static const double maxMonthlyCost = 999999999;

  @override
  State<FinanceParamsForm> createState() => _FinanceParamsFormState();
}

class _FinanceParamsFormState extends State<FinanceParamsForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _sale = TextEditingController(
    text: widget.config.precioVentaLitro > 0
        ? ThousandsInputFormatter.format(
            widget.config.precioVentaLitro,
            decimals: 2,
          )
        : '',
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.config.costoOperativoMensual > 0
        ? ThousandsInputFormatter.format(widget.config.costoOperativoMensual)
        : '',
  );

  @override
  void didUpdateWidget(covariant FinanceParamsForm old) {
    super.didUpdateWidget(old);
    if (old.config != widget.config) {
      if (widget.config.precioVentaLitro > 0) {
        _sale.text = ThousandsInputFormatter.format(
          widget.config.precioVentaLitro,
          decimals: 2,
        );
      }
      if (widget.config.costoOperativoMensual > 0) {
        _cost.text = ThousandsInputFormatter.format(
          widget.config.costoOperativoMensual,
        );
      }
    }
  }

  @override
  void dispose() {
    _sale.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.onSave(
      ThousandsInputFormatter.parse(_sale.text) ?? 0,
      ThousandsInputFormatter.parse(_cost.text) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double sale = ThousandsInputFormatter.parse(_sale.text) ?? 0;
    final double cost = ThousandsInputFormatter.parse(_cost.text) ?? 0;
    final double margin = sale - widget.purchasePrice;
    final double gross = margin * widget.monthlyLiters;
    final double net = gross - cost;
    final bool hasData = sale > 0 && widget.purchasePrice > 0;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Widget saleField = AppTextField(
                key: const ValueKey<String>('finance-sale-field'),
                label: 'Precio de venta por litro',
                controller: _sale,
                enabled: widget.canEdit,
                hint: 'Ej. 2.300',
                helper: 'Lo que paga la industria',
                monospace: true,
                prefixIcon: Icons.sell_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: AppInputs.money(maxIntegerDigits: 5),
                validator: (String? v) => (v ?? '').trim().isEmpty
                    ? null
                    : AppValidators.money(
                        v,
                        min: 0,
                        max: FinanceParamsForm.maxSalePrice,
                      ),
                onChanged: (_) => setState(() {}),
              );
              final Widget costField = AppTextField(
                key: const ValueKey<String>('finance-cost-field'),
                label: 'Costo operativo mensual',
                controller: _cost,
                enabled: widget.canEdit,
                hint: 'Ej. 4.500.000',
                helper: 'Transporte, tanque, personal, energía',
                monospace: true,
                prefixIcon: Icons.receipt_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: AppInputs.money(
                  maxIntegerDigits: 9,
                  decimals: 0,
                ),
                validator: (String? v) => (v ?? '').trim().isEmpty
                    ? null
                    : AppValidators.money(
                        v,
                        min: 0,
                        max: FinanceParamsForm.maxMonthlyCost,
                      ),
                onChanged: (_) => setState(() {}),
              );
              if (c.maxWidth < 420) {
                return Column(
                  children: <Widget>[
                    saleField,
                    const SizedBox(height: 12),
                    costField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: saleField),
                  const SizedBox(width: 12),
                  Expanded(child: costField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppTheme.border),
            ),
            child: hasData
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _line(
                        'Margen por litro',
                        '${AppFormatters.formatCurrency(sale)} − ${AppFormatters.formatCurrency(widget.purchasePrice)}',
                        AppFormatters.formatCurrency(margin),
                        margin >= 0 ? Tone.success : Tone.danger,
                      ),
                      _line(
                        'Margen bruto mensual',
                        '${AppFormatters.formatLiters(widget.monthlyLiters)} en 30 días',
                        AppFormatters.formatCurrency(gross),
                        gross >= 0 ? Tone.neutral : Tone.danger,
                      ),
                      const Divider(height: 14, color: AppTheme.dividerLight),
                      _line(
                        'Ganancia estimada mensual',
                        'Margen bruto − costo operativo',
                        AppFormatters.formatCurrency(net),
                        net >= 0 ? Tone.success : Tone.danger,
                        strong: true,
                      ),
                    ],
                  )
                : Text(
                    'Ingresa el precio de venta para calcular el margen por litro y la ganancia estimada del mes.',
                    style: AppTheme.bodyStyle(fontSize: 12.5),
                  ),
          ),
          if (widget.config.actualizadoEn != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Última actualización: ${AppFormatters.formatDateTime(widget.config.actualizadoEn!)}',
              style: AppTheme.bodyStyle(
                fontSize: 11.5,
                color: AppTheme.textMuted,
              ),
            ),
          ],
          if (widget.canEdit) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: widget.saving ? null : _save,
                icon: widget.saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 17),
                label: const Text('Guardar parámetros'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    String label,
    String hint,
    String value,
    Tone tone, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTheme.bodyStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: AppTheme.monoStyle(
                  fontSize: strong ? 16 : 13.5,
                  fontWeight: FontWeight.w700,
                  color: tone == Tone.neutral ? AppTheme.textPrimary : tone.fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
