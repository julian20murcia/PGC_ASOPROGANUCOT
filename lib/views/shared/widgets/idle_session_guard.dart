import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Cierra la sesión tras [timeout] sin interacción (mouse o teclado).
///
/// [warningBefore] antes del cierre muestra un aviso con cuenta regresiva y el
/// botón "Seguir conectado". Solo se activa cuando [enabled] es true (en la
/// plataforma de escritorio).
class IdleSessionGuard extends StatefulWidget {
  const IdleSessionGuard({
    super.key,
    required this.child,
    required this.onTimeout,
    this.enabled = true,
    this.timeout = const Duration(minutes: 10),
    this.warningBefore = const Duration(seconds: 60),
  });

  final Widget child;
  final VoidCallback onTimeout;
  final bool enabled;
  final Duration timeout;
  final Duration warningBefore;

  /// Escritorio real (Windows, macOS, Linux).
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  State<IdleSessionGuard> createState() => _IdleSessionGuardState();
}

class _IdleSessionGuardState extends State<IdleSessionGuard> with WidgetsBindingObserver {
  Timer? _idleTimer;
  Timer? _tick;
  DateTime _lastActivity = clock.now();
  bool _warning = false;
  int _secondsLeft = 0;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _restart();
  }

  @override
  void didUpdateWidget(IdleSessionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _restart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idleTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de suspensión/minimizado, verifica el tiempo real transcurrido.
    if (state == AppLifecycleState.resumed) _checkElapsed();
  }

  bool _onKey(KeyEvent event) {
    _activity();
    return false;
  }

  void _activity() {
    if (!widget.enabled || _fired) return;
    _lastActivity = clock.now();
    if (_warning) {
      setState(() => _warning = false);
    }
    _restart();
  }

  void _restart() {
    _idleTimer?.cancel();
    _tick?.cancel();
    if (!widget.enabled) return;
    final Duration untilWarning = widget.timeout - widget.warningBefore;
    _idleTimer = Timer(untilWarning, _startWarning);
  }

  void _checkElapsed() {
    if (!widget.enabled || _fired) return;
    final Duration idle = clock.now().difference(_lastActivity);
    if (idle >= widget.timeout) {
      _expire();
    } else if (idle >= widget.timeout - widget.warningBefore && !_warning) {
      _startWarning();
    }
  }

  void _startWarning() {
    if (!mounted || _fired) return;
    setState(() {
      _warning = true;
      _secondsLeft = (widget.timeout - clock.now().difference(_lastActivity)).inSeconds
          .clamp(0, widget.warningBefore.inSeconds);
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final int left = (widget.timeout - clock.now().difference(_lastActivity)).inSeconds;
      if (left <= 0) {
        _expire();
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  void _expire() {
    if (_fired) return;
    _fired = true;
    _tick?.cancel();
    _idleTimer?.cancel();
    if (mounted) setState(() => _warning = false);
    widget.onTimeout();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activity(),
      onPointerHover: (_) => _activity(),
      onPointerSignal: (_) => _activity(),
      child: Stack(
        children: <Widget>[
          widget.child,
          if (_warning)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x66082826),
                child: Center(
                  child: _IdleWarningCard(
                    secondsLeft: _secondsLeft,
                    onStay: _activity,
                    onLogout: _expire,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IdleWarningCard extends StatelessWidget {
  const _IdleWarningCard({required this.secondsLeft, required this.onStay, required this.onLogout});

  final int secondsLeft;
  final VoidCallback onStay;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.shadowMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: secondsLeft / 60,
                    strokeWidth: 4,
                    backgroundColor: AppTheme.accentSoft,
                    color: AppTheme.accent,
                  ),
                  Text(
                    '$secondsLeft',
                    style: AppTheme.monoStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('¿Sigues ahí?', style: AppTheme.titleStyle()),
            const SizedBox(height: 6),
            Text(
              'Por seguridad, la sesión se cerrará automáticamente en $secondsLeft segundos por inactividad.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(onPressed: onLogout, child: const Text('Cerrar sesión')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey<String>('idle_stay_button'),
                    onPressed: onStay,
                    child: const Text('Seguir conectado'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
