import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/privacy_notice.dart';
import '../../models/producer_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/privacy_notice_view.dart';
import '../shared/widgets/ui_kit.dart';

/// Módulo administrativo de Productores y Autorización de Datos Personales (Ley 1581 de 2012).
class ProducersModuleView extends StatefulWidget {
  const ProducersModuleView({super.key});

  @override
  State<ProducersModuleView> createState() => _ProducersModuleViewState();
}

class _ProducersModuleViewState extends State<ProducersModuleView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProducerController>().loadProducers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreateDialog() async {
    final AuthController auth = context.read<AuthController>();
    final ProducerController ctrl = context.read<ProducerController>();
    ctrl.clearFeedback();

    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProducerFormDialog(
        actorUid: auth.currentUser?.uid ?? 'admin',
        suggestedCode: ctrl.suggestedNextCode(),
      ),
    );
    if (created == true && mounted) {
      _showToast(ctrl.feedbackMessage ?? 'Productor registrado correctamente.');
    }
  }

  Future<void> _openEditDialog(ProducerModel producer) async {
    final AuthController auth = context.read<AuthController>();
    final ProducerController ctrl = context.read<ProducerController>();
    ctrl.clearFeedback();

    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProducerFormDialog(
        actorUid: auth.currentUser?.uid ?? 'admin',
        suggestedCode: producer.codigoAsociado,
        existingProducer: producer,
      ),
    );
    if (updated == true && mounted) {
      _showToast(ctrl.feedbackMessage ?? 'Productor actualizado.');
    }
  }

  Future<void> _toggleStatus(ProducerModel producer) async {
    final AuthController auth = context.read<AuthController>();
    final ProducerController ctrl = context.read<ProducerController>();
    final bool ok = await ctrl.toggleProducerStatus(
      producer: producer,
      actorUid: auth.currentUser?.uid ?? 'admin',
    );
    if (!mounted) return;
    _showToast(
      ok
          ? (ctrl.feedbackMessage ?? 'Estado actualizado.')
          : (ctrl.errorMessage ?? 'No fue posible actualizar el estado.'),
      isError: !ok,
    );
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
    final ProducerController ctrl = context.watch<ProducerController>();
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
            _buildToolbar(ctrl, isNarrow),
            const SizedBox(height: 14),
            if (ctrl.isLoading && ctrl.allProducers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: DairyLoader(
                    size: DairyLoaderSize.lg,
                    label: 'Cargando productores…',
                    hint: 'Un momento por favor.',
                  ),
                ),
              )
            else if (ctrl.filteredProducers.isEmpty)
              _buildEmptyState(ctrl)
            else
              _buildTableSection(ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ProducerController ctrl, bool isNarrow) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Productores', style: AppTheme.titleStyle(isMobile: isNarrow)),
        const SizedBox(height: 4),
        const Text(
          'Padrón de ganaderos asociados en Susa, fincas, acceso móvil y autorización de datos.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: ctrl.isLoading ? null : ctrl.loadProducers,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Actualizar'),
        ),
        PrimaryActionButton(
          label: 'Nuevo productor',
          icon: Icons.add_rounded,
          fullWidth: false,
          onPressed: _openCreateDialog,
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
        _ProducerSummaryStrip(ctrl: ctrl, isNarrow: isNarrow),
      ],
    );
  }

  Widget _buildToolbar(ProducerController ctrl, bool isNarrow) {
    final String countText =
        ctrl.filteredProducers.length == ctrl.allProducers.length
        ? '${ctrl.allProducers.length} ${ctrl.allProducers.length == 1 ? 'productor' : 'productores'}'
        : '${ctrl.filteredProducers.length} de ${ctrl.allProducers.length}';

    final Widget searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        onChanged: ctrl.setSearchQuery,
        decoration: InputDecoration(
          hintText: 'Buscar por código, nombre, cédula, finca o vereda…',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 17),
          suffixIcon: ctrl.searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    ctrl.setSearchQuery('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 15),
                )
              : null,
        ),
      ),
    );

    final Widget veredaDropdown = SizedBox(
      height: 36,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.veredaFilter,
        prefixIcon: Icons.place_outlined,
        searchHint: 'Buscar vereda…',
        options: <AppSelectOption<String>>[
          const AppSelectOption<String>(
            value: 'ALL',
            label: 'Todas las veredas',
          ),
          ...ctrl.availableVeredas.map(
            (String vereda) =>
                AppSelectOption<String>(value: vereda, label: vereda),
          ),
        ],
        onChanged: ctrl.setVeredaFilter,
      ),
    );

    final Widget statusDropdown = SizedBox(
      height: 36,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.statusFilter,
        prefixIcon: Icons.toggle_on_outlined,
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'ALL', label: 'Todos los estados'),
          AppSelectOption<String>(
            value: 'ACTIVO',
            label: 'Activos',
            icon: Icons.check_circle_outline_rounded,
          ),
          AppSelectOption<String>(
            value: 'INACTIVO',
            label: 'Inactivos',
            icon: Icons.pause_circle_outline_rounded,
          ),
        ],
        onChanged: ctrl.setStatusFilter,
      ),
    );

    if (isNarrow) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            searchField,
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: veredaDropdown),
                const SizedBox(width: 10),
                Expanded(child: statusDropdown),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                AppCountPill(text: countText),
                if (ctrl.hasActiveFilters)
                  TextButton.icon(
                    onPressed: () {
                      _searchCtrl.clear();
                      ctrl.clearFilters();
                    },
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('Limpiar filtros'),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: searchField),
          const SizedBox(width: 10),
          SizedBox(width: 205, child: veredaDropdown),
          const SizedBox(width: 8),
          SizedBox(width: 192, child: statusDropdown),
          const SizedBox(width: 12),
          AppCountPill(text: countText),
          if (ctrl.hasActiveFilters) ...<Widget>[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Limpiar filtros',
              onPressed: () {
                _searchCtrl.clear();
                ctrl.clearFilters();
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ProducerController ctrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppIconBadge(
            icon: Icons.agriculture_outlined,
            color: AppTheme.primaryGreen,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            ctrl.hasActiveFilters
                ? 'No hay productores que coincidan con la búsqueda'
                : 'Aún no hay productores registrados',
            style: AppTheme.subtitleStyle(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            ctrl.hasActiveFilters
                ? 'Prueba con otro código, cédula o limpia los filtros activos.'
                : 'Registra el primer ganadero asociado en Susa con su autorización de datos.',
            style: const TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          if (ctrl.hasActiveFilters)
            OutlinedButton(
              onPressed: () {
                _searchCtrl.clear();
                ctrl.clearFilters();
              },
              child: const Text('Limpiar filtros'),
            )
          else
            PrimaryActionButton(
              label: 'Registrar productor',
              icon: Icons.add_rounded,
              fullWidth: false,
              onPressed: _openCreateDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildTableSection(ProducerController ctrl) {
    final List<ProducerModel> rows = ctrl.paginatedProducers;

    bool? sortIndicator(ProducerSortColumn column) =>
        ctrl.sortColumn == column ? ctrl.sortAscending : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CleanDataTable(
          columns: <CleanTableColumn>[
            CleanTableColumn(
              label: 'Código',
              sortAscending: sortIndicator(ProducerSortColumn.codigo),
              onSort: () => ctrl.toggleSort(ProducerSortColumn.codigo),
            ),
            CleanTableColumn(
              label: 'Productor',
              sortAscending: sortIndicator(ProducerSortColumn.nombre),
              onSort: () => ctrl.toggleSort(ProducerSortColumn.nombre),
            ),
            CleanTableColumn(
              label: 'Cédula',
              sortAscending: sortIndicator(ProducerSortColumn.cedula),
              onSort: () => ctrl.toggleSort(ProducerSortColumn.cedula),
            ),
            CleanTableColumn(
              label: 'Finca y Vereda',
              sortAscending: sortIndicator(ProducerSortColumn.vereda),
              onSort: () => ctrl.toggleSort(ProducerSortColumn.vereda),
            ),
            const CleanTableColumn(label: 'Acceso móvil'),
            CleanTableColumn(
              label: 'Estado',
              sortAscending: sortIndicator(ProducerSortColumn.estado),
              onSort: () => ctrl.toggleSort(ProducerSortColumn.estado),
            ),
            const CleanTableColumn(label: 'Acciones'),
          ],
          rows: rows.map((ProducerModel p) {
            final bool hasMobile =
                p.uidUsuario != null && p.uidUsuario!.isNotEmpty;
            return <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  p.codigoAsociado,
                  style: AppTheme.monoStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkBlack,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ProducerAvatar(name: p.nombreCompleto, active: p.isActivo),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        p.nombreCompleto,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (p.telefono.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.phone_outlined,
                              size: 11,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              p.telefono,
                              style: AppTheme.monoStyle(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
              Text(p.cedula, style: AppTheme.monoStyle(fontSize: 13)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    p.nombreFinca,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.place_outlined,
                        size: 12,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Vereda ${p.vereda}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _MobileLinkBadge(linked: hasMobile),
              InkWell(
                onTap: () => _toggleStatus(p),
                borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
                child: _ProducerStatusBadge(active: p.isActivo),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppRowActionButton(
                    tooltip: 'Editar productor',
                    icon: Icons.edit_outlined,
                    color: AppTheme.skyBlue,
                    onPressed: () => _openEditDialog(p),
                  ),
                  const SizedBox(width: 6),
                  AppRowActionButton(
                    tooltip: p.isActivo
                        ? 'Marcar inactivo'
                        : 'Reactivar productor',
                    icon: p.isActivo
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    color: p.isActivo
                        ? AppTheme.warning
                        : AppTheme.primaryGreen,
                    onPressed: () => _toggleStatus(p),
                  ),
                ],
              ),
            ];
          }).toList(),
        ),
        const SizedBox(height: 12),
        _buildPaginationBar(ctrl),
      ],
    );
  }

  Widget _buildPaginationBar(ProducerController ctrl) {
    final int total = ctrl.filteredProducers.length;
    final int start = total == 0
        ? 0
        : ((ctrl.currentPage - 1) * ctrl.itemsPerPage) + 1;
    final int end = (ctrl.currentPage * ctrl.itemsPerPage).clamp(0, total);

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        Text(
          'Mostrando $start–$end de $total productores',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 150,
              height: 34,
              child: AppSelect<int>(
                dense: true,
                value: ctrl.itemsPerPage,
                menuMinWidth: 150,
                options: const <int>[10, 20, 40]
                    .map(
                      (int size) => AppSelectOption<int>(
                        value: size,
                        label: '$size por página',
                      ),
                    )
                    .toList(),
                onChanged: ctrl.setItemsPerPage,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: ctrl.currentPage > 1
                  ? () => ctrl.setPage(ctrl.currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            AppCountPill(text: '${ctrl.currentPage} / ${ctrl.totalPages}'),
            IconButton(
              onPressed: ctrl.currentPage < ctrl.totalPages
                  ? () => ctrl.setPage(ctrl.currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProducerSummaryStrip extends StatelessWidget {
  const _ProducerSummaryStrip({required this.ctrl, required this.isNarrow});

  final ProducerController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      AppMetricTile(
        title: 'Total productores',
        value: '${ctrl.totalCount}',
        subtitle: 'Registrados en el padrón',
        icon: Icons.agriculture_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppMetricTile(
        title: 'Productores activos',
        value: '${ctrl.activeCount}',
        subtitle: 'Habilitados para entrega',
        icon: Icons.check_circle_outline_rounded,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
        title: 'Con acceso móvil',
        value: '${ctrl.linkedMobileCount}',
        subtitle: 'Consulta en teléfono',
        icon: Icons.smartphone_outlined,
        accentColor: AppTheme.warmGold,
      ),
      AppMetricTile(
        title: 'Veredas registradas',
        value: '${ctrl.veredasCount}',
        subtitle: 'Zona lechera de Susa',
        icon: Icons.place_outlined,
        accentColor: AppTheme.indigoAccent,
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

class _ProducerAvatar extends StatelessWidget {
  const _ProducerAvatar({required this.name, required this.active});

  final String name;
  final bool active;

  static const List<Color> _palette = <Color>[
    AppTheme.primaryGreen,
    AppTheme.skyBlue,
    AppTheme.tealAccent,
    AppTheme.indigoAccent,
    AppTheme.warmGold,
  ];

  @override
  Widget build(BuildContext context) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    final String initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    final Color color = active
        ? _palette[name.codeUnits.fold<int>(0, (int a, int b) => a + b) %
              _palette.length]
        : AppTheme.textMuted;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MobileLinkBadge extends StatelessWidget {
  const _MobileLinkBadge({required this.linked});

  final bool linked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: linked ? AppTheme.primaryGreenLight : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        border: Border.all(
          color: linked
              ? AppTheme.primaryGreen.withValues(alpha: 0.25)
              : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            linked ? Icons.smartphone_rounded : Icons.phonelink_off_rounded,
            size: 13,
            color: linked ? AppTheme.primaryGreen : AppTheme.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            linked ? 'Vinculada' : 'Sin cuenta',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: linked ? AppTheme.successText : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProducerStatusBadge extends StatelessWidget {
  const _ProducerStatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color bg = active ? AppTheme.successBg : AppTheme.dangerBg;
    final Color fg = active ? AppTheme.successText : AppTheme.dangerText;
    final Color dot = active ? AppTheme.success : AppTheme.danger;

    return Tooltip(
      message: active ? 'Clic para desactivar' : 'Clic para reactivar',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              active ? 'Activo' : 'Inactivo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProducerFormDialog extends StatefulWidget {
  const _ProducerFormDialog({
    required this.actorUid,
    required this.suggestedCode,
    this.existingProducer,
  });

  final String actorUid;
  final String suggestedCode;
  final ProducerModel? existingProducer;

  @override
  State<_ProducerFormDialog> createState() => _ProducerFormDialogState();
}

class _ProducerFormDialogState extends State<_ProducerFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeCtrl;
  late final TextEditingController _cedulaCtrl;
  late final TextEditingController _nombresCtrl;
  late final TextEditingController _apellidosCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _fincaCtrl;
  late final TextEditingController _veredaCtrl;
  late final TextEditingController _mobileEmailCtrl;
  late final TextEditingController _mobilePasswordCtrl;

  late Future<PrivacyNotice> _noticeFuture;
  PrivacyNotice? _notice;

  late bool _isActive;
  late bool _acceptedHabeasData;
  bool _createMobileAccount = false;
  bool _obscurePassword = true;

  bool get _isEditing => widget.existingProducer != null;
  bool get _alreadyLinked =>
      widget.existingProducer?.uidUsuario != null &&
      widget.existingProducer!.uidUsuario!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final ProducerModel? p = widget.existingProducer;
    _codeCtrl = TextEditingController(
      text: p?.codigoAsociado ?? widget.suggestedCode,
    );
    _cedulaCtrl = TextEditingController(text: p?.cedula ?? '');
    _nombresCtrl = TextEditingController(text: p?.nombres ?? '');
    _apellidosCtrl = TextEditingController(text: p?.apellidos ?? '');
    _telefonoCtrl = TextEditingController(text: p?.telefono ?? '');
    _fincaCtrl = TextEditingController(text: p?.nombreFinca ?? '');
    _veredaCtrl = TextEditingController(text: p?.vereda ?? '');
    _mobileEmailCtrl = TextEditingController();
    _mobilePasswordCtrl = TextEditingController();

    if (!_isEditing) _noticeFuture = _loadNotice();
    _isActive = p?.isActivo ?? true;
    _acceptedHabeasData = p?.aceptoHabeasData ?? false;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _cedulaCtrl.dispose();
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _telefonoCtrl.dispose();
    _fincaCtrl.dispose();
    _veredaCtrl.dispose();
    _mobileEmailCtrl.dispose();
    _mobilePasswordCtrl.dispose();
    super.dispose();
  }

  Future<PrivacyNotice> _loadNotice() async {
    final notice = await context.read<ProducerController>().loadPrivacyNotice();
    if (mounted) _notice = notice;
    return notice;
  }

  void _retryNotice() {
    final pendingNotice = _loadNotice();
    setState(() {
      _notice = null;
      _acceptedHabeasData = false;
      _noticeFuture = pendingNotice;
    });
  }

  String _noticeError(Object? error) {
    if (error is FormatException) return error.message;
    if (error is FirebaseException &&
        (error.code == 'permission-denied' ||
            error.code == 'unauthenticated')) {
      return 'No tienes acceso al aviso institucional. Verifica la sesión y las reglas de Firestore.';
    }
    return 'No se pudo consultar el aviso institucional. Verifica la conexión y reintenta.';
  }

  Future<void> _showPolicyPdf() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Política y aviso de privacidad'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: PdfPreview(
          build: (_) async {
            final pdf = await rootBundle.load(
              'docs/privacidad/politica-y-aviso-v1-1-asoproganucott.pdf',
            );
            return pdf.buffer.asUint8List(pdf.offsetInBytes, pdf.lengthInBytes);
          },
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          pdfFileName: 'politica-y-aviso-v1-1-asoproganucott.pdf',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Future<void> _submit() async {
    if (!_acceptedHabeasData || (!_isEditing && _notice == null)) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final ProducerController ctrl = context.read<ProducerController>();
    final String estado = _isActive ? 'ACTIVO' : 'INACTIVO';

    late final bool ok;
    if (_isEditing) {
      ok = await ctrl.updateProducer(
        previous: widget.existingProducer!,
        codigoAsociado: _codeCtrl.text,
        cedula: _cedulaCtrl.text,
        nombres: _nombresCtrl.text,
        apellidos: _apellidosCtrl.text,
        telefono: _telefonoCtrl.text,
        nombreFinca: _fincaCtrl.text,
        vereda: _veredaCtrl.text,
        estado: estado,
        aceptoHabeasData: _acceptedHabeasData,
        actorUid: widget.actorUid,
        createMobileAccount: !_alreadyLinked && _createMobileAccount,
        mobileEmail: _mobileEmailCtrl.text,
        mobilePassword: _mobilePasswordCtrl.text,
      );
    } else {
      ok = await ctrl.createProducer(
        codigoAsociado: _codeCtrl.text,
        cedula: _cedulaCtrl.text,
        nombres: _nombresCtrl.text,
        apellidos: _apellidosCtrl.text,
        telefono: _telefonoCtrl.text,
        nombreFinca: _fincaCtrl.text,
        vereda: _veredaCtrl.text,
        estado: estado,
        aceptoHabeasData: _acceptedHabeasData,
        actorUid: widget.actorUid,
        privacyNotice: _notice,
        createMobileAccount: _createMobileAccount,
        mobileEmail: _mobileEmailCtrl.text,
        mobilePassword: _mobilePasswordCtrl.text,
      );
    }

    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    IconData? icon,
    String? hint,
    bool mono = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(label),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: mono ? AppTheme.monoStyle(fontSize: 13.5) : null,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon, size: 17),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _pair(Widget a, Widget b, {int flexA = 1, int flexB = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: flexA, child: a),
        const SizedBox(width: 12),
        Expanded(flex: flexB, child: b),
      ],
    );
  }

  Widget _buildPrivacySection(ProducerController ctrl) {
    return FutureBuilder<PrivacyNotice>(
      future: _noticeFuture,
      builder: (context, snapshot) {
        final PrivacyNotice? notice = snapshot.data;
        final bool loading = snapshot.connectionState != ConnectionState.done;
        if (loading || notice == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'La asociación utiliza los datos para registrar entregas de leche, liquidar pagos y permitir la consulta del historial. El productor puede consultar, actualizar y rectificar sus datos.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (loading)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppTheme.canvasAlt,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Cargando el aviso institucional…',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        child: LinearProgressIndicator(minHeight: 4),
                      ),
                    ],
                  ),
                )
              else ...<Widget>[
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.cloud_off_rounded,
                          size: 17,
                          color: AppTheme.dangerText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _noticeError(snapshot.error),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppTheme.dangerText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _retryNotice,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reintentar'),
                    ),
                    TextButton.icon(
                      onPressed: _showPolicyPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Ver copia de la política (PDF)'),
                    ),
                  ],
                ),
              ],
            ],
          );
        }

        final Map<String, String> data = notice.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.canvasAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreenLight,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusPill,
                          ),
                        ),
                        child: Text(
                          'Versión ${data['version']}',
                          style: AppTheme.monoStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successText,
                          ),
                        ),
                      ),
                      Text(
                        data['responsable'] ?? '',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _PrivacyDetailLine(
                    label: 'Contacto',
                    text:
                        '${data['direccion']} · ${data['telefono']} · ${data['correo']}',
                  ),
                  const SizedBox(height: 5),
                  _PrivacyDetailLine(
                    label: 'Finalidad',
                    text: data['finalidades'] ?? '',
                  ),
                  const SizedBox(height: 5),
                  _PrivacyDetailLine(
                    label: 'Derechos',
                    text: data['derechos'] ?? '',
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: <Widget>[
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            PrivacyNoticeView.openPolicy(context, notice),
                        icon: const Icon(Icons.open_in_new, size: 15),
                        label: const Text('Ver política de tratamiento'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _showPolicyPdf,
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 15,
                        ),
                        label: const Text('Ver copia de la política (PDF)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: _acceptedHabeasData
                    ? AppTheme.primaryGreenLight
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(
                  color: _acceptedHabeasData
                      ? AppTheme.primaryGreen.withValues(alpha: 0.45)
                      : AppTheme.inputBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppTheme.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusCard,
                        ),
                      ),
                      value: _acceptedHabeasData,
                      onChanged: ctrl.isSaving
                          ? null
                          : (bool? value) {
                              setState(
                                () => _acceptedHabeasData = value == true,
                              );
                            },
                      title: const Text(
                        'Entregué el aviso y el productor autorizó previamente el tratamiento de sus datos.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (_acceptedHabeasData)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 9),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.verified_outlined,
                            size: 14,
                            color: AppTheme.primaryGreen,
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Constancia digital automática al guardar (Ley 1581 de 2012).',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.successText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProducerDataColumn(bool enabled, ProducerController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _FormSection(
          step: 1,
          icon: Icons.badge_outlined,
          title: 'Datos del productor',
          subtitle: 'Identificación y finca',
        ),
        const SizedBox(height: 10),
        _pair(
          _field(
            label: 'Código de asociado',
            controller: _codeCtrl,
            enabled: enabled,
            icon: Icons.tag_rounded,
            hint: 'ASO-001',
            mono: true,
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Código requerido.' : null,
          ),
          _field(
            label: 'Cédula / Documento',
            controller: _cedulaCtrl,
            enabled: enabled,
            icon: Icons.credit_card_rounded,
            hint: '1073500123',
            mono: true,
            keyboardType: TextInputType.number,
            validator: (String? v) =>
                (v == null || v.trim().length < 5) ? 'Documento inválido.' : null,
          ),
          flexA: 2,
          flexB: 3,
        ),
        const SizedBox(height: 10),
        _pair(
          _field(
            label: 'Nombres',
            controller: _nombresCtrl,
            enabled: enabled,
            hint: 'Ej. José Luis',
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Ingresa los nombres.' : null,
          ),
          _field(
            label: 'Apellidos',
            controller: _apellidosCtrl,
            enabled: enabled,
            hint: 'Ej. Rodríguez López',
            validator: (String? v) => (v == null || v.trim().isEmpty)
                ? 'Ingresa los apellidos.'
                : null,
          ),
        ),
        const SizedBox(height: 10),
        _pair(
          _field(
            label: 'Teléfono de contacto',
            controller: _telefonoCtrl,
            enabled: enabled,
            icon: Icons.phone_outlined,
            hint: '3101234567',
            mono: true,
            keyboardType: TextInputType.phone,
          ),
          _field(
            label: 'Vereda',
            controller: _veredaCtrl,
            enabled: enabled,
            icon: Icons.place_outlined,
            hint: 'Ej. La Glorieta',
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Ingresa la vereda.' : null,
          ),
        ),
        const SizedBox(height: 10),
        _field(
          label: 'Nombre de la finca',
          controller: _fincaCtrl,
          enabled: enabled,
          icon: Icons.cottage_outlined,
          hint: 'Ej. Finca El Porvenir',
          validator: (String? v) => (v == null || v.trim().isEmpty)
              ? 'Ingresa el nombre de la finca.'
              : null,
        ),
        const SizedBox(height: 12),
        AppToggleCard(
          icon: _isActive
              ? Icons.check_circle_outline_rounded
              : Icons.pause_circle_outline_rounded,
          color: _isActive ? AppTheme.primaryGreen : AppTheme.textMuted,
          title: 'Productor activo',
          subtitle: 'Permite recibir entregas de leche en planta.',
          value: _isActive,
          onChanged: ctrl.isSaving
              ? null
              : (bool val) => setState(() => _isActive = val),
        ),
      ],
    );
  }

  Widget _buildPrivacyAndAccessColumn(ProducerController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FormSection(
          step: 2,
          icon: Icons.privacy_tip_outlined,
          title: 'Aviso de privacidad',
          subtitle: 'Ley 1581 de 2012',
          done: _isEditing || _acceptedHabeasData,
        ),
        const SizedBox(height: 10),
        if (!_isEditing)
          _buildPrivacySection(ctrl)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppInlineNotice(
                icon: Icons.verified_user_outlined,
                background: AppTheme.skyBlueLight,
                foreground: const Color(0xFF075985),
                message:
                    widget.existingProducer!.soporteAutorizacion == null
                    ? 'Autorización registrada en afiliación inicial del productor.'
                    : 'Autorización registrada (${widget.existingProducer!.soporteAutorizacion}).',
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showPolicyPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                  label: const Text('Ver copia de la política (PDF)'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        _FormSection(
          step: 3,
          icon: Icons.smartphone_rounded,
          title: 'Acceso móvil',
          subtitle: 'Portal del ganadero',
          done: _alreadyLinked,
        ),
        const SizedBox(height: 10),
        _buildMobileAccessSection(ctrl),
      ],
    );
  }

  Widget _buildMobileAccessSection(ProducerController ctrl) {
    if (_alreadyLinked) {
      return const AppInlineNotice(
        icon: Icons.verified_user_outlined,
        background: AppTheme.primaryGreenLight,
        foreground: AppTheme.successText,
        message:
            'Este productor ya tiene acceso móvil vinculado para consultar entregas y pagos.',
      );
    }
    return AppToggleCard(
      icon: Icons.smartphone_rounded,
      color: AppTheme.warmGold,
      title: 'Acceso móvil del productor',
      subtitle:
          'Crea o vincula su usuario para consultar entregas y comprobantes en el celular.',
      value: _createMobileAccount,
      onChanged: ctrl.isSaving
          ? null
          : (bool val) => setState(() => _createMobileAccount = val),
      child: !_createMobileAccount
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _field(
                  label: 'Correo electrónico de acceso',
                  controller: _mobileEmailCtrl,
                  enabled: !ctrl.isSaving,
                  icon: Icons.alternate_email_rounded,
                  hint: 'productor@correo.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (String? v) {
                    if (!_createMobileAccount) return null;
                    if (v == null || !v.trim().contains('@')) {
                      return 'Ingresa un correo válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                const _FieldLabel('Contraseña inicial'),
                TextFormField(
                  controller: _mobilePasswordCtrl,
                  enabled: !ctrl.isSaving,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    hintText: 'Mínimo 6 caracteres',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                  validator: (String? v) {
                    if (!_createMobileAccount) return null;
                    if (v == null || v.length < 6) {
                      return 'Mínimo 6 caracteres.';
                    }
                    return null;
                  },
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();
    final bool enabled = !ctrl.isSaving;
    final bool wideLayout = MediaQuery.sizeOf(context).width >= 840;
    final bool readyToSave = _isEditing || (_acceptedHabeasData && _notice != null);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wideLayout ? 900 : 580,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(22, 16, 14, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      AppTheme.primaryGreenLight,
                      AppTheme.surface,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.dividerLight),
                  ),
                ),
                child: AppDialogHeader(
                  icon: _isEditing
                      ? Icons.edit_outlined
                      : Icons.agriculture_rounded,
                  title: _isEditing ? 'Editar productor' : 'Nuevo productor',
                  subtitle: _isEditing
                      ? 'Actualiza los datos del ganadero asociado y su estado.'
                      : 'Registra al ganadero asociado en el padrón oficial de Susa.',
                  onClose: ctrl.isSaving
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (ctrl.errorMessage != null) ...<Widget>[
                        AppInlineNotice.danger(message: ctrl.errorMessage!),
                        const SizedBox(height: 14),
                      ],
                      if (wideLayout)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 6,
                              child: _buildProducerDataColumn(enabled, ctrl),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              flex: 5,
                              child: _buildPrivacyAndAccessColumn(ctrl),
                            ),
                          ],
                        )
                      else ...<Widget>[
                        _buildProducerDataColumn(enabled, ctrl),
                        const SizedBox(height: 18),
                        _buildPrivacyAndAccessColumn(ctrl),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                decoration: const BoxDecoration(
                  color: AppTheme.canvas,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        readyToSave
                            ? 'El registro y su autorización quedan guardados en auditoría.'
                            : 'Confirma el aviso de privacidad para habilitar el guardado.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: ctrl.isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    PrimaryActionButton(
                      label: _isEditing
                          ? 'Guardar cambios'
                          : 'Guardar productor',
                      icon: Icons.check_rounded,
                      fullWidth: false,
                      isLoading: ctrl.isSaving,
                      onPressed:
                          _acceptedHabeasData &&
                              (_isEditing || _notice != null) &&
                              !ctrl.isSaving
                          ? _submit
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyDetailLine extends StatelessWidget {
  const _PrivacyDetailLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontFamily: AppTheme.fontFamilyName,
          fontSize: 12,
          height: 1.4,
          color: AppTheme.textSecondary,
        ),
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          TextSpan(text: text),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// Encabezado numerado de cada sección del formulario.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.step,
    required this.icon,
    required this.title,
    this.subtitle,
    this.done = false,
  });

  final int step;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? AppTheme.primaryGreen : AppTheme.inkBlack,
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : Text(
                  '$step',
                  style: AppTheme.monoStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 17, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(title, style: AppTheme.subtitleStyle()),
        if (subtitle != null) ...<Widget>[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
        ],
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
      ],
    );
  }
}
