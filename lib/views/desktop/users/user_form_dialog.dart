import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/producer_controller.dart';
import '../../../controllers/user_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/security/permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/producer_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/pro_ui.dart';
import 'permission_tree_editor.dart';
import 'user_form_rules.dart';

/// Abre el asistente de creación/edición. Devuelve true si se guardó.
Future<bool> showUserFormDialog(BuildContext context, {UserModel? user, int initialStep = 0}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UserFormDialog(existingUser: user, initialStep: initialStep),
  );
  return ok ?? false;
}

class UserFormDialog extends StatefulWidget {
  const UserFormDialog({super.key, this.existingUser, this.initialStep = 0});

  final UserModel? existingUser;
  final int initialStep;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _RoleOption {
  const _RoleOption(this.role, this.title, this.description, this.icon);
  final String role;
  final String title;
  final String description;
  final IconData icon;
}

const List<_RoleOption> _roles = <_RoleOption>[
  _RoleOption(
    AppConstants.roleAdmin,
    'Administrador',
    'Acceso total: usuarios, tarifas, cierres de quincena, reportes y configuración.',
    Icons.admin_panel_settings_outlined,
  ),
  _RoleOption(
    AppConstants.roleOperario,
    'Operario',
    'Trabaja en planta: registra entregas y consulta lo que le permitas módulo por módulo.',
    Icons.engineering_outlined,
  ),
  _RoleOption(
    AppConstants.roleProductor,
    'Productor',
    'Usa la app móvil para ver sus entregas, liquidaciones y comunicados.',
    Icons.agriculture_outlined,
  ),
];

const List<String> _stepLabels = <String>['Datos', 'Rol', 'Permisos', 'Revisar'];

class _UserFormDialogState extends State<UserFormDialog> {
  final GlobalKey<FormState> _dataForm = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _doc;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  late int _step;
  late String _role;
  late bool _active;
  late Map<String, List<String>> _perms;
  late final Map<String, List<String>> _initialPerms;
  String? _productorId;
  String? _error;
  String? _stepError;
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.existingUser != null;

  UserModel? get _actor {
    try {
      return context.read<AuthController>().currentUser;
    } on ProviderNotFoundException {
      return null;
    }
  }

  bool get _isSelf => _isEdit && _actor?.uid == widget.existingUser!.uid;

  @override
  void initState() {
    super.initState();
    final UserModel? u = widget.existingUser;
    _name = TextEditingController(text: u?.nombreCompleto ?? '');
    _doc = TextEditingController(text: u?.documento ?? '');
    _email = TextEditingController(text: u?.correo ?? '');
    _phone = TextEditingController(text: u?.telefono ?? '');
    _role = u?.rol ?? AppConstants.roleOperario;
    _active = u?.activo ?? true;
    _perms = PermissionTree.normalize(u?.effectivePermissions ?? Permissions.defaultsFor(_role));
    _initialPerms = PermissionTree.copy(_perms);
    _step = widget.initialStep.clamp(0, 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final ProducerController pc = context.read<ProducerController>();
        if (pc.allProducers.isEmpty && !pc.isLoading) pc.loadProducers();
      } on ProviderNotFoundException {
        // Sin productores disponibles para vincular.
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _doc.dispose();
    _email.dispose();
    _phone.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  List<ProducerModel> _linkableProducers() {
    try {
      return context
          .watch<ProducerController>()
          .allProducers
          .where((ProducerModel p) => p.isActivo && (p.uidUsuario == null || p.uidUsuario!.isEmpty))
          .toList()
        ..sort((ProducerModel a, ProducerModel b) => a.nombreCompleto.compareTo(b.nombreCompleto));
    } on ProviderNotFoundException {
      return const <ProducerModel>[];
    }
  }

  void _selectRole(String role) {
    if (role == _role) return;
    setState(() {
      _role = role;
      _stepError = null;
      // Al cambiar de rol se parte de los permisos de ese rol.
      _perms = PermissionTree.normalize(
        widget.existingUser?.rol == role
            ? widget.existingUser!.effectivePermissions
            : Permissions.defaultsFor(role),
      );
      if (role != AppConstants.roleProductor) _productorId = null;
    });
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        final bool ok = _dataForm.currentState?.validate() ?? true;
        return ok;
      case 1:
        final String? err = UserFormRules.producerLink(role: _role, productorId: _productorId, isCreate: !_isEdit);
        setState(() => _stepError = err);
        return err == null;
      default:
        return true;
    }
  }

  void _goTo(int step) {
    if (step == _step) return;
    if (step > _step) {
      for (int s = _step; s < step; s++) {
        if (!_validateStep(s)) {
          setState(() => _step = s);
          return;
        }
      }
    }
    setState(() {
      _step = step;
      _stepError = null;
    });
  }

  Future<void> _submit() async {
    for (int s = 0; s < 3; s++) {
      if (s == 0 && _step != 0) {
        // El formulario de datos no está montado: validar con las reglas.
        final bool ok = UserFormRules.fullName(_name.text) == null &&
            UserFormRules.document(_doc.text) == null &&
            (_isEdit || UserFormRules.email(_email.text) == null) &&
            UserFormRules.phone(_phone.text) == null &&
            UserFormRules.password(_pass.text, isRequired: !_isEdit) == null &&
            UserFormRules.confirmPassword(_pass.text, _confirm.text) == null;
        if (!ok) {
          setState(() => _step = 0);
          WidgetsBinding.instance.addPostFrameCallback((_) => _dataForm.currentState?.validate());
          return;
        }
        continue;
      }
      if (!_validateStep(s)) {
        setState(() => _step = s);
        return;
      }
    }
    final UserController uc = context.read<UserController>();
    final String actorUid = _actor?.uid ?? '';
    setState(() {
      _saving = true;
      _error = null;
    });
    bool ok;
    if (_isEdit) {
      final bool permsChanged = !PermissionTree.equals(_perms, _initialPerms) || _role != widget.existingUser!.rol;
      final bool backToRole = _role == AppConstants.roleOperario &&
          PermissionTree.equals(_perms, Permissions.defaultsFor(_role));
      ok = await uc.updateUser(
        previousUser: widget.existingUser!,
        nombreCompleto: _name.text,
        documento: _doc.text,
        telefono: _phone.text,
        rol: _role,
        activo: _active,
        actorUid: actorUid,
        permisos: permsChanged && !backToRole ? UserFormRules.permissionsToSend(_role, _perms) : null,
        resetPermisosToRole: permsChanged && backToRole && widget.existingUser!.permisos != null,
        newPassword: _pass.text.isEmpty ? null : _pass.text,
      );
    } else {
      ok = await uc.createUser(
        nombreCompleto: _name.text,
        documento: _doc.text,
        correo: _email.text,
        telefono: _phone.text,
        rol: _role,
        password: _pass.text,
        activo: _active,
        actorUid: actorUid,
        permisos: UserFormRules.permissionsToSend(_role, _perms),
        productorId: _role == AppConstants.roleProductor ? _productorId : null,
      );
    }
    if (!mounted) return;
    if (ok) {
      if (_role == AppConstants.roleProductor && !_isEdit) {
        try {
          context.read<ProducerController>().loadProducers();
        } on ProviderNotFoundException {
          // Nada que refrescar.
        }
      }
      Navigator.of(context).pop(true);
      return;
    }
    final String msg = uc.errorMessage ?? 'No fue posible guardar el usuario.';
    final String low = msg.toLowerCase();
    setState(() {
      _saving = false;
      _error = msg;
      if (low.contains('documento') || low.contains('correo') || low.contains('contraseña') ||
          low.contains('nombre') || low.contains('teléfono')) {
        _step = 0;
      } else if (low.contains('productor') || low.contains('rol') || low.contains('administrador')) {
        _step = 1;
      } else if (low.contains('permiso')) {
        _step = 2;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool last = _step == 3;
    return AppDialog(
      width: 680,
      icon: _isEdit ? Icons.manage_accounts_outlined : Icons.person_add_alt_1_outlined,
      title: _isEdit ? 'Editar usuario' : 'Nuevo usuario',
      subtitle: _isEdit
          ? widget.existingUser!.nombreCompleto
          : 'Crea una cuenta de acceso en cuatro pasos.',
      footerLeading: Text(
        'Paso ${_step + 1} de 4 · ${_stepLabels[_step]}',
        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted),
      ),
      actions: <Widget>[
        if (_step > 0)
          OutlinedButton(
            onPressed: _saving ? null : () => _goTo(_step - 1),
            child: const Text('Atrás'),
          )
        else
          OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
        FilledButton(
          key: const ValueKey<String>('user-form-next'),
          onPressed: _saving ? null : (last ? _submit : () => _goTo(_step + 1)),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
              : Text(last ? (_isEdit ? 'Guardar cambios' : 'Crear usuario') : 'Siguiente'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _StepHeader(current: _step, onTap: _saving ? null : _goTo),
          const SizedBox(height: 16),
          if (_error != null) ...<Widget>[
            _InlineError(message: _error!, onClose: () => setState(() => _error = null)),
            const SizedBox(height: 12),
          ],
          switch (_step) {
            0 => _dataStep(),
            1 => _roleStep(),
            2 => PermissionTreeEditor(
                role: _role,
                value: _perms,
                onChanged: (Map<String, List<String>> p) => setState(() => _perms = p),
              ),
            _ => _reviewStep(),
          },
        ],
      ),
    );
  }

  // ───────────────────────── Paso 1: datos ─────────────────────────

  Widget _dataStep() {
    final PasswordStrength strength = UserFormRules.strength(_pass.text);
    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
        );
    return Form(
      key: _dataForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('user-name'),
            label: 'Nombre completo',
            required: true,
            controller: _name,
            hint: 'Ej. Ana María Gómez',
            prefixIcon: Icons.person_outline_rounded,
            inputFormatters: AppInputs.personName(max: FieldLimits.fullName),
            validator: UserFormRules.fullName,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          pair(
            AppTextField(
              key: const ValueKey<String>('user-doc'),
              label: 'Documento',
              required: true,
              controller: _doc,
              hint: 'Solo números',
              prefixIcon: Icons.badge_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: AppInputs.document(),
              validator: UserFormRules.document,
              monospace: true,
            ),
            AppTextField(
              key: const ValueKey<String>('user-phone'),
              label: 'Celular',
              controller: _phone,
              hint: '3101234567',
              helper: 'Opcional',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: AppInputs.phone(),
              validator: UserFormRules.phone,
              monospace: true,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            key: const ValueKey<String>('user-email'),
            label: 'Correo electrónico',
            required: !_isEdit,
            enabled: !_isEdit,
            controller: _email,
            hint: 'nombre@correo.com',
            helper: _isEdit ? 'El correo de acceso no se puede cambiar.' : 'Con este correo o el documento inicia sesión.',
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: AppInputs.email(),
            validator: _isEdit ? null : UserFormRules.email,
          ),
          const SizedBox(height: 12),
          pair(
            AppTextField(
              key: const ValueKey<String>('user-pass'),
              label: _isEdit ? 'Nueva contraseña' : 'Contraseña',
              required: !_isEdit,
              controller: _pass,
              obscure: _obscure,
              helper: _isEdit ? 'Déjala vacía para no cambiarla' : 'Mínimo 8, con letras y números',
              prefixIcon: Icons.lock_outline_rounded,
              inputFormatters: AppInputs.password(),
              validator: (String? v) => UserFormRules.password(v, isRequired: !_isEdit),
              onChanged: (_) => setState(() {}),
              suffix: IconButton(
                tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 17),
              ),
            ),
            AppTextField(
              key: const ValueKey<String>('user-confirm'),
              label: 'Confirmar contraseña',
              required: !_isEdit,
              controller: _confirm,
              obscure: _obscure,
              prefixIcon: Icons.lock_reset_rounded,
              inputFormatters: AppInputs.password(),
              validator: (String? v) => UserFormRules.confirmPassword(_pass.text, v),
            ),
          ),
          if (strength != PasswordStrength.empty) ...<Widget>[
            const SizedBox(height: 8),
            _StrengthMeter(strength: strength),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Cuenta activa', style: AppTheme.subtitleStyle().copyWith(fontSize: 13)),
                      Text(
                        _isSelf
                            ? 'No puedes suspender tu propia cuenta.'
                            : 'Si la desactivas, la persona no podrá iniciar sesión.',
                        style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _active,
                  onChanged: _isSelf ? null : (bool v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Paso 2: rol ─────────────────────────

  Widget _roleStep() {
    final bool actorIsAdmin = _actor?.isAdmin ?? true;
    final List<ProducerModel> producers = _role == AppConstants.roleProductor ? _linkableProducers() : const <ProducerModel>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_isSelf) ...<Widget>[
          Text('No puedes cambiar tu propio rol.', style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.warningText)),
          const SizedBox(height: 8),
        ],
        for (final _RoleOption o in _roles) ...<Widget>[
          _RoleCard(
            option: o,
            selected: _role == o.role,
            disabledReason: _isSelf && o.role != _role
                ? 'No puedes cambiar tu propio rol'
                : (!actorIsAdmin && o.role == AppConstants.roleAdmin)
                    ? 'Solo un administrador puede crear administradores'
                    : (_isEdit && o.role == AppConstants.roleProductor && widget.existingUser!.rol != AppConstants.roleProductor)
                        ? 'Para vincular un productor crea una cuenta nueva de productor'
                        : null,
            onTap: () => _selectRole(o.role),
          ),
          const SizedBox(height: 8),
        ],
        if (_role == AppConstants.roleProductor && !_isEdit) ...<Widget>[
          const SizedBox(height: 4),
          LabeledField(
            label: 'Productor al que pertenece la cuenta',
            required: true,
            hint: producers.isEmpty
                ? 'No hay productores activos sin cuenta. Créalo primero en el módulo Productores.'
                : 'Solo aparecen productores activos que aún no tienen cuenta en la app.',
            child: AppSelect<String?>(
              value: _productorId,
              prefixIcon: Icons.agriculture_outlined,
              hintText: 'Seleccionar productor…',
              searchable: true,
              searchHint: 'Buscar por nombre, código o cédula…',
              enabled: producers.isNotEmpty,
              options: <AppSelectOption<String?>>[
                for (final ProducerModel p in producers)
                  AppSelectOption<String?>(
                    value: p.productorId,
                    label: p.nombreCompleto,
                    description: '${p.codigoAsociado} · CC ${p.cedula}',
                  ),
              ],
              onChanged: (String? v) => setState(() {
                _productorId = v;
                _stepError = null;
              }),
            ),
          ),
        ],
        if (_role == AppConstants.roleProductor && _isEdit)
          Text(
            'La cuenta sigue vinculada a su productor. Solo cambia los datos de acceso.',
            style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
        if (_stepError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_stepError!, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.dangerText)),
        ],
      ],
    );
  }

  // ───────────────────────── Paso 4: revisar ─────────────────────────

  Widget _reviewStep() {
    ProducerModel? linked;
    if (_productorId != null) {
      try {
        linked = context
            .read<ProducerController>()
            .allProducers
            .where((ProducerModel p) => p.productorId == _productorId)
            .firstOrNull;
      } on ProviderNotFoundException {
        linked = null;
      }
    }
    final Map<String, List<String>> effective = _role == AppConstants.roleAdmin ? Permissions.full() : _perms;
    final List<_KV> rows = <_KV>[
      _KV('Nombre', _name.text.trim()),
      _KV('Documento', _doc.text.trim()),
      _KV('Correo', _email.text.trim()),
      _KV('Celular', _phone.text.trim().isEmpty ? 'No registrado' : _phone.text.trim()),
      _KV('Rol', AppConstants.roleShortLabel(_role)),
      if (linked != null) _KV('Productor vinculado', '${linked.nombreCompleto} (${linked.codigoAsociado})'),
      _KV('Estado', _active ? 'Activa' : 'Suspendida'),
      if (_isEdit) _KV('Contraseña', _pass.text.isEmpty ? 'Sin cambios' : 'Se cambiará'),
      _KV(
        'Permisos',
        _role == AppConstants.roleProductor
            ? 'Solo app móvil'
            : _role == AppConstants.roleAdmin
                ? 'Acceso total'
                : '${Permissions.countGranted(effective)} de ${Permissions.totalActions}',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < rows.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : const Border(top: BorderSide(color: AppTheme.dividerLight)),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 160,
                        child: Text(rows[i].k, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted)),
                      ),
                      Expanded(
                        child: Text(
                          rows[i].v,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_role == AppConstants.roleOperario) ...<Widget>[
          const SizedBox(height: 12),
          Text('PODRÁ', style: AppTheme.overlineStyle()),
          const SizedBox(height: 6),
          if (effective.isEmpty)
            Text('Sin permisos: no verá ningún módulo.', style: AppTheme.bodyStyle(color: AppTheme.warningText))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final PermModule m in Permissions.modules)
                  if (effective[m.key]?.isNotEmpty == true)
                    StatusBadge(
                      '${m.label}: ${effective[m.key]!.map(PermAction.label).join(', ').toLowerCase()}',
                      tone: Tone.brand,
                      icon: m.icon,
                    ),
              ],
            ),
        ],
      ],
    );
  }
}

class _KV {
  const _KV(this.k, this.v);
  final String k;
  final String v;
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.onTap});
  final int current;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < _stepLabels.length; i++) ...<Widget>[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: i <= current ? AppTheme.brand : AppTheme.border,
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current ? AppTheme.brand : (i == current ? AppTheme.brandSoft : AppTheme.surfaceSunken),
                      border: Border.all(color: i <= current ? AppTheme.brand : AppTheme.border),
                    ),
                    child: i < current
                        ? const Icon(Icons.check_rounded, size: 13, color: AppTheme.surface)
                        : Text(
                            '${i + 1}',
                            style: AppTheme.monoStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: i == current ? AppTheme.brand : AppTheme.textMuted,
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _stepLabels[i],
                    style: AppTheme.bodyStyle(
                      fontSize: 12.5,
                      fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
                      color: i == current ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.option, required this.selected, required this.onTap, this.disabledReason});
  final _RoleOption option;
  final bool selected;
  final VoidCallback onTap;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final bool disabled = disabledReason != null;
    final Widget card = Material(
      color: selected ? AppTheme.brandSoft : AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: selected ? AppTheme.brand : AppTheme.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        key: ValueKey<String>('role-${option.role}'),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.surface : AppTheme.surfaceSunken,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(option.icon, size: 18, color: selected ? AppTheme.brand : AppTheme.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(option.title, style: AppTheme.subtitleStyle()),
                      const SizedBox(height: 2),
                      Text(
                        disabledReason ?? option.description,
                        style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? AppTheme.brand : AppTheme.borderStrong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return card;
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});
  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final Color c = switch (strength) {
      PasswordStrength.weak => AppTheme.danger,
      PasswordStrength.fair => AppTheme.warning,
      PasswordStrength.good => AppTheme.success,
      PasswordStrength.strong => AppTheme.brand,
      PasswordStrength.empty => AppTheme.border,
    };
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: strength.fraction,
              minHeight: 5,
              color: c,
              backgroundColor: AppTheme.surfaceSunken,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: Text(
            'Seguridad: ${strength.label}',
            style: AppTheme.bodyStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.dangerText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              key: const ValueKey<String>('user-form-error'),
              style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.dangerText, height: 1.35),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.dangerText),
          ),
        ],
      ),
    );
  }
}
