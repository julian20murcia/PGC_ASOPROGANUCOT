import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';

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
      builder: (_) => _UserFormDialog(
        actorUid: auth.currentUser?.uid ?? 'admin',
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
        Text(
          'Usuarios',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
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

    final Widget roleDropdown = SizedBox(
      height: 36,
      child: DropdownButtonFormField<String>(
        initialValue: ctrl.roleFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          SizedBox(width: 175, child: roleDropdown),
          const SizedBox(width: 8),
          SizedBox(width: 168, child: statusDropdown),
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
          const Icon(
            Icons.person_search_outlined,
            size: 32,
            color: AppTheme.cowBlack,
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
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        user.isAdmin ? AppTheme.cowBlack : AppTheme.surfaceMuted,
                    child: Text(
                      user.initials,
                      style: TextStyle(
                        fontSize: 11.5,
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
                  IconButton(
                    tooltip: 'Editar usuario',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openEditDialog(user),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Enviar recuperación de contraseña',
                    visualDensity: VisualDensity.compact,
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

class _UserSummaryStrip extends StatelessWidget {
  const _UserSummaryStrip({
    required this.ctrl,
    required this.isNarrow,
  });

  final UserController ctrl;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      _UserMetricCard(
        title: 'Total usuarios',
        value: '${ctrl.totalCount}',
        subtitle: 'Registrados en plataforma',
        icon: Icons.people_outline_rounded,
        accentColor: AppTheme.skyBlue,
      ),
      _UserMetricCard(
        title: 'Cuentas activas',
        value: '${ctrl.activeCount}',
        subtitle: 'Con acceso habilitado',
        icon: Icons.verified_user_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      _UserMetricCard(
        title: 'Personal de planta',
        value: '${ctrl.adminCount + ctrl.operarioCount}',
        subtitle: '${ctrl.adminCount} admin · ${ctrl.operarioCount} operarios',
        icon: Icons.badge_outlined,
        accentColor: AppTheme.warmGold,
      ),
      _UserMetricCard(
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

class _UserMetricCard extends StatelessWidget {
  const _UserMetricCard({
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
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
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
                              _isEditing ? 'Editar usuario' : 'Nuevo usuario',
                              style: AppTheme.subtitleStyle(),
                            ),
                            Text(
                              _isEditing
                                  ? 'Actualiza datos, rol o estado del usuario.'
                                  : 'Completa los datos para habilitar el acceso al sistema.',
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
                  const _FieldLabel('Nombre completo'),
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
                            const _FieldLabel('Cédula / Documento'),
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
                            const _FieldLabel('Teléfono'),
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
                  const _FieldLabel('Correo electrónico'),
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
                    const _FieldLabel('Contraseña de acceso'),
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
                  const _FieldLabel('Rol del usuario'),
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
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusPill),
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
                      borderRadius: BorderRadius.circular(10),
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
