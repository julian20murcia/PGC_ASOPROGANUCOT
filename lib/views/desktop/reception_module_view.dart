import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/reception_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/permissions.dart';
import '../../core/services/file_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_rules.dart';
import '../../models/milk_reception_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_date_range_picker.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/pro_ui.dart';
import '../shared/widgets/ui_kit.dart';
import 'reception/quick_capture_bar.dart';
import 'reception/reception_export.dart';
import 'reception/reception_grid_logic.dart';
import 'reception/reception_records_table.dart';
import 'reception/reception_spreadsheet.dart';

enum _ReceptionView { planilla, registros }

/// Módulo de recepción de leche: captura rápida + planilla tipo hoja de
/// cálculo por rango de fechas (edición in-place, sin modales) + registros.
class ReceptionModuleView extends StatefulWidget {
  const ReceptionModuleView({super.key});

  @override
  State<ReceptionModuleView> createState() => _ReceptionModuleViewState();
}

class _ReceptionModuleViewState extends State<ReceptionModuleView> {
  _ReceptionView _view = _ReceptionView.planilla;

  // Memo de la planilla: solo se reconstruye si cambian entregas, productores o rango.
  Object? _matrixKey;
  PlanillaMatrix? _matrixCache;

  PlanillaMatrix _planilla(ReceptionController ctrl) {
    final DateRangeValue range = ctrl.range;
    final List<MilkReceptionModel> inRange = ctrl.rangeReceptions;
    final Object key = (inRange, ctrl.activeProducers, range.start, range.end);
    if (_matrixCache == null || key != _matrixKey) {
      _matrixCache = PlanillaMatrix.build(
        activeProducers: ctrl.activeProducers,
        receptions: inRange,
        start: range.start,
        end: range.end,
      );
      _matrixKey = key;
    }
    return _matrixCache!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ReceptionController ctrl = context.read<ReceptionController>();
      ctrl.loadRange(
        ctrl.range,
        isOnlineOverride: context.read<UserController>().isOnline,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isOnline = context.watch<UserController>().isOnline;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ReceptionController>().setOnlineStatus(isOnline);
      }
    });
  }

  UserModel get _actor =>
      context.read<AuthController>().currentUser ?? UserModel.bootstrapAdmin();

  String _operatorName(String uid) {
    final UserModel? me = context.read<AuthController>().currentUser;
    if (me != null && me.uid == uid) return me.nombreCompleto;
    for (final UserModel u in context.read<UserController>().allUsers) {
      if (u.uid == uid) return u.nombreCompleto;
    }
    if (uid.isEmpty) return '—';
    return uid.length > 10 ? 'Operario ${uid.substring(0, 6)}' : uid;
  }

  // ── Operaciones de celda (sin diálogos) ────────────────────────────────────

  Future<String?> _createCell(
    PlanillaRow row,
    DateTime day,
    String jornada,
    double liters,
  ) async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    if (row.producer == null) return 'Productor inactivo';
    final res = await ctrl.registerCellDelivery(
      producer: row.producer!,
      day: day,
      jornada: jornada,
      litros: liters,
      operarioUid: _actor.uid,
    );
    if (res.duplicateFound != null) {
      return 'Ya existe una entrega en esa jornada '
          '(${formatLitersCo(res.duplicateFound!.litros)} L). Actualiza la planilla.';
    }
    return res.saved
        ? null
        : (res.error ?? ctrl.errorMessage ?? 'No se pudo guardar');
  }

  Future<String?> _editCell(MilkReceptionModel existing, double liters) async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    final bool ok = await ctrl.editDeliveryLitros(
      existing: existing,
      nuevosLitros: liters,
      motivo: autoCorrectionReason(existing.litros, liters),
      actor: _actor,
    );
    return ok ? null : (ctrl.errorMessage ?? 'No se pudo corregir');
  }

  Future<String?> _annulCell(MilkReceptionModel existing) async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    final bool ok = await ctrl.annulDelivery(
      existing: existing,
      motivo: autoAnnulReason(existing),
      actor: _actor,
    );
    if (ok && mounted) {
      showAppToast(
        context,
        'Entrega anulada y registrada en auditoría.',
        tone: Tone.success,
      );
    }
    return ok ? null : (ctrl.errorMessage ?? 'No se pudo anular');
  }

  // ── Construcción ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = context.watch<ReceptionController>();
    final UserModel user =
        context.watch<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final bool canCreate = user.can(Permissions.recepcion, PermAction.crear);
    // Correcciones y anulaciones según el árbol de permisos (también lo
    // exige `firestore.rules` mediante can('recepcion', 'editar'|'eliminar')).
    final bool canEdit = user.can(Permissions.recepcion, PermAction.editar);
    final bool canAnnul = user.can(Permissions.recepcion, PermAction.eliminar);
    final bool canExport = user.can(Permissions.recepcion, PermAction.exportar);
    final bool narrow = MediaQuery.sizeOf(context).width < 900;

    final DateRangeValue range = ctrl.range;
    final PlanillaMatrix fullMatrix = _planilla(ctrl);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool fill = c.hasBoundedHeight && c.maxHeight >= 640;
        final EdgeInsets pad = EdgeInsets.symmetric(
          horizontal: narrow ? 16 : 24,
          vertical: 16,
        );
        final List<Widget> top = <Widget>[
          PageHeader(
            title: 'Recepción de Leche',
            subtitle:
                'Captura diaria por productor y jornada · planilla editable como hoja de cálculo',
            actions: <Widget>[
              if (ctrl.pendingSyncCount > 0)
                OutlinedButton.icon(
                  onPressed: ctrl.isSyncing ? null : ctrl.syncPendingNow,
                  icon: ctrl.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 17),
                  label: Text('Sincronizar (${ctrl.pendingSyncCount})'),
                ),
              OutlinedButton.icon(
                onPressed: ctrl.isLoading ? null : () => ctrl.loadRange(range),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Actualizar'),
              ),
              if (canExport)
                ExportButton(
                  title: 'Descargar planilla',
                  subtitle: 'Recepción · ${range.label}',
                  build: (ExportFormat f) => ReceptionExport.build(
                    format: f,
                    matrix: fullMatrix,
                    records: ctrl.rangeReceptions,
                    rangeLabel: range.label,
                    rangeKey: range.start == range.end
                        ? range.startIso
                        : '${range.startIso}_${range.endIso}',
                    operatorName: _operatorName,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _summary(ctrl, range),
          const SizedBox(height: 12),
          QuickCaptureBar(canCreate: canCreate),
          const SizedBox(height: 12),
        ];
        final Widget work = _workArea(
          ctrl: ctrl,
          matrix: fullMatrix,
          canCreate: canCreate,
          canEdit: canEdit,
          canAnnul: canAnnul,
        );
        if (fill) {
          return Padding(
            padding: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ...top,
                Expanded(child: work),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ...top,
              SizedBox(height: 520, child: work),
            ],
          ),
        );
      },
    );
  }

  Widget _summary(ReceptionController ctrl, DateRangeValue range) {
    final bool isToday = range == DateRangePresets.today();
    final int active = ctrl.activeProducers.length;
    return StatStrip(
      minItemWidth: 150,
      items: <StatItem>[
        StatItem(
          label: isToday ? 'Litros recibidos hoy' : 'Litros del período',
          value: '${formatLitersCo(ctrl.rangeTotalLiters)} L',
          hint: range.label,
          icon: Icons.water_drop_outlined,
        ),
        StatItem(
          label: 'Mañana',
          value: '${formatLitersCo(ctrl.rangeMorningLiters)} L',
          icon: Icons.wb_sunny_outlined,
          tone: Tone.brand,
        ),
        StatItem(
          label: 'Tarde',
          value: '${formatLitersCo(ctrl.rangeAfternoonLiters)} L',
          icon: Icons.wb_twilight_rounded,
          tone: Tone.accent,
        ),
        StatItem(
          label: 'Entregas',
          value: ThousandsInputFormatter.format(ctrl.rangeDeliveriesCount),
          icon: Icons.receipt_long_outlined,
          tone: Tone.info,
        ),
        StatItem(
          label: 'Productores',
          value: '${ctrl.rangeProducersDelivered} / $active',
          hint: 'entregaron / activos',
          icon: Icons.people_alt_outlined,
          tone: Tone.success,
        ),
        StatItem(
          label: 'Pendientes de sincronizar',
          value: ThousandsInputFormatter.format(ctrl.pendingSyncCount),
          hint: ctrl.pendingSyncCount > 0
              ? 'Usa «Sincronizar» arriba'
              : (ctrl.isFromOfflineCache
                    ? 'Mostrando caché sin conexión'
                    : 'Todo al día'),
          icon: Icons.cloud_sync_outlined,
          tone: ctrl.pendingSyncCount > 0 ? Tone.warning : Tone.neutral,
        ),
      ],
    );
  }

  Widget _workArea({
    required ReceptionController ctrl,
    required PlanillaMatrix matrix,
    required bool canCreate,
    required bool canEdit,
    required bool canAnnul,
  }) {
    final DateTime now = DateTime.now();
    final Widget toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AppSegmentedControl<_ReceptionView>(
            selected: _view,
            onChanged: (_ReceptionView v) => setState(() => _view = v),
            segments: const <AppSegment<_ReceptionView>>[
              AppSegment<_ReceptionView>(
                value: _ReceptionView.planilla,
                label: 'Planilla',
                icon: Icons.grid_on_rounded,
              ),
              AppSegment<_ReceptionView>(
                value: _ReceptionView.registros,
                label: 'Registros',
                icon: Icons.list_alt_rounded,
              ),
            ],
          ),
          AppDateRangeField(
            dense: true,
            value: ctrl.range,
            lastDate: DateTime(now.year, now.month, now.day),
            onChanged: ctrl.setDateRange,
          ),
          _rangeShortcut('Hoy', DateRangePresets.today(now), ctrl),
          _rangeShortcut(
            'Esta quincena',
            DateRangePresets.quincenaOf(now),
            ctrl,
          ),
          _rangeShortcut(
            'Quincena anterior',
            DateRangePresets.quincenaOf(
              DateRangePresets.quincenaOf(
                now,
              ).start.subtract(const Duration(days: 1)),
            ),
            ctrl,
          ),
          AppSearchField(
            width: 220,
            hint: 'Buscar productor o código…',
            initialValue: ctrl.searchQuery,
            onChanged: ctrl.setSearchQuery,
          ),
          if (_view == _ReceptionView.registros) ...<Widget>[
            SizedBox(
              width: 170,
              child: AppSelect<String>(
                dense: true,
                value: ctrl.shiftFilter,
                prefixIcon: Icons.schedule_rounded,
                options: const <AppSelectOption<String>>[
                  AppSelectOption<String>(
                    value: 'ALL',
                    label: 'Todas las jornadas',
                  ),
                  AppSelectOption<String>(
                    value: AppConstants.shiftMorning,
                    label: 'Mañana',
                  ),
                  AppSelectOption<String>(
                    value: AppConstants.shiftAfternoon,
                    label: 'Tarde',
                  ),
                ],
                onChanged: ctrl.setShiftFilter,
              ),
            ),
            SizedBox(
              width: 170,
              child: AppSelect<String>(
                dense: true,
                value: ctrl.statusFilter,
                prefixIcon: Icons.filter_list_rounded,
                options: const <AppSelectOption<String>>[
                  AppSelectOption<String>(
                    value: 'ACTIVE',
                    label: 'Solo activas',
                  ),
                  AppSelectOption<String>(
                    value: 'PENDING',
                    label: 'Pendientes',
                  ),
                  AppSelectOption<String>(value: 'ANNULLED', label: 'Anuladas'),
                  AppSelectOption<String>(value: 'ALL', label: 'Todas'),
                ],
                onChanged: ctrl.setStatusFilter,
              ),
            ),
          ],
        ],
      ),
    );

    Widget content;
    if (ctrl.isLoading &&
        ctrl.activeProducers.isEmpty &&
        ctrl.rangeReceptions.isEmpty) {
      content = const Center(
        child: DairyLoader(
          size: DairyLoaderSize.lg,
          label: 'Cargando entregas…',
          hint: 'Un momento por favor.',
        ),
      );
    } else if (_view == _ReceptionView.planilla) {
      final String q = ctrl.searchQuery.trim().toLowerCase();
      final PlanillaMatrix visible = q.isEmpty
          ? matrix
          : PlanillaMatrix(
              days: matrix.days,
              rows: matrix.rows
                  .where(
                    (PlanillaRow r) =>
                        r.codigo.toLowerCase().contains(q) ||
                        r.nombre.toLowerCase().contains(q),
                  )
                  .toList(),
            );
      content = visible.rows.isEmpty
          ? EmptyState(
              icon: Icons.grid_off_rounded,
              title: q.isEmpty
                  ? 'No hay productores activos'
                  : 'Sin coincidencias',
              message: q.isEmpty
                  ? 'Registra productores activos para capturar entregas en la planilla.'
                  : 'Ningún productor coincide con «${ctrl.searchQuery}».',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _legend(canCreate || canEdit),
                const Divider(height: 1),
                Expanded(
                  child: ReceptionSpreadsheet(
                    key: ValueKey<String>(
                      'planilla-${ctrl.range.startIso}-${ctrl.range.endIso}',
                    ),
                    matrix: visible,
                    canCreate: canCreate,
                    canEdit: canEdit,
                    canAnnul: canAnnul,
                    isCorrected: ctrl.isCorrected,
                    onCreate: _createCell,
                    onEdit: _editCell,
                    onAnnul: _annulCell,
                  ),
                ),
              ],
            );
    } else {
      content = ReceptionRecordsTable(
        items: ctrl.filteredReceptions,
        canEdit: canEdit,
        canAnnul: canAnnul,
        isCorrected: ctrl.isCorrected,
        operatorName: _operatorName,
        onEdit: _editCell,
        onAnnul: _annulCell,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          toolbar,
          SizedBox(
            height: 2,
            child: ctrl.isLoading
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          const Divider(height: 1),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _rangeShortcut(
    String label,
    DateRangeValue value,
    ReceptionController ctrl,
  ) {
    final bool active = ctrl.range == value;
    return TextButton(
      onPressed: active ? null : () => ctrl.setDateRange(value),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        disabledForegroundColor: AppTheme.brand,
        backgroundColor: active ? AppTheme.brandSoft : null,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _legend(bool editable) {
    final TextStyle s = AppTheme.bodyStyle(
      fontSize: 11.5,
      color: AppTheme.textMuted,
    );
    Widget item(Widget icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        icon,
        const SizedBox(width: 5),
        Text(text, style: s),
      ],
    );
    return Container(
      color: AppTheme.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (editable) ...<Widget>[
            item(const KeyCap('Enter'), 'editar / guardar'),
            item(const KeyCap('↑↓←→'), 'mover'),
            item(const KeyCap('Tab'), 'siguiente'),
            item(const KeyCap('Esc'), 'cancelar'),
            item(const KeyCap('Supr'), 'anular'),
          ] else
            Text(
              'Solo lectura: no tienes permiso para registrar o corregir.',
              style: s,
            ),
          item(
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
              ),
            ),
            'pendiente',
          ),
          item(
            const Icon(
              Icons.change_history_rounded,
              size: 10,
              color: AppTheme.info,
            ),
            'corregida',
          ),
          item(
            const Icon(Icons.lock_rounded, size: 10, color: AppTheme.textMuted),
            'liquidada',
          ),
          item(
            const Icon(Icons.error_rounded, size: 10, color: AppTheme.danger),
            'error',
          ),
        ],
      ),
    );
  }
}
