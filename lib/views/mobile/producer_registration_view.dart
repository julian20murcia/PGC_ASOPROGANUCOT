import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services/firebase_callable.dart';
import '../../core/theme/app_theme.dart';
import '../../firebase_options.dart';
import '../../models/privacy_notice.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/privacy_notice_view.dart';

class ProducerRegistrationView extends StatefulWidget {
  const ProducerRegistrationView({super.key});

  static bool get isSupported => !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<ProducerRegistrationView> createState() => _ProducerRegistrationViewState();
}

class _ProducerRegistrationViewState extends State<ProducerRegistrationView> {
  static const _appName = 'ProducerRegistration';
  static const _consent = 'Leí el aviso y la política de tratamiento. Autorizo el uso de mis datos para verificar mi teléfono, activar mi cuenta y consultar mi historial en el portal.';

  final _form = GlobalKey<FormState>();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late Future<PrivacyNotice> _notice;
  FirebaseAuth? _registrationAuth;
  User? _verifiedUser;
  String? _verificationId;
  String? _error;
  bool _accepted = false;
  bool _busy = false;
  bool _verifying = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _notice = PrivacyNotice.load();
  }

  @override
  void dispose() {
    _attempt++;
    unawaited(_closeAuthSession());
    _document.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _closeAuthSession() async {
    try {
      await _registrationAuth?.signOut();
    } on FirebaseAuthException {
      // La sesión secundaria no se usa para consultar datos del portal.
    }
  }

  Future<FirebaseAuth> _auth() async {
    if (_registrationAuth != null) return _registrationAuth!;
    final FirebaseApp app;
    try {
      app = Firebase.app(_appName);
    } on FirebaseException {
      final created = await Firebase.initializeApp(
        name: _appName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return _registrationAuth = FirebaseAuth.instanceFor(app: created);
    }
    return _registrationAuth = FirebaseAuth.instanceFor(app: app);
  }

  String? get _mobile {
    final input = _phone.text.replaceAll(RegExp(r'[\s().-]'), '');
    final match = RegExp(r'^(?:\+?57|0057)?(3\d{9})$').firstMatch(input);
    return match == null ? null : '+57${match.group(1)}';
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  String _phoneError(FirebaseException error) {
    return switch (error.code) {
      'invalid-verification-code' => 'El código del mensaje es incorrecto.',
      'session-expired' => 'El código venció. Solicita uno nuevo.',
      'too-many-requests' => 'Se alcanzó el límite de intentos. Intenta más tarde.',
      'operation-not-allowed' => 'La verificación por SMS aún no está habilitada.',
      _ => 'No se pudo verificar el teléfono. Revisa la conexión y vuelve a intentar.',
    };
  }

  Future<void> _sendCode() async {
    if (!_accepted || _busy || !(_form.currentState?.validate() ?? false)) return;
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = await _auth();
      if (!mounted || attempt != _attempt) return;
      await auth.verifyPhoneNumber(
        phoneNumber: _mobile!,
        verificationCompleted: (credential) {
          unawaited(_verify(credential, attempt));
        },
        verificationFailed: (error) {
          if (attempt == _attempt && _verifiedUser == null && !_verifying) {
            _showError(_phoneError(error));
          }
        },
        codeSent: (id, _) {
          if (!mounted || attempt != _attempt || _verifiedUser != null) return;
          setState(() {
            _verificationId = id;
            if (!_verifying) _busy = false;
          });
        },
        codeAutoRetrievalTimeout: (id) {
          if (!mounted || attempt != _attempt || _verifiedUser != null) return;
          setState(() {
            _verificationId = id;
            if (!_verifying) _busy = false;
          });
        },
      );
    } on FirebaseException catch (error) {
      if (attempt == _attempt) _showError(_phoneError(error));
    }
  }

  Future<void> _verify(PhoneAuthCredential credential, int attempt) async {
    if (!mounted || attempt != _attempt || _verifying || _verifiedUser != null) return;
    _verifying = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = await _auth();
      final result = await auth.signInWithCredential(credential);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _verifiedUser = result.user;
        _busy = false;
      });
    } on FirebaseException catch (error) {
      if (attempt == _attempt) _showError(_phoneError(error));
    } finally {
      _verifying = false;
    }
  }

  void _confirmCode() {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: _code.text.trim(),
    );
    unawaited(_verify(credential, _attempt));
  }

  Future<void> _activate(PrivacyNotice notice) async {
    if (!_accepted || _busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _verifiedUser?.getIdToken();
      if (token == null) {
        _showError('Verifica de nuevo el teléfono por SMS.');
        return;
      }
      await callFirebaseFunction('registerProducerAccount', <String, dynamic>{
        'documento': _document.text.trim(),
        'password': _password.text,
        'aviso': notice.data,
        'aceptado': _accepted,
        'declaracion': _consent,
      }, idToken: token, timeout: const Duration(seconds: 60));
      if (mounted) Navigator.of(context).pop(_document.text.trim());
    } on StateError catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo terminar el alta. Verifica tu conexión y reintenta.');
    }
  }

  Future<void> _restartVerification() async {
    ++_attempt;
    setState(() {
      _busy = true;
      _verificationId = null;
      _verifiedUser = null;
      _error = null;
    });
    _code.clear();
    _password.clear();
    _confirmation.clear();
    await _closeAuthSession();
    if (mounted) setState(() => _busy = false);
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
                        TextButton(
                          onPressed: () {
                            final pending = PrivacyNotice.load();
                            setState(() {
                              _notice = pending;
                            });
                          },
                          child: const Text('Reintentar'),
                        ),
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
    final verified = _verifiedUser != null;
    final codeSent = _verificationId != null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Aviso de privacidad', style: AppTheme.subtitleStyle()),
          const SizedBox(height: 12),
          PrivacyNoticeView(notice: notice),
          const Text('Firebase recibe el número para verificarlo por SMS y prevenir abusos.'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: _busy || codeSent || verified ? null : (value) {
              setState(() => _accepted = value ?? false);
            },
            title: const Text(_consent),
          ),
          const SizedBox(height: 16),
          const Text('Usa el documento y el celular registrados en la asociación.'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _document,
            enabled: _accepted && !_busy && !codeSent && !verified,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Número de identificación'),
            validator: (value) => RegExp(r'^\d{5,24}$').hasMatch(value?.trim() ?? '')
                ? null : 'Ingresa un número de identificación válido.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            enabled: _accepted && !_busy && !codeSent && !verified,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Celular registrado'),
            validator: (_) => _mobile == null ? 'Ingresa un celular colombiano válido.' : null,
          ),
          if (codeSent && !verified) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'Código del SMS'),
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                  ? null : 'Ingresa el código de seis dígitos.',
            ),
          ],
          if (verified) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Contraseña'),
              validator: (value) => (value ?? '').length < 8 || (value ?? '').length > 128
                  ? 'Usa entre 8 y 128 caracteres.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
              validator: (value) => value != _password.text ? 'Las contraseñas deben coincidir.' : null,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.dangerText)),
          ],
          const SizedBox(height: 20),
          PrimaryActionButton(
            label: verified ? 'Crear cuenta' : codeSent ? 'Verificar código' : 'Enviar código por SMS',
            isLoading: _busy,
            onPressed: !_accepted || _busy ? null : verified
                ? () => _activate(notice) : codeSent ? _confirmCode : _sendCode,
          ),
          if (codeSent || verified)
            TextButton(
              onPressed: _busy ? null : _restartVerification,
              child: const Text('Cambiar datos o solicitar otro código'),
            ),
        ],
      ),
    );
  }
}
