import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Cuadro redondeado con ícono tintado, usado en cabeceras, métricas y diálogos.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.color = AppTheme.primaryGreen,
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Tecla de atajo estilo teclado físico (p. ej. `Enter`, `Esc`).
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.inputBorder),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppTheme.inputBorder, offset: Offset(0, 1.5)),
        ],
      ),
      child: Text(
        label,
        style: AppTheme.monoStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Segmento individual de [AppSegmentedControl].
class AppSegment<T> {
  const AppSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Control segmentado con indicador animado (reemplaza pills / toggles sueltos).
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 36,
    this.expand = false,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Si es `true`, los segmentos se reparten el ancho disponible.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = segments.map((AppSegment<T> s) {
      final Widget item = _SegmentButton<T>(
        segment: s,
        selected: s.value == selected,
        onTap: () => onChanged(s.value),
      );
      return expand ? Expanded(child: item) : item;
    }).toList();

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl + 2),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _SegmentButton<T> extends StatefulWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final AppSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegmentButton<T>> createState() => _SegmentButtonState<T>();
}

class _SegmentButtonState<T> extends State<_SegmentButton<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool sel = widget.selected;
    final Color fg = sel
        ? Colors.white
        : (_hover ? AppTheme.textPrimary : AppTheme.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        selected: sel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel
                  ? AppTheme.inkBlack
                  : (_hover ? AppTheme.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              boxShadow: sel
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x290C3B24),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.segment.icon != null) ...<Widget>[
                  Icon(widget.segment.icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamilyName,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                    child: Text(
                      widget.segment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cabecera estándar para diálogos: ícono, título, subtítulo y cierre opcional.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = AppTheme.primaryGreen,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppIconBadge(icon: icon, color: color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppTheme.subtitleStyle().copyWith(fontSize: 16.5),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null)
          IconButton(
            tooltip: 'Cerrar',
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
      ],
    );
  }
}

/// Fila "etiqueta: valor" para resúmenes dentro de diálogos o tarjetas.
class AppInfoRow extends StatelessWidget {
  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final TextStyle valueStyle = mono
        ? AppTheme.monoStyle(
            fontSize: emphasize ? 15 : 13,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          )
        : TextStyle(
            fontSize: 13,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: AppTheme.textPrimary,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Caja de resumen con fondo suave para agrupar [AppInfoRow].
class AppInfoPanel extends StatelessWidget {
  const AppInfoPanel({
    super.key,
    required this.children,
    this.color = AppTheme.canvasAlt,
    this.borderColor = AppTheme.border,
  });

  final List<Widget> children;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: children),
    );
  }
}

/// Aviso en línea (info / advertencia / error) con ícono.
class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.background = AppTheme.warningBg,
    this.foreground = AppTheme.warningText,
  });

  const AppInlineNotice.danger({
    super.key,
    required this.message,
    this.icon = Icons.error_outline_rounded,
  }) : background = AppTheme.dangerBg,
       foreground = AppTheme.dangerText;

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de métrica compacta con franja de acento superior.
class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.accentColor = AppTheme.inkBlack,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final bool tintValue =
        accentColor == AppTheme.primaryGreen ||
        accentColor == AppTheme.warningText;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080C3B24),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(height: 3, color: accentColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppIconBadge(icon: icon, color: accentColor, size: 28),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: AppTheme.monoStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: tintValue ? accentColor : AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón de acción compacto (30×30) para filas de tabla.
class AppRowActionButton extends StatelessWidget {
  const AppRowActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppTheme.textSecondary,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          side: BorderSide(color: color.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          hoverColor: color.withValues(alpha: 0.08),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

/// Pastilla con texto monoespaciado (contadores, paginación).
class AppCountPill extends StatelessWidget {
  const AppCountPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: AppTheme.monoStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Tarjeta con interruptor, ícono y contenido opcional desplegable.
class AppToggleCard extends StatelessWidget {
  const AppToggleCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: value ? color.withValues(alpha: 0.06) : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: value ? color.withValues(alpha: 0.35) : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconBadge(icon: icon, color: color, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                activeTrackColor: AppTheme.primaryGreen,
                onChanged: onChanged,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: child == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(2, 12, 6, 4),
                    child: child,
                  ),
          ),
        ],
      ),
    );
  }
}
