import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';

/// Módulo administrativo de Usuarios de ASOPROGANUCOTT.
/// Cabecera editorial limpia con propiedades numéricas, barra de herramientas integrada y tabla completa.
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
      builder: (_) =>
          _UserFormDialog(actorUid: auth.currentUser?.uid ?? 'admin'),
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
        actorUid: auth.currentUser?.uid ?? 'admin',
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
      actorUid: auth.currentUser?.uid ?? 'admin',
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
      builder: (_) => _PasswordResetDialog(user: user),
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
            _buildEditorialHeader(ctrl, isNarrow),
            const SizedBox(height: 16),
            _buildToolbar(ctrl, isNarrow),
            const SizedBox(height: 14),
            if (ctrl.isLoading && ctrl.allUsers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: DairyLoader(
                    size: DairyLoaderSize.lg,
                    label: 'Cargando usuarios…',
                    hint: 'Un momento por favor.',
                  ),
                ),
              )
            else if (ctrl.filteredUsers.isEmpty)
              _buildEmptyState(ctrl)
            else
              _buildTableSection(ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorialHeader(UserController ctrl, bool isNarrow) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Usuarios', style: AppTheme.titleStyle(isMobile: isNarrow)),
        const SizedBox(height: 4),
        const Text(
          'Administra las cuentas del personal de planta y los productores asociados.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: ctrl.isLoading ? null : ctrl.loadUsers,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Actualizar'),
        ),
        PrimaryActionButton(
          label: 'Nuevo usuario',
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
        _UserSummaryStrip(ctrl: ctrl, isNarrow: isNarrow),
      ],
    );
  }

  Widget _buildToolbar(UserController ctrl, bool isNarrow) {
    final String countText = ctrl.filteredUsers.length == ctrl.allUsers.length
        ? '${ctrl.allUsers.length} ${ctrl.allUsers.length == 1 ? 'usuario' : 'usuarios'}'
        : '${ctrl.filteredUsers.length} de ${ctrl.allUsers.length}';

    final Widget searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        onChanged: ctrl.setSearchQuery,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, documento o correo…',
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

    final Widget roleDropdown = SizedBox(
      height: 36,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.roleFilter,
        prefixIcon: Icons.badge_outlined,
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'ALL', label: 'Todos los roles'),
          AppSelectOption<String>(
            value: AppConstants.roleAdmin,
            label: 'Administrador',
            icon: Icons.admin_panel_settings_outlined,
          ),
          AppSelectOption<String>(
            value: AppConstants.roleOperario,
            label: 'Operario',
            icon: Icons.engineering_outlined,
          ),
          AppSelectOption<String>(
            value: AppConstants.roleProductor,
            label: 'Productor',
            icon: Icons.agriculture_outlined,
          ),
        ],
        onChanged: ctrl.setRoleFilter,
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
            value: 'ACTIVE',
            label: 'Activos',
            icon: Icons.check_circle_outline_rounded,
          ),
          AppSelectOption<String>(
            value: 'INACTIVE',
            label: 'Suspendidos',
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
                Expanded(child: roleDropdown),
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
          SizedBox(width: 190, child: roleDropdown),
          const SizedBox(width: 8),
          SizedBox(width: 205, child: statusDropdown),
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

  Widget _buildEmptyState(UserController ctrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const AppIconBadge(
            icon: Icons.person_search_outlined,
            color: AppTheme.skyBlue,
            size: 52,
          ),
          const SizedBox(height: 12),
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
                : 'Crea el primer Administrador, Operario o Productor para gestionar el sistema.',
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
              label: 'Crear usuario',
              icon: Icons.add_rounded,
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
              label: 'Registro',
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
                  _UserAvatar(user: user),
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
              Text(user.documento, style: AppTheme.monoStyle(fontSize: 13)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.mail_outline_rounded,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    user.correo,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              _RoleBadge(rol: user.rol),
              InkWell(
                onTap: () => _toggleStatus(user),
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                child: _StatusPillButton(active: user.activo),
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
                  AppRowActionButton(
                    tooltip: 'Editar usuario',
                    icon: Icons.edit_outlined,
                    color: AppTheme.skyBlue,
                    onPressed: () => _openEditDialog(user),
                  ),
                  const SizedBox(width: 6),
                  AppRowActionButton(
                    tooltip: 'Enviar recuperación de contraseña',
                    icon: Icons.lock_reset_outlined,
                    color: AppTheme.warmGold,
                    onPressed: () => _sendPasswordReset(user),
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
          'Mostrando $start–$end de $total usuarios',
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
                options: const <int>[7, 15, 30]
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

class _UserSummaryStrip extends StatelessWidget {
  const _UserSummaryStrip({required this.ctrl, required this.isNarrow});

  final UserController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      AppMetricTile(
        title: 'Total usuarios',
        value: '${ctrl.totalCount}',
        subtitle: 'Registrados en plataforma',
        icon: Icons.people_outline_rounded,
        accentColor: AppTheme.skyBlue,
      ),
      AppMetricTile(
        title: 'Cuentas activas',
        value: '${ctrl.activeCount}',
        subtitle: 'Con acceso habilitado',
        icon: Icons.verified_user_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
        title: 'Personal de planta',
        value: '${ctrl.adminCount + ctrl.operarioCount}',
        subtitle: '${ctrl.adminCount} admin · ${ctrl.operarioCount} operarios',
        icon: Icons.badge_outlined,
        accentColor: AppTheme.warmGold,
      ),
      AppMetricTile(
        title: 'Productores',
        value: '${ctrl.productorCount}',
        subtitle: 'Asociados en campo',
        icon: Icons.agriculture_outlined,
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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.rol});

  final String rol;

  @override
  Widget build(BuildContext context) {
    final _RoleStyle style = _RoleStyle.of(rol);
    final bool admin = rol == AppConstants.roleAdmin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: admin ? AppTheme.inkBlack : style.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: admin
              ? AppTheme.inkBlack
              : style.color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(style.icon, size: 13, color: admin ? Colors.white : style.color),
          const SizedBox(width: 5),
          Text(
            AppConstants.roleShortLabel(rol),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: admin ? Colors.white : style.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final Color color = user.activo
        ? _RoleStyle.of(user.rol).color
        : AppTheme.textMuted;
    final bool admin = user.isAdmin && user.activo;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: admin ? AppTheme.inkBlack : color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: admin ? 1 : 0.3)),
      ),
      child: Text(
        user.initials,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: admin ? Colors.white : color,
        ),
      ),
    );
  }
}

class _StatusPillButton extends StatelessWidget {
  const _StatusPillButton({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color bg = active ? AppTheme.successBg : AppTheme.dangerBg;
    final Color fg = active ? AppTheme.successText : AppTheme.dangerText;
    final Color dot = active ? AppTheme.success : AppTheme.danger;

    return Tooltip(
      message: active ? 'Clic para suspender' : 'Clic para activar',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              active ? 'Activo' : 'Suspendido',
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

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.actorUid, this.existingUser});

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

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    IconData? icon,
    String? hint,
    String? helper,
    bool mono = false,
    bool obscure = false,
    Widget? suffix,
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
          obscureText: obscure,
          keyboardType: keyboardType,
          style: mono ? AppTheme.monoStyle(fontSize: 14) : null,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            prefixIcon: icon == null ? null : Icon(icon, size: 17),
            suffixIcon: suffix,
          ),
          validator: validator,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final UserController userCtrl = context.watch<UserController>();
    final bool enabled = !userCtrl.isSaving;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
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
                      ? Icons.manage_accounts_outlined
                      : Icons.person_add_alt_1_rounded,
                  title: _isEditing ? 'Editar usuario' : 'Nuevo usuario',
                  subtitle: _isEditing
                      ? 'Actualiza datos, rol o estado del usuario.'
                      : 'Completa los datos para habilitar el acceso al sistema.',
                  onClose: userCtrl.isSaving
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (userCtrl.errorMessage != null) ...<Widget>[
                        AppInlineNotice.danger(message: userCtrl.errorMessage!),
                        const SizedBox(height: 14),
                      ],
                      const _SectionTitle(
                        icon: Icons.badge_outlined,
                        title: 'Datos personales',
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Nombre completo',
                        controller: _nameCtrl,
                        enabled: enabled,
                        icon: Icons.person_outline_rounded,
                        hint: 'Ej. María Fernanda Gómez',
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
                            child: _field(
                              label: 'Cédula / Documento',
                              controller: _docCtrl,
                              enabled: enabled,
                              icon: Icons.credit_card_rounded,
                              hint: '1073500123',
                              mono: true,
                              keyboardType: TextInputType.number,
                              validator: (String? v) =>
                                  (v == null || v.trim().length < 5)
                                  ? 'Documento inválido.'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              label: 'Teléfono',
                              controller: _phoneCtrl,
                              enabled: enabled,
                              icon: Icons.phone_outlined,
                              hint: '3101234567',
                              mono: true,
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        icon: Icons.key_outlined,
                        title: 'Credenciales de acceso',
                      ),
                      const SizedBox(height: 10),
                      _field(
                        label: 'Correo electrónico',
                        controller: _emailCtrl,
                        enabled: !_isEditing && enabled,
                        icon: Icons.alternate_email_rounded,
                        hint: 'correo@asoproganucot.com',
                        helper: _isEditing
                            ? 'El correo de acceso no se puede modificar.'
                            : null,
                        suffix: _isEditing
                            ? const Icon(Icons.lock_outline_rounded, size: 16)
                            : null,
                        keyboardType: TextInputType.emailAddress,
                        validator: (String? v) {
                          if (v == null || !v.trim().contains('@')) {
                            return 'Ingresa un correo electrónico válido.';
                          }
                          return null;
                        },
                      ),
                      if (!_isEditing) ...<Widget>[
                        const SizedBox(height: 14),
                        _field(
                          label: 'Contraseña de acceso',
                          controller: _passwordCtrl,
                          enabled: enabled,
                          icon: Icons.lock_outline_rounded,
                          hint: 'Mínimo 6 caracteres',
                          obscure: _obscurePassword,
                          suffix: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
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
                          validator: (String? v) => (v == null || v.length < 6)
                              ? 'Debe tener al menos 6 caracteres.'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Rol y estado',
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final bool stack = c.maxWidth < 420;
                          final List<Widget>
                          options = AppConstants.allRoles.map((String role) {
                            final Widget tile = _RoleOptionTile(
                              role: role,
                              selected: _selectedRole == role,
                              onTap: userCtrl.isSaving
                                  ? null
                                  : () => setState(() => _selectedRole = role),
                            );
                            return stack
                                ? Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: tile,
                                  )
                                : Expanded(child: tile);
                          }).toList();
                          if (stack) return Column(children: options);
                          final List<Widget> spaced = <Widget>[];
                          for (int i = 0; i < options.length; i++) {
                            if (i > 0) spaced.add(const SizedBox(width: 8));
                            spaced.add(options[i]);
                          }
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: spaced,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      AppToggleCard(
                        icon: _isActive
                            ? Icons.verified_user_outlined
                            : Icons.block_rounded,
                        color: _isActive
                            ? AppTheme.primaryGreen
                            : AppTheme.textMuted,
                        title: 'Cuenta activa',
                        subtitle: 'Permite el ingreso al sistema según su rol.',
                        value: _isActive,
                        onChanged: userCtrl.isSaving
                            ? null
                            : (bool val) => setState(() => _isActive = val),
                      ),
                      const SizedBox(height: 10),
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: userCtrl.isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    PrimaryActionButton(
                      label: _isEditing ? 'Guardar cambios' : 'Crear usuario',
                      icon: Icons.check_rounded,
                      fullWidth: false,
                      isLoading: userCtrl.isSaving,
                      onPressed: _save,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: AppTheme.primaryGreen),
        const SizedBox(width: 7),
        Text(title, style: AppTheme.subtitleStyle()),
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Apariencia (ícono, color y descripción) de cada rol del sistema.
class _RoleStyle {
  const _RoleStyle(this.icon, this.color, this.description);

  final IconData icon;
  final Color color;
  final String description;

  static _RoleStyle of(String role) {
    switch (role) {
      case AppConstants.roleAdmin:
        return const _RoleStyle(
          Icons.admin_panel_settings_outlined,
          AppTheme.inkBlack,
          'Gestión completa del sistema',
        );
      case AppConstants.roleOperario:
        return const _RoleStyle(
          Icons.engineering_outlined,
          AppTheme.primaryGreen,
          'Recepción de leche en planta',
        );
      default:
        return const _RoleStyle(
          Icons.agriculture_outlined,
          AppTheme.indigoAccent,
          'Consulta móvil de entregas y pagos',
        );
    }
  }
}

class _RoleOptionTile extends StatefulWidget {
  const _RoleOptionTile({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final String role;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_RoleOptionTile> createState() => _RoleOptionTileState();
}

class _RoleOptionTileState extends State<_RoleOptionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final _RoleStyle style = _RoleStyle.of(widget.role);
    final bool sel = widget.selected;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel
                  ? style.color.withValues(alpha: 0.07)
                  : (_hover ? AppTheme.canvasAlt : AppTheme.surface),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
              border: Border.all(
                color: sel ? style.color : AppTheme.border,
                width: sel ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppIconBadge(
                      icon: style.icon,
                      color: style.color,
                      size: 30,
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: sel ? 1 : 0,
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: style.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppConstants.roleLabel(widget.role),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  style.description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordResetDialog extends StatelessWidget {
  const _PasswordResetDialog({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDialogHeader(
                icon: Icons.lock_reset_rounded,
                color: AppTheme.warmGold,
                title: 'Restablecer contraseña',
                subtitle: 'Se enviará un enlace seguro al correo del usuario.',
                onClose: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 16),
              AppInfoPanel(
                children: <Widget>[
                  AppInfoRow(label: 'Usuario', value: user.nombreCompleto),
                  AppInfoRow(label: 'Correo', value: user.correo),
                  AppInfoRow(
                    label: 'Rol',
                    value: AppConstants.roleLabel(user.rol),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '¿Enviar correo de restablecimiento de contraseña a ${user.correo}?',
                style: const TextStyle(
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
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Enviar enlace'),
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
