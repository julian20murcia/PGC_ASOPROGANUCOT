import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/rate_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../core/security/permissions.dart';
import '../../core/services/settlement_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/milk_reception_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/pro_ui.dart';
import 'rates/finance_params_form.dart';
import 'rates/new_rate_form.dart';
import 'rates/rate_panels.dart';

/// Módulo de tarifas por litro (`RF-12`): precio vigente, historial,
/// publicación de nuevas tarifas con simulación de impacto y parámetros
/// financieros para las predicciones del panel.
class RatesModuleView extends StatefulWidget {
  const RatesModuleView({super.key});

  @override
  State<RatesModuleView> createState() => _RatesModuleViewState();
}

class _RatesModuleViewState extends State<RatesModuleView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RateController rates = context.read<RateController>();
      rates.loadRates();
      rates.loadFinance();
      final SettlementController settlements = context
          .read<SettlementController>();
      if (!settlements.loadedOnce && !settlements.isLoading) {
        settlements.loadData();
      }
    });
  }

  double _litersLast30Days(List<MilkReceptionModel> receptions) {
    final DateTime now = DateTime.now();
    final String from = AppFormatters.toIsoDate(
      now.subtract(const Duration(days: 29)),
    );
    final String to = AppFormatters.toIsoDate(now);
    int t = 0;
    for (final MilkReceptionModel r in receptions) {
      if (r.anulado) continue;
      if (r.fechaEntrega.compareTo(from) >= 0 &&
          r.fechaEntrega.compareTo(to) <= 0) {
        t += (r.litros * 1000).round();
      }
    }
    return t / 1000.0;
  }

  Future<bool> _createRate(
    UserModel? user,
    double price,
    DateTime start,
    String obs,
  ) async {
    if (user == null) return false;
    final RateController ctrl = context.read<RateController>();
    final bool ok = await ctrl.createRate(
      actor: user,
      precioPorLitro: price,
      fechaInicioVigencia: start,
      observacion: obs,
    );
    if (!mounted) return ok;
    showAppToast(
      context,
      ok
          ? (ctrl.feedbackMessage ?? 'Tarifa publicada')
          : (ctrl.errorMessage ?? 'No se pudo publicar la tarifa'),
      tone: ok ? Tone.success : Tone.danger,
    );
    if (ok) context.read<SettlementController>().loadData();
    return ok;
  }

  Future<bool> _saveFinance(UserModel? user, double sale, double cost) async {
    if (user == null) return false;
    final String? err = await context.read<RateController>().saveFinance(
      actor: user,
      precioVentaLitro: sale,
      costoOperativoMensual: cost,
    );
    if (!mounted) return err == null;
    showAppToast(
      context,
      err ?? 'Parámetros financieros guardados',
      tone: err == null ? Tone.success : Tone.danger,
    );
    return err == null;
  }

  @override
  Widget build(BuildContext context) {
    final RateController ctrl = context.watch<RateController>();
    final SettlementController settlements = context
        .watch<SettlementController>();
    final UserModel? user = context.watch<AuthController>().currentUser;
    final bool canCreate =
        user?.can(Permissions.tarifas, PermAction.crear) ?? false;
    final QuincenaPeriod current = QuincenaPeriod.currentForDate(
      DateTime.now(),
    );
    final bool narrow = MediaQuery.sizeOf(context).width < 700;

    final Widget left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RateHeroPanel(ctrl: ctrl),
        const SizedBox(height: 12),
        RateHistoryPanel(ctrl: ctrl),
      ],
    );

    final Widget right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (canCreate) ...<Widget>[
          Panel(
            title: 'Nueva tarifa vigente',
            subtitle:
                'La tarifa actual se cierra automáticamente y queda en el historial',
            icon: Icons.add_chart_rounded,
            child: NewRateForm(
              currentPrice: ctrl.effectivePricePerLiter,
              currentPeriodLiters: settlements.currentPeriodLiters,
              currentPeriodLabel: current.label,
              saving: ctrl.isSaving,
              onSubmit: (double p, DateTime d, String o) =>
                  _createRate(user, p, d, o),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Panel(
          title: 'Parámetros financieros',
          subtitle:
              'Alimentan las predicciones de ganancia del panel de inicio',
          icon: Icons.account_balance_wallet_outlined,
          child: FinanceParamsForm(
            config: ctrl.finance,
            purchasePrice: ctrl.effectivePricePerLiter,
            monthlyLiters: _litersLast30Days(settlements.allReceptions),
            canEdit: canCreate,
            saving: ctrl.isSavingFinance,
            onSave: (double s, double c) => _saveFinance(user, s, c),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: AppTheme.canvas,
      child: ListView(
        padding: EdgeInsets.all(narrow ? 16 : 24),
        children: <Widget>[
          PageHeader(
            title: 'Tarifas por litro',
            subtitle:
                'Precio de compra al productor, su historial y los parámetros de venta.',
            actions: <Widget>[
              if (ctrl.fromCache)
                const StatusBadge(
                  'Datos sin conexión',
                  tone: Tone.warning,
                  icon: Icons.cloud_off_rounded,
                ),
              OutlinedButton.icon(
                onPressed: ctrl.isLoading
                    ? null
                    : () {
                        ctrl.loadRates();
                        ctrl.loadFinance();
                      },
                icon: ctrl.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ctrl.isLoading && ctrl.rates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                if (c.maxWidth < 1040) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[left, const SizedBox(height: 12), right],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 7, child: left),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: right),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
