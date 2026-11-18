import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/cow_balloon_3d_widget.dart';
import 'widgets/dairy_loader.dart';
import 'widgets/design_system_widgets.dart';

/// Pantalla de inicio de sesión editorial de ASOPROGANUCOTT.
/// Panel izquierdo en tinta negra `#0E1117` con curvas lácteas y vaca Holstein 3D;
/// hoja derecha en blanco puro `#FFFFFF` con formulario limpio y telón al autenticar.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>
    with SingleTickerProviderStateMixin {
  final TextEditingController _identifierCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final GlobalKey _cowContainerKey = GlobalKey();

  late final AnimationController _entryController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _line1Anim;
  late final Animation<double> _line2Anim;
  late final Animation<double> _line3Anim;

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _didLoadSaved = false;
  bool _capsLockOn = false;
  Offset _pointerNormalized = Offset.zero;
  String? _localNotice;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();
    _fadeAnim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.72, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );
    _line1Anim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.10, 0.62, curve: Curves.easeOutCubic),
    );
    _line2Anim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.24, 0.78, curve: Curves.easeOutCubic),
    );
    _line3Anim = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.38, 0.94, curve: Curves.easeOutCubic),
    );
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _refreshCapsLock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadSaved) {
      final AuthController auth = context.read<AuthController>();
      _rememberMe = auth.rememberMe;
      if (auth.savedIdentifier.isNotEmpty) {
        _identifierCtrl.text = auth.savedIdentifier;
      }
      _didLoadSaved = true;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _entryController.dispose();
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
    final bool active = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    if (active != _capsLockOn && mounted) {
      setState(() => _capsLockOn = active);
    }
  }

  void _updatePointerFromGlobal(Offset globalPosition) {
    final Size screenSize = MediaQuery.of(context).size;
    final BuildContext? cowCtx = _cowContainerKey.currentContext;
    Offset center = Offset(screenSize.width * 0.22, screenSize.height * 0.42);

    if (cowCtx != null) {
      final RenderBox? box = cowCtx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final Offset topLeft = box.localToGlobal(Offset.zero);
        center = Offset(
          topLeft.dx + box.size.width * 0.5,
          topLeft.dy + box.size.height * 0.5,
        );
      }
    }

    final double halfW = (screenSize.width * 0.45).clamp(200.0, 2000.0);
    final double halfH = (screenSize.height * 0.45).clamp(200.0, 2000.0);

    setState(() {
      _pointerNormalized = Offset(
        ((globalPosition.dx - center.dx) / halfW).clamp(-1.0, 1.0),
        ((globalPosition.dy - center.dy) / halfH).clamp(-1.0, 1.0),
      );
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
    final bool ok = await context.read<UserController>().sendPasswordReset(
          identifier,
        );
    if (!mounted) return;
    setState(() {
      _localNotice = ok
          ? 'Enviamos un correo de recuperación de contraseña a $identifier.'
          : context.read<UserController>().errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final Size size = MediaQuery.of(context).size;
    final bool isDesktop = size.width >= 900;

    return MouseRegion(
      onHover: (PointerHoverEvent event) =>
          _updatePointerFromGlobal(event.position),
      onExit: (_) => setState(() => _pointerNormalized = Offset.zero),
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Stack(
          children: <Widget>[
            SafeArea(
              top: !isDesktop,
              bottom: !isDesktop,
              child: isDesktop
                  ? _buildDesktopLayout(auth)
                  : _buildMobileLayout(auth),
            ),
            // Telón institucional oscuro durante la validación de credenciales
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

  Widget _buildDesktopLayout(AuthController auth) {
    return Row(
      children: <Widget>[
        // Panel izquierdo editorial en tinta negra (44%)
        Expanded(
          flex: 44,
          child: Container(
            color: AppTheme.inkBlack,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const MilkFlowBackground(opacity: 0.92),
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 28, 36, 26),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Encabezado de marca
                        Row(
                          children: <Widget>[
                            const AsoproganucotLogo(
                              size: 38,
                              compact: true,
                              onDark: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    AppConstants.appName,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const Text(
                                    'Susa · Cundinamarca',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0x88FFFFFF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Escenario central vaca Holstein
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 230,
                                maxHeight: 185,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  // Halos de escenario sutiles (luz sobre suelo oscuro)
                                  Container(
                                    width: 154,
                                    height: 154,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                      ),
                                      gradient: RadialGradient(
                                        colors: <Color>[
                                          Colors.white.withValues(alpha: 0.09),
                                          AppTheme.primaryGreen
                                              .withValues(alpha: 0.04),
                                          Colors.transparent,
                                        ],
                                        stops: const <double>[0.0, 0.55, 1.0],
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      key: _cowContainerKey,
                                      alignment: Alignment.center,
                                      child: CowBalloon3DWidget(
                                        pointerNormalized: _pointerNormalized,
                                        showContactShadow: false,
                                        scaleFactor: 0.26,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Titular editorial escalonado
                        _StaggeredLine(
                          animation: _line1Anim,
                          text: 'Recepción láctea,',
                          color: Colors.white,
                        ),
                        _StaggeredLine(
                          animation: _line2Anim,
                          text: 'control quincenal y',
                          color: Colors.white,
                        ),
                        _StaggeredLine(
                          animation: _line3Anim,
                          text: 'trazabilidad en campo.',
                          color: const Color(0xFFA7F3D0),
                          italic: true,
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                          child: const Text(
                            'Planta de Acopio · Gestión de Productores y Liquidaciones',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0x88FFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Hoja derecha pura y blanca (56%)
        Expanded(
          flex: 56,
          child: Container(
            color: AppTheme.surface,
            alignment: Alignment.center,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _buildLoginForm(auth, isMobile: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(AuthController auth) {
    return Column(
      children: <Widget>[
        Container(
          height: 185,
          width: double.infinity,
          color: AppTheme.inkBlack,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const MilkFlowBackground(opacity: 0.9),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const AsoproganucotLogo(
                          size: 32,
                          compact: true,
                          onDark: true,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppConstants.appName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Text(
                          'Susa',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0x88FFFFFF),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Container(
                        key: _cowContainerKey,
                        alignment: Alignment.center,
                        child: CowBalloon3DWidget(
                          pointerNormalized: _pointerNormalized,
                          showContactShadow: false,
                          scaleFactor: 0.28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: AppTheme.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildLoginForm(auth, isMobile: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(AuthController auth, {required bool isMobile}) {
    final String? error = auth.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'ACCESO AL SISTEMA',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryGreen,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Iniciar sesión',
          style: AppTheme.serifStyle(
            fontSize: isMobile ? 25 : 29,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ingresa tu usuario o correo institucional para continuar.',
          style: TextStyle(
            fontSize: 13.5,
            color: AppTheme.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        const _FieldLabel('Usuario o correo electrónico'),
        const SizedBox(height: 6),
        TextField(
          controller: _identifierCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.username],
          onChanged: (_) {
            if (auth.errorMessage != null) auth.clearError();
          },
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          decoration: const InputDecoration(
            hintText: 'usuario@asoproganucott.com',
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Contraseña'),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onChanged: (_) {
            _refreshCapsLock();
            if (auth.errorMessage != null) auth.clearError();
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Ingresa tu contraseña',
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppTheme.textMuted,
            ),
            suffixIcon: IconButton(
              tooltip: _obscurePassword
                  ? 'Mostrar contraseña'
                  : 'Ocultar contraseña',
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
        if (_capsLockOn) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warningBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.keyboard_capslock_rounded,
                  size: 15,
                  color: AppTheme.warningText,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Bloq Mayús activado',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.warningText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: AppTheme.inkBlack,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(
                            color: AppTheme.inputBorder,
                            width: 1.3,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (bool? v) {
                            setState(() => _rememberMe = v ?? true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'Recordar acceso',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: auth.isLoading ? null : _handleForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '¿Olvidaste tu contraseña?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.dangerBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.danger.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 17,
                  color: AppTheme.dangerText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.dangerText,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_localNotice != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: AppTheme.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              _localNotice!,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.successText,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        PrimaryActionButton(
          label: 'Ingresar al sistema',
          icon: Icons.login_rounded,
          isLoading: auth.isLoading,
          isMobile: isMobile,
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Row(
          children: <Widget>[
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: AppTheme.textMuted,
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Asociación de Productores y Ganaderos · Susa, Cundinamarca.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StaggeredLine extends StatelessWidget {
  const _StaggeredLine({
    required this.animation,
    required this.text,
    required this.color,
    this.italic = false,
  });

  final Animation<double> animation;
  final String text;
  final Color color;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double v = animation.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * 12),
            child: child,
          ),
        );
      },
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.sourceSerif4(
          fontSize: 28,
          height: 1.16,
          letterSpacing: -0.45,
          fontWeight: FontWeight.w500,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: color,
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
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }
}
