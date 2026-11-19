import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/pro_ui.dart';
import 'reports/activity_tab.dart' show canReadActivity;
import 'users/user_activity_panel.dart';
import 'users/user_form_dialog.dart';
import 'users/user_table.dart';

/// Módulo "Usuarios y permisos": cuentas de acceso, roles, árbol de
/// permisos por módulo y actividad de cada persona.
class UsersModuleView extends StatefulWidget {
  const UsersModuleView({super.key});

  @override
  State<UsersModuleView> createState() => _UsersModuleViewState();
}

class _UsersModuleViewState extends State<UsersModuleView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserController>().loadUsers();
    });
  }

  Future<void> _create() async {
    final UserController uc = context.read<UserController>();
    uc.clearFeedback();
    final bool ok = await showUserFormDialog(context);
    if (ok && mounted) {
      showAppToast(context, uc.feedbackMessage ?? 'Usuario creado correctamente.', tone: Tone.success);
    }
  }

  Future<void> _onAction(UserModel u, UserRowAction action) async {
    final UserController uc = context.read<UserController>();
    final UserModel? me = context.read<AuthController>().currentUser;
    switch (action) {
      case UserRowAction.edit:
      case UserRowAction.permissions:
        uc.clearFeedback();
        final bool ok = await showUserFormDialog(
          context,
          user: u,
          initialStep: action == UserRowAction.permissions ? 2 : 0,
        );
        if (ok && mounted) {
          showAppToast(context, uc.feedbackMessage ?? 'Usuario actualizado.', tone: Tone.success);
        }
      case UserRowAction.activity:
        await showUserActivityPanel(context, u);
      case UserRowAction.resetPassword:
        final bool confirm = await confirmAction(
          context,
          title: 'Restablecer contraseña',
          message: 'Se enviará a ${u.correo} un enlace para que ${u.nombreCompleto} cree una contraseña nueva. '
              'Su contraseña actual seguirá funcionando hasta que la cambie.',
          confirmLabel: 'Enviar enlace',
        );
        if (!confirm || !mounted) return;
        final bool ok = await uc.sendPasswordReset(u.correo);
        if (!mounted) return;
        showAppToast(
          context,
          ok ? (uc.feedbackMessage ?? 'Enlace enviado.') : (uc.errorMessage ?? 'No se pudo enviar el enlace.'),
          tone: ok ? Tone.success : Tone.danger,
        );
      case UserRowAction.toggleStatus:
        final bool suspending = u.activo;
        final bool confirm = await confirmAction(
          context,
          title: suspending ? 'Suspender cuenta' : 'Activar cuenta',
          message: suspending
              ? '${u.nombreCompleto} no podrá iniciar sesión y se cerrarán sus sesiones abiertas. '
                  'Su historial se conserva y puedes reactivarla cuando quieras.'
              : '${u.nombreCompleto} podrá volver a iniciar sesión con sus permisos actuales.',
          confirmLabel: suspending ? 'Suspender' : 'Activar',
          destructive: suspending,
        );
        if (!confirm || !mounted) return;
        final bool ok = await uc.toggleUserStatus(user: u, actorUid: me?.uid ?? '');
        if (!mounted) return;
        showAppToast(
          context,
          ok ? (uc.feedbackMessage ?? 'Estado actualizado.') : (uc.errorMessage ?? 'No se pudo cambiar el estado.'),
          tone: ok ? Tone.success : Tone.danger,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserController uc = context.watch<UserController>();
    final UserModel? me = context.watch<AuthController>().currentUser;
    final bool canCreate = me?.can(Permissions.usuarios, PermAction.crear) ?? false;
    final UserRowPermissions rowPerms = UserRowPermissions(
      canEdit: me?.can(Permissions.usuarios, PermAction.editar) ?? false,
      canSuspend: me?.can(Permissions.usuarios, PermAction.eliminar) ?? false,
      canSeeActivity: canReadActivity(me),
    );
    final bool narrow = MediaQuery.sizeOf(context).width < 900;
    final List<UserModel> page = uc.paginatedUsers;
    final int filteredCount = uc.filteredUsers.length;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              title: 'Usuarios y permisos',
              subtitle: 'Quién entra a la plataforma, con qué rol y qué puede hacer en cada módulo.',
              actions: <Widget>[
                OutlinedButton.icon(
                  onPressed: uc.isLoading ? null : uc.loadUsers,
                  icon: uc.isLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Actualizar'),
                ),
                if (canCreate)
                  FilledButton.icon(
                    key: const ValueKey<String>('users-new'),
                    onPressed: _create,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                    label: const Text('Nuevo usuario'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            StatStrip(
              items: <StatItem>[
                StatItem(label: 'Usuarios', value: '${uc.totalCount}', icon: Icons.people_alt_outlined),
                StatItem(
                  label: 'Activos',
                  value: '${uc.activeCount}',
                  hint: '${uc.totalCount - uc.activeCount} suspendidos',
                  icon: Icons.verified_user_outlined,
                  tone: Tone.success,
                ),
                StatItem(
                  label: 'Administradores',
                  value: '${uc.adminCount}',
                  icon: Icons.admin_panel_settings_outlined,
                ),
                StatItem(label: 'Operarios', value: '${uc.operarioCount}', icon: Icons.engineering_outlined, tone: Tone.info),
                StatItem(
                  label: 'Productores con app',
                  value: '${uc.productorCount}',
                  icon: Icons.phone_android_rounded,
                  tone: Tone.accent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (uc.isFromOfflineCache) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warningBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.cloud_off_rounded, size: 17, color: AppTheme.warningText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sin conexión: se muestra la última copia guardada. Crear o editar usuarios requiere internet.',
                        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.warningText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        AppSearchField(
                          hint: 'Buscar por nombre, documento o correo…',
                          initialValue: uc.searchQuery,
                          width: 300,
                          onChanged: uc.setSearchQuery,
                        ),
                        SizedBox(
                          width: 190,
                          child: AppSelect<String>(
                            dense: true,
                            value: uc.roleFilter,
                            prefixIcon: Icons.badge_outlined,
                            options: <AppSelectOption<String>>[
                              const AppSelectOption<String>(value: 'ALL', label: 'Todos los roles'),
                              for (final String r in AppConstants.allRoles)
                                AppSelectOption<String>(value: r, label: AppConstants.roleShortLabel(r)),
                            ],
                            onChanged: uc.setRoleFilter,
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: AppSelect<String>(
                            dense: true,
                            value: uc.statusFilter,
                            prefixIcon: Icons.toggle_on_outlined,
                            options: const <AppSelectOption<String>>[
                              AppSelectOption<String>(value: 'ALL', label: 'Todos los estados'),
                              AppSelectOption<String>(value: 'ACTIVE', label: 'Activos'),
                              AppSelectOption<String>(value: 'INACTIVE', label: 'Suspendidos'),
                            ],
                            onChanged: uc.setStatusFilter,
                          ),
                        ),
                        if (uc.hasActiveFilters)
                          TextButton.icon(
                            onPressed: uc.clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                            label: const Text('Limpiar'),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '$filteredCount ${filteredCount == 1 ? 'usuario' : 'usuarios'}',
                            style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (uc.isLoading && uc.allUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (uc.errorMessage != null && uc.allUsers.isEmpty)
                    EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'No se pudieron cargar los usuarios',
                      message: uc.errorMessage,
                      action: OutlinedButton(onPressed: uc.loadUsers, child: const Text('Reintentar')),
                    )
                  else if (page.isEmpty)
                    EmptyState(
                      icon: Icons.person_search_outlined,
                      title: uc.hasActiveFilters ? 'Ningún usuario coincide' : 'Aún no hay usuarios',
                      message: uc.hasActiveFilters
                          ? 'Prueba con otra búsqueda o limpia los filtros.'
                          : 'Crea la primera cuenta con el botón "Nuevo usuario".',
                    )
                  else
                    UserTable(users: page, me: me, perms: rowPerms, onAction: _onAction),
                  if (uc.totalPages > 1) _Pagination(uc: uc),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.uc});
  final UserController uc;

  @override
  Widget build(BuildContext context) {
    final int total = uc.filteredUsers.length;
    final int start = (uc.currentPage - 1) * uc.itemsPerPage + 1;
    final int end = (start + uc.itemsPerPage - 1).clamp(0, total);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Mostrando $start–$end de $total',
              style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          IconButton(
            tooltip: 'Página anterior',
            visualDensity: VisualDensity.compact,
            onPressed: uc.currentPage <= 1 ? null : () => uc.setPage(uc.currentPage - 1),
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Text('${uc.currentPage} / ${uc.totalPages}', style: AppTheme.monoStyle(fontSize: 12)),
          IconButton(
            tooltip: 'Página siguiente',
            visualDensity: VisualDensity.compact,
            onPressed: uc.currentPage >= uc.totalPages ? null : () => uc.setPage(uc.currentPage + 1),
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
