import 'package:flutter/material.dart';

import '../../core/services/firebase_callable.dart';
import '../../core/theme/app_theme.dart';
import '../../models/privacy_notice.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/privacy_notice_view.dart';

class ProducerRegistrationView extends StatefulWidget {
  const ProducerRegistrationView({super.key, this.activationCode});

  final String? activationCode;

  @override
  State<ProducerRegistrationView> createState() => _ProducerRegistrationViewState();
}

class _ProducerRegistrationViewState extends State<ProducerRegistrationView> {
  static const _consent = 'Leí el aviso y la política de tratamiento. Autorizo el uso de mis datos para verificar el documento y el teléfono del padrón, activar mi cuenta y consultar mi historial en el portal.';
  static final _codePattern = RegExp(r'^[A-Za-z0-9_-]{1,128}\.[A-Za-z0-9_-]{43}$');
  static final _phonePattern = RegExp(r'^(?:\+?57|0057)?3\d{9}$');

  final _form = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late Future<PrivacyNotice> _notice;
  String? _error;
  bool _policyOpened = false;
  bool _accepted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _notice = PrivacyNotice.load();
  }

  @override
  void dispose() {
    _link.dispose();
    _document.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String get _code {
    final input = widget.activationCode ?? _link.text.trim();
    if (_codePattern.hasMatch(input)) return input;
    final link = Uri.tryParse(input);
    final route = link == null ? null : Uri.tryParse(link.fragment);
    return route?.queryParameters['clave'] ?? '';
  }

  Future<void> _activate(PrivacyNotice notice) async {
    if (!_accepted || _busy || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await callFirebaseFunction('registerProducerAccount', <String, dynamic>{
        'clave': _code,
        'documento': _document.text.trim(),
        'telefono': _phone.text.trim(),
        'password': _password.text,
        'aviso': notice.data,
        'aceptado': _accepted,
        'declaracion': _consent,
      }, timeout: const Duration(seconds: 60));
      if (mounted && widget.activationCode != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Acceso activado'),
            content: const Text('Entra con tu documento y la contraseña de tu cuenta.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ir al inicio de sesión'),
              ),
            ],
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(_document.text.trim());
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo terminar el alta. Verifica tu conexión y reintenta.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reloadNotice() {
    final pending = PrivacyNotice.load();
    setState(() {
      _policyOpened = false;
      _accepted = false;
      _notice = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta de productor')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: FutureBuilder<PrivacyNotice>(
                future: _notice,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  final notice = snapshot.data;
                  if (notice == null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('El registro requiere el aviso institucional vigente. Consulta a la asociación si el aviso sigue sin estar disponible.'),
                        TextButton(onPressed: _reloadNotice, child: const Text('Reintentar')),
                      ],
                    );
                  }
                  return _registrationForm(notice);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _registrationForm(PrivacyNotice notice) {
    final editable = _accepted && !_busy;
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Aviso de privacidad', style: AppTheme.subtitleStyle()),
            const SizedBox(height: 12),
            PrivacyNoticeView(
              notice: notice,
              onPolicyOpened: () => setState(() => _policyOpened = true),
            ),
            if (!_policyOpened)
              const Text('Abre la política para poder confirmar tu autorización.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepted,
              onChanged: !_policyOpened || _busy
                  ? null : (value) => setState(() => _accepted = value ?? false),
              title: const Text(_consent),
            ),
            const SizedBox(height: 16),
            const Text('Usa el documento y el celular registrados en la asociación.'),
            const SizedBox(height: 12),
            if (widget.activationCode == null) ...[
              TextFormField(
                controller: _link,
                enabled: editable,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Enlace de activación'),
                validator: (_) => _codePattern.hasMatch(_code) ? null : 'Pega el enlace que te entregó la asociación.',
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _document,
              enabled: editable,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Número de identificación'),
              validator: (value) => RegExp(r'^\d{5,24}$').hasMatch(value?.trim() ?? '')
                  ? null : 'Ingresa un número de identificación válido.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              enabled: editable,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Celular registrado'),
              validator: (value) => _phonePattern.hasMatch((value ?? '').replaceAll(RegExp(r'[\s().-]'), ''))
                  ? null : 'Ingresa un celular colombiano válido.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              enabled: editable,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Contraseña'),
              validator: (value) => (value ?? '').length < 8 || (value ?? '').length > 128
                  ? 'Usa entre 8 y 128 caracteres.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              enabled: editable,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
              validator: (value) => value != _password.text ? 'Las contraseñas deben coincidir.' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppTheme.dangerText)),
            ],
            const SizedBox(height: 20),
            PrimaryActionButton(
              label: 'Crear cuenta',
              isLoading: _busy,
              onPressed: editable ? () => _activate(notice) : null,
            ),
          ],
        ),
      ),
    );
  }
}
