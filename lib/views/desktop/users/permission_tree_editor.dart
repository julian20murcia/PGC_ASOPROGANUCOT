import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/security/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/pro_ui.dart';
import 'user_form_rules.dart';

/// Árbol de permisos por módulo con interruptor maestro y acciones.
///
/// * ADMIN: siempre tiene todo (árbol bloqueado con explicación).
/// * PRODUCTOR: no usa la plataforma de escritorio (árbol oculto).
/// * OPERARIO: editable; "Ver" se marca solo al marcar otra acción y
///   quitar "Ver" quita todo el módulo.
class PermissionTreeEditor extends StatelessWidget {
  const PermissionTreeEditor({
    super.key,
    required this.role,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });

  final String role;
  final Map<String, List<String>> value;
  final ValueChanged<Map<String, List<String>>> onChanged;
  final bool readOnly;

  bool get _locked => role == AppConstants.roleAdmin || readOnly;

  @override
  Widget build(BuildContext context) {
    if (role == AppConstants.roleProductor) {
      return const _Notice(
        icon: Icons.phone_android_rounded,
        tone: Tone.info,
        title: 'Los productores usan solo la app móvil',
        message: 'Una cuenta de productor no entra a la plataforma de escritorio, por eso no tiene '
            'permisos por módulo. Desde la app consulta sus entregas, liquidaciones y comunicados.',
      );
    }
    final Map<String, List<String>> effective = role == AppConstants.roleAdmin ? Permissions.full() : value;
    final int granted = Permissions.countGranted(effective);
    final bool isDefault = PermissionTree.equals(effective, Permissions.defaultsFor(role));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (role == AppConstants.roleAdmin) ...<Widget>[
          const _Notice(
            icon: Icons.verified_user_outlined,
            tone: Tone.brand,
            title: 'El administrador siempre tiene acceso total',
            message: 'Por seguridad sus permisos no se pueden recortar. Si esta persona no debe tener '
                'acceso completo, asígnale el rol Operario y elige sus permisos.',
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '$granted de ${Permissions.totalActions}',
                      style: AppTheme.monoStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: ' permisos concedidos',
                      style: AppTheme.bodyStyle(fontSize: 13),
                    ),
                    if (!_locked)
                      TextSpan(
                        text: isDefault ? ' · los del rol' : ' · personalizados',
                        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),
            ),
            if (!_locked) ...<Widget>[
              TextButton.icon(
                onPressed: isDefault ? null : () => onChanged(PermissionTree.normalize(Permissions.defaultsFor(role))),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Restablecer a permisos del rol'),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                key: const ValueKey<String>('perm-all'),
                onPressed: () => onChanged(PermissionTree.all()),
                child: const Text('Todo'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                key: const ValueKey<String>('perm-none'),
                onPressed: () => onChanged(PermissionTree.none()),
                child: const Text('Nada'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < Permissions.modules.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1),
                _ModuleRow(
                  module: Permissions.modules[i],
                  perms: effective,
                  locked: _locked,
                  onChanged: onChanged,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.module,
    required this.perms,
    required this.locked,
    required this.onChanged,
  });

  final PermModule module;
  final Map<String, List<String>> perms;
  final bool locked;
  final ValueChanged<Map<String, List<String>>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ModuleGrant grant = PermissionTree.moduleGrant(perms, module.key);
    final int n = perms[module.key]?.length ?? 0;
    final bool on = grant != ModuleGrant.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: on ? AppTheme.brandSoft : AppTheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(module.icon, size: 16, color: on ? AppTheme.brand : AppTheme.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(module.label, style: AppTheme.subtitleStyle().copyWith(fontSize: 13.5)),
                    Text(
                      module.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              if (grant == ModuleGrant.partial)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StatusBadge('$n de ${module.actions.length}', tone: Tone.accent),
                ),
              TriStateSwitch(
                key: ValueKey<String>('perm-master-${module.key}'),
                state: grant,
                onTap: locked ? null : () => onChanged(PermissionTree.tapModule(perms, module.key)),
              ),
            ],
          ),
          if (module.actions.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String a in module.actions)
                    _ActionCheck(
                      key: ValueKey<String>('perm-${module.key}-$a'),
                      label: PermAction.label(a),
                      hint: module.actionHints[a] ??
                          (a == PermAction.ver ? 'Entrar al módulo y consultar' : null),
                      value: PermissionTree.has(perms, module.key, a),
                      onChanged: locked
                          ? null
                          : (bool v) => onChanged(PermissionTree.toggleAction(perms, module.key, a, v)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionCheck extends StatelessWidget {
  const _ActionCheck({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    return Material(
      color: value ? AppTheme.brandSoft : AppTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: value ? AppTheme.brandMuted : AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: value,
                  onChanged: enabled ? (bool? v) => onChanged!(v ?? false) : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted),
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

/// Interruptor de tres estados (nada / parcial / todo).
class TriStateSwitch extends StatelessWidget {
  const TriStateSwitch({super.key, required this.state, this.onTap});

  final ModuleGrant state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color track = switch (state) {
      ModuleGrant.none => AppTheme.borderStrong,
      ModuleGrant.partial => AppTheme.brandMuted,
      ModuleGrant.all => AppTheme.brand,
    };
    final Alignment align = switch (state) {
      ModuleGrant.none => Alignment.centerLeft,
      ModuleGrant.partial => Alignment.center,
      ModuleGrant.all => Alignment.centerRight,
    };
    return Semantics(
      toggled: state == ModuleGrant.all,
      mixed: state == ModuleGrant.partial,
      button: true,
      label: switch (state) {
        ModuleGrant.none => 'Sin acceso',
        ModuleGrant.partial => 'Acceso parcial',
        ModuleGrant.all => 'Acceso total',
      },
      child: Tooltip(
        message: switch (state) {
          ModuleGrant.all => 'Quitar todo el módulo',
          _ => 'Conceder todo el módulo',
        },
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: Opacity(
              opacity: enabled ? 1 : 0.55,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 38,
                height: 22,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(11)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  alignment: align,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle),
                    child: state == ModuleGrant.partial
                        ? Center(
                            child: Container(width: 7, height: 2, color: AppTheme.brand),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.tone, required this.title, required this.message});
  final IconData icon;
  final Tone tone;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: tone.fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTheme.subtitleStyle(color: tone.fg).copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(message, style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
