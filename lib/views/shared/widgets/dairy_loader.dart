import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

enum DairyLoaderSize { xs, sm, md, lg }

/// Indicador de carga original de ASOPROGANUCOT:
/// cantina lechera tradicional con llenado ondulatorio y órbita de sincronización.
class DairyLoader extends StatefulWidget {
  const DairyLoader({
    super.key,
    this.label = 'Cargando…',
    this.hint,
    this.size = DairyLoaderSize.md,
    this.inline,
    this.color,
  });

  final String? label;
  final String? hint;
  final DairyLoaderSize size;
  final bool? inline;
  final Color? color;

  @override
  State<DairyLoader> createState() => _DairyLoaderState();
}

class _DairyLoaderState extends State<DairyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _boxSize {
    switch (widget.size) {
      case DairyLoaderSize.xs:
        return 18;
      case DairyLoaderSize.sm:
        return 26;
      case DairyLoaderSize.md:
        return 58;
      case DairyLoaderSize.lg:
        return 80;
    }
  }

  double get _strokeWidth {
    switch (widget.size) {
      case DairyLoaderSize.xs:
        return 1.8;
      case DairyLoaderSize.sm:
        return 2.0;
      case DairyLoaderSize.md:
      case DairyLoaderSize.lg:
        return 2.2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmall =
        widget.size == DairyLoaderSize.xs || widget.size == DairyLoaderSize.sm;
    final bool isInline = widget.inline ?? isSmall;
    final Color tone = widget.color ??
        (widget.size == DairyLoaderSize.xs
            ? DefaultTextStyle.of(context).style.color ?? Colors.white
            : AppTheme.inkBlack);

    final double dim = _boxSize;
    final Widget churn = SizedBox(
      width: dim,
      height: dim,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _MilkChurnPainter(
              progress: _controller.value,
              color: tone,
              strokeWidth: _strokeWidth,
              compact: isSmall,
            ),
          );
        },
      ),
    );

    final String? cleanLabel =
        (widget.label == null || widget.label!.trim().isEmpty)
            ? null
            : widget.label;
    final String? cleanHint =
        (widget.hint == null || widget.hint!.trim().isEmpty) ? null : widget.hint;

    if (cleanLabel == null && cleanHint == null) {
      return churn;
    }

    if (isInline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          churn,
          if (cleanLabel != null) ...<Widget>[
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                cleanLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.size == DairyLoaderSize.xs ? 12.5 : 13.5,
                  fontWeight: FontWeight.w500,
                  color: widget.color ?? AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            churn,
            if (cleanLabel != null) ...<Widget>[
              const SizedBox(height: 14),
              Text(
                cleanLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.size == DairyLoaderSize.lg ? 15 : 13.5,
                  fontWeight: FontWeight.w600,
                  color: widget.color ?? AppTheme.textPrimary,
                ),
              ),
            ],
            if (cleanHint != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                cleanHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: (widget.color ?? AppTheme.textMuted)
                      .withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MilkChurnPainter extends CustomPainter {
  _MilkChurnPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.compact,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset center = Offset(w * 0.5, h * 0.5);

    // Anillo orbital sutil solo en tamaños medianos y grandes
    if (!compact) {
      final double orbitRadius = math.min(w, h) * 0.46;
      final Rect orbitRect = Rect.fromCircle(center: center, radius: orbitRadius);
      final Paint trackPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawCircle(center, orbitRadius, trackPaint);

      final double startAngle = progress * 2 * math.pi - math.pi / 2;
      final Paint arcPaint = Paint()
        ..color = AppTheme.primaryGreen.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6;
      canvas.drawArc(orbitRect, startAngle, math.pi * 0.65, false, arcPaint);

      final double dotAngle = startAngle + math.pi * 0.65;
      final Offset dotCenter = Offset(
        center.dx + orbitRadius * math.cos(dotAngle),
        center.dy + orbitRadius * math.sin(dotAngle),
      );
      canvas.drawCircle(
        dotCenter,
        2.3,
        Paint()..color = AppTheme.primaryGreen,
      );
    }

    // Geometría de cantina lechera tradicional de Susa
    final double scale = compact ? 0.88 : 0.56;
    final double cw = w * scale;
    final double ch = h * scale;
    final double ox = (w - cw) * 0.5;
    final double oy = (h - ch) * 0.5;

    final Path churnBody = Path()
      // Borde izquierdo del cuello hacia hombro y cuerpo
      ..moveTo(ox + cw * 0.34, oy + ch * 0.17)
      ..lineTo(ox + cw * 0.34, oy + ch * 0.28)
      ..cubicTo(
        ox + cw * 0.24,
        oy + ch * 0.33,
        ox + cw * 0.18,
        oy + ch * 0.40,
        ox + cw * 0.18,
        oy + ch * 0.48,
      )
      ..lineTo(ox + cw * 0.19, oy + ch * 0.87)
      ..quadraticBezierTo(
        ox + cw * 0.20,
        oy + ch * 0.94,
        ox + cw * 0.28,
        oy + ch * 0.94,
      )
      ..lineTo(ox + cw * 0.72, oy + ch * 0.94)
      ..quadraticBezierTo(
        ox + cw * 0.80,
        oy + ch * 0.94,
        ox + cw * 0.81,
        oy + ch * 0.87,
      )
      ..lineTo(ox + cw * 0.82, oy + ch * 0.48)
      ..cubicTo(
        ox + cw * 0.82,
        oy + ch * 0.40,
        ox + cw * 0.76,
        oy + ch * 0.33,
        ox + cw * 0.66,
        oy + ch * 0.28,
      )
      ..lineTo(ox + cw * 0.66, oy + ch * 0.17)
      ..close();

    // Nivel de leche con ciclo suave
    final double cycle = 0.5 - 0.5 * math.cos(progress * 2 * math.pi);
    final double fillFraction = 0.24 + cycle * 0.52;
    final double liquidBottom = oy + ch * 0.94;
    final double liquidHeight = ch * 0.62 * fillFraction;
    final double waveY = liquidBottom - liquidHeight;

    canvas.save();
    canvas.clipPath(churnBody);

    final Path backWave = Path()..moveTo(ox, liquidBottom);
    final Path frontWave = Path()..moveTo(ox, liquidBottom);
    final double phase = progress * 2 * math.pi;
    final double amp = compact ? ch * 0.035 : ch * 0.04;

    for (double x = ox; x <= ox + cw; x += math.max(1.0, cw / 18)) {
      final double nx = ((x - ox) / cw) * 2 * math.pi;
      final double yBack = waveY - 1.5 + math.sin(nx - phase * 1.3 + 1.1) * (amp * 0.8);
      final double yFront = waveY + math.sin(nx + phase * 1.8) * amp;
      backWave.lineTo(x, yBack);
      frontWave.lineTo(x, yFront);
    }
    backWave
      ..lineTo(ox + cw, liquidBottom)
      ..close();
    frontWave
      ..lineTo(ox + cw, liquidBottom)
      ..close();

    canvas.drawPath(
      backWave,
      Paint()
        ..color = color.withValues(alpha: 0.24)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      frontWave,
      Paint()
        ..color = color.withValues(alpha: 0.88)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();

    // Contorno principal de la cantina
    final Paint outlinePaint = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(churnBody, outlinePaint);

    // Tapa y collar de la boca
    canvas.drawLine(
      Offset(ox + cw * 0.29, oy + ch * 0.17),
      Offset(ox + cw * 0.71, oy + ch * 0.17),
      outlinePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ox + cw * 0.38, oy + ch * 0.08, cw * 0.24, ch * 0.08),
        const Radius.circular(2),
      ),
      outlinePaint,
    );

    // Asas laterales características de la cantina
    final Path leftHandle = Path()
      ..moveTo(ox + cw * 0.20, oy + ch * 0.42)
      ..cubicTo(
        ox + cw * 0.04,
        oy + ch * 0.40,
        ox + cw * 0.04,
        oy + ch * 0.56,
        ox + cw * 0.18,
        oy + ch * 0.56,
      );
    final Path rightHandle = Path()
      ..moveTo(ox + cw * 0.80, oy + ch * 0.42)
      ..cubicTo(
        ox + cw * 0.96,
        oy + ch * 0.40,
        ox + cw * 0.96,
        oy + ch * 0.56,
        ox + cw * 0.82,
        oy + ch * 0.56,
      );
    canvas.drawPath(leftHandle, outlinePaint);
    canvas.drawPath(rightHandle, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _MilkChurnPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.compact != compact;
  }
}

/// Marcador de fondo limpio para superficies oscuras de ASOPROGANUCOT
/// sin animaciones ni partículas continuas para mantener máxima fluidez.
class MilkFlowBackground extends StatelessWidget {
  const MilkFlowBackground({
    super.key,
    this.bottomMasked = false,
    this.opacity = 1.0,
  });

  final bool bottomMasked;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// Telón de transición institucional de ASOPROGANUCOT con flujo lácteo y
/// disolución radial al completar el acceso o carga inicial.
class AsoproganucotCurtain extends StatelessWidget {
  const AsoproganucotCurtain({
    super.key,
    this.statusText = 'Preparando entorno…',
    this.eyebrow = 'ASOPROGANUCOT · SUSA',
    this.revealProgress = 0.0,
    this.onSkip,
  });

  final String statusText;
  final String eyebrow;

  /// Valor en `[0.0, 1.0]`: `0.0` mantiene el telón cerrado, `> 0.0` abre una
  /// disolución radial desde el centro hacia afuera.
  final double revealProgress;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final Widget body = Container(
      color: AppTheme.inkBlack,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const MilkFlowBackground(opacity: 0.9),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      eyebrow,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w600,
                        color: Color(0x99FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const DairyLoader(
                      size: DairyLoaderSize.md,
                      label: null,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.sourceSerif4(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xB8FFFFFF),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _IndeterminateHairlineBar(),
                    if (onSkip != null) ...<Widget>[
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0x99FFFFFF),
                        ),
                        child: const Text(
                          'Continuar ahora',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (revealProgress <= 0.001) {
      return body;
    }

    final double p = Curves.easeInOutCubic.transform(revealProgress.clamp(0.0, 1.0));
    final double r = (-0.25 + 1.55 * p).clamp(0.0, 2.0);
    final double inner = math.max(0.0, r - 0.14);

    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return RadialGradient(
            center: Alignment.center,
            radius: 1.0,
            stops: <double>[inner.clamp(0.0, 1.0), r.clamp(0.0, 1.0)],
            colors: const <Color>[
              Colors.transparent,
              Colors.white,
            ],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: Opacity(
          opacity: (1.0 - p * 0.25).clamp(0.0, 1.0),
          child: body,
        ),
      ),
    );
  }
}

class _IndeterminateHairlineBar extends StatefulWidget {
  const _IndeterminateHairlineBar();

  @override
  State<_IndeterminateHairlineBar> createState() =>
      _IndeterminateHairlineBarState();
}

class _IndeterminateHairlineBarState extends State<_IndeterminateHairlineBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 2,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(2),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final double v = _controller.value;
          final double alignX = -1.6 + v * 3.2;
          return Align(
            alignment: Alignment(alignX.clamp(-1.0, 1.0), 0),
            child: Container(
              width: 68,
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        },
      ),
    );
  }
}
