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
import '../shared/widgets/ui_kit.dart';

class ProducerRegistrationView extends StatefulWidget {
  const ProducerRegistrationView({super.key, this.privacyNoticeLoader});

  final Future<PrivacyNotice> Function()? privacyNoticeLoader;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<ProducerRegistrationView> createState() =>
      _ProducerRegistrationViewState();
}

class _ProducerRegistrationViewState extends State<ProducerRegistrationView> {
  static const _appName = 'ProducerRegistration';
  static const _consent =
      'Leí el aviso y la política de tratamiento. Autorizo el uso de mis datos para verificar mi teléfono, activar mi cuenta y consultar mi historial en el portal.';

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
  bool _policyOpened = false;
  bool _accepted = false;
  bool _busy = false;
  bool _verifying = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _notice = _loadNotice();
  }

  Future<PrivacyNotice> _loadNotice() =>
      (widget.privacyNoticeLoader ?? PrivacyNotice.load)();

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

  bool _isIntegrityVerificationFailure(FirebaseException error) {
    final String code = error.code.toLowerCase();
    final String msg = (error.message ?? '').toLowerCase();
    return code == 'app-not-authorized' ||
        code == 'missing-client-identifier' ||
        code == 'invalid-app-credential' ||
        msg.contains('play_integrity_token') ||
        msg.contains('17028') ||
        msg.contains('play integrity');
  }

  String _phoneError(FirebaseException error) {
    final String msg = (error.message ?? '').toLowerCase();
    if (_isIntegrityVerificationFailure(error)) {
      return 'No se pudo validar la integridad de la app con Google Play. '
          'Verifica tu conexión e intenta nuevamente para usar la verificación web.';
    }
    return switch (error.code) {
      'invalid-verification-code' => 'El código del mensaje es incorrecto.',
      'session-expired' => 'El código venció. Solicita uno nuevo.',
      'too-many-requests' =>
        'Se alcanzó el límite de intentos. Intenta más tarde.',
      'operation-not-allowed' =>
        'La verificación por SMS no está habilitada en Firebase Auth.',
      'invalid-phone-number' => 'El número de celular no tiene formato válido.',
      'quota-exceeded' =>
        'Se superó la cuota diaria de SMS. Intenta más tarde.',
      'billing-not-enabled' =>
        'El proyecto Firebase requiere facturación activa para enviar SMS reales.',
      'captcha-check-failed' =>
        'La verificación de seguridad (reCAPTCHA) no se completó.',
      'web-context-cancelled' =>
        'Cancelaste la verificación de seguridad en el navegador. Intenta de nuevo.',
      'network-request-failed' =>
        'Sin conexión a internet para solicitar el SMS.',
      _ => msg.contains('billing')
          ? 'El proyecto Firebase requiere facturación activa para enviar SMS reales.'
          : 'No se pudo verificar el teléfono (${error.code}). Revisa la conexión y vuelve a intentar.',
    };
  }

  Future<void> _sendCode({bool forceRecaptcha = false}) async {
    if (!_accepted ||
        (_busy && !forceRecaptcha) ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = await _auth();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await auth.setSettings(forceRecaptchaFlow: forceRecaptcha);
      }
      if (!mounted || attempt != _attempt) return;
      await auth.verifyPhoneNumber(
        phoneNumber: _mobile!,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) {
          unawaited(_verify(credential, attempt));
        },
        verificationFailed: (error) {
          if (attempt != _attempt || _verifiedUser != null || _verifying) {
            return;
          }
          if (!forceRecaptcha &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              _isIntegrityVerificationFailure(error)) {
            unawaited(_sendCode(forceRecaptcha: true));
            return;
          }
          _showError(_phoneError(error));
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
      if (attempt == _attempt) {
        if (!forceRecaptcha &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            _isIntegrityVerificationFailure(error)) {
          unawaited(_sendCode(forceRecaptcha: true));
          return;
        }
        _showError(_phoneError(error));
      }
    } catch (_) {
      if (attempt == _attempt) {
        _showError(
          'No se pudo iniciar la verificación por SMS. Intenta nuevamente.',
        );
      }
    }
  }

  Future<void> _verify(PhoneAuthCredential credential, int attempt) async {
    if (!mounted ||
        attempt != _attempt ||
        _verifying ||
        _verifiedUser != null) {
      return;
    }
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
    if (!_accepted || _busy || !(_form.currentState?.validate() ?? false)) {
      return;
    }
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
      await callFirebaseFunction(
        'registerProducerAccount',
        <String, dynamic>{
          'documento': _document.text.trim(),
          'password': _password.text,
          'aviso': notice.data,
          'aceptado': _accepted,
          'declaracion': _consent,
        },
        idToken: token,
        timeout: const Duration(seconds: 60),
      );
      if (mounted) Navigator.of(context).pop(_document.text.trim());
    } on StateError catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError(
        'No se pudo terminar el alta. Verifica tu conexión y reintenta.',
      );
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

  Future<void> _openPolicyAndAccept(PrivacyNotice notice) async {
    FocusScope.of(context).unfocus();
    final bool? accepted = await PrivacyNoticeView.showPolicyPreview(
      context,
      notice: notice,
      requireScrollToAccept: true,
      onPolicyOpened: () {
        if (mounted) setState(() => _policyOpened = true);
      },
    );
    if (!mounted) return;
    if (accepted == true) {
      setState(() {
        _policyOpened = true;
        _accepted = true;
      });
    }
  }

  Future<void> _openPolicyConsultation(PrivacyNotice notice) async {
    await PrivacyNoticeView.showPolicyPreview(
      context,
      notice: notice,
      requireScrollToAccept: false,
      onPolicyOpened: () {
        if (mounted) setState(() => _policyOpened = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(title: const Text('Crear cuenta de productor')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: FutureBuilder<PrivacyNotice>(
                future: _notice,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: LinearProgressIndicator(),
                    );
                  }
                  final PrivacyNotice? notice = snapshot.data;
                  if (notice == null) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusCard + 2,
                        ),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const AppInlineNotice.danger(
                            message:
                                'El registro requiere el aviso institucional vigente. Consulta a la asociación si el aviso sigue sin estar disponible.',
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final Future<PrivacyNotice> pending =
                                    _loadNotice();
                                setState(() {
                                  _notice = pending;
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 17),
                              label: const Text('Reintentar'),
                            ),
                          ),
                        ],
                      ),
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
    final bool verified = _verifiedUser != null;
    final bool codeSent = _verificationId != null;
    final int currentStep = verified
        ? 3
        : _accepted
        ? 2
        : 1;
    final Map<String, String> data = notice.data;

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RegistrationStepper(
            currentStep: currentStep,
            step1Done: _accepted,
            step2Done: verified,
          ),
          const SizedBox(height: 14),
          if (!_accepted) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const AppIconBadge(
                        icon: Icons.privacy_tip_outlined,
                        color: AppTheme.primaryGreen,
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Aviso de privacidad',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Versión ${data['version']} · ${data['responsable']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.canvasAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${data['finalidades']}',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${data['derechos']}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryActionButton(
                    label: 'Leer política aquí y aceptar',
                    icon: Icons.menu_book_outlined,
                    isMobile: true,
                    fullWidth: true,
                    onPressed: _busy ? null : () => _openPolicyAndAccept(notice),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => PrivacyNoticeView.openPolicy(
                              context,
                              notice,
                              onPolicyOpened: () {
                                if (mounted) {
                                  setState(() => _policyOpened = true);
                                }
                              },
                            ),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('Abrir enlace en navegador'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Material(
                    color: AppTheme.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppTheme.primaryGreen,
                      value: _accepted,
                      onChanged: _busy || codeSent || verified
                          ? null
                          : (bool? value) {
                              if (!_policyOpened) {
                                _openPolicyAndAccept(notice);
                              } else {
                                setState(() => _accepted = value ?? false);
                              }
                            },
                      title: const Text(
                        _consent,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.38,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...<Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreenLight,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
                border: Border.all(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 20,
                        color: AppTheme.primaryGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Política leída y autorización aceptada',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successText,
                              ),
                            ),
                            Text(
                              'Versión ${data['version']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    _consent,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _openPolicyConsultation(notice),
                        icon: const Icon(Icons.menu_book_outlined, size: 15),
                        label: const Text('Ver política'),
                      ),
                      if (!_busy && !codeSent && !verified)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => setState(() => _accepted = false),
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Cambiar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    AppIconBadge(
                      icon: Icons.sms_outlined,
                      color: AppTheme.skyBlue,
                      size: 34,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Identificación y verificación SMS',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Usa el documento y el celular registrados en la asociación.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Firebase recibe el número para verificarlo por SMS y prevenir abusos.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _document,
                  enabled: _accepted && !_busy && !codeSent && !verified,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Número de identificación',
                    prefixIcon: Icon(Icons.badge_outlined, size: 18),
                  ),
                  validator: (value) =>
                      RegExp(r'^\d{5,24}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Ingresa un número de identificación válido.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  enabled: _accepted && !_busy && !codeSent && !verified,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Celular registrado',
                    hintText: 'Ej. 3101234567',
                    prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
                  ),
                  validator: (_) => _mobile == null
                      ? 'Ingresa un celular colombiano válido.'
                      : null,
                ),
                if (codeSent && !verified) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofillHints: const <String>[AutofillHints.oneTimeCode],
                    decoration: const InputDecoration(
                      labelText: 'Código del SMS',
                      prefixIcon: Icon(Icons.password_rounded, size: 18),
                    ),
                    validator: (value) =>
                        RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Ingresa el código de seis dígitos.',
                  ),
                ],
                if (verified) ...<Widget>[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  const Text(
                    'Define tu contraseña de acceso',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                      ),
                      suffixIcon: IconButton(
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
                    ),
                    validator: (value) =>
                        (value ?? '').length < 8 || (value ?? '').length > 128
                        ? 'Usa entre 8 y 128 caracteres.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmation,
                    obscureText: _obscureConfirmation,
                    decoration: InputDecoration(
                      labelText: 'Confirmar contraseña',
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                      ),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmation
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () => setState(
                          () => _obscureConfirmation = !_obscureConfirmation,
                        ),
                        icon: Icon(
                          _obscureConfirmation
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                      ),
                    ),
                    validator: (value) => value != _password.text
                        ? 'Las contraseñas deben coincidir.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            AppInlineNotice.danger(message: _error!),
          ],
          const SizedBox(height: 16),
          PrimaryActionButton(
            label: verified
                ? 'Crear cuenta'
                : codeSent
                ? 'Verificar código'
                : 'Enviar código por SMS',
            isMobile: true,
            isLoading: _busy,
            onPressed: !_accepted || _busy
                ? null
                : verified
                ? () => _activate(notice)
                : codeSent
                ? _confirmCode
                : () => _sendCode(),
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

class _RegistrationStepper extends StatelessWidget {
  const _RegistrationStepper({
    required this.currentStep,
    required this.step1Done,
    required this.step2Done,
  });

  final int currentStep;
  final bool step1Done;
  final bool step2Done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StepChip(
              number: '1',
              label: 'Privacidad',
              active: currentStep == 1,
              done: step1Done,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _StepChip(
              number: '2',
              label: 'Celular SMS',
              active: currentStep == 2,
              done: step2Done,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _StepChip(
              number: '3',
              label: 'Contraseña',
              active: currentStep == 3,
              done: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.number,
    required this.label,
    required this.active,
    required this.done,
  });

  final String number;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final Color bg = done
        ? AppTheme.primaryGreenLight
        : active
        ? AppTheme.inkBlack
        : AppTheme.surfaceMuted;
    final Color fg = done
        ? AppTheme.successText
        : active
        ? Colors.white
        : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle,
            size: done ? 14 : 7,
            color: fg,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              done ? label : '$number. $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
