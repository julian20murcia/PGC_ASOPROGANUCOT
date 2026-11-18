import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum DairyLoaderSize { xs, sm, md, lg }

/// Indicador de carga animado de ASOPROGANUCOT:
/// una botella de leche que se llena con doble ola sinusoidal y gota cayendo.
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
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _height {
    switch (widget.size) {
      case DairyLoaderSize.xs:
        return 18;
      case DairyLoaderSize.sm:
        return 24;
      case DairyLoaderSize.md:
        return 56;
      case DairyLoaderSize.lg:
        return 76;
    }
  }

  double get _strokeWidth {
    switch (widget.size) {
      case DairyLoaderSize.xs:
        return 4.0;
      case DairyLoaderSize.sm:
        return 3.4;
      case DairyLoaderSize.md:
      case DairyLoaderSize.lg:
        return 2.4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmall = widget.size == DairyLoaderSize.xs ||
        widget.size == DairyLoaderSize.sm;
    final bool isInline = widget.inline ?? isSmall;
    final Color tone = widget.color ??
        (widget.size == DairyLoaderSize.xs
            ? DefaultTextStyle.of(context).style.color ?? Colors.white
            : AppTheme.cowBlack);

    final double height = _height;
    final double width = height * (48.0 / 80.0);

    final Widget bottle = SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _DairyBottlePainter(
              progress: _controller.value,
              color: tone,
              strokeWidth: _strokeWidth,
              isTiny: widget.size == DairyLoaderSize.xs,
            ),
          );
        },
      ),
    );

    final bool hasText =
        (widget.label != null && widget.label!.isNotEmpty) ||
            (widget.hint != null && widget.hint!.isNotEmpty);

    if (!hasText) {
      return Semantics(label: 'Cargando', child: bottle);
    }

    final Widget copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isInline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        if (widget.label != null && widget.label!.isNotEmpty)
          Text(
            widget.label!,
            textAlign: isInline ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: widget.size == DairyLoaderSize.lg
                  ? 15.5
                  : widget.size == DairyLoaderSize.sm
                      ? 13
                      : 14,
              fontWeight: widget.size == DairyLoaderSize.sm
                  ? FontWeight.w500
                  : FontWeight.w600,
              color: widget.size == DairyLoaderSize.xs
                  ? tone
                  : AppTheme.textPrimary,
            ),
          ),
        if (widget.hint != null && widget.hint!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              widget.hint!,
              textAlign: isInline ? TextAlign.left : TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );

    if (isInline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          bottle,
          SizedBox(width: widget.size == DairyLoaderSize.xs ? 8 : 10),
          Flexible(child: copy),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        bottle,
        SizedBox(height: widget.size == DairyLoaderSize.lg ? 18 : 14),
        copy,
      ],
    );
  }
}

class _DairyBottlePainter extends CustomPainter {
  const _DairyBottlePainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.isTiny,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final bool isTiny;

  @override
  void paint(Canvas canvas, Size size) {
    // Coordenadas lógicas viewBox 0 -14 48 80
    final double scaleX = size.width / 48.0;
    final double scaleY = size.height / 80.0;
    final double s = math.min(scaleX, scaleY);

    canvas.save();
    canvas.translate(
      (size.width - 48.0 * s) * 0.5,
      (size.height - 80.0 * s) * 0.5 + 14.0 * s,
    );
    canvas.scale(s, s);

    // Silueta exacta de la botella de leche
    final Path bottlePath = Path()
      ..moveTo(19, 4)
      ..lineTo(29, 4)
      ..lineTo(29, 14)
      ..cubicTo(29, 18, 38, 21, 38, 29)
      ..lineTo(38, 55)
      ..arcToPoint(
        const Offset(33, 60),
        radius: const Radius.circular(5),
        clockwise: true,
      )
      ..lineTo(15, 60)
      ..arcToPoint(
        const Offset(10, 55),
        radius: const Radius.circular(5),
        clockwise: true,
      )
      ..lineTo(10, 29)
      ..cubicTo(10, 21, 19, 18, 19, 14)
      ..close();

    // 1. Gota cayendo (4 ciclos por vuelta de 2.6s)
    final double dropPhase = (progress * 4.0) % 1.0;
    final double dropY = -12.0 + dropPhase * 30.0;
    final double dropOpacity = dropPhase < 0.25
        ? dropPhase / 0.25
        : (1.0 - (dropPhase - 0.25) / 0.75);
    if (dropOpacity > 0.01) {
      final Paint dropPaint = Paint()
        ..color = color.withValues(alpha: dropOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(24, dropY), 2.4, dropPaint);
    }

    // 2. Nivel de llenado (0->0.10 entra, 0.10->0.72 sube de 54 a 22, 0.88->1 fade out)
    double fillDy = 22.0;
    double fillOpacity = 1.0;
    if (progress < 0.10) {
      final double t = progress / 0.10;
      fillDy = 54.0 - t * 6.0;
      fillOpacity = t;
    } else if (progress < 0.72) {
      final double t = Curves.easeInOut.transform((progress - 0.10) / 0.62);
      fillDy = 48.0 - t * 26.0;
      fillOpacity = 1.0;
    } else if (progress <= 0.88) {
      fillDy = 22.0;
      fillOpacity = 1.0;
    } else {
      fillDy = 22.0;
      fillOpacity = (1.0 - (progress - 0.88) / 0.12).clamp(0.0, 1.0);
    }

    canvas.save();
    canvas.clipPath(bottlePath);

    if (fillOpacity > 0.01) {
      final double frontAlpha = (isTiny ? 0.58 : 0.34) * fillOpacity;
      final double backAlpha = (isTiny ? 0.30 : 0.18) * fillOpacity;

      final Path backWave = _buildWavePath(
        yBase: fillDy,
        phase: -progress * math.pi * 2 * 1.4,
        amplitude: 3.2,
      );
      canvas.drawPath(
        backWave,
        Paint()
          ..color = color.withValues(alpha: backAlpha)
          ..style = PaintingStyle.fill,
      );

      final Path frontWave = _buildWavePath(
        yBase: fillDy + 1.0,
        phase: progress * math.pi * 2 * 2.0,
        amplitude: 3.6,
      );
      canvas.drawPath(
        frontWave,
        Paint()
          ..color = color.withValues(alpha: frontAlpha)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();

    // 3. Contorno de cristal de la botella
    final Paint glassPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(bottlePath, glassPaint);
    canvas.drawLine(const Offset(17, 4), const Offset(31, 4), glassPaint);

    canvas.restore();
  }

  Path _buildWavePath({
    required double yBase,
    required double phase,
    required double amplitude,
  }) {
    final Path path = Path()..moveTo(6, 70);
    for (double x = 6; x <= 42; x += 2.0) {
      final double y =
          yBase + math.sin((x / 48.0) * math.pi * 2 * 1.5 + phase) * amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(42, 70);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _DairyBottlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
