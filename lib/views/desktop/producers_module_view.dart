import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/privacy_notice.dart';
import '../../models/producer_model.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/privacy_notice_view.dart';

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
        Text(
          'Productores',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
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
    final String countText = ctrl.filteredProducers.length == ctrl.allProducers.length
        ? '${ctrl.allProducers.length} ${ctrl.allProducers.length == 1 ? 'productor' : 'productores'}'
        : '${ctrl.filteredProducers.length} de ${ctrl.allProducers.length}';

    final Widget searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        onChanged: ctrl.setSearchQuery,
        decoration: InputDecoration(
          hintText: 'Buscar por código, nombre, cédula, finca o vereda…',
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

    final List<DropdownMenuItem<String>> veredaItems =
        <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: 'ALL',
        child: Text('Todas las veredas', overflow: TextOverflow.ellipsis),
      ),
      ...ctrl.availableVeredas.map(
        (String vereda) => DropdownMenuItem<String>(
          value: vereda,
          child: Text(vereda, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    final Widget veredaDropdown = SizedBox(
      height: 36,
      child: DropdownButtonFormField<String>(
        initialValue: ctrl.veredaFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: veredaItems,
        onChanged: (String? value) {
          if (value != null) ctrl.setVeredaFilter(value);
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
            value: 'ALL',
            child: Text('Todos los estados', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: 'ACTIVO',
            child: Text('Activos', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem<String>(
            value: 'INACTIVO',
            child: Text('Inactivos', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: (String? value) {
          if (value != null) ctrl.setStatusFilter(value);
        },
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
                Text(
                  countText,
                  style: AppTheme.monoStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
                if (ctrl.hasActiveFilters)
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      ctrl.clearFilters();
                    },
                    child: const Text('Limpiar filtros'),
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
          SizedBox(width: 180, child: veredaDropdown),
          const SizedBox(width: 8),
          SizedBox(width: 162, child: statusDropdown),
          const SizedBox(width: 12),
          Text(
            countText,
            style: AppTheme.monoStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          if (ctrl.hasActiveFilters) ...<Widget>[
            const SizedBox(width: 6),
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                ctrl.clearFilters();
              },
              child: const Text('Limpiar'),
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
          const Icon(
            Icons.agriculture_outlined,
            size: 32,
            color: AppTheme.inkBlack,
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
            style:
                const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    Text(
                      p.telefono,
                      style: AppTheme.monoStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                ],
              ),
              Text(
                p.cedula,
                style: AppTheme.monoStyle(fontSize: 13),
              ),
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
                  Text(
                    'Vereda ${p.vereda}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
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
                  IconButton(
                    tooltip: 'Editar productor',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openEditDialog(p),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip:
                        p.isActivo ? 'Marcar inactivo' : 'Reactivar productor',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _toggleStatus(p),
                    icon: Icon(
                      p.isActivo
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 18,
                      color: p.isActivo
                          ? AppTheme.textSecondary
                          : AppTheme.primaryGreen,
                    ),
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
    final int start =
        total == 0 ? 0 : ((ctrl.currentPage - 1) * ctrl.itemsPerPage) + 1;
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
            DropdownButton<int>(
              value: ctrl.itemsPerPage,
              underline: const SizedBox.shrink(),
              items: const <int>[10, 20, 40]
                  .map(
                    (int size) => DropdownMenuItem<int>(
                      value: size,
                      child: Text(
                        '$size por página',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (int? val) {
                if (val != null) ctrl.setItemsPerPage(val);
              },
            ),
            const SizedBox(width: 8),
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
    );
  }
}

class _ProducerSummaryStrip extends StatelessWidget {
  const _ProducerSummaryStrip({
    required this.ctrl,
    required this.isNarrow,
  });

  final ProducerController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      _MetricBox(
        title: 'Total productores',
        value: '${ctrl.totalCount}',
        subtitle: 'Registrados en el padrón',
        icon: Icons.agriculture_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      _MetricBox(
        title: 'Productores activos',
        value: '${ctrl.activeCount}',
        subtitle: 'Habilitados para entrega',
        icon: Icons.check_circle_outline_rounded,
        accentColor: AppTheme.primaryGreen,
      ),
      _MetricBox(
        title: 'Con acceso móvil',
        value: '${ctrl.linkedMobileCount}',
        subtitle: 'Consulta en teléfono',
        icon: Icons.smartphone_outlined,
        accentColor: AppTheme.warmGold,
      ),
      _MetricBox(
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

class _MetricBox extends StatelessWidget {
  const _MetricBox({
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
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.24),
                  ),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.monoStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: accentColor == AppTheme.primaryGreen
                  ? AppTheme.primaryGreen
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

  final TextEditingController _authorizationCtrl = TextEditingController();
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
    _authorizationCtrl.dispose();
    super.dispose();
  }

  Future<PrivacyNotice> _loadNotice() async {
    final notice = await PrivacyNotice.load();
    _notice = notice;
    return notice;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedHabeasData) return;

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
        authorizationReference: _authorizationCtrl.text,
        createMobileAccount: _createMobileAccount,
        mobileEmail: _mobileEmailCtrl.text,
        mobilePassword: _mobilePasswordCtrl.text,
      );
    }

    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 590,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.inkBlack,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isEditing
                            ? Icons.edit_outlined
                            : Icons.agriculture_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _isEditing
                                ? 'Editar productor'
                                : 'Nuevo productor',
                            style: AppTheme.subtitleStyle(),
                          ),
                          Text(
                            _isEditing
                                ? 'Actualiza los datos del ganadero asociado y su estado.'
                                : 'Registra al ganadero asociado en el padrón oficial de Susa.',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: ctrl.isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                  if (ctrl.errorMessage != null) ...<Widget>[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        ctrl.errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.dangerText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!_isEditing) ...[
                    Text('Aviso de privacidad', style: AppTheme.subtitleStyle()),
                    FutureBuilder<PrivacyNotice>(
                      future: _noticeFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Aviso de privacidad no disponible. Verifica la conexión o solicita la configuración del aviso institucional.'),
                              TextButton(
                                onPressed: () => setState(() => _noticeFuture = _loadNotice()),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          );
                        }
                        final notice = snapshot.data;
                        if (notice == null) return const LinearProgressIndicator();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PrivacyNoticeView(notice: notice),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _acceptedHabeasData,
                              onChanged: ctrl.isSaving ? null : (value) {
                                setState(() => _acceptedHabeasData = value == true);
                              },
                              title: const Text('Entregué el aviso y el productor autorizó previamente el tratamiento de sus datos.'),
                            ),
                            if (_acceptedHabeasData)
                              TextFormField(
                                controller: _authorizationCtrl,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                  labelText: 'Referencia del soporte firmado o electrónico',
                                ),
                                validator: (value) => (value ?? '').trim().isEmpty
                                    ? 'Ingresa la referencia del soporte consultable.'
                                    : null,
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (_isEditing) ...[
                    Text(widget.existingProducer!.soporteAutorizacion == null
                        ? 'Autorización histórica. Verifica el soporte en el archivo de la asociación.'
                        : 'Soporte de autorización: ${widget.existingProducer!.soporteAutorizacion}'),
                    const SizedBox(height: 12),
                  ],
                  if (_isEditing || _acceptedHabeasData) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Código de asociado'),
                            TextFormField(
                              controller: _codeCtrl,
                              enabled: !ctrl.isSaving,
                              style: AppTheme.monoStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'ASO-001',
                              ),
                              validator: (String? v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Código requerido.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Cédula / Documento'),
                            TextFormField(
                              controller: _cedulaCtrl,
                              enabled: !ctrl.isSaving,
                              keyboardType: TextInputType.number,
                              style: AppTheme.monoStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: '1073500123',
                              ),
                              validator: (String? v) =>
                                  (v == null || v.trim().length < 5)
                                      ? 'Documento inválido.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Nombres'),
                            TextFormField(
                              controller: _nombresCtrl,
                              enabled: !ctrl.isSaving,
                              decoration: const InputDecoration(
                                hintText: 'Ej. José Luis',
                              ),
                              validator: (String? v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Ingresa los nombres.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Apellidos'),
                            TextFormField(
                              controller: _apellidosCtrl,
                              enabled: !ctrl.isSaving,
                              decoration: const InputDecoration(
                                hintText: 'Ej. Rodríguez López',
                              ),
                              validator: (String? v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Ingresa los apellidos.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Teléfono de contacto'),
                            TextFormField(
                              controller: _telefonoCtrl,
                              enabled: !ctrl.isSaving,
                              keyboardType: TextInputType.phone,
                              style: AppTheme.monoStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: '3101234567',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const _FieldLabel('Vereda'),
                            TextFormField(
                              controller: _veredaCtrl,
                              enabled: !ctrl.isSaving,
                              decoration: const InputDecoration(
                                hintText: 'Ej. La Glorieta',
                              ),
                              validator: (String? v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Ingresa la vereda.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Nombre de la finca'),
                  TextFormField(
                    controller: _fincaCtrl,
                    enabled: !ctrl.isSaving,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Finca El Porvenir',
                    ),
                    validator: (String? v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Ingresa el nombre de la finca.'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  // Estado operativo
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.canvasAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Productor activo',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Permite recibir entregas de leche en planta.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isActive,
                          activeTrackColor: AppTheme.primaryGreen,
                          onChanged: ctrl.isSaving
                              ? null
                              : (bool val) => setState(() => _isActive = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Acceso a aplicación móvil del productor (RF-07)
                  if (_alreadyLinked)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreenLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                            color: AppTheme.primaryGreen,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Este productor ya tiene acceso móvil vinculado para consultar entregas y pagos.',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.successText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Acceso móvil del productor',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Crea o vincula su usuario para consultar entregas y comprobantes en el celular.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _createMobileAccount,
                                activeTrackColor: AppTheme.inkBlack,
                                onChanged: ctrl.isSaving
                                    ? null
                                    : (bool val) => setState(
                                          () => _createMobileAccount = val,
                                        ),
                              ),
                            ],
                          ),
                          if (_createMobileAccount) ...<Widget>[
                            const SizedBox(height: 10),
                            const _FieldLabel('Correo electrónico de acceso'),
                            TextFormField(
                              controller: _mobileEmailCtrl,
                              enabled: !ctrl.isSaving,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'productor@correo.com',
                              ),
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
                                hintText: 'Mínimo 6 caracteres',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () =>
                                        _obscurePassword = !_obscurePassword,
                                  ),
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
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
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
                      label: _isEditing
                          ? 'Guardar cambios'
                          : 'Guardar productor',
                      fullWidth: false,
                      isLoading: ctrl.isSaving,
                      onPressed:
                          _acceptedHabeasData && !ctrl.isSaving ? _submit : null,
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
