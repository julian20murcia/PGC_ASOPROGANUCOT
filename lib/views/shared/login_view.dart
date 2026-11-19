import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_rules.dart';
import '../mobile/producer_registration_view.dart';
import 'widgets/cow_balloon_3d_widget.dart';
import 'widgets/dairy_loader.dart';
import 'widgets/design_system_widgets.dart';

/// Inicio de sesión de ASOPROGANUCOTT (paleta "Pradera").
///
/// Escritorio: panel de marca a la izquierda (mensaje + ilustración
/// interactiva) y formulario a la derecha. Móvil: una columna limpia.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  /// Identificador: correo o documento (letras, dígitos y `@ . _ - +`).
  static final List<TextInputFormatter> identifierFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9@._+\-]')),
    LengthLimitingTextInputFormatter(FieldLimits.email),
  ];

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> with SingleTickerProviderStateMixin {
  final TextEditingController _identifierCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  late final AnimationController _entry =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 760))..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _entry, curve: const Interval(0, 0.72, curve: Curves.easeOut));
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero)
      .animate(CurvedAnimation(parent: _entry, curve: const Interval(0, 0.75, curve: Curves.easeOutCubic)));

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _didLoadSaved = false;
  bool _capsLockOn = false;
  String? _localNotice;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _refreshCapsLock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadSaved) {
      final AuthController auth = context.read<AuthController>();
      _rememberMe = auth.rememberMe;
      if (auth.savedIdentifier.isNotEmpty) _identifierCtrl.text = auth.savedIdentifier;
      _didLoadSaved = true;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _entry.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    _refreshCapsLock();
    return false;
  }

  void _refreshCapsLock() {
    final bool active = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (active != _capsLockOn && mounted) setState(() => _capsLockOn = active);
  }

  /// Alta digital del productor desde la app móvil (flujo de `main`).
  Future<void> _registerProducer() async {
    FocusScope.of(context).unfocus();
    final String? document = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ProducerRegistrationView()),
    );
    if (!mounted || document == null) return;
    _identifierCtrl.text = document;
    _passwordCtrl.clear();
    setState(() {
      _localNotice = 'Ingresa con tu documento y la contraseña de tu cuenta.';
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _localNotice = null);
    final AuthController auth = context.read<AuthController>();
    await auth.signIn(
      identifier: _identifierCtrl.text,
      password: _passwordCtrl.text,
      rememberMe: _rememberMe,
    );
  }

  Future<void> _handleForgotPassword() async {
    final String identifier = _identifierCtrl.text.trim();
    if (!identifier.contains('@')) {
      setState(() {
        _localNotice =
            'Escribe tu correo electrónico en el primer campo y pulsa "¿Olvidaste tu contraseña?" para enviar el enlace.';
      });
      return;
    }
    final UserController users = context.read<UserController>();
    final bool ok = await users.sendPasswordReset(identifier);
    if (!mounted) return;
    setState(() {
      _localNotice = ok ? 'Enviamos un correo de recuperación de contraseña a $identifier.' : users.errorMessage;
    });
  }

  void _onFieldChanged(AuthController auth) {
    if (auth.errorMessage != null) auth.clearError();
    if (auth.sessionEndedReason != null) auth.clearSessionEndedReason();
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final bool isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Stack(
          children: <Widget>[
            SafeArea(
              top: false,
              bottom: !isDesktop,
              child: isDesktop ? _buildDesktop(auth) : _buildMobile(auth),
            ),
            // Telón mientras se validan las credenciales.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !auth.isLoading,
                child: AnimatedOpacity(
                  opacity: auth.isLoading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: const AsoproganucotCurtain(
                    eyebrow: 'VERIFICANDO ACCESO · SUSA',
                    statusText: 'Verificando tus credenciales de acceso…',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(AuthController auth) {
    return Row(
      children: <Widget>[
        Expanded(flex: 46, child: _BrandPanel(entry: _entry)),
        Expanded(
          flex: 54,
          child: Container(
            color: AppTheme.surface,
            alignment: Alignment.center,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 32),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _buildForm(auth, isMobile: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(AuthController auth) {
    final double top = MediaQuery.paddingOf(context).top;
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          ModernWaveHeader(
            height: (MediaQuery.sizeOf(context).height * 0.34).clamp(240.0, 300.0) + top,
            padding: EdgeInsets.fromLTRB(24, top + 18, 24, 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const AsoproganucotLogo(size: 72, compact: false, onDark: true),
                const SizedBox(height: 12),
                Text(
                  AppConstants.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recepción láctea y consulta de productores',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.78)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeTransition(opacity: _fade, child: _buildForm(auth, isMobile: true)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice({required IconData icon, required String text, required Color bg, required Color fg}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTheme.bodyStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w500, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      );

  Widget _buildForm(AuthController auth, {required bool isMobile}) {
    final String? error = auth.errorMessage;
    final String? sessionReason = auth.sessionEndedReason;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.brandSoft, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.verified_user_rounded, size: 13, color: AppTheme.brand),
                const SizedBox(width: 6),
                Text(
                  'ACCESO AL SISTEMA',
                  style: GoogleFonts.inter(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppTheme.brand),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Iniciar sesión',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 24 : 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ingresa con tu correo o número de documento para continuar.',
            style: AppTheme.bodyStyle(fontSize: 13.5, height: 1.45),
          ),
          if (sessionReason != null && sessionReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            _notice(icon: Icons.lock_clock_outlined, text: sessionReason, bg: AppTheme.infoBg, fg: AppTheme.infoText),
          ],
          const SizedBox(height: 22),
          _label('Correo o documento'),
          TextField(
            key: const Key('login-identifier'),
            controller: _identifierCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.username, AutofillHints.email],
            inputFormatters: LoginView.identifierFormatters,
            onChanged: (_) => _onFieldChanged(auth),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              hintText: 'usuario@asoproganucott.com o 1073500123',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 14),
          _label('Contraseña'),
          TextField(
            key: const Key('login-password'),
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            inputFormatters: AppInputs.password(),
            onChanged: (_) {
              _refreshCapsLock();
              _onFieldChanged(auth);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Tu contraseña',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.textMuted),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          if (_capsLockOn) ...<Widget>[
            const SizedBox(height: 8),
            _notice(
              icon: Icons.keyboard_capslock_rounded,
              text: 'Bloq Mayús activado',
              bg: AppTheme.warningBg,
              fg: AppTheme.warningText,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              if (AuthController.persistentMobileSession)
                // En el celular la sesión siempre se mantiene iniciada.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.verified_user_outlined, size: 16, color: AppTheme.brand),
                      const SizedBox(width: 6),
                      Text(
                        'La sesión queda guardada en este teléfono',
                        style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: AppTheme.brand,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.inputBorder, width: 1.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (bool? v) => setState(() => _rememberMe = v ?? true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Recordar acceso', style: AppTheme.bodyStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: auth.isLoading ? null : _handleForgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('¿Olvidaste tu contraseña?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (error != null && error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _notice(icon: Icons.error_outline_rounded, text: error, bg: AppTheme.dangerBg, fg: AppTheme.dangerText),
          ],
          if (_localNotice != null) ...<Widget>[
            const SizedBox(height: 12),
            _notice(icon: Icons.mark_email_read_outlined, text: _localNotice!, bg: AppTheme.brandSoft, fg: AppTheme.brandDeep),
          ],
          const SizedBox(height: 18),
          PrimaryActionButton(
            label: 'Ingresar al sistema',
            icon: Icons.arrow_forward_rounded,
            isLoading: auth.isLoading,
            isMobile: isMobile,
            color: AppTheme.brand,
            onPressed: _submit,
          ),
          if (ProducerRegistrationView.isSupported) ...<Widget>[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const Key('login-register-producer'),
                onPressed: auth.isLoading ? null : _registerProducer,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Crear cuenta de productor'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(Icons.shield_outlined, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Asociación de Productores y Ganaderos · Susa, Cundinamarca.',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Panel de marca del escritorio. Aísla el seguimiento del puntero para que
/// mover el mouse no reconstruya el formulario.
class _BrandPanel extends StatefulWidget {
  const _BrandPanel({required this.entry});
  final AnimationController entry;

  @override
  State<_BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<_BrandPanel> {
  final GlobalKey _cowKey = GlobalKey();
  Offset _pointer = Offset.zero;

  void _track(Offset global) {
    final RenderBox? box = _cowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final Offset center = box.localToGlobal(box.size.center(Offset.zero));
    final Size screen = MediaQuery.sizeOf(context);
    final double hw = (screen.width * 0.45).clamp(200.0, 2000.0);
    final double hh = (screen.height * 0.45).clamp(200.0, 2000.0);
    setState(() {
      _pointer = Offset(
        ((global.dx - center.dx) / hw).clamp(-1.0, 1.0),
        ((global.dy - center.dy) / hh).clamp(-1.0, 1.0),
      );
    });
  }

  Animation<double> _interval(double a, double b) =>
      CurvedAnimation(parent: widget.entry, curve: Interval(a, b, curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (PointerHoverEvent e) => _track(e.position),
      onExit: (_) => setState(() => _pointer = Offset.zero),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppTheme.brandInk, AppTheme.brandDeep, Color(0xFF0E5A53)],
            stops: <double>[0, 0.55, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const MilkFlowBackground(opacity: 0.92),
            // Halo ámbar suave detrás de la ilustración.
            Positioned(
              right: -120,
              top: -80,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[AppTheme.accent.withValues(alpha: 0.18), AppTheme.accent.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 32, 40, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const AsoproganucotLogo(size: 38, compact: true, onDark: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              AppConstants.appName,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.2),
                            ),
                            Text(
                              'Susa · Cundinamarca',
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 320),
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                                gradient: RadialGradient(
                                  colors: <Color>[
                                    Colors.white.withValues(alpha: 0.14),
                                    AppTheme.brand.withValues(alpha: 0.10),
                                    Colors.transparent,
                                  ],
                                  stops: const <double>[0, 0.55, 1],
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Container(
                                key: _cowKey,
                                alignment: Alignment.center,
                                child: CowBalloon3DWidget(
                                  pointerNormalized: _pointer,
                                  showContactShadow: false,
                                  scaleFactor: 0.38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _Line(animation: _interval(0.10, 0.62), text: 'Recepción láctea,', color: Colors.white),
                  _Line(animation: _interval(0.24, 0.78), text: 'liquidaciones claras y', color: Colors.white),
                  _Line(animation: _interval(0.38, 0.94), text: 'decisiones con datos.', color: AppTheme.accent),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _interval(0.5, 1),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const <Widget>[
                        _Feature(icon: Icons.water_drop_outlined, text: 'Acopio por jornada'),
                        _Feature(icon: Icons.receipt_long_outlined, text: 'Cierre quincenal'),
                        _Feature(icon: Icons.auto_graph_rounded, text: 'Predicciones'),
                        _Feature(icon: Icons.cloud_off_outlined, text: 'Funciona sin internet'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
                  const SizedBox(height: 10),
                  Text(
                    'Planta de Acopio · Gestión de Productores y Liquidaciones',
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(text, style: AppTheme.bodyStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.animation, required this.text, required this.color});
  final Animation<double> animation;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - animation.value) * 12), child: child),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(fontSize: 26, height: 1.22, letterSpacing: -0.6, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
