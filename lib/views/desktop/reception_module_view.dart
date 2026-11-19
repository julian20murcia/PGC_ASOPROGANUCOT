import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/reception_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';

/// Módulo administrativo de captura rápida de leche cruda en planta y consulta auditada.
class ReceptionModuleView extends StatefulWidget {
  const ReceptionModuleView({super.key});

  @override
  State<ReceptionModuleView> createState() => _ReceptionModuleViewState();
}

class _ReceptionModuleViewState extends State<ReceptionModuleView> {
  final TextEditingController _producerInputCtrl = TextEditingController();
  final TextEditingController _litersCtrl = TextEditingController();
  final TextEditingController _searchTableCtrl = TextEditingController();

  final FocusNode _producerFocus = FocusNode();
  final FocusNode _litersFocus = FocusNode();

  String _producerInputQuery = '';
  bool _syncedConnectivityOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final UserController userCtrl = context.read<UserController>();
      context.read<ReceptionController>().loadReceptions(
        isOnlineOverride: userCtrl.isOnline,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isOnline = context.watch<UserController>().isOnline;
    if (!_syncedConnectivityOnce) {
      _syncedConnectivityOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ReceptionController>().setOnlineStatus(isOnline);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ReceptionController>().setOnlineStatus(isOnline);
        }
      });
    }
  }

  @override
  void dispose() {
    _producerInputCtrl.dispose();
    _litersCtrl.dispose();
    _searchTableCtrl.dispose();
    _producerFocus.dispose();
    _litersFocus.dispose();
    super.dispose();
  }

  void _pickProducer(ProducerModel producer) {
    final ReceptionController ctrl = context.read<ReceptionController>();
    ctrl.selectProducer(producer);
    setState(() {
      _producerInputQuery = '';
      _producerInputCtrl.text =
          '${producer.codigoAsociado} · ${producer.nombreCompleto}';
    });
    _litersFocus.requestFocus();
  }

  void _clearSelectedProducer() {
    context.read<ReceptionController>().selectProducer(null);
    _producerInputCtrl.clear();
    setState(() => _producerInputQuery = '');
    _producerFocus.requestFocus();
  }

  void _onProducerInputSubmitted(String value) {
    final ReceptionController ctrl = context.read<ReceptionController>();
    final ProducerModel? exact = ctrl.findExactProducer(value);
    if (exact != null) {
      _pickProducer(exact);
      return;
    }
    final List<ProducerModel> matches = ctrl.matchProducersByCodeOrQuery(value);
    if (matches.isNotEmpty) {
      _pickProducer(matches.first);
    }
  }

  Future<void> _submitDelivery({bool allowDuplicate = false}) async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    final AuthController auth = context.read<AuthController>();

    if (ctrl.selectedProducer == null && _producerInputCtrl.text.isNotEmpty) {
      final ProducerModel? match =
          ctrl.findExactProducer(_producerInputCtrl.text) ??
          ctrl.matchProducersByCodeOrQuery(_producerInputCtrl.text).firstOrNull;
      if (match != null) {
        ctrl.selectProducer(match);
      }
    }

    final String rawLiters = _litersCtrl.text.replaceAll(',', '.').trim();
    final double? liters = double.tryParse(rawLiters);
    if (liters == null || liters <= 0) {
      _showToast(
        'Ingresa una cantidad válida de litros mayor a cero.',
        isError: true,
      );
      _litersFocus.requestFocus();
      return;
    }

    final String operarioUid = auth.currentUser?.uid ?? 'operario';
    final result = await ctrl.registerDelivery(
      litros: liters,
      operarioUid: operarioUid,
      allowDuplicate: allowDuplicate,
    );

    if (!mounted) return;

    if (result.duplicateFound != null) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _DuplicateDeliveryDialog(existing: result.duplicateFound!),
      );
      if (confirm == true && mounted) {
        await _submitDelivery(allowDuplicate: true);
      } else if (mounted) {
        _litersFocus.requestFocus();
      }
      return;
    }

    if (result.saved) {
      _producerInputCtrl.clear();
      _litersCtrl.clear();
      setState(() => _producerInputQuery = '');
      _showToast(ctrl.feedbackMessage ?? 'Entrega registrada.');
      _producerFocus.requestFocus();
    } else if (ctrl.errorMessage != null) {
      _showToast(ctrl.errorMessage!, isError: true);
    }
  }

  Future<void> _openEditDialog(MilkReceptionModel reception) async {
    final UserModel actor =
        context.read<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final ReceptionController ctrl = context.read<ReceptionController>();
    ctrl.clearFeedback();

    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuditCorrectionDialog(
        reception: reception,
        actor: actor,
        isAnnulment: false,
      ),
    );
    if (updated == true && mounted) {
      _showToast(ctrl.feedbackMessage ?? 'Entrega corregida.');
    }
  }

  Future<void> _openAnnulDialog(MilkReceptionModel reception) async {
    final UserModel actor =
        context.read<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final ReceptionController ctrl = context.read<ReceptionController>();
    ctrl.clearFeedback();

    final bool? annulled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuditCorrectionDialog(
        reception: reception,
        actor: actor,
        isAnnulment: true,
      ),
    );
    if (annulled == true && mounted) {
      _showToast(ctrl.feedbackMessage ?? 'Entrega anulada.');
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.inkBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = context.watch<ReceptionController>();
    final UserModel currentUser =
        context.watch<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final bool isNarrow = MediaQuery.of(context).size.width < 920;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 24,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(ctrl, isNarrow),
            const SizedBox(height: 16),
            _buildQuickCaptureCard(ctrl, isNarrow),
            const SizedBox(height: 18),
            _buildTableToolbar(ctrl, isNarrow),
            const SizedBox(height: 12),
            if (ctrl.isLoading && ctrl.allReceptions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: DairyLoader(
                    size: DairyLoaderSize.lg,
                    label: 'Cargando entregas…',
                    hint: 'Un momento por favor.',
                  ),
                ),
              )
            else if (ctrl.filteredReceptions.isEmpty)
              _buildEmptyState()
            else
              _buildTableSection(ctrl, currentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ReceptionController ctrl, bool isNarrow) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Recepción de Leche',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
        const SizedBox(height: 4),
        const Text(
          'Registro diario en planta por productor y jornada (mañana y tarde).',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
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
          onPressed: ctrl.isLoading ? null : () => ctrl.loadReceptions(),
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Actualizar'),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isNarrow) ...<Widget>[
          titleBlock,
          const SizedBox(height: 12),
          actions,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              actions,
            ],
          ),
        const SizedBox(height: 16),
        _ReceptionSummaryStrip(ctrl: ctrl, isNarrow: isNarrow),
      ],
    );
  }

  Widget _buildQuickCaptureCard(ReceptionController ctrl, bool isNarrow) {
    final ProducerModel? selected = ctrl.selectedProducer;
    final List<ProducerModel> suggestions = selected == null
        ? ctrl.matchProducersByCodeOrQuery(_producerInputQuery)
        : const <ProducerModel>[];
    final bool hasLiters =
        (double.tryParse(_litersCtrl.text.replaceAll(',', '.').trim()) ?? 0) >
        0;

    final Widget producerField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _StepLabel(
          step: 1,
          label: 'Productor',
          hint: 'código, cédula o nombre',
          done: selected != null,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _producerInputCtrl,
          focusNode: _producerFocus,
          textInputAction: TextInputAction.next,
          onChanged: (String val) {
            if (ctrl.selectedProducer != null) {
              ctrl.selectProducer(null);
            }
            setState(() => _producerInputQuery = val);
          },
          onSubmitted: _onProducerInputSubmitted,
          decoration: InputDecoration(
            hintText: ctrl.activeProducers.isEmpty
                ? 'Primero registra productores activos en el módulo Productores'
                : 'Ej. ASO-001, cédula o nombre y presiona Enter',
            prefixIcon: Icon(
              selected != null
                  ? Icons.check_circle_rounded
                  : Icons.search_rounded,
              size: 18,
              color: selected != null ? AppTheme.primaryGreen : null,
            ),
            suffixIcon: (_producerInputCtrl.text.isNotEmpty || selected != null)
                ? IconButton(
                    tooltip: 'Limpiar selección',
                    onPressed: _clearSelectedProducer,
                    icon: const Icon(Icons.close_rounded, size: 16),
                  )
                : null,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: selected != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _SelectedProducerCard(producer: selected),
                )
              : suggestions.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (int i = 0; i < suggestions.length; i++)
                        _ProducerSuggestionChip(
                          producer: suggestions[i],
                          isEnterTarget:
                              i == 0 && _producerInputQuery.trim().isNotEmpty,
                          onTap: () => _pickProducer(suggestions[i]),
                        ),
                    ],
                  ),
                )
              : _producerInputQuery.trim().isNotEmpty
              ? const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.person_off_outlined,
                        size: 15,
                        color: AppTheme.dangerText,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'No se encontraron productores activos con ese criterio.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.dangerText,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    final Widget shiftSelector = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _StepLabel(step: 2, label: 'Jornada', done: true),
        const SizedBox(height: 6),
        AppSegmentedControl<String>(
          height: 42,
          expand: true,
          selected: ctrl.selectedShift,
          onChanged: ctrl.setSelectedShift,
          segments: const <AppSegment<String>>[
            AppSegment<String>(
              value: AppConstants.shiftMorning,
              label: 'Mañana',
              icon: Icons.wb_sunny_outlined,
            ),
            AppSegment<String>(
              value: AppConstants.shiftAfternoon,
              label: 'Tarde',
              icon: Icons.wb_twilight_rounded,
            ),
          ],
        ),
      ],
    );

    final Widget litersField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _StepLabel(step: 3, label: 'Litros', done: hasLiters),
        const SizedBox(height: 6),
        TextField(
          controller: _litersCtrl,
          focusNode: _litersFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: AppTheme.monoStyle(fontSize: 17, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitDelivery(),
          decoration: InputDecoration(
            hintText: '0.0',
            suffixText: 'L',
            suffixStyle: AppTheme.monoStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
            prefixIcon: const Icon(Icons.water_drop_outlined, size: 18),
          ),
        ),
      ],
    );

    final Widget submitButton = PrimaryActionButton(
      label: 'Registrar entrega',
      icon: Icons.check_rounded,
      fullWidth: isNarrow,
      isMobile: isNarrow,
      isLoading: ctrl.isSaving,
      onPressed: () => _submitDelivery(),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D0C3B24),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[AppTheme.primaryGreenLight, AppTheme.surface],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border(bottom: BorderSide(color: AppTheme.dividerLight)),
            ),
            child: Row(
              children: <Widget>[
                const AppIconBadge(icon: Icons.bolt_rounded, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Captura rápida en planta',
                        style: AppTheme.subtitleStyle(),
                      ),
                      const Text(
                        'Productor → jornada → litros',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isNarrow)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      KeyCap('Enter'),
                      SizedBox(width: 6),
                      Text(
                        'avanzar y guardar',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      producerField,
                      const SizedBox(height: 14),
                      shiftSelector,
                      const SizedBox(height: 14),
                      litersField,
                      const SizedBox(height: 16),
                      submitButton,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 5, child: producerField),
                      const SizedBox(width: 14),
                      Expanded(flex: 3, child: shiftSelector),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: litersField),
                      const SizedBox(width: 14),
                      Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: submitButton,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableToolbar(ReceptionController ctrl, bool isNarrow) {
    final Widget periodChips = AppSegmentedControl<ReceptionDateFilterMode>(
      selected: ctrl.dateFilterMode,
      onChanged: ctrl.setDateFilterMode,
      segments: const <AppSegment<ReceptionDateFilterMode>>[
        AppSegment<ReceptionDateFilterMode>(
          value: ReceptionDateFilterMode.today,
          label: 'Hoy',
          icon: Icons.today_rounded,
        ),
        AppSegment<ReceptionDateFilterMode>(
          value: ReceptionDateFilterMode.quincena,
          label: 'Quincena actual',
        ),
        AppSegment<ReceptionDateFilterMode>(
          value: ReceptionDateFilterMode.all,
          label: 'Todo',
        ),
      ],
    );

    final Widget searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchTableCtrl,
        onChanged: ctrl.setSearchQuery,
        decoration: const InputDecoration(
          hintText: 'Filtrar entregas por productor, código o fecha…',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          prefixIcon: Icon(Icons.search_rounded, size: 17),
        ),
      ),
    );

    final Widget shiftDropdown = SizedBox(
      height: 36,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.shiftFilter,
        prefixIcon: Icons.schedule_rounded,
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'ALL', label: 'Todas las jornadas'),
          AppSelectOption<String>(
            value: AppConstants.shiftMorning,
            label: 'Mañana',
            icon: Icons.wb_sunny_outlined,
          ),
          AppSelectOption<String>(
            value: AppConstants.shiftAfternoon,
            label: 'Tarde',
            icon: Icons.wb_twilight_rounded,
          ),
        ],
        onChanged: ctrl.setShiftFilter,
      ),
    );

    final Widget statusDropdown = SizedBox(
      height: 36,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.statusFilter,
        prefixIcon: Icons.filter_list_rounded,
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(
            value: 'ACTIVE',
            label: 'Solo activas',
            icon: Icons.check_circle_outline_rounded,
          ),
          AppSelectOption<String>(
            value: 'ANNULLED',
            label: 'Anuladas',
            icon: Icons.block_rounded,
          ),
          AppSelectOption<String>(value: 'ALL', label: 'Todas'),
        ],
        onChanged: ctrl.setStatusFilter,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                periodChips,
                const SizedBox(height: 10),
                searchField,
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: shiftDropdown),
                    const SizedBox(width: 8),
                    Expanded(child: statusDropdown),
                  ],
                ),
              ],
            )
          : Row(
              children: <Widget>[
                periodChips,
                const SizedBox(width: 12),
                Expanded(child: searchField),
                const SizedBox(width: 8),
                SizedBox(width: 190, child: shiftDropdown),
                const SizedBox(width: 8),
                SizedBox(width: 172, child: statusDropdown),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIconBadge(
            icon: Icons.water_drop_outlined,
            color: AppTheme.skyBlue,
            size: 48,
          ),
          SizedBox(height: 12),
          Text(
            'Sin entregas registradas en el filtro seleccionado',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Registra una entrega arriba o cambia el filtro de período.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTableSection(ReceptionController ctrl, UserModel currentUser) {
    final List<MilkReceptionModel> rows = ctrl.paginatedReceptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CleanDataTable(
          columns: const <CleanTableColumn>[
            CleanTableColumn(label: 'Fecha y Hora'),
            CleanTableColumn(label: 'Jornada'),
            CleanTableColumn(label: 'Productor'),
            CleanTableColumn(label: 'Litros', numeric: true),
            CleanTableColumn(label: 'Envío'),
            CleanTableColumn(label: 'Estado'),
            CleanTableColumn(label: 'Acciones'),
          ],
          rows: rows.map((MilkReceptionModel r) {
            final bool isMorning = r.jornada == AppConstants.shiftMorning;
            return <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    r.fechaEntrega,
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    r.horaEntrega,
                    style: AppTheme.monoStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              _ShiftBadge(isMorning: isMorning),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    r.nombreProductorSnap,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    r.codigoAsociadoSnap,
                    style: AppTheme.monoStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              Text(
                '${r.litros.toStringAsFixed(1)} L',
                style:
                    AppTheme.monoStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: r.anulado
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                    ).copyWith(
                      decoration: r.anulado ? TextDecoration.lineThrough : null,
                    ),
              ),
              SyncStatusBadge(
                isSynced: r.isSynced,
                syncedLabel: 'Sincronizado',
                pendingLabel: 'Pendiente',
              ),
              _ReceptionStateChip(reception: r),
              if (currentUser.isAdmin && r.canBeModified)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppRowActionButton(
                      tooltip: 'Corregir litros',
                      icon: Icons.edit_outlined,
                      color: AppTheme.skyBlue,
                      onPressed: () => _openEditDialog(r),
                    ),
                    const SizedBox(width: 6),
                    AppRowActionButton(
                      tooltip: 'Anular entrega',
                      icon: Icons.block_rounded,
                      color: AppTheme.danger,
                      onPressed: () => _openAnnulDialog(r),
                    ),
                  ],
                )
              else
                const Text('—', style: TextStyle(color: AppTheme.textMuted)),
            ];
          }).toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            Text(
              'Mostrando ${rows.length} de ${ctrl.filteredReceptions.length} registros',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  onPressed: ctrl.currentPage > 1
                      ? () => ctrl.setPage(ctrl.currentPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    '${ctrl.currentPage} / ${ctrl.totalPages}',
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: ctrl.currentPage < ctrl.totalPages
                      ? () => ctrl.setPage(ctrl.currentPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _ReceptionSummaryStrip extends StatelessWidget {
  const _ReceptionSummaryStrip({required this.ctrl, required this.isNarrow});

  final ReceptionController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      AppMetricTile(
        title: 'Litros recibidos hoy',
        value: '${ctrl.todayTotalLiters.toStringAsFixed(1)} L',
        subtitle:
            'Mañana ${ctrl.todayMorningLiters.toStringAsFixed(1)} L · Tarde ${ctrl.todayAfternoonLiters.toStringAsFixed(1)} L',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppMetricTile(
        title: 'Entregas de hoy',
        value: '${ctrl.todayDeliveriesCount}',
        subtitle: 'Registros activos del día',
        icon: Icons.fact_check_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
        title: 'Acumulado quincenal',
        value: '${ctrl.quincenaTotalLiters.toStringAsFixed(1)} L',
        subtitle: ctrl.currentQuincenaLabel,
        icon: Icons.calendar_today_outlined,
        accentColor: AppTheme.warmGold,
      ),
      AppMetricTile(
        title: 'Estado de envío',
        value: ctrl.pendingSyncCount == 0
            ? 'Al día'
            : '${ctrl.pendingSyncCount} pend.',
        subtitle: ctrl.pendingSyncCount == 0
            ? 'Todo respaldado en la nube'
            : 'Pendiente por subir al reconectar',
        icon: Icons.cloud_done_outlined,
        accentColor: ctrl.pendingSyncCount == 0
            ? AppTheme.tealAccent
            : AppTheme.warningText,
      ),
    ];

    if (isNarrow) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: cards[2]),
              const SizedBox(width: 10),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
        const SizedBox(width: 12),
        Expanded(child: cards[3]),
      ],
    );
  }
}

/// Etiqueta numerada de cada paso de la captura; se vuelve ✓ al completarse.
class _StepLabel extends StatelessWidget {
  const _StepLabel({
    required this.step,
    required this.label,
    this.hint,
    this.done = false,
  });

  final int step;
  final String label;
  final String? hint;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? AppTheme.primaryGreen : AppTheme.surfaceMuted,
              shape: BoxShape.circle,
              border: Border.all(
                color: done ? AppTheme.primaryGreen : AppTheme.inputBorder,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : Text(
                    '$step',
                    style: AppTheme.monoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '· $hint',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _initials(String name) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((String p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

/// Ficha del productor seleccionado en la captura.
class _SelectedProducerCard extends StatelessWidget {
  const _SelectedProducerCard({required this.producer});

  final ProducerModel producer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppTheme.primaryGreen.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(producer.nombreCompleto),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  producer.nombreCompleto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.successText,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${producer.codigoAsociado} · Finca ${producer.nombreFinca} · ${producer.vereda}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sugerencia de productor; la primera se marca como destino de `Enter`.
class _ProducerSuggestionChip extends StatefulWidget {
  const _ProducerSuggestionChip({
    required this.producer,
    required this.onTap,
    this.isEnterTarget = false,
  });

  final ProducerModel producer;
  final VoidCallback onTap;
  final bool isEnterTarget;

  @override
  State<_ProducerSuggestionChip> createState() =>
      _ProducerSuggestionChipState();
}

class _ProducerSuggestionChipState extends State<_ProducerSuggestionChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _hover || widget.isEnterTarget;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            color: active ? AppTheme.primaryGreenLight : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(
              color: active
                  ? AppTheme.primaryGreen.withValues(alpha: 0.45)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? AppTheme.primaryGreen : AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  widget.producer.codigoAsociado,
                  style: AppTheme.monoStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                widget.producer.nombreCompleto,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (widget.isEnterTarget) ...<Widget>[
                const SizedBox(width: 6),
                const Icon(
                  Icons.keyboard_return_rounded,
                  size: 13,
                  color: AppTheme.primaryGreen,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  const _ShiftBadge({required this.isMorning});

  final bool isMorning;

  @override
  Widget build(BuildContext context) {
    final Color fg = isMorning ? AppTheme.warningText : AppTheme.indigoAccent;
    final Color bg = isMorning ? AppTheme.warningBg : AppTheme.indigoLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isMorning ? Icons.wb_sunny_outlined : Icons.wb_twilight_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            isMorning ? 'Mañana' : 'Tarde',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceptionStateChip extends StatelessWidget {
  const _ReceptionStateChip({required this.reception});

  final MilkReceptionModel reception;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;

    if (reception.anulado) {
      bg = AppTheme.dangerBg;
      fg = AppTheme.dangerText;
      label = 'Anulada';
    } else if (reception.isLiquidada) {
      bg = AppTheme.surfaceMuted;
      fg = AppTheme.textPrimary;
      label = 'Liquidada';
    } else {
      bg = AppTheme.primaryGreenLight;
      fg = AppTheme.successText;
      label = 'Activa';
    }

    return Tooltip(
      message: reception.anulado && reception.motivoAnulacion != null
          ? 'Motivo: ${reception.motivoAnulacion}'
          : '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _DuplicateDeliveryDialog extends StatelessWidget {
  const _DuplicateDeliveryDialog({required this.existing});

  final MilkReceptionModel existing;

  @override
  Widget build(BuildContext context) {
    final String shiftName = existing.jornada == AppConstants.shiftMorning
        ? 'Mañana'
        : 'Tarde';

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AppDialogHeader(
                icon: Icons.content_copy_rounded,
                color: AppTheme.warning,
                title: 'Posible entrega duplicada',
                subtitle: 'Este productor ya entregó hoy en la misma jornada.',
              ),
              const SizedBox(height: 16),
              AppInfoPanel(
                color: AppTheme.warningBg.withValues(alpha: 0.45),
                borderColor: AppTheme.warning.withValues(alpha: 0.25),
                children: <Widget>[
                  AppInfoRow(
                    label: 'Productor',
                    value: existing.nombreProductorSnap,
                  ),
                  AppInfoRow(
                    label: 'Fecha',
                    value: existing.fechaEntrega,
                    mono: true,
                  ),
                  AppInfoRow(label: 'Jornada', value: shiftName),
                  AppInfoRow(
                    label: 'Hora',
                    value: existing.horaEntrega,
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Litros registrados',
                    value: '${existing.litros.toStringAsFixed(1)} L',
                    mono: true,
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '¿Deseas confirmar el registro de esta entrega adicional en la misma jornada?',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warning,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Confirmar y guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditCorrectionDialog extends StatefulWidget {
  const _AuditCorrectionDialog({
    required this.reception,
    required this.actor,
    required this.isAnnulment,
  });

  final MilkReceptionModel reception;
  final UserModel actor;
  final bool isAnnulment;

  @override
  State<_AuditCorrectionDialog> createState() => _AuditCorrectionDialogState();
}

class _AuditCorrectionDialogState extends State<_AuditCorrectionDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _litersCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _litersCtrl = TextEditingController(
      text: widget.reception.litros.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _litersCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ReceptionController ctrl = context.read<ReceptionController>();
    late final bool ok;
    if (widget.isAnnulment) {
      ok = await ctrl.annulDelivery(
        existing: widget.reception,
        motivo: _reasonCtrl.text,
        actor: widget.actor,
      );
    } else {
      final double parsed = double.parse(
        _litersCtrl.text.replaceAll(',', '.').trim(),
      );
      ok = await ctrl.editDeliveryLitros(
        existing: widget.reception,
        nuevosLitros: parsed,
        motivo: _reasonCtrl.text,
        actor: widget.actor,
      );
    }

    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = context.watch<ReceptionController>();
    final MilkReceptionModel r = widget.reception;
    final bool annul = widget.isAnnulment;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppDialogHeader(
                  icon: annul ? Icons.block_rounded : Icons.edit_outlined,
                  color: annul ? AppTheme.danger : AppTheme.skyBlue,
                  title: annul ? 'Anular entrega' : 'Corregir litros',
                  subtitle: '${r.nombreProductorSnap} · ${r.fechaEntrega}',
                  onClose: ctrl.isSaving
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
                const SizedBox(height: 16),
                AppInfoPanel(
                  children: <Widget>[
                    AppInfoRow(
                      label: 'Código',
                      value: r.codigoAsociadoSnap,
                      mono: true,
                    ),
                    AppInfoRow(
                      label: 'Jornada',
                      value: r.jornada == AppConstants.shiftMorning
                          ? 'Mañana · ${r.horaEntrega}'
                          : 'Tarde · ${r.horaEntrega}',
                    ),
                    AppInfoRow(
                      label: 'Litros actuales',
                      value: '${r.litros.toStringAsFixed(1)} L',
                      mono: true,
                      emphasize: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (ctrl.errorMessage != null) ...<Widget>[
                  AppInlineNotice.danger(message: ctrl.errorMessage!),
                  const SizedBox(height: 12),
                ],
                if (annul) ...<Widget>[
                  const AppInlineNotice(
                    icon: Icons.warning_amber_rounded,
                    message:
                        'La entrega dejará de contar en liquidaciones. La acción '
                        'queda registrada en la bitácora de auditoría.',
                  ),
                  const SizedBox(height: 14),
                ] else ...<Widget>[
                  const Text(
                    'Nueva cantidad de litros',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _litersCtrl,
                    enabled: !ctrl.isSaving,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: AppTheme.monoStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      suffixText: 'L',
                      prefixIcon: Icon(Icons.water_drop_outlined, size: 18),
                    ),
                    validator: (String? v) {
                      final double? val = double.tryParse(
                        (v ?? '').replaceAll(',', '.').trim(),
                      );
                      if (val == null || val <= 0) {
                        return 'Ingresa una cantidad mayor a cero.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                const Text(
                  'Motivo de la modificación (auditoría obligatoria)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _reasonCtrl,
                  enabled: !ctrl.isSaving,
                  autofocus: annul,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Error de digitación al pesar cantina #2.',
                  ),
                  validator: (String? v) => (v == null || v.trim().length < 5)
                      ? 'Indica el motivo (mínimo 5 caracteres).'
                      : null,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: ctrl.isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    PrimaryActionButton(
                      label: annul
                          ? 'Confirmar anulación'
                          : 'Guardar corrección',
                      icon: annul ? Icons.block_rounded : Icons.check_rounded,
                      color: annul ? AppTheme.danger : AppTheme.primaryGreen,
                      fullWidth: false,
                      isLoading: ctrl.isSaving,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
