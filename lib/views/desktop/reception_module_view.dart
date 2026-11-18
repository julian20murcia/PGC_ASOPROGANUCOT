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
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';

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
      _showToast('Ingresa una cantidad válida de litros mayor a cero.', isError: true);
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
        builder: (_) => _DuplicateDeliveryDialog(
          existing: result.duplicateFound!,
        ),
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
        context.read<AuthController>().currentUser ?? UserModel.bootstrapAdmin();
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
        context.read<AuthController>().currentUser ?? UserModel.bootstrapAdmin();
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
        context.watch<AuthController>().currentUser ?? UserModel.bootstrapAdmin();
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

    final Widget producerField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '1. Productor (código, cédula o nombre)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
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
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            suffixIcon: (_producerInputCtrl.text.isNotEmpty || selected != null)
                ? IconButton(
                    tooltip: 'Limpiar selección',
                    onPressed: _clearSelectedProducer,
                    icon: const Icon(Icons.close_rounded, size: 16),
                  )
                : null,
          ),
        ),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.primaryGreen.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${selected.codigoAsociado} · ${selected.nombreCompleto} · Finca ${selected.nombreFinca} (${selected.vereda})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_producerInputQuery.trim().isNotEmpty ||
            ctrl.activeProducers.isNotEmpty) ...<Widget>[
          if (suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestions.map((ProducerModel p) {
                return ActionChip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 15),
                  backgroundColor: AppTheme.surfaceMuted,
                  side: const BorderSide(color: AppTheme.border),
                  label: Text(
                    '${p.codigoAsociado} · ${p.nombreCompleto}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  onPressed: () => _pickProducer(p),
                );
              }).toList(),
            ),
          ] else if (_producerInputQuery.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'No se encontraron productores activos con ese criterio.',
              style: TextStyle(fontSize: 12, color: AppTheme.dangerText),
            ),
          ],
        ],
      ],
    );

    final Widget shiftSelector = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '2. Jornada',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: _ShiftToggleButton(
                label: 'Mañana',
                icon: Icons.wb_sunny_outlined,
                selected: ctrl.selectedShift == AppConstants.shiftMorning,
                onTap: () => ctrl.setSelectedShift(AppConstants.shiftMorning),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShiftToggleButton(
                label: 'Tarde',
                icon: Icons.nights_stay_outlined,
                selected: ctrl.selectedShift == AppConstants.shiftAfternoon,
                onTap: () => ctrl.setSelectedShift(AppConstants.shiftAfternoon),
              ),
            ),
          ],
        ),
      ],
    );

    final Widget litersField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '3. Litros recibidos',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _litersCtrl,
          focusNode: _litersFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: AppTheme.monoStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          onSubmitted: (_) => _submitDelivery(),
          decoration: const InputDecoration(
            hintText: '0.0',
            suffixText: 'L',
            prefixIcon: Icon(Icons.water_drop_outlined, size: 18),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.bolt_rounded,
                size: 18,
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Captura rápida en planta',
                  style: AppTheme.subtitleStyle(),
                ),
              ),
              if (!isNarrow)
                const Text(
                  'Atajo: Enter para avanzar y guardar',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isNarrow) ...<Widget>[
            producerField,
            const SizedBox(height: 12),
            shiftSelector,
            const SizedBox(height: 12),
            litersField,
            const SizedBox(height: 14),
            PrimaryActionButton(
              label: 'Registrar entrega',
              icon: Icons.check_rounded,
              isLoading: ctrl.isSaving,
              onPressed: () => _submitDelivery(),
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: producerField),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: shiftSelector),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: litersField),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(top: 23),
                  child: PrimaryActionButton(
                    label: 'Registrar entrega',
                    icon: Icons.check_rounded,
                    fullWidth: false,
                    isLoading: ctrl.isSaving,
                    onPressed: () => _submitDelivery(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTableToolbar(ReceptionController ctrl, bool isNarrow) {
    final Widget periodChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _FilterPill(
          label: 'Hoy',
          selected: ctrl.dateFilterMode == ReceptionDateFilterMode.today,
          onTap: () => ctrl.setDateFilterMode(ReceptionDateFilterMode.today),
        ),
        _FilterPill(
          label: 'Quincena actual',
          selected: ctrl.dateFilterMode == ReceptionDateFilterMode.quincena,
          onTap: () => ctrl.setDateFilterMode(ReceptionDateFilterMode.quincena),
        ),
        _FilterPill(
          label: 'Todo',
          selected: ctrl.dateFilterMode == ReceptionDateFilterMode.all,
          onTap: () => ctrl.setDateFilterMode(ReceptionDateFilterMode.all),
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
      child: DropdownButtonFormField<String>(
        initialValue: ctrl.shiftFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'ALL',
            child: Text('Todas las jornadas', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: AppConstants.shiftMorning,
            child: Text('Mañana', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: AppConstants.shiftAfternoon,
            child: Text('Tarde', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: (String? val) {
          if (val != null) ctrl.setShiftFilter(val);
        },
      ),
    );

    final Widget statusDropdown = SizedBox(
      height: 36,
      child: DropdownButtonFormField<String>(
        initialValue: ctrl.statusFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'ACTIVE',
            child: Text('Solo activas', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: 'ANNULLED',
            child: Text('Anuladas', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: 'ALL',
            child: Text('Todas', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: (String? val) {
          if (val != null) ctrl.setStatusFilter(val);
        },
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
                SizedBox(width: 165, child: shiftDropdown),
                const SizedBox(width: 8),
                SizedBox(width: 140, child: statusDropdown),
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
          Icon(
            Icons.water_drop_outlined,
            size: 30,
            color: AppTheme.inkBlack,
          ),
          SizedBox(height: 10),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isMorning
                      ? AppTheme.warningBg
                      : AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
                ),
                child: Text(
                  isMorning ? 'Mañana' : 'Tarde',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isMorning
                        ? AppTheme.warningText
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
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
                style: AppTheme.monoStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: r.anulado ? AppTheme.textMuted : AppTheme.textPrimary,
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
                    IconButton(
                      tooltip: 'Corregir litros',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openEditDialog(r),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Anular entrega',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openAnnulDialog(r),
                      icon: const Icon(
                        Icons.block_rounded,
                        size: 18,
                        color: AppTheme.dangerText,
                      ),
                    ),
                  ],
                )
              else
                const Text(
                  '—',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
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
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
                Text(
                  '${ctrl.currentPage} / ${ctrl.totalPages}',
                  style: AppTheme.monoStyle(fontSize: 13),
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
  const _ReceptionSummaryStrip({
    required this.ctrl,
    required this.isNarrow,
  });

  final ReceptionController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      _MetricTile(
        title: 'Litros recibidos hoy',
        value: '${ctrl.todayTotalLiters.toStringAsFixed(1)} L',
        subtitle:
            'Mañana ${ctrl.todayMorningLiters.toStringAsFixed(1)} L · Tarde ${ctrl.todayAfternoonLiters.toStringAsFixed(1)} L',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      _MetricTile(
        title: 'Entregas de hoy',
        value: '${ctrl.todayDeliveriesCount}',
        subtitle: 'Registros activos del día',
        icon: Icons.fact_check_outlined,
      ),
      _MetricTile(
        title: 'Acumulado quincenal',
        value: '${ctrl.quincenaTotalLiters.toStringAsFixed(1)} L',
        subtitle: ctrl.currentQuincenaLabel,
        icon: Icons.calendar_today_outlined,
      ),
      _MetricTile(
        title: 'Estado de envío',
        value: ctrl.pendingSyncCount == 0
            ? 'Al día'
            : '${ctrl.pendingSyncCount} pend.',
        subtitle: ctrl.pendingSyncCount == 0
            ? 'Todo respaldado en la nube'
            : 'Pendiente por subir al reconectar',
        icon: Icons.cloud_done_outlined,
        accentColor: ctrl.pendingSyncCount == 0
            ? AppTheme.primaryGreen
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.accentColor = AppTheme.inkBlack,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.monoStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: accentColor == AppTheme.primaryGreen
                  ? AppTheme.primaryGreen
                  : accentColor == AppTheme.warningText
                      ? AppTheme.warningText
                      : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftToggleButton extends StatelessWidget {
  const _ShiftToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.inkBlack : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppTheme.inkBlack : AppTheme.inputBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.inkBlack : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppTheme.inkBlack : AppTheme.inputBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
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
    final String shiftName =
        existing.jornada == AppConstants.shiftMorning ? 'Mañana' : 'Tarde';

    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.warning,
            size: 24,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text('Posible entrega duplicada'),
          ),
        ],
      ),
      content: Text(
        '${existing.nombreProductorSnap} ya registró una entrega hoy '
        '(${existing.fechaEntrega}) en la jornada $shiftName por '
        '${existing.litros.toStringAsFixed(1)} L a las ${existing.horaEntrega}.\n\n'
        '¿Deseas confirmar el registro de esta entrega adicional en la misma jornada?',
        style: const TextStyle(fontSize: 13.5, height: 1.45),
      ),
      actions: <Widget>[
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar y guardar'),
        ),
      ],
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
      final double parsed =
          double.parse(_litersCtrl.text.replaceAll(',', '.').trim());
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

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.isAnnulment ? 'Anular entrega' : 'Corregir litros',
                  style: AppTheme.subtitleStyle(),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.reception.nombreProductorSnap} · ${widget.reception.fechaEntrega}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                if (ctrl.errorMessage != null) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ctrl.errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.dangerText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!widget.isAnnulment) ...<Widget>[
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppTheme.monoStyle(fontSize: 15),
                    decoration: const InputDecoration(suffixText: 'L'),
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
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _reasonCtrl,
                  enabled: !ctrl.isSaving,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Error de digitación al pesar cantina #2.',
                  ),
                  validator: (String? v) => (v == null || v.trim().length < 5)
                      ? 'Indica el motivo (mínimo 5 caracteres).'
                      : null,
                ),
                const SizedBox(height: 18),
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
                      label: widget.isAnnulment
                          ? 'Confirmar anulación'
                          : 'Guardar corrección',
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
