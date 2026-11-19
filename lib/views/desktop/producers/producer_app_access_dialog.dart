import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/producer_controller.dart';
import '../../../controllers/user_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/pro_ui.dart';

/// Mini formulario para crear el acceso a la app móvil de un productor.
/// Devuelve true si la cuenta se creó (la Cloud Function vincula el productor).
Future<bool> showProducerAppAccessDialog(
  BuildContext context, {
  required ProducerModel producer,
  required String actorUid,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AppAccessDialog(producer: producer, actorUid: actorUid),
  );
  return ok ?? false;
}

class _AppAccessDialog extends StatefulWidget {
  const _AppAccessDialog({required this.producer, required this.actorUid});

  final ProducerModel producer;
  final String actorUid;

  @override
  State<_AppAccessDialog> createState() => _AppAccessDialogState();
}

class _AppAccessDialogState extends State<_AppAccessDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final UserController users = context.read<UserController>();
    final ProducerController producers = context.read<ProducerController>();
    setState(() {
      _saving = true;
      _error = null;
    });
    final ProducerModel p = widget.producer;
    final bool ok = await users.createUser(
      nombreCompleto: p.nombreCompleto,
      documento: p.cedula,
      correo: _email.text.trim().toLowerCase(),
      telefono: p.telefono,
      rol: AppConstants.roleProductor,
      password: _password.text,
      activo: p.isActivo,
      actorUid: widget.actorUid,
      permisos: null,
      productorId: p.productorId,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = users.errorMessage ?? 'No fue posible crear el acceso.';
      });
      return;
    }
    await producers.loadProducers();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      width: 460,
      icon: Icons.smartphone_rounded,
      title: 'Acceso a la app móvil',
      subtitle: widget.producer.nombreCompleto,
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'El productor podrá ver sus entregas, liquidaciones y comunicados desde el celular. '
              'Entrégale estos datos de ingreso de forma privada.',
              style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.dangerBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Text(
                  _error!,
                  style: AppTheme.bodyStyle(
                    fontSize: 12.5,
                    color: AppTheme.dangerText,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            AppTextField(
              key: const Key('producer-access-email'),
              label: 'Correo electrónico',
              required: true,
              autofocus: true,
              enabled: !_saving,
              controller: _email,
              hint: 'productor@correo.com',
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: AppInputs.email(),
              textInputAction: TextInputAction.next,
              validator: AppValidators.email,
            ),
            const SizedBox(height: 14),
            AppTextField(
              key: const Key('producer-access-password'),
              label: 'Contraseña inicial',
              required: true,
              enabled: !_saving,
              controller: _password,
              obscure: _obscure,
              hint: 'Mínimo 8 caracteres, letras y números',
              prefixIcon: Icons.lock_outline_rounded,
              inputFormatters: AppInputs.password(),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: AppValidators.password,
              suffix: IconButton(
                tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Ahora no'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: const Text('Crear acceso'),
        ),
      ],
    );
  }
}
