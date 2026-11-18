import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/cow_balloon_3d_widget.dart';
import 'widgets/dairy_loader.dart';
import 'widgets/design_system_widgets.dart';

/// Pantalla de inicio de sesión multiplataforma estilo Houston + Holstein.
/// Incluye modelo 3D nítido animado con el puntero y animaciones de carga.
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

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _didLoadSaved = false;
  Offset _pointerNormalized = Offset.zero;
  String? _localNotice;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _fadeAnim = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
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
    _entryController.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _updatePointerFromGlobal(Offset globalPosition) {
    final Size screenSize = MediaQuery.of(context).size;
    final BuildContext? cowCtx = _cowContainerKey.currentContext;
    Offset center = Offset(screenSize.width * 0.25, screenSize.height * 0.36);

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

    final double halfW = (screenSize.width * 0.5).clamp(200.0, 2000.0);
    final double halfH = (screenSize.height * 0.5).clamp(200.0, 2000.0);

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
            'Escribe tu correo electrónico en el primer campo y pulsa "¿La olvidaste?" para enviar el enlace de recuperación.';
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
      onHover: (event) => _updatePointerFromGlobal(event.position),
      onExit: (_) => setState(() => _pointerNormalized = Offset.zero),
      child: Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: isDesktop
                  ? _buildDesktopLayout(auth)
                  : _buildMobileLayout(auth),
            ),
            // Overlay animado con DairyLoader al iniciar sesión
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !auth.isLoading,
                child: AnimatedOpacity(
                  opacity: auth.isLoading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                  child: Container(
                    color: AppTheme.canvas.withValues(alpha: 0.88),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: AppTheme.cowBlack.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const DairyLoader(
                        size: DairyLoaderSize.lg,
                        label: 'Validando credenciales…',
                        hint: 'Conectando con Firebase Auth y tu perfil en ASOPROGANUCOTT.',
                      ),
                    ),
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
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: <Widget>[
          // Marco izquierdo Holstein con modelo 3D proporcionado
          Expanded(
            flex: 11,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: const CowSpotPatternPainter(
                  spotColor: Color(0x0E14161D),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(44, 28, 36, 28),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const AsoproganucotLogo(size: 46, compact: true),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    AppConstants.appName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.cowBlack,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const Text(
                                    'Susa · Valle de Ubaté, Cundinamarca',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 340,
                                  maxHeight: 280,
                                ),
                                child: Container(
                                  key: _cowContainerKey,
                                  alignment: Alignment.center,
                                  child: CowBalloon3DWidget(
                                    pointerNormalized: _pointerNormalized,
                                    scaleFactor: 0.25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Todo tu proceso,\nen un solo lugar.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    height: 1.12,
                                    letterSpacing: -0.8,
                                    color: AppTheme.cowBlack,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Ingresa para continuar con la recepción diaria de leche cruda, gestión de asociados, liquidación quincenal y consulta en campo.',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    height: 1.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  runSpacing: 6,
                                  children: <Widget>[
                                    const Text(
                                      'Recepción',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    _metaDot(),
                                    const Text(
                                      'Offline-First',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                    _metaDot(),
                                    const Text(
                                      'Liquidación',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Pantalla blanca flotante derecha
          Expanded(
            flex: 10,
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppTheme.cowBlack.withValues(alpha: 0.045),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(36),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _buildFormCardContent(auth, isMobile: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaDot() {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppTheme.textMuted,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildMobileLayout(AuthController auth) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: <Widget>[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: CustomPaint(
                painter: const CowSpotPatternPainter(
                  spotColor: Color(0x0C14161D),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        key: _cowContainerKey,
                        height: 150,
                        width: double.infinity,
                        child: CowBalloon3DWidget(
                          pointerNormalized: _pointerNormalized,
                          scaleFactor: 0.28,
                        ),
                      ),
                      const AsoproganucotLogo(size: 86),
                      const SizedBox(height: 4),
                      const Text(
                        'Susa · Valle de Ubaté, Cundinamarca',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: _buildFormCardContent(auth, isMobile: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCardContent(AuthController auth, {required bool isMobile}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: AsoproganucotLogo(size: isMobile ? 64 : 108),
        ),
        const SizedBox(height: 18),
        Text(
          'Inicia sesión',
          style: AppTheme.titleStyle(isMobile: isMobile),
        ),
        const SizedBox(height: 4),
        const Text(
          'Usa las credenciales asignadas a tu cuenta.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        if (auth.errorMessage != null) ...<Widget>[
          const SizedBox(height: 16),
          _AlertBanner(
            message: auth.errorMessage!,
            isError: true,
          ),
        ],
        if (_localNotice != null) ...<Widget>[
          const SizedBox(height: 16),
          _AlertBanner(
            message: _localNotice!,
            isError: false,
          ),
        ],
        const SizedBox(height: 22),
        const Text(
          'Correo electrónico o documento',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _identifierCtrl,
          enabled: !auth.isLoading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: (_) => auth.clearError(),
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          decoration: const InputDecoration(
            hintText: 'usuario@asoproganucot.com o cédula',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text(
              'Contraseña',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            TextButton(
              onPressed: auth.isLoading ? null : _handleForgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.textSecondary,
              ),
              child: const Text(
                '¿La olvidaste?',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          enabled: !auth.isLoading,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onChanged: (_) => auth.clearError(),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Ingresa tu contraseña',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
            suffixIcon: IconButton(
              onPressed: auth.isLoading
                  ? null
                  : () => setState(() => _obscurePassword = !_obscurePassword),
              tooltip: _obscurePassword
                  ? 'Mostrar contraseña'
                  : 'Ocultar contraseña',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        InkWell(
          onTap: auth.isLoading
              ? null
              : () => setState(() => _rememberMe = !_rememberMe),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: auth.isLoading
                        ? null
                        : (bool? v) =>
                            setState(() => _rememberMe = v ?? true),
                    activeColor: AppTheme.cowBlack,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Mantener mi sesión iniciada',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: isMobile ? 50 : 44,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cowBlack,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.cowBlack.withValues(alpha: 0.78),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
            ),
            child: auth.isLoading
                ? const DairyLoader(
                    size: DairyLoaderSize.xs,
                    label: 'Iniciando sesión…',
                    color: Colors.white,
                  )
                : const Text(
                    'Iniciar sesión',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const <Widget>[
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: AppTheme.primaryGreen,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Acceso cifrado · Firebase Auth & Hive',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
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

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final Color bg = isError ? AppTheme.dangerBg : AppTheme.canvasAlt;
    final Color fg = isError ? AppTheme.dangerText : AppTheme.textPrimary;
    final Color border = isError
        ? AppTheme.danger.withValues(alpha: 0.35)
        : AppTheme.border;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.4, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
