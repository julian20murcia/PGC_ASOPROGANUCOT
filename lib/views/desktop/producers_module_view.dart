import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_date_range_picker.dart';
import '../shared/widgets/pro_ui.dart';
import 'producers/producer_app_access_dialog.dart';
import 'producers/producer_detail_panel.dart';
import 'producers/producer_directory_export.dart';
import 'producers/producer_form_wizard.dart';
import 'producers/producer_table.dart';

/// Módulo administrativo de Productores y Autorización de Datos Personales (Ley 1581 de 2012).
class ProducersModuleView extends StatefulWidget {
  const ProducersModuleView({super.key});

  @override
  State<ProducersModuleView> createState() => _ProducersModuleViewState();
}

class _ProducersModuleViewState extends State<ProducersModuleView> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProducerController>().refreshAll();
    });
  }

  UserModel? get _user => context.read<AuthController>().currentUser;
  String get _actorUid => _user?.uid ?? 'admin';

  bool _can(String action) =>
      _user?.can(Permissions.productores, action) ?? false;
  bool get _canCreateAppAccess =>
      _user?.can(Permissions.usuarios, PermAction.crear) ?? false;

  Future<void> _openCreate() async {
    final ProducerWizardResult? result = await showProducerWizard(
      context,
      actorUid: _actorUid,
      canCreateAppAccess: _canCreateAppAccess,
    );
    if (result == null || !mounted) return;
    setState(() => _selectedId = result.producer.productorId);
    showAppToast(
      context,
      'Productor "${result.producer.nombreCompleto}" registrado.',
      tone: Tone.success,
    );
    if (result.wantsAppAccess) await _createAppAccess(result.producer);
  }

  Future<void> _openEdit(ProducerModel producer) async {
    final ProducerWizardResult? result = await showProducerWizard(
      context,
      actorUid: _actorUid,
      existing: producer,
    );
    if (result == null || !mounted) return;
    showAppToast(context, 'Cambios guardados.', tone: Tone.success);
  }

  Future<void> _toggleStatus(ProducerModel p) async {
    final bool confirmed = await confirmAction(
      context,
      title: p.isActivo ? 'Inactivar productor' : 'Activar productor',
      message: p.isActivo
          ? '${p.nombreCompleto} dejará de aparecer en la recepción de leche. Su historial de entregas y pagos se conserva.'
          : '${p.nombreCompleto} podrá volver a entregar leche en la planta.',
      confirmLabel: p.isActivo ? 'Inactivar' : 'Activar',
      destructive: p.isActivo,
    );
    if (!confirmed || !mounted) return;
    final ProducerController ctrl = context.read<ProducerController>();
    final bool ok = await ctrl.toggleProducerStatus(
      producer: p,
      actorUid: _actorUid,
    );
    if (!mounted) return;
    showAppToast(
      context,
      ok
          ? (ctrl.feedbackMessage ?? 'Estado actualizado.')
          : (ctrl.errorMessage ?? 'No fue posible actualizar el estado.'),
      tone: ok ? Tone.success : Tone.danger,
    );
  }

  Future<void> _createAppAccess(ProducerModel p) async {
    final bool ok = await showProducerAppAccessDialog(
      context,
      producer: p,
      actorUid: _actorUid,
    );
    if (ok && mounted) {
      showAppToast(
        context,
        'Acceso móvil creado para ${p.nombreCompleto}.',
        tone: Tone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();
    context.watch<AuthController>();
    final ProducerModel? selected = _selectedId == null
        ? null
        : ctrl.byId(_selectedId!);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedId != null) setState(() => _selectedId = null);
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final bool narrow = c.maxWidth < 900;
            final double pad = narrow ? 16 : 24;
            final bool shortScreen = c.maxHeight < (narrow ? 820 : 600);
            final double drawerWidth = (c.maxWidth * 0.92)
                .clamp(300, 400)
                .toDouble();

            final Widget table = ProducerTable(
              selectedId: _selectedId,
              onSelect: (ProducerModel p) => setState(
                () => _selectedId = _selectedId == p.productorId
                    ? null
                    : p.productorId,
              ),
              onCreate: _can(PermAction.crear) ? _openCreate : null,
            );

            final List<Widget> top = <Widget>[
              _buildHeader(ctrl),
              const SizedBox(height: 12),
              _buildStats(ctrl),
              if (ctrl.errorMessage != null &&
                  ctrl.allProducers.isEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _ErrorBanner(
                  message: ctrl.errorMessage!,
                  onRetry: ctrl.refreshAll,
                ),
              ],
              const SizedBox(height: 12),
            ];

            final Widget content = shortScreen
                ? SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ...top,
                        SizedBox(height: 460, child: table),
                      ],
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ...top,
                        Expanded(child: table),
                      ],
                    ),
                  );

            return Stack(
              children: <Widget>[
                Positioned.fill(child: content),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  right: selected == null ? -drawerWidth - 24 : 0,
                  width: drawerWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: const Border(
                        left: BorderSide(color: AppTheme.border),
                      ),
                      boxShadow: selected == null
                          ? const <BoxShadow>[]
                          : AppTheme.shadowMd,
                    ),
                    child: selected == null
                        ? const ColoredBox(color: AppTheme.surface)
                        : ProducerDetailPanel(
                            key: ValueKey<String>(selected.productorId),
                            producer: selected,
                            onClose: () => setState(() => _selectedId = null),
                            onEdit: _can(PermAction.editar)
                                ? () => _openEdit(selected)
                                : null,
                            onToggleStatus:
                                (selected.isActivo
                                    ? _can(PermAction.eliminar)
                                    : _can(PermAction.editar))
                                ? () => _toggleStatus(selected)
                                : null,
                            onCreateAppAccess: _canCreateAppAccess
                                ? () => _createAppAccess(selected)
                                : null,
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(ProducerController ctrl) {
    return PageHeader(
      title: 'Productores',
      subtitle:
          'Padrón de asociados, litros entregados y autorización de datos (Ley 1581).',
      actions: <Widget>[
        AppDateRangeField(
          key: const Key('producer-period-field'),
          dense: true,
          value: ctrl.period,
          lastDate: DateTime.now(),
          onChanged: ctrl.setPeriod,
        ),
        IconButton.outlined(
          tooltip: 'Actualizar',
          onPressed: ctrl.isLoading ? null : ctrl.refreshAll,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppTheme.inputBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
          ),
        ),
        if (_can(PermAction.exportar))
          ExportButton(
            label: 'Exportar',
            title: 'Exportar directorio',
            subtitle:
                'Productores filtrados con litros de ${ctrl.period.label}',
            build: (format) {
              final ProducerController c = context.read<ProducerController>();
              return ProducerDirectoryExport.build(
                format,
                producers: c.filteredProducers,
                statsFor: c.statsFor,
                periodLabel: c.period.label,
              );
            },
          ),
        if (_can(PermAction.crear))
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Nuevo productor'),
          ),
      ],
    );
  }

  Widget _buildStats(ProducerController ctrl) {
    final String liters = ctrl.isLoadingDeliveries && !ctrl.deliveriesLoaded
        ? '…'
        : AppFormatters.formatLiters(ctrl.periodLiters);
    return StatStrip(
      minItemWidth: 190,
      items: <StatItem>[
        StatItem(
          label: 'Productores activos',
          value: '${ctrl.activeCount}',
          hint: 'de ${ctrl.totalCount} registrados',
          icon: Icons.groups_outlined,
        ),
        StatItem(
          label: 'Litros en el período',
          value: liters,
          hint: '${ctrl.periodDeliveries} entregas · ${ctrl.period.label}',
          icon: Icons.water_drop_outlined,
          tone: Tone.info,
        ),
        StatItem(
          label: 'Sin entregas',
          value: '${ctrl.activeWithoutDeliveries}',
          hint: 'activos sin leche en el período',
          icon: Icons.report_gmailerrorred_outlined,
          tone: ctrl.activeWithoutDeliveries > 0 ? Tone.warning : Tone.success,
        ),
        StatItem(
          label: 'Con acceso a la app',
          value: '${ctrl.linkedMobileCount}',
          hint: '${ctrl.veredasCount} veredas',
          icon: Icons.smartphone_rounded,
          tone: Tone.accent,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: AppTheme.dangerText,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
