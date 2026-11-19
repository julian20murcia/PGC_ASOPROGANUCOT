import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../core/security/permissions.dart';
import '../../core/services/settlement_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_date_range_picker.dart';
import '../shared/widgets/pro_ui.dart';
import 'settlements/close_quincena_wizard.dart';
import 'settlements/settlement_period_detail.dart';
import 'settlements/settlements_overview.dart';

/// Módulo de liquidaciones quincenales: cierre guiado, quincenas cerradas,
/// detalle por productor / día, comprobantes y pagos (`RF-13` a `RF-15`).
class SettlementsModuleView extends StatefulWidget {
  const SettlementsModuleView({super.key});

  @override
  State<SettlementsModuleView> createState() => _SettlementsModuleViewState();
}

class _SettlementsModuleViewState extends State<SettlementsModuleView> {
  String? _openKey;
  DateRangeValue? _range;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettlementController>().loadData();
    });
  }

  Future<void> _openWizard(QuincenaPeriod period) async {
    final String? key = await showCloseQuincenaWizard(context, initial: period);
    if (!mounted) return;
    if (key != null) setState(() => _openKey = key);
  }

  List<SettlementPeriodGroup> _filtered(List<SettlementPeriodGroup> all) {
    final String q = _query.trim().toLowerCase();
    return all.where((SettlementPeriodGroup g) {
      if (_range != null &&
          !(g.periodoInicio.compareTo(_range!.endIso) <= 0 &&
              g.periodoFin.compareTo(_range!.startIso) >= 0)) {
        return false;
      }
      if (q.isEmpty) return true;
      if (g.label.toLowerCase().contains(q)) return true;
      return g.settlements.any(
        (SettlementModel s) =>
            s.nombreProductorSnap.toLowerCase().contains(q) ||
            s.cedulaProductorSnap.toLowerCase().contains(q) ||
            s.numeroComprobante.toLowerCase().contains(q),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final UserModel? user = context.watch<AuthController>().currentUser;
    final bool canClose =
        user?.can(Permissions.liquidaciones, PermAction.crear) ?? false;
    final List<SettlementPeriodGroup> groups = ctrl.periodGroups;

    if (_openKey != null) {
      final SettlementPeriodGroup? g = groups
          .where((SettlementPeriodGroup x) => x.key == _openKey)
          .firstOrNull;
      if (g != null) {
        return ColoredBox(
          color: AppTheme.canvas,
          child: SettlementPeriodDetail(
            key: ValueKey<String>(g.key),
            group: g,
            onBack: () => setState(() => _openKey = null),
          ),
        );
      }
    }

    final bool narrow = MediaQuery.sizeOf(context).width < 700;
    return ColoredBox(
      color: AppTheme.canvas,
      child: RefreshIndicator(
        onRefresh: ctrl.loadData,
        child: ListView(
          padding: EdgeInsets.all(narrow ? 16 : 24),
          children: <Widget>[
            PageHeader(
              title: 'Liquidaciones Quincenales',
              subtitle:
                  'Cierra quincenas, consulta lo liquidado a cada productor y registra los pagos.',
              actions: <Widget>[
                if (ctrl.fromCache)
                  const StatusBadge(
                    'Datos sin conexión',
                    tone: Tone.warning,
                    icon: Icons.cloud_off_rounded,
                  ),
                OutlinedButton.icon(
                  onPressed: ctrl.isLoading ? null : ctrl.loadData,
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
            if (ctrl.isLoading && !ctrl.loadedOnce)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...<Widget>[
              if (ctrl.errorMessage != null && !ctrl.isClosing) ...<Widget>[
                _ErrorBanner(
                  message: ctrl.errorMessage!,
                  onDismiss: ctrl.clearFeedback,
                ),
                const SizedBox(height: 12),
              ],
              CurrentPeriodPanel(canClose: canClose, onClose: _openWizard),
              const SizedBox(height: 12),
              ClosedPeriodsPanel(
                groups: _filtered(groups),
                range: _range,
                onRangeChanged: (DateRangeValue v) =>
                    setState(() => _range = v),
                onClearRange: () => setState(() => _range = null),
                onQueryChanged: (String v) => setState(() => _query = v),
                onOpen: (SettlementPeriodGroup g) =>
                    setState(() => _openKey = g.key),
                emptyAction: canClose && _range == null
                    ? FilledButton.icon(
                        onPressed: () => _openWizard(
                          QuincenaPeriod.previousForDate(DateTime.now()),
                        ),
                        icon: const Icon(Icons.lock_clock_rounded, size: 17),
                        label: const Text('Cerrar primera quincena'),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppTheme.dangerText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: AppTheme.dangerText,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Descartar',
            onPressed: onDismiss,
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppTheme.dangerText,
            ),
          ),
        ],
      ),
    );
  }
}
