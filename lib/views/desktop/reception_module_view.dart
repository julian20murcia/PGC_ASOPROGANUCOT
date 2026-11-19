import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/reception_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/voice_service.dart';
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
    VoiceService.instance.speak(producer.nombreCompleto);
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
    final String? spokenName = ctrl.selectedProducer?.nombreCompleto;
    final bool spokenMorning = ctrl.selectedShift == AppConstants.shiftMorning;
    final result = await ctrl.registerDelivery(
      litros: liters,
      operarioUid: operarioUid,
      allowDuplicate: allowDuplicate,
    );

    if (!mounted) return;

    if (result.duplicateFound != null) {
      VoiceService.instance.speak(
        'Atención: posible entrega duplicada de '
        '${result.duplicateFound!.nombreProductorSnap}',
      );
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
      if (spokenName != null) {
        VoiceService.instance.speak(
          'Registrado: ${VoiceService.spokenLiters(liters)} litros, '
          '$spokenName, jornada ${spokenMorning ? 'mañana' : 'tarde'}',
        );
      }
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

  Future<void> _openMatrixCellDialog({
    required ProducerModel producer,
    required DateTime day,
  }) async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    ctrl.clearFeedback();
    final String dateStr = ReceptionController.formatDate(day);

    final String? toastMessage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MatrixCellDialog(
        producer: producer,
        day: day,
        dateStr: dateStr,
      ),
    );
    if (toastMessage != null && toastMessage.isNotEmpty && mounted) {
      _showToast(toastMessage);
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
            else if (ctrl.viewMode == ReceptionViewMode.matrix)
              if (ctrl.matrixRows.isEmpty)
                _buildEmptyMatrixState(ctrl)
              else
                _ReceptionPlanillaMatrix(
                  ctrl: ctrl,
                  isNarrow: isNarrow,
                  onCellTap: (ProducerModel producer, DateTime day) =>
                      _openMatrixCellDialog(producer: producer, day: day),
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
                if (!isNarrow) ...<Widget>[
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
                  const SizedBox(width: 12),
                ],
                const _VoiceToggle(),
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
    final bool isMatrix = ctrl.viewMode == ReceptionViewMode.matrix;

    final Widget viewSwitch = AppSegmentedControl<ReceptionViewMode>(
      selected: ctrl.viewMode,
      onChanged: ctrl.setViewMode,
      segments: const <AppSegment<ReceptionViewMode>>[
        AppSegment<ReceptionViewMode>(
          value: ReceptionViewMode.matrix,
          label: 'Planilla por días',
          icon: Icons.grid_on_rounded,
        ),
        AppSegment<ReceptionViewMode>(
          value: ReceptionViewMode.list,
          label: 'Lista detallada',
          icon: Icons.view_list_rounded,
        ),
      ],
    );

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
        decoration: InputDecoration(
          hintText: isMatrix
              ? 'Filtrar productor, código, finca o vereda…'
              : 'Filtrar entregas por productor, código o fecha…',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 17),
          suffixIcon: ctrl.searchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar filtro',
                  onPressed: () {
                    _searchTableCtrl.clear();
                    ctrl.setSearchQuery('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 15),
                )
              : null,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              viewSwitch,
              if (isMatrix) _QuincenaNavigator(ctrl: ctrl) else periodChips,
            ],
          ),
          const SizedBox(height: 10),
          if (isNarrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                searchField,
                const SizedBox(height: 8),
                if (isMatrix)
                  shiftDropdown
                else
                  Row(
                    children: <Widget>[
                      Expanded(child: shiftDropdown),
                      const SizedBox(width: 8),
                      Expanded(child: statusDropdown),
                    ],
                  ),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(child: searchField),
                const SizedBox(width: 8),
                SizedBox(width: 192, child: shiftDropdown),
                if (!isMatrix) ...<Widget>[
                  const SizedBox(width: 8),
                  SizedBox(width: 172, child: statusDropdown),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyMatrixState(ReceptionController ctrl) {
    final bool hasSearch = ctrl.searchQuery.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppIconBadge(
            icon: Icons.calendar_view_month_outlined,
            color: AppTheme.primaryGreen,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch
                ? 'Ningún productor coincide con la búsqueda en esta quincena'
                : 'No hay productores activos para mostrar en la planilla',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            hasSearch
                ? 'Limpia o ajusta el filtro de búsqueda para ver toda la planilla.'
                : 'Registra productores activos en el módulo Productores para iniciar la planilla diaria.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
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

/// Interruptor para activar o silenciar la lectura en voz alta del productor.
class _VoiceToggle extends StatelessWidget {
  const _VoiceToggle();

  @override
  Widget build(BuildContext context) {
    final VoiceService voice = VoiceService.instance;
    return ListenableBuilder(
      listenable: voice,
      builder: (BuildContext context, _) {
        final bool on = voice.enabled;
        return Tooltip(
          message: on
              ? 'Lectura en voz alta activada: dice el nombre del productor. Clic para silenciar.'
              : 'Lectura en voz alta silenciada. Clic para activar.',
          child: Material(
            color: on ? AppTheme.primaryGreenLight : AppTheme.surfaceMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              side: BorderSide(
                color: on
                    ? AppTheme.primaryGreen.withValues(alpha: 0.35)
                    : AppTheme.border,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              onTap: () {
                voice.toggle();
                if (voice.enabled) voice.speak('Lectura en voz alta activada');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      on
                          ? Icons.record_voice_over_rounded
                          : Icons.voice_over_off_rounded,
                      size: 16,
                      color: on ? AppTheme.primaryGreen : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      on ? 'Voz' : 'Silencio',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: on ? AppTheme.successText : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatCompactLiters(double value) {
  if ((value - value.roundToDouble()).abs() < 0.005) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

const List<String> _weekdayShortNames = <String>[
  'Lun',
  'Mar',
  'Mié',
  'Jue',
  'Vie',
  'Sáb',
  'Dom',
];

const List<String> _weekdayFullNames = <String>[
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

String _formatMatrixPrettyDate(DateTime day) {
  final String weekday = _weekdayFullNames[(day.weekday - 1).clamp(0, 6)];
  final String month = ReceptionController.shortMonthName(day.month);
  return '$weekday ${day.day} de $month ${day.year}';
}

/// Navegador de quincenas (anterior / actual / siguiente) para la planilla estilo EvolMilk.
class _QuincenaNavigator extends StatelessWidget {
  const _QuincenaNavigator({required this.ctrl});

  final ReceptionController ctrl;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl + 2),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Quincena anterior',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: ctrl.previousMatrixQuincena,
                icon: const Icon(Icons.chevron_left_rounded, size: 19),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.date_range_rounded,
                      size: 14,
                      color: AppTheme.primaryGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ctrl.matrixQuincenaLabel,
                      style: AppTheme.monoStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Quincena siguiente',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed:
                    ctrl.canGoNextMatrixQuincena ? ctrl.nextMatrixQuincena : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 19),
              ),
            ],
          ),
        ),
        if (!ctrl.isCurrentMatrixQuincena)
          SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: ctrl.goToCurrentMatrixQuincena,
              icon: const Icon(Icons.today_rounded, size: 15),
              label: const Text('Hoy'),
            ),
          ),
      ],
    );
  }
}

/// Tabla matriz estilo EvolMilk Web: productores en filas, días de la quincena en columnas y totales fijos.
class _ReceptionPlanillaMatrix extends StatefulWidget {
  const _ReceptionPlanillaMatrix({
    required this.ctrl,
    required this.isNarrow,
    required this.onCellTap,
  });

  final ReceptionController ctrl;
  final bool isNarrow;
  final void Function(ProducerModel producer, DateTime day) onCellTap;

  @override
  State<_ReceptionPlanillaMatrix> createState() =>
      _ReceptionPlanillaMatrixState();
}

class _ReceptionPlanillaMatrixState extends State<_ReceptionPlanillaMatrix> {
  static const double _headerHeight = 52.0;
  static const double _rowHeight = 54.0;
  static const double _footerHeight = 46.0;
  static const double _dayColWidth = 70.0;

  final ScrollController _hScrollCtrl = ScrollController();
  String? _hoveredProducerId;
  bool _scrolledToTodayOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTodayIfNeeded());
  }

  void _scrollToTodayIfNeeded() {
    if (!mounted || _scrolledToTodayOnce || !_hScrollCtrl.hasClients) return;
    _scrolledToTodayOnce = true;
    final String todayStr = ReceptionController.formatDate(DateTime.now());
    final int idx = widget.ctrl.matrixDays.indexWhere(
      (DateTime d) => ReceptionController.formatDate(d) == todayStr,
    );
    if (idx > 6) {
      final double maxScroll = _hScrollCtrl.position.maxScrollExtent;
      final double target = ((idx - 5) * _dayColWidth).clamp(0.0, maxScroll);
      if (target > 0) {
        _hScrollCtrl.jumpTo(target);
      }
    }
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = widget.ctrl;
    final List<ReceptionMatrixRow> rows = ctrl.paginatedMatrixRows;
    final List<DateTime> days = ctrl.matrixDays;
    final Map<String, double> dayTotals = ctrl.matrixDayTotals;
    final String todayStr = ReceptionController.formatDate(DateTime.now());
    final double leftWidth = widget.isNarrow ? 176.0 : 236.0;
    final double rightWidth = widget.isNarrow ? 92.0 : 108.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildBanner(ctrl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: leftWidth,
                    child: _buildLeftColumn(rows, ctrl),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _hScrollCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _hScrollCtrl,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: days.length * _dayColWidth,
                          child: _buildCenterColumns(
                            ctrl: ctrl,
                            rows: rows,
                            days: days,
                            dayTotals: dayTotals,
                            todayStr: todayStr,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: rightWidth,
                    child: _buildRightColumn(rows, ctrl),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildFooterPagination(ctrl, rows),
      ],
    );
  }

  Widget _buildBanner(ReceptionController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceMuted,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const AppIconBadge(
                icon: Icons.calendar_view_month_rounded,
                size: 28,
                color: AppTheme.primaryGreen,
              ),
              Text(
                ctrl.matrixRangeLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Text(
                '· Clic en cualquier celda para registrar o editar',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _MatrixLegendItem(
                badgeText: 'M',
                fg: AppTheme.warningText,
                bg: AppTheme.warningBg,
                label: 'Mañana',
              ),
              _MatrixLegendItem(
                badgeText: 'T',
                fg: AppTheme.indigoAccent,
                bg: AppTheme.indigoLight,
                label: 'Tarde',
              ),
              _MatrixLegendItem(
                dotColor: AppTheme.warning,
                label: 'Pendiente',
              ),
              _MatrixLegendItem(
                icon: Icons.lock_rounded,
                fg: AppTheme.textSecondary,
                label: 'Liquidada',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeftColumn(
    List<ReceptionMatrixRow> rows,
    ReceptionController ctrl,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border, width: 1.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: AppTheme.canvasAlt,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: const Text(
              'PRODUCTOR',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          for (final ReceptionMatrixRow row in rows)
            MouseRegion(
              onEnter: (_) =>
                  setState(() => _hoveredProducerId = row.producer.productorId),
              onExit: (_) {
                if (_hoveredProducerId == row.producer.productorId) {
                  setState(() => _hoveredProducerId = null);
                }
              },
              child: Container(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _hoveredProducerId == row.producer.productorId
                      ? AppTheme.canvasAlt
                      : AppTheme.surface,
                  border: const Border(
                    bottom: BorderSide(color: AppTheme.dividerLight),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: row.producer.isActivo
                                ? AppTheme.primaryGreenLight
                                : AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            row.producer.codigoAsociado,
                            style: AppTheme.monoStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: row.producer.isActivo
                                  ? AppTheme.successText
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            row.producer.nombreCompleto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.producer.isActivo
                          ? '${row.producer.nombreFinca} · ${row.producer.vereda}'
                          : 'Inactivo · ${row.producer.nombreFinca}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            height: _footerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: AppTheme.canvasAlt,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'TOTAL PLANTA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${ctrl.matrixTotalDeliveries} ent.',
                  style: AppTheme.monoStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterColumns({
    required ReceptionController ctrl,
    required List<ReceptionMatrixRow> rows,
    required List<DateTime> days,
    required Map<String, double> dayTotals,
    required String todayStr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: days.map((DateTime day) {
            final String dateStr = ReceptionController.formatDate(day);
            final bool isToday = dateStr == todayStr;
            final bool isSunday = day.weekday == DateTime.sunday;
            final String dayShort =
                _weekdayShortNames[(day.weekday - 1).clamp(0, 6)];

            return Container(
              width: _dayColWidth,
              height: _headerHeight,
              decoration: BoxDecoration(
                color: isToday
                    ? AppTheme.primaryGreenLight
                    : (isSunday ? AppTheme.surfaceMuted : AppTheme.canvasAlt),
                border: Border(
                  right: const BorderSide(color: AppTheme.dividerLight),
                  bottom: BorderSide(
                    color: isToday ? AppTheme.primaryGreen : AppTheme.border,
                    width: isToday ? 2.2 : 1.0,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    dayShort,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                      color: isToday
                          ? AppTheme.primaryGreen
                          : (isSunday
                                ? AppTheme.textMuted
                                : AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    day.day.toString().padLeft(2, '0'),
                    style: AppTheme.monoStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday
                          ? AppTheme.primaryGreen
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        for (final ReceptionMatrixRow row in rows)
          MouseRegion(
            onEnter: (_) =>
                setState(() => _hoveredProducerId = row.producer.productorId),
            onExit: (_) {
              if (_hoveredProducerId == row.producer.productorId) {
                setState(() => _hoveredProducerId = null);
              }
            },
            child: Row(
              children: days.map((DateTime day) {
                final String dateStr = ReceptionController.formatDate(day);
                final bool isToday = dateStr == todayStr;
                final bool isFuture = dateStr.compareTo(todayStr) > 0;
                final double liters = row.litersForDate(dateStr);
                final double morning = row.morningLitersForDate(dateStr);
                final double afternoon = row.afternoonLitersForDate(dateStr);
                final bool hasEntries = row.entriesForDate(dateStr).isNotEmpty;
                final bool rowHovered =
                    _hoveredProducerId == row.producer.productorId;

                return _MatrixDayCell(
                  width: _dayColWidth,
                  height: _rowHeight,
                  isToday: isToday,
                  isFuture: isFuture,
                  isInactiveEmpty: !row.producer.isActivo && !hasEntries,
                  isRowHovered: rowHovered,
                  liters: liters,
                  morningLiters: morning,
                  afternoonLiters: afternoon,
                  hasAnnulledOnly: liters <= 0 && hasEntries,
                  hasPendingSync: row.hasPendingSyncForDate(dateStr),
                  hasLiquidated: row.hasLiquidatedForDate(dateStr),
                  hasEdited: row.hasEditedForDate(dateStr),
                  showShiftBreakdown: ctrl.shiftFilter == 'ALL',
                  onTap: (isFuture || (!row.producer.isActivo && !hasEntries))
                      ? null
                      : () => widget.onCellTap(row.producer, day),
                );
              }).toList(),
            ),
          ),
        Row(
          children: days.map((DateTime day) {
            final String dateStr = ReceptionController.formatDate(day);
            final bool isToday = dateStr == todayStr;
            final double total = dayTotals[dateStr] ?? 0.0;
            return Container(
              width: _dayColWidth,
              height: _footerHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday
                    ? AppTheme.primaryGreenLight.withValues(alpha: 0.7)
                    : AppTheme.canvasAlt,
                border: const Border(
                  right: BorderSide(color: AppTheme.dividerLight),
                  top: BorderSide(color: AppTheme.border),
                ),
              ),
              child: Text(
                total > 0 ? _formatCompactLiters(total) : '0',
                style: AppTheme.monoStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: total > 0 ? AppTheme.primaryGreen : AppTheme.textMuted,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRightColumn(
    List<ReceptionMatrixRow> rows,
    ReceptionController ctrl,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border, width: 1.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerRight,
            decoration: const BoxDecoration(
              color: AppTheme.canvasAlt,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: const Text(
              'TOTAL (L)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          for (final ReceptionMatrixRow row in rows)
            MouseRegion(
              onEnter: (_) =>
                  setState(() => _hoveredProducerId = row.producer.productorId),
              onExit: (_) {
                if (_hoveredProducerId == row.producer.productorId) {
                  setState(() => _hoveredProducerId = null);
                }
              },
              child: Container(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: _hoveredProducerId == row.producer.productorId
                      ? AppTheme.canvasAlt
                      : AppTheme.surface,
                  border: const Border(
                    bottom: BorderSide(color: AppTheme.dividerLight),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${row.totalLiters.toStringAsFixed(1)} L',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: row.totalLiters > 0
                            ? AppTheme.primaryGreen
                            : AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      '${row.deliveryCount} ent.',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            height: _footerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerRight,
            decoration: const BoxDecoration(
              color: AppTheme.primaryGreenLight,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${ctrl.matrixGrandTotal.toStringAsFixed(1)} L',
                style: AppTheme.monoStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterPagination(
    ReceptionController ctrl,
    List<ReceptionMatrixRow> rows,
  ) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        Text(
          'Mostrando ${rows.length} de ${ctrl.matrixRows.length} productores en ${ctrl.matrixQuincenaLabel}',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        if (ctrl.matrixTotalPages > 1)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: ctrl.matrixPage > 1
                    ? () => ctrl.setMatrixPage(ctrl.matrixPage - 1)
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
                  '${ctrl.matrixPage} / ${ctrl.matrixTotalPages}',
                  style: AppTheme.monoStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: ctrl.matrixPage < ctrl.matrixTotalPages
                    ? () => ctrl.setMatrixPage(ctrl.matrixPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
      ],
    );
  }
}

class _MatrixLegendItem extends StatelessWidget {
  const _MatrixLegendItem({
    this.badgeText,
    this.dotColor,
    this.icon,
    this.fg = AppTheme.textSecondary,
    this.bg = AppTheme.surface,
    required this.label,
  });

  final String? badgeText;
  final Color? dotColor;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (badgeText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeText!,
              style: AppTheme.monoStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          )
        else if (dotColor != null)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          )
        else if (icon != null)
          Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _MatrixDayCell extends StatefulWidget {
  const _MatrixDayCell({
    required this.width,
    required this.height,
    required this.isToday,
    required this.isFuture,
    required this.isInactiveEmpty,
    required this.isRowHovered,
    required this.liters,
    required this.morningLiters,
    required this.afternoonLiters,
    required this.hasAnnulledOnly,
    required this.hasPendingSync,
    required this.hasLiquidated,
    required this.hasEdited,
    required this.showShiftBreakdown,
    required this.onTap,
  });

  final double width;
  final double height;
  final bool isToday;
  final bool isFuture;
  final bool isInactiveEmpty;
  final bool isRowHovered;
  final double liters;
  final double morningLiters;
  final double afternoonLiters;
  final bool hasAnnulledOnly;
  final bool hasPendingSync;
  final bool hasLiquidated;
  final bool hasEdited;
  final bool showShiftBreakdown;
  final VoidCallback? onTap;

  @override
  State<_MatrixDayCell> createState() => _MatrixDayCellState();
}

class _MatrixDayCellState extends State<_MatrixDayCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool hasValue = widget.liters > 0;
    final bool interactive = widget.onTap != null;
    final Color baseBg = widget.isFuture || widget.isInactiveEmpty
        ? AppTheme.canvasAlt.withValues(alpha: 0.7)
        : widget.isToday
        ? AppTheme.primaryGreenLight.withValues(alpha: 0.28)
        : (widget.isRowHovered ? AppTheme.canvasAlt : AppTheme.surface);
    final Color hoverBg = hasValue
        ? AppTheme.primaryGreenLight.withValues(alpha: 0.65)
        : AppTheme.primaryGreenLight.withValues(alpha: 0.35);

    Widget content;
    if (hasValue) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            _formatCompactLiters(widget.liters),
            maxLines: 1,
            style: AppTheme.monoStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: widget.hasLiquidated
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary,
            ),
          ),
          if (widget.showShiftBreakdown) ...<Widget>[
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.morningLiters > 0)
                    Text(
                      widget.afternoonLiters > 0
                          ? 'M${_formatCompactLiters(widget.morningLiters)}'
                          : 'M',
                      style: AppTheme.monoStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warningText,
                      ),
                    ),
                  if (widget.morningLiters > 0 &&
                      widget.afternoonLiters > 0)
                    const Text(
                      '·',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  if (widget.afternoonLiters > 0)
                    Text(
                      widget.morningLiters > 0
                          ? 'T${_formatCompactLiters(widget.afternoonLiters)}'
                          : 'T',
                      style: AppTheme.monoStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.indigoAccent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    } else if (widget.hasAnnulledOnly) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.dangerBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Anul.',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.dangerText,
          ),
        ),
      );
    } else if (interactive && _hover) {
      content = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 15,
          color: AppTheme.primaryGreen,
        ),
      );
    } else {
      content = Text(
        widget.isFuture ? '' : '—',
        style: const TextStyle(fontSize: 12, color: AppTheme.border),
      );
    }

    Widget? cornerIndicator;
    if (widget.hasLiquidated) {
      cornerIndicator = const Icon(
        Icons.lock_rounded,
        size: 10,
        color: AppTheme.textMuted,
      );
    } else if (widget.hasPendingSync) {
      cornerIndicator = Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: AppTheme.warning,
          shape: BoxShape.circle,
        ),
      );
    } else if (widget.hasEdited) {
      cornerIndicator = Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: AppTheme.skyBlue,
          shape: BoxShape.circle,
        ),
      );
    }

    return Tooltip(
      message: widget.isFuture
          ? 'Fecha futura'
          : widget.isInactiveEmpty
          ? 'Productor inactivo'
          : (hasValue
                ? 'Clic para inspeccionar o corregir'
                : 'Clic para registrar entrega'),
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: interactive && _hover ? hoverBg : baseBg,
              border: Border(
                right: const BorderSide(color: AppTheme.dividerLight),
                bottom: const BorderSide(color: AppTheme.dividerLight),
                top: interactive && _hover
                    ? BorderSide(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.55),
                        width: 1.2,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Center(child: content),
                if (cornerIndicator != null)
                  Positioned(top: 2, right: 2, child: cornerIndicator),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo rápido por celda de la planilla: registra entregas nuevas o corrige en línea con auditoría.
class _MatrixCellDialog extends StatefulWidget {
  const _MatrixCellDialog({
    required this.producer,
    required this.day,
    required this.dateStr,
  });

  final ProducerModel producer;
  final DateTime day;
  final String dateStr;

  @override
  State<_MatrixCellDialog> createState() => _MatrixCellDialogState();
}

class _MatrixCellDialogState extends State<_MatrixCellDialog> {
  final GlobalKey<FormState> _createFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  final TextEditingController _newLitersCtrl = TextEditingController();
  final TextEditingController _editLitersCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();

  late String _newShift;
  bool _showAddForm = false;
  String? _editingReceptionId;
  bool _annulMode = false;

  static const List<String> _quickReasons = <String>[
    'Error de digitación',
    'Ajuste de báscula',
    'Verificación de cantina',
  ];

  @override
  void initState() {
    super.initState();
    final ReceptionController ctrl = context.read<ReceptionController>();
    final UserModel user =
        context.read<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final List<MilkReceptionModel> entries = _entriesForCell(ctrl);
    final List<MilkReceptionModel> active = entries
        .where((MilkReceptionModel r) => !r.anulado)
        .toList();

    final bool hasMorning = active.any(
      (MilkReceptionModel r) => r.jornada == AppConstants.shiftMorning,
    );
    final bool hasAfternoon = active.any(
      (MilkReceptionModel r) => r.jornada == AppConstants.shiftAfternoon,
    );
    if (hasMorning && !hasAfternoon) {
      _newShift = AppConstants.shiftAfternoon;
    } else if (hasAfternoon && !hasMorning) {
      _newShift = AppConstants.shiftMorning;
    } else if (ctrl.shiftFilter == AppConstants.shiftMorning ||
        ctrl.shiftFilter == AppConstants.shiftAfternoon) {
      _newShift = ctrl.shiftFilter;
    } else {
      _newShift = AppConstants.shiftMorning;
    }

    _showAddForm = active.isEmpty && widget.producer.isActivo;

    final List<MilkReceptionModel> editable = active
        .where((MilkReceptionModel r) => r.canBeModified && r.isSynced)
        .toList();
    if (user.isAdmin && editable.length == 1) {
      _startEditing(editable.first, annul: false, notify: false);
    }
  }

  List<MilkReceptionModel> _entriesForCell(ReceptionController ctrl) {
    return ctrl.allReceptions
        .where(
          (MilkReceptionModel r) =>
              r.productorId == widget.producer.productorId &&
              r.fechaEntrega == widget.dateStr,
        )
        .toList();
  }

  void _startEditing(
    MilkReceptionModel r, {
    required bool annul,
    bool notify = true,
  }) {
    _editingReceptionId = r.recepcionId;
    _annulMode = annul;
    _editLitersCtrl.text = r.litros.toStringAsFixed(1);
    _reasonCtrl.clear();
    if (notify) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _newLitersCtrl.dispose();
    _editLitersCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitNew({bool allowDuplicate = false}) async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;

    final ReceptionController ctrl = context.read<ReceptionController>();
    final AuthController auth = context.read<AuthController>();
    final double liters = double.parse(
      _newLitersCtrl.text.replaceAll(',', '.').trim(),
    );
    final String operarioUid = auth.currentUser?.uid ?? 'operario';

    final result = await ctrl.registerDeliveryForProducer(
      producer: widget.producer,
      litros: liters,
      jornada: _newShift,
      operarioUid: operarioUid,
      fechaEntrega: widget.dateStr,
      allowDuplicate: allowDuplicate,
    );
    if (!mounted) return;

    if (result.duplicateFound != null) {
      VoiceService.instance.speak(
        'Atención: posible entrega duplicada de ${widget.producer.nombreCompleto}',
      );
      final bool? confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _DuplicateDeliveryDialog(existing: result.duplicateFound!),
      );
      if (confirm == true && mounted) {
        await _submitNew(allowDuplicate: true);
      }
      return;
    }

    if (result.saved) {
      final bool isMorning = _newShift == AppConstants.shiftMorning;
      VoiceService.instance.speak(
        'Registrado: ${VoiceService.spokenLiters(liters)} litros, '
        '${widget.producer.nombreCompleto}, jornada ${isMorning ? 'mañana' : 'tarde'}',
      );
      Navigator.of(context).pop(
        ctrl.feedbackMessage ?? 'Entrega registrada correctamente.',
      );
    }
  }

  Future<void> _submitEditOrAnnul(
    MilkReceptionModel target,
    UserModel actor,
  ) async {
    if (!(_editFormKey.currentState?.validate() ?? false)) return;
    final ReceptionController ctrl = context.read<ReceptionController>();

    late final bool ok;
    if (_annulMode) {
      ok = await ctrl.annulDelivery(
        existing: target,
        motivo: _reasonCtrl.text,
        actor: actor,
      );
    } else {
      final double parsed = double.parse(
        _editLitersCtrl.text.replaceAll(',', '.').trim(),
      );
      ok = await ctrl.editDeliveryLitros(
        existing: target,
        nuevosLitros: parsed,
        motivo: _reasonCtrl.text,
        actor: actor,
      );
    }
    if (ok && mounted) {
      Navigator.of(context).pop(
        ctrl.feedbackMessage ??
            (_annulMode
                ? 'Entrega anulada y registrada en auditoría.'
                : 'Entrega corregida correctamente.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = context.watch<ReceptionController>();
    final UserModel currentUser =
        context.watch<AuthController>().currentUser ??
        UserModel.bootstrapAdmin();
    final List<MilkReceptionModel> entries = _entriesForCell(ctrl);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDialogHeader(
                icon: Icons.water_drop_rounded,
                color: AppTheme.primaryGreen,
                title: widget.producer.nombreCompleto,
                subtitle:
                    '${widget.producer.codigoAsociado} · ${widget.producer.nombreFinca} · ${_formatMatrixPrettyDate(widget.day)}',
                onClose: ctrl.isSaving || ctrl.isSyncing
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 14),
              if (ctrl.errorMessage != null) ...<Widget>[
                AppInlineNotice.danger(message: ctrl.errorMessage!),
                const SizedBox(height: 12),
              ],
              if (entries.isNotEmpty) ...<Widget>[
                const Text(
                  'Entregas registradas en esta fecha',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final MilkReceptionModel r in entries) ...<Widget>[
                  _buildEntryCard(r, ctrl, currentUser),
                  const SizedBox(height: 10),
                ],
              ],
              if (!_showAddForm && widget.producer.isActivo)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: ctrl.isSaving
                        ? null
                        : () {
                            ctrl.clearFeedback();
                            setState(() {
                              _showAddForm = true;
                              _editingReceptionId = null;
                            });
                          },
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('Registrar entrega en este día'),
                  ),
                ),
              if (_showAddForm) _buildCreateForm(ctrl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard(
    MilkReceptionModel r,
    ReceptionController ctrl,
    UserModel currentUser,
  ) {
    final bool isMorning = r.jornada == AppConstants.shiftMorning;
    final bool isEditingThis = _editingReceptionId == r.recepcionId;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEditingThis ? AppTheme.surface : AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isEditingThis ? AppTheme.primaryGreen : AppTheme.border,
          width: isEditingThis ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _ShiftBadge(isMorning: isMorning),
                  Text(
                    r.horaEntrega,
                    style: AppTheme.monoStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  _ReceptionStateChip(reception: r),
                  SyncStatusBadge(
                    isSynced: r.isSynced,
                    syncedLabel: 'Sinc.',
                    pendingLabel: 'Pend.',
                  ),
                ],
              ),
              Text(
                '${r.litros.toStringAsFixed(1)} L',
                style: AppTheme.monoStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: r.anulado ? AppTheme.textMuted : AppTheme.primaryGreen,
                ).copyWith(
                  decoration: r.anulado ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          if (r.anulado && r.motivoAnulacion != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Motivo anulación: ${r.motivoAnulacion}',
              style: const TextStyle(fontSize: 12, color: AppTheme.dangerText),
            ),
          ],
          if (currentUser.isAdmin && r.canBeModified) ...<Widget>[
            const SizedBox(height: 8),
            if (!r.isSynced)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  const Text(
                    'Sincroniza antes de corregir o anular.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.warningText,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: ctrl.isSyncing ? null : ctrl.syncPendingNow,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                    label: Text(
                      ctrl.isSyncing ? 'Sincronizando…' : 'Sincronizar ahora',
                    ),
                  ),
                ],
              )
            else if (!isEditingThis)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: ctrl.isSaving
                        ? null
                        : () => _startEditing(r, annul: false),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Corregir litros'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                    ),
                    onPressed: ctrl.isSaving
                        ? null
                        : () => _startEditing(r, annul: true),
                    icon: const Icon(Icons.block_rounded, size: 15),
                    label: const Text('Anular entrega'),
                  ),
                ],
              )
            else
              _buildInlineEditor(r, ctrl, currentUser),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineEditor(
    MilkReceptionModel target,
    ReceptionController ctrl,
    UserModel actor,
  ) {
    return Form(
      key: _editFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(height: 16),
          if (_annulMode)
            const AppInlineNotice(
              icon: Icons.warning_amber_rounded,
              message:
                  'La entrega dejará de contar en liquidaciones. La acción se registra en la bitácora (Ley 527).',
            )
          else ...<Widget>[
            const Text(
              'Nueva cantidad de litros',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _editLitersCtrl,
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
          ],
          const SizedBox(height: 10),
          const Text(
            'Motivo de auditoría (Ley 527 de 1999)',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _quickReasons.map((String reason) {
              return ActionChip(
                label: Text(reason, style: const TextStyle(fontSize: 11.5)),
                padding: EdgeInsets.zero,
                onPressed: ctrl.isSaving
                    ? null
                    : () => setState(() => _reasonCtrl.text = reason),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _reasonCtrl,
            enabled: !ctrl.isSaving,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Ej. Error de digitación al pesar cantina.',
            ),
            validator: (String? v) => (v == null || v.trim().length < 5)
                ? 'Indica el motivo (mínimo 5 caracteres).'
                : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (!_annulMode)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  onPressed: ctrl.isSaving
                      ? null
                      : () => setState(() => _annulMode = true),
                  icon: const Icon(Icons.block_rounded, size: 16),
                  label: const Text('Anular'),
                )
              else
                TextButton.icon(
                  onPressed: ctrl.isSaving
                      ? null
                      : () => setState(() => _annulMode = false),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Corregir litros'),
                ),
              OutlinedButton(
                onPressed: ctrl.isSaving
                    ? null
                    : () => setState(() => _editingReceptionId = null),
                child: const Text('Cancelar'),
              ),
              PrimaryActionButton(
                label: _annulMode ? 'Confirmar anulación' : 'Guardar corrección',
                icon: _annulMode ? Icons.block_rounded : Icons.check_rounded,
                color: _annulMode ? AppTheme.danger : AppTheme.primaryGreen,
                fullWidth: false,
                isLoading: ctrl.isSaving,
                onPressed: () => _submitEditOrAnnul(target, actor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(ReceptionController ctrl) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Form(
        key: _createFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Registrar entrega para este día',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            AppSegmentedControl<String>(
              height: 40,
              expand: true,
              selected: _newShift,
              onChanged: (String value) => setState(() => _newShift = value),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _newLitersCtrl,
              enabled: !ctrl.isSaving,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: AppTheme.monoStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              onFieldSubmitted: (_) => _submitNew(),
              decoration: InputDecoration(
                labelText: 'Litros entregados',
                hintText: '0.0',
                suffixText: 'L',
                suffixStyle: AppTheme.monoStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
                prefixIcon: const Icon(Icons.water_drop_outlined, size: 18),
              ),
              validator: (String? v) {
                final double? val = double.tryParse(
                  (v ?? '').replaceAll(',', '.').trim(),
                );
                if (val == null || val <= 0) {
                  return 'Ingresa una cantidad válida mayor a cero.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: ctrl.isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
                const SizedBox(width: 10),
                PrimaryActionButton(
                  label: 'Registrar entrega',
                  icon: Icons.check_rounded,
                  fullWidth: false,
                  isLoading: ctrl.isSaving,
                  onPressed: _submitNew,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
