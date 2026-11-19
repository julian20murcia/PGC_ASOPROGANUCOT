import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Kit visual del portal móvil del productor ("Pradera móvil").
///
/// Identidad: encabezado con degradado teal → brandDeep, superficies blancas,
/// radios 16–20, sombras suaves y tipografía ≥ 14 px para lectura en campo.
class MobileTokens {
  MobileTokens._();

  static const double radius = 18;
  static const double radiusSm = 14;
  static const double gutter = 16;

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[AppTheme.brand, AppTheme.brandDeep],
  );

  static const Color morning = AppTheme.brand;
  static const Color afternoon = AppTheme.accent;

  static List<BoxShadow> get cardShadow => const <BoxShadow>[
        BoxShadow(
          color: Color(0x0F0B3B37),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
        BoxShadow(
          color: Color(0x080F1B1E),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ];

  static TextStyle display({double size = 28, Color color = AppTheme.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: color,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  static TextStyle title({double size = 17, Color color = AppTheme.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: color,
      );

  static TextStyle body({
    double size = 14,
    Color color = AppTheme.textSecondary,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static TextStyle label({Color color = AppTheme.textMuted, double size = 12.5}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      );

  static TextStyle number({
    double size = 15,
    Color color = AppTheme.textPrimary,
    FontWeight weight = FontWeight.w700,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.2,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

/// Tonos semánticos del kit móvil.
enum MTone { brand, accent, success, warning, danger, info, neutral }

extension MToneColors on MTone {
  Color get fg => switch (this) {
        MTone.brand => AppTheme.brand,
        MTone.accent => AppTheme.accentDeep,
        MTone.success => AppTheme.successText,
        MTone.warning => AppTheme.warningText,
        MTone.danger => AppTheme.dangerText,
        MTone.info => AppTheme.infoText,
        MTone.neutral => AppTheme.textSecondary,
      };

  Color get solid => switch (this) {
        MTone.brand => AppTheme.brand,
        MTone.accent => AppTheme.accent,
        MTone.success => AppTheme.success,
        MTone.warning => AppTheme.warning,
        MTone.danger => AppTheme.danger,
        MTone.info => AppTheme.info,
        MTone.neutral => AppTheme.textMuted,
      };

  Color get bg => switch (this) {
        MTone.brand => AppTheme.brandSoft,
        MTone.accent => AppTheme.accentSoft,
        MTone.success => AppTheme.successBg,
        MTone.warning => AppTheme.warningBg,
        MTone.danger => AppTheme.dangerBg,
        MTone.info => AppTheme.infoBg,
        MTone.neutral => AppTheme.surfaceSunken,
      };
}

/// Superficie blanca con radio amplio y sombra suave. Nunca anidar una dentro de otra.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = AppTheme.surface,
    this.radius = MobileTokens.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        boxShadow: MobileTokens.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Título de sección con acción opcional.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: MobileTokens.title(), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Píldora de estado legible en campo.
class TonePill extends StatelessWidget {
  const TonePill(this.text, {super.key, this.tone = MTone.neutral, this.icon, this.onDark = false});

  final String text;
  final MTone tone;
  final IconData? icon;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color fg = onDark ? Colors.white : tone.fg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.16) : tone.bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icono dentro de un cuadro redondeado tonal.
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.tone = MTone.brand, this.size = 40});

  final IconData icon;
  final MTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.52, color: tone.solid),
    );
  }
}

/// Encabezado degradado de cada pestaña.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.bottom,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(
        gradient: MobileTokens.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _HeaderDecor()),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 12, bottom == null ? 22 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (leading != null) ...<Widget>[leading!, const SizedBox(width: 6)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MobileTokens.title(size: 22, color: Colors.white),
                          ),
                          if (subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MobileTokens.body(
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                if (bottom != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Padding(padding: const EdgeInsets.only(right: 8), child: bottom!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ondas decorativas sutiles del encabezado (identidad "pradera").
class _HeaderDecor extends StatelessWidget {
  const _HeaderDecor();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: CustomPaint(painter: _WavePainter()),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.05), size.width * 0.32, p);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 1.05), size.width * 0.22, p);
    final Path wave = Path()
      ..moveTo(0, size.height * 0.82)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.70, size.width * 0.6, size.height * 0.86)
      ..quadraticBezierTo(size.width * 0.82, size.height * 0.96, size.width, size.height * 0.84)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, Paint()..color = Colors.white.withValues(alpha: 0.04));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Botón circular translúcido para el encabezado.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(icon, color: Colors.white, size: 21),
                  if (badge > 0)
                    Positioned(top: 4, right: 3, child: CountBadge(count: badge, ringColor: AppTheme.brand)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Contador rojo/ámbar para no leídos.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.ringColor = AppTheme.surface});

  final int count;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final String text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppTheme.danger,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: ringColor, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
      ),
    );
  }
}

/// Número animado desde 0 (contador) con formato personalizado.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final double value;
  final String Function(double) format;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final double safe = value.isFinite ? value : 0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: safe),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(format(v), maxLines: 1, style: style),
      ),
    );
  }
}

/// Entrada escalonada (fade + slide) sin temporizadores.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final int delay = (widget.index.clamp(0, 8)) * 70;
    final int total = 420 + delay;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: total))..forward();
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, (1 - _t.value) * 18), child: child),
      ),
    );
  }
}

/// Brillo animado para esqueletos de carga.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double x = _c.value * 3 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect r) => LinearGradient(
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            colors: const <Color>[AppTheme.surfaceSunken, AppTheme.surface, AppTheme.surfaceSunken],
            stops: const <double>[0.25, 0.5, 0.75],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}

/// Bloque gris de esqueleto.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 12});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Esqueleto genérico de lista para una pestaña.
class TabSkeleton extends StatelessWidget {
  const TabSkeleton({super.key, this.rows = 4, this.hero = true});

  final int rows;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(MobileTokens.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hero) ...<Widget>[
              const SkeletonBox(height: 132, radius: MobileTokens.radius),
              const SizedBox(height: 16),
            ],
            for (int i = 0; i < rows; i++) ...<Widget>[
              const Row(
                children: <Widget>[
                  SkeletonBox(width: 44, height: 44, radius: 14),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SkeletonBox(height: 14, width: 160, radius: 6),
                        SizedBox(height: 8),
                        SkeletonBox(height: 12, width: 100, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso de modo sin conexión (datos en caché).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warningBg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión: estás viendo los últimos datos guardados.',
              style: MobileTokens.body(size: 13.5, color: AppTheme.warningText, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensaje de error con reintento.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusSm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.dangerText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: MobileTokens.body(size: 13.5, color: AppTheme.dangerText),
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Estado vacío amable para móvil.
class MobileEmpty extends StatelessWidget {
  const MobileEmpty({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.brandSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: AppTheme.brand),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: MobileTokens.title(size: 16.5)),
          if (message != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: MobileTokens.body(size: 14, color: AppTheme.textMuted, height: 1.4),
            ),
          ],
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Fila etiqueta / valor (perfil, detalle).
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.icon, this.mono = false});

  final String label;
  final String value;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 5,
            child: Text(label, style: MobileTokens.body(size: 14, color: AppTheme.textMuted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              value.trim().isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? MobileTokens.number(size: 14, weight: FontWeight.w600)
                  : MobileTokens.body(size: 14, color: AppTheme.textPrimary, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre una hoja inferior con el estilo del portal.
Future<T?> showMobileSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    useSafeArea: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: AppTheme.borderStrong, borderRadius: BorderRadius.circular(99)),
        ),
        Flexible(child: builder(ctx)),
      ],
    ),
  );
}

/// Confirmación con estilo móvil. Devuelve `true` si el usuario confirma.
Future<bool> showMobileConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: IconChip(icon, tone: destructive ? MTone.danger : MTone.brand, size: 48),
      title: Text(title, textAlign: TextAlign.center, style: MobileTokens.title(size: 18)),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: MobileTokens.body(size: 14.5, height: 1.45),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppTheme.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Fechas en español sin depender de la inicialización de `intl`.
class MobileDates {
  MobileDates._();

  static const List<String> weekdays = <String>[
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];
  static const List<String> weekdayInitials = <String>['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const List<String> months = <String>[
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static String cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static DateTime? parseIso(String iso) {
    final List<String> p = iso.trim().split('-');
    if (p.length != 3) return null;
    final int? y = int.tryParse(p[0]);
    final int? m = int.tryParse(p[1]);
    final int? d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String monthShort(int m) => cap(months[(m - 1) % 12].substring(0, 3));

  static String monthYear(DateTime d) => '${cap(months[d.month - 1])} ${d.year}';

  /// "Miércoles 18 de noviembre".
  static String longDay(DateTime d) => '${cap(weekdays[d.weekday - 1])} ${d.day} de ${months[d.month - 1]}';

  /// "18 nov".
  static String shortDay(DateTime d) => '${d.day} ${months[d.month - 1].substring(0, 3)}';

  static String shortIso(String iso) {
    final DateTime? d = parseIso(iso);
    return d == null ? iso : shortDay(d);
  }

  static String longIso(String iso) {
    final DateTime? d = parseIso(iso);
    return d == null ? iso : longDay(d);
  }

  /// "1 – 15 nov 2026".
  static String period(String startIso, String endIso) {
    final DateTime? s = parseIso(startIso);
    final DateTime? e = parseIso(endIso);
    if (s == null || e == null) return '$startIso – $endIso';
    if (s.month == e.month && s.year == e.year) {
      return '${s.day} – ${e.day} ${months[e.month - 1].substring(0, 3)} ${e.year}';
    }
    return '${shortDay(s)} – ${shortDay(e)} ${e.year}';
  }

  static String hhmm(String horaEntrega) {
    final List<String> p = horaEntrega.split(':');
    if (p.length < 2) return horaEntrega;
    final int h = int.tryParse(p[0]) ?? 0;
    final String suffix = h < 12 ? 'a. m.' : 'p. m.';
    final int h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${p[1]} $suffix';
  }

  static String greeting(DateTime now) {
    final int h = now.hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

/// Formato compacto de litros para celdas pequeñas: 1.250 → "1,3k".
String compactLiters(double v) {
  if (v >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1).replaceAll('.', ',');
}
