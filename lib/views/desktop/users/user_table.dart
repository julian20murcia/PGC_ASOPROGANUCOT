import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/security/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/pro_ui.dart';
import '../reports/activity_widgets.dart';

enum UserRowAction { edit, permissions, activity, resetPassword, toggleStatus }

Tone roleTone(String role) => switch (role) {
  AppConstants.roleAdmin => Tone.brand,
  AppConstants.roleOperario => Tone.info,
  _ => Tone.accent,
};

/// Qué acciones del menú puede ver el usuario actual sobre [target].
class UserRowPermissions {
  const UserRowPermissions({required this.canEdit, required this.canSuspend, required this.canSeeActivity});

  final bool canEdit;
  final bool canSuspend;
  final bool canSeeActivity;
}

class _Col {
  const _Col(this.label, this.flex);
  final String label;
  final int flex;
}

const List<_Col> _cols = <_Col>[
  _Col('Usuario', 5),
  _Col('Documento', 2),
  _Col('Correo', 4),
  _Col('Rol', 2),
  _Col('Estado', 2),
  _Col('Último acceso', 2),
  _Col('Permisos', 2),
];

/// Tabla compacta de usuarios.
class UserTable extends StatelessWidget {
  const UserTable({super.key, required this.users, required this.me, required this.perms, required this.onAction});

  final List<UserModel> users;
  final UserModel? me;
  final UserRowPermissions perms;
  final void Function(UserModel user, UserRowAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double minWidth = 940;
        final bool scroll = c.maxWidth < minWidth;
        final Widget table = SizedBox(
          width: scroll ? minWidth : c.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  border: Border(bottom: BorderSide(color: AppTheme.dividerLight)),
                ),
                child: Row(
                  children: <Widget>[
                    for (final _Col col in _cols) Expanded(flex: col.flex, child: DataHeaderCell(col.label)),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              for (final UserModel u in users)
                _UserRow(user: u, isMe: me?.uid == u.uid, perms: perms, onAction: onAction),
            ],
          ),
        );
        return scroll ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table) : table;
      },
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({required this.user, required this.isMe, required this.perms, required this.onAction});
  final UserModel user;
  final bool isMe;
  final UserRowPermissions perms;
  final void Function(UserModel user, UserRowAction action) onAction;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final UserModel u = widget.user;
    final TextStyle cell = AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary);
    Widget text(String s, {TextStyle? style}) =>
        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style ?? cell);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 46,
        padding: const EdgeInsets.only(left: 16, right: 4),
        decoration: BoxDecoration(
          color: _hover ? AppTheme.surfaceMuted : AppTheme.surface,
          border: const Border(bottom: BorderSide(color: AppTheme.dividerLight)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: _cols[0].flex,
              child: Row(
                children: <Widget>[
                  InitialsAvatar(u.nombreCompleto, size: 28),
                  const SizedBox(width: 10),
                  Flexible(
                    child: text(u.nombreCompleto, style: cell.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  if (widget.isMe) ...<Widget>[const SizedBox(width: 6), const StatusBadge('Tú', tone: Tone.neutral)],
                ],
              ),
            ),
            Expanded(
              flex: _cols[1].flex,
              child: text(u.documento, style: AppTheme.monoStyle(fontSize: 12.5)),
            ),
            Expanded(
              flex: _cols[2].flex,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: text(u.correo, style: cell.copyWith(color: AppTheme.textSecondary)),
              ),
            ),
            Expanded(
              flex: _cols[3].flex,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(AppConstants.roleShortLabel(u.rol), tone: roleTone(u.rol)),
              ),
            ),
            Expanded(
              flex: _cols[4].flex,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  u.activo ? 'Activo' : 'Suspendido',
                  tone: u.activo ? Tone.success : Tone.danger,
                  dot: true,
                ),
              ),
            ),
            Expanded(
              flex: _cols[5].flex,
              child: Tooltip(
                message: u.ultimoAcceso == null
                    ? 'Nunca ha iniciado sesión'
                    : 'Último acceso: ${_full(u.ultimoAcceso!)}',
                child: text(
                  relativeTimeLabel(u.ultimoAcceso),
                  style: cell.copyWith(color: u.ultimoAcceso == null ? AppTheme.textMuted : AppTheme.textSecondary),
                ),
              ),
            ),
            Expanded(
              flex: _cols[6].flex,
              child: _PermSummary(user: u),
            ),
            SizedBox(width: 40, child: _menu(context, u)),
          ],
        ),
      ),
    );
  }

  Widget _menu(BuildContext context, UserModel u) {
    final UserRowPermissions p = widget.perms;
    final List<PopupMenuEntry<UserRowAction>> items = <PopupMenuEntry<UserRowAction>>[
      if (p.canEdit) _item(UserRowAction.edit, Icons.edit_outlined, 'Editar datos'),
      if (p.canEdit && u.rol == AppConstants.roleOperario)
        _item(UserRowAction.permissions, Icons.admin_panel_settings_outlined, 'Permisos'),
      if (p.canSeeActivity) _item(UserRowAction.activity, Icons.manage_search_rounded, 'Ver actividad'),
      if (p.canEdit)
        _item(UserRowAction.resetPassword, Icons.mark_email_read_outlined, 'Restablecer contraseña (correo)'),
      if (p.canSuspend && !widget.isMe) ...<PopupMenuEntry<UserRowAction>>[
        const PopupMenuDivider(height: 8),
        _item(
          UserRowAction.toggleStatus,
          u.activo ? Icons.block_rounded : Icons.check_circle_outline_rounded,
          u.activo ? 'Suspender cuenta' : 'Activar cuenta',
          danger: u.activo,
        ),
      ],
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<UserRowAction>(
      key: ValueKey<String>('user-menu-${u.uid}'),
      tooltip: 'Acciones',
      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AppTheme.textSecondary),
      position: PopupMenuPosition.under,
      onSelected: (UserRowAction a) => widget.onAction(u, a),
      itemBuilder: (_) => items,
    );
  }

  PopupMenuItem<UserRowAction> _item(UserRowAction a, IconData icon, String label, {bool danger = false}) {
    final Color c = danger ? AppTheme.dangerText : AppTheme.textPrimary;
    return PopupMenuItem<UserRowAction>(
      value: a,
      height: 38,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: danger ? AppTheme.danger : AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: AppTheme.bodyStyle(fontSize: 13, color: c)),
        ],
      ),
    );
  }

  static String _full(DateTime d) {
    final DateTime l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _PermSummary extends StatelessWidget {
  const _PermSummary({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    if (user.isAdmin) {
      return Text(
        'Acceso total',
        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.brand, fontWeight: FontWeight.w600),
      );
    }
    if (user.isProductor) {
      return Text('Solo app móvil', style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted));
    }
    final int n = Permissions.countGranted(user.effectivePermissions);
    final int total = Permissions.totalActions;
    return Tooltip(
      message: user.permisos == null ? 'Permisos predeterminados del rol' : 'Permisos personalizados',
      child: Row(
        children: <Widget>[
          Text('$n/$total', style: AppTheme.monoStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : n / total,
                minHeight: 4,
                color: user.permisos == null ? AppTheme.brandMuted : AppTheme.brand,
                backgroundColor: AppTheme.surfaceSunken,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
