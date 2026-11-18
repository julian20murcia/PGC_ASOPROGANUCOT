import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/design_system_widgets.dart';

/// Módulo administrativo completo de Usuarios (RF-01, RF-02, RF-03).
/// Permite listar, buscar, filtrar, crear en Firebase Auth + Firestore, editar,
/// activar/suspender y enviar restablecimiento de contraseña.
class UsersModuleView extends StatefulWidget {
  const UsersModuleView({super.key});

  @override
  State<UsersModuleView> createState() => _UsersModuleViewState();
}

class _UsersModuleViewState extends State<UsersModuleView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserController>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreateDialog() async {
    final AuthController auth = context.read<AuthController>();
    final UserController userCtrl = context.read<UserController>();
    userCtrl.clearFeedback();

    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(
        actorUid: auth.currentUser?.uid ?? 'bootstrap-admin',
      ),
    );
    if (created == true && mounted) {
      _showToast(userCtrl.feedbackMessage ?? 'Usuario creado correctamente.');
    }
  }

  Future<void> _openEditDialog(UserModel user) async {
    final AuthController auth = context.read<AuthController>();
    final UserController userCtrl = context.read<UserController>();
    userCtrl.clearFeedback();

    final bool? updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(
        actorUid: auth.currentUser?.uid ?? 'bootstrap-admin',
        existingUser: user,
      ),
    );
    if (updated == true && mounted) {
      _showToast(userCtrl.feedbackMessage ?? 'Usuario actualizado.');
    }
  }

  Future<void> _toggleStatus(UserModel user) async {
    final AuthController auth = context.read<AuthController>();
    final UserController userCtrl = context.read<UserController>();
    final bool ok = await userCtrl.toggleUserStatus(
      user: user,
      actorUid: auth.currentUser?.uid ?? 'bootstrap-admin',
    );
    if (!mounted) return;
    _showToast(
      ok
          ? (userCtrl.feedbackMessage ?? 'Estado actualizado.')
          : (userCtrl.errorMessage ?? 'No fue posible actualizar el estado.'),
      isError: !ok,
    );
  }

  Future<void> _sendPasswordReset(UserModel user) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Restablecer contraseña'),
          content: Text(
            '¿Enviar correo de restablecimiento de contraseña a ${user.correo}?',
          ),
          actions: <Widget>[
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Enviar enlace'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final UserController userCtrl = context.read<UserController>();
    final bool ok = await userCtrl.sendPasswordReset(user.correo);
    if (!mounted) return;
    _showToast(
      ok
          ? (userCtrl.feedbackMessage ?? 'Enlace enviado.')
          : (userCtrl.errorMessage ?? 'Error al enviar enlace.'),
      isError: !ok,
    );
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.cowBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserController ctrl = context.watch<UserController>();
    final bool isNarrow = MediaQuery.of(context).size.width < 760;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isNarrow ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildHeader(ctrl, isNarrow),
          const SizedBox(height: 20),
          _buildKpis(ctrl),
          const SizedBox(height: 20),
          _buildFilterToolbar(ctrl, isNarrow),
          const SizedBox(height: 16),
          if (ctrl.isLoading && ctrl.allUsers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          else if (ctrl.filteredUsers.isEmpty)
            _buildEmptyState(ctrl)
          else
            _buildTableSection(ctrl),
        ],
      ),
    );
  }

  Widget _buildHeader(UserController ctrl, bool isNarrow) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            Text(
              'Gestión de Usuarios',
              style: AppTheme.titleStyle(isMobile: isNarrow),
            ),
            SyncStatusBadge(
              isSynced: !ctrl.isFromOfflineCache,
              syncedLabel: 'Sincronizado (Cloud)',
              pendingLabel: 'Caché local (Hive)',
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Administra cuentas de acceso en Firebase Auth y sus roles RBAC (Administrador, Operario y Productor).',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: ctrl.isLoading ? null : ctrl.loadUsers,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Actualizar'),
        ),
        PrimaryActionButton(
          label: 'Nuevo usuario',
          icon: Icons.person_add_alt_1_rounded,
          fullWidth: false,
          onPressed: _openCreateDialog,
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          titleBlock,
          const SizedBox(height: 16),
          actions,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }

  Widget _buildKpis(UserController ctrl) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 1000
            ? 4
            : width >= 560
                ? 2
                : 1;
        final double spacing = 12;
        final double cardWidth =
            (width - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            SizedBox(
              width: cardWidth,
              child: AppKpiCard(
                title: 'Total usuarios',
                value: '${ctrl.totalCount}',
                subtitle: '${ctrl.activeCount} cuentas activas',
                icon: Icons.groups_2_outlined,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AppKpiCard(
                title: 'Administradores',
                value: '${ctrl.adminCount}',
                subtitle: 'Control total en planta',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AppKpiCard(
                title: 'Operarios',
                value: '${ctrl.operarioCount}',
                subtitle: 'Recepción diaria de leche',
                icon: Icons.inventory_2_outlined,
                accentColor: AppTheme.primaryGreen,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: AppKpiCard(
                title: 'Productores',
                value: '${ctrl.productorCount}',
                subtitle: 'Acceso app móvil de consulta',
                icon: Icons.agriculture_outlined,
                accentColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterToolbar(UserController ctrl, bool isNarrow) {
    final Widget searchField = TextField(
      controller: _searchCtrl,
      onChanged: ctrl.setSearchQuery,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, documento, correo o teléfono...',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: ctrl.searchQuery.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchCtrl.clear();
                  ctrl.setSearchQuery('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              )
            : null,
      ),
    );

    final Widget roleDropdown = DropdownButtonFormField<String>(
      initialValue: ctrl.roleFilter,
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
          value: 'ALL',
          child: Text('Todos los roles', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: AppConstants.roleAdmin,
          child: Text('Administrador', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: AppConstants.roleOperario,
          child: Text('Operario', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: AppConstants.roleProductor,
          child: Text('Productor', overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: (String? value) {
        if (value != null) ctrl.setRoleFilter(value);
      },
    );

    final Widget statusDropdown = DropdownButtonFormField<String>(
      initialValue: ctrl.statusFilter,
      isExpanded: true,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
          value: 'ALL',
          child: Text('Todos los estados', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: 'ACTIVE',
          child: Text('Activos', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: 'INACTIVE',
          child: Text('Suspendidos', overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: (String? value) {
        if (value != null) ctrl.setStatusFilter(value);
      },
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: isNarrow
          ? Column(
              children: <Widget>[
                searchField,
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(child: roleDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: statusDropdown),
                  ],
                ),
                if (ctrl.hasActiveFilters) ...<Widget>[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _searchCtrl.clear();
                        ctrl.clearFilters();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                      label: const Text('Limpiar filtros'),
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: roleDropdown),
                const SizedBox(width: 12),
                SizedBox(width: 180, child: statusDropdown),
                if (ctrl.hasActiveFilters) ...<Widget>[
                  const SizedBox(width: 8),
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

  Widget _buildEmptyState(UserController ctrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_search_outlined,
              size: 26,
              color: AppTheme.cowBlack,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ctrl.hasActiveFilters
                ? 'No hay usuarios que coincidan con los filtros'
                : 'Aún no hay usuarios creados',
            style: AppTheme.subtitleStyle(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            ctrl.hasActiveFilters
                ? 'Prueba con otro documento, nombre o limpia los filtros activos.'
                : 'Crea el primer Administrador, Operario o Productor para usar el inicio de sesión con credenciales reales.',
            style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
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
              label: 'Crear primer usuario',
              icon: Icons.person_add_alt_1_rounded,
              fullWidth: false,
              onPressed: _openCreateDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildTableSection(UserController ctrl) {
    final List<UserModel> rows = ctrl.paginatedUsers;

    bool? sortIndicator(UserSortColumn column) =>
        ctrl.sortColumn == column ? ctrl.sortAscending : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CleanDataTable(
          columns: <CleanTableColumn>[
            CleanTableColumn(
              label: 'Usuario',
              sortAscending: sortIndicator(UserSortColumn.nombreCompleto),
              onSort: () => ctrl.toggleSort(UserSortColumn.nombreCompleto),
            ),
            CleanTableColumn(
              label: 'Documento',
              sortAscending: sortIndicator(UserSortColumn.documento),
              onSort: () => ctrl.toggleSort(UserSortColumn.documento),
            ),
            CleanTableColumn(
              label: 'Correo electrónico',
              sortAscending: sortIndicator(UserSortColumn.correo),
              onSort: () => ctrl.toggleSort(UserSortColumn.correo),
            ),
            CleanTableColumn(
              label: 'Rol',
              sortAscending: sortIndicator(UserSortColumn.rol),
              onSort: () => ctrl.toggleSort(UserSortColumn.rol),
            ),
            CleanTableColumn(
              label: 'Estado',
              sortAscending: sortIndicator(UserSortColumn.activo),
              onSort: () => ctrl.toggleSort(UserSortColumn.activo),
            ),
            CleanTableColumn(
              label: 'Creación',
              sortAscending: sortIndicator(UserSortColumn.fechaCreacion),
              onSort: () => ctrl.toggleSort(UserSortColumn.fechaCreacion),
            ),
            const CleanTableColumn(label: 'Acciones'),
          ],
          rows: rows.map((UserModel user) {
            return <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircleAvatar(
                    radius: 17,
                    backgroundColor:
                        user.isAdmin ? AppTheme.cowBlack : AppTheme.surfaceMuted,
                    child: Text(
                      user.initials,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: user.isAdmin ? Colors.white : AppTheme.cowBlack,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        user.nombreCompleto,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (user.telefono.isNotEmpty)
                        Text(
                          user.telefono,
                          style: AppTheme.monoStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Text(
                user.documento,
                style: AppTheme.monoStyle(fontSize: 13),
              ),
              Text(
                user.correo,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              _RoleBadge(rol: user.rol),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Switch(
                    value: user.activo,
                    activeThumbColor: AppTheme.cowBlack,
                    onChanged: (_) => _toggleStatus(user),
                  ),
                  const SizedBox(width: 4),
                  _StatusBadge(active: user.activo),
                ],
              ),
              Text(
                _dateFormat.format(user.fechaCreacion.toLocal()),
                style: AppTheme.monoStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Editar usuario',
                    onPressed: () => _openEditDialog(user),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Enviar recuperación de contraseña',
                    onPressed: () => _sendPasswordReset(user),
                    icon: const Icon(Icons.lock_reset_outlined, size: 19),
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

  Widget _buildPaginationBar(UserController ctrl) {
    final int total = ctrl.filteredUsers.length;
    final int start = total == 0 ? 0 : ((ctrl.currentPage - 1) * ctrl.itemsPerPage) + 1;
    final int end = (ctrl.currentPage * ctrl.itemsPerPage).clamp(0, total);

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        Text(
          'Mostrando $start–$end de $total usuarios',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButton<int>(
              value: ctrl.itemsPerPage,
              underline: const SizedBox.shrink(),
              items: const <int>[7, 15, 30]
                  .map(
                    (int size) => DropdownMenuItem<int>(
                      value: size,
                      child: Text(
                        '$size / pág.',
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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.rol});

  final String rol;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late Color border;

    switch (rol) {
      case AppConstants.roleAdmin:
        bg = AppTheme.cowBlack;
        fg = Colors.white;
        border = AppTheme.cowBlack;
        break;
      case AppConstants.roleOperario:
        bg = AppTheme.primaryGreenLight;
        fg = AppTheme.primaryGreen;
        border = AppTheme.primaryGreen.withValues(alpha: 0.25);
        break;
      default:
        bg = AppTheme.surfaceMuted;
        fg = AppTheme.textPrimary;
        border = AppTheme.border;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        border: Border.all(color: border),
      ),
      child: Text(
        AppConstants.roleShortLabel(rol),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppTheme.successBg : AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Text(
        active ? 'Activo' : 'Suspendido',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? AppTheme.successText : AppTheme.dangerText,
        ),
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.actorUid,
    this.existingUser,
  });

  final String actorUid;
  final UserModel? existingUser;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _docCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passwordCtrl;

  late String _selectedRole;
  late bool _isActive;
  bool _obscurePassword = true;

  bool get _isEditing => widget.existingUser != null;

  @override
  void initState() {
    super.initState();
    final UserModel? u = widget.existingUser;
    _nameCtrl = TextEditingController(text: u?.nombreCompleto ?? '');
    _docCtrl = TextEditingController(text: u?.documento ?? '');
    _emailCtrl = TextEditingController(text: u?.correo ?? '');
    _phoneCtrl = TextEditingController(text: u?.telefono ?? '');
    _passwordCtrl = TextEditingController();
    _selectedRole = u?.rol ?? AppConstants.roleAdmin;
    _isActive = u?.activo ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _docCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final UserController userCtrl = context.read<UserController>();
    bool ok;

    if (_isEditing) {
      ok = await userCtrl.updateUser(
        previousUser: widget.existingUser!,
        nombreCompleto: _nameCtrl.text,
        documento: _docCtrl.text,
        telefono: _phoneCtrl.text,
        rol: _selectedRole,
        activo: _isActive,
        actorUid: widget.actorUid,
      );
    } else {
      ok = await userCtrl.createUser(
        nombreCompleto: _nameCtrl.text,
        documento: _docCtrl.text,
        correo: _emailCtrl.text,
        telefono: _phoneCtrl.text,
        rol: _selectedRole,
        password: _passwordCtrl.text,
        activo: _isActive,
        actorUid: widget.actorUid,
      );
    }

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserController userCtrl = context.watch<UserController>();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.cowBlack,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isEditing
                              ? Icons.edit_outlined
                              : Icons.person_add_alt_1_rounded,
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
                              _isEditing ? 'Editar usuario' : 'Crear nuevo usuario',
                              style: AppTheme.subtitleStyle(),
                            ),
                            Text(
                              _isEditing
                                  ? 'Actualiza datos, rol o estado del usuario.'
                                  : 'Se registrará en Firebase Authentication y Cloud Firestore.',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: userCtrl.isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (userCtrl.errorMessage != null) ...<Widget>[
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
                        userCtrl.errorMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.dangerText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _FieldLabel('Nombre completo'),
                  TextFormField(
                    controller: _nameCtrl,
                    enabled: !userCtrl.isSaving,
                    decoration: const InputDecoration(
                      hintText: 'Ej. María Fernanda Gómez',
                    ),
                    validator: (String? v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Ingresa el nombre completo.'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel('Cédula / Documento'),
                            TextFormField(
                              controller: _docCtrl,
                              enabled: !userCtrl.isSaving,
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel('Teléfono'),
                            TextFormField(
                              controller: _phoneCtrl,
                              enabled: !userCtrl.isSaving,
                              keyboardType: TextInputType.phone,
                              style: AppTheme.monoStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: '3101234567',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _FieldLabel('Correo electrónico'),
                  TextFormField(
                    controller: _emailCtrl,
                    enabled: !_isEditing && !userCtrl.isSaving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'correo@asoproganucot.com',
                    ),
                    validator: (String? v) {
                      if (v == null || !v.trim().contains('@')) {
                        return 'Ingresa un correo electrónico válido.';
                      }
                      return null;
                    },
                  ),
                  if (!_isEditing) ...<Widget>[
                    const SizedBox(height: 14),
                    _FieldLabel('Contraseña de acceso'),
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !userCtrl.isSaving,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Mínimo 6 caracteres',
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                      validator: (String? v) =>
                          (v == null || v.length < 6)
                              ? 'Debe tener al menos 6 caracteres.'
                              : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _FieldLabel('Rol en el sistema (RBAC)'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppConstants.allRoles.map((String role) {
                      final bool selected = _selectedRole == role;
                      return ChoiceChip(
                        label: Text(AppConstants.roleLabel(role)),
                        selected: selected,
                        selectedColor: AppTheme.cowBlack,
                        backgroundColor: AppTheme.canvasAlt,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.textPrimary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selected
                                ? AppTheme.cowBlack
                                : AppTheme.inputBorder,
                          ),
                        ),
                        showCheckmark: false,
                        onSelected: userCtrl.isSaving
                            ? null
                            : (_) => setState(() => _selectedRole = role),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
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
                                'Cuenta activa',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Permite el ingreso al sistema según su rol.',
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
                          activeThumbColor: AppTheme.cowBlack,
                          onChanged: userCtrl.isSaving
                              ? null
                              : (bool val) => setState(() => _isActive = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: userCtrl.isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      PrimaryActionButton(
                        label: _isEditing ? 'Guardar cambios' : 'Crear usuario',
                        icon: Icons.check_rounded,
                        fullWidth: false,
                        isLoading: userCtrl.isSaving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
