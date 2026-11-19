import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import 'dairy_loader.dart';

/// Emblema oficial de ASOPROGANUCOT (variante completa o compacta para sidebar).
class AsoproganucotLogo extends StatelessWidget {
  const AsoproganucotLogo({
    super.key,
    this.size = 64,
    this.compact = false,
    this.onDark = false,
  });

  final double size;
  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final String assetPath = onDark
        ? AppConstants.darkLogoAssetPath
        : AppConstants.logoAssetPath;

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onDark ? Colors.white : AppTheme.inkBlack,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          'AS',
          style: TextStyle(
            color: onDark ? AppTheme.inkBlack : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.34,
          ),
        ),
      ),
    );
  }
}

/// Patrón orgánico sutil estilo vaca Holstein sobre fondo claro.
class CowSpotPatternPainter extends CustomPainter {
  const CowSpotPatternPainter({
    this.spotColor = const Color(0x0D14161D),
  });

  final Color spotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = spotColor
      ..style = PaintingStyle.fill;

    final Path topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.28, 0)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.11,
        size.width * 0.16,
        size.height * 0.14,
        size.width * 0.13,
        size.height * 0.24,
      )
      ..cubicTo(
        size.width * 0.10,
        size.height * 0.33,
        0,
        size.height * 0.28,
        0,
        size.height * 0.18,
      )
      ..close();
    canvas.drawPath(topLeft, paint);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.31, size.height * 0.14),
        width: 40,
        height: 24,
      ),
      paint,
    );

    final Path bottomRight = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.68, size.height)
      ..cubicTo(
        size.width * 0.66,
        size.height * 0.87,
        size.width * 0.80,
        size.height * 0.83,
        size.width * 0.84,
        size.height * 0.72,
      )
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.64,
        size.width,
        size.height * 0.66,
        size.width,
        size.height * 0.78,
      )
      ..close();
    canvas.drawPath(bottomRight, paint);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.72, size.height * 0.78),
        width: 28,
        height: 18,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CowSpotPatternPainter oldDelegate) =>
      oldDelegate.spotColor != spotColor;
}

/// Píldora compacta de propiedad estadística (reemplaza cards genéricas en cabeceras).
class HeaderPropertyChip extends StatelessWidget {
  const HeaderPropertyChip({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.dotColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final Color effectiveDot = dotColor ?? AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: effectiveDot.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: effectiveDot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (value.isNotEmpty) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              value,
              style: AppTheme.monoStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta métrica KPI del Design System (`ui-design-system`) para dashboards operativos.
class AppKpiCard extends StatelessWidget {
  const AppKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.accentColor = AppTheme.primaryGreen,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: accentColor.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (icon != null) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(icon, size: 17, color: accentColor),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTheme.monoStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Indicador visual compacto de estado de sincronización o red.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    super.key,
    required this.isSynced,
    this.syncedLabel = 'Sincronizado',
    this.pendingLabel = 'Sin conexión',
  });

  final bool isSynced;
  final String syncedLabel;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) {
    final Color bg = isSynced ? AppTheme.successBg : AppTheme.warningBg;
    final Color fg = isSynced ? AppTheme.successText : AppTheme.warningText;
    final Color dot = isSynced ? AppTheme.success : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        border: Border.all(color: dot.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isSynced ? syncedLabel : pendingLabel,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón primario con `DairyLoader` integrado en carga.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isMobile = false,
    this.fullWidth = true,
    this.color = AppTheme.primaryGreen,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isMobile;
  final bool fullWidth;

  /// Color de fondo (p. ej. `AppTheme.danger` para acciones destructivas).
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: isMobile ? 48 : 38,
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isLoading
              ? color.withValues(alpha: 0.72)
              : AppTheme.border,
          disabledForegroundColor:
              isLoading ? Colors.white : AppTheme.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
        ),
        child: isLoading
            ? const DairyLoader(
                size: DairyLoaderSize.xs,
                label: '',
                color: Colors.white,
              )
            : Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Definición de columna para `CleanDataTable`.
class CleanTableColumn {
  const CleanTableColumn({
    required this.label,
    this.numeric = false,
    this.sortAscending,
    this.onSort,
  });

  final String label;
  final bool numeric;
  final bool? sortAscending;
  final VoidCallback? onSort;
}

/// Tabla administrativa limpia de ancho completo.
class CleanDataTable extends StatelessWidget {
  const CleanDataTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<CleanTableColumn> columns;
  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 58,
                horizontalMargin: 16,
                columnSpacing: 22,
                headingRowColor: WidgetStateProperty.all(
                  AppTheme.primaryGreenLight.withValues(alpha: 0.55),
                ),
                dividerThickness: 1,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.dividerLight,
                    width: 1,
                  ),
                ),
                columns: columns.map((CleanTableColumn col) {
                  return DataColumn(
                    numeric: col.numeric,
                    label: InkWell(
                      onTap: col.onSort,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              col.label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            if (col.onSort != null) ...<Widget>[
                              const SizedBox(width: 4),
                              Icon(
                                col.sortAscending == null
                                    ? Icons.unfold_more_rounded
                                    : col.sortAscending!
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                size: 15,
                                color: col.sortAscending == null
                                    ? AppTheme.textMuted
                                    : AppTheme.primaryGreen,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
                rows: rows
                    .map(
                      (List<Widget> cells) => DataRow(
                        color: WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            if (states.contains(WidgetState.hovered)) {
                              return AppTheme.canvasAlt;
                            }
                            return null;
                          },
                        ),
                        cells: cells.map((Widget w) => DataCell(w)).toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Cabecera móvil limpia con fondo en tinta negra `#0E1117`, barra de estado clara
/// y bordes inferiores redondeados para empalmar con el cuerpo claro.
class ModernWaveHeader extends StatelessWidget {
  const ModernWaveHeader({
    super.key,
    required this.height,
    required this.child,
    this.bottomSurfaceColor = AppTheme.surface,
    this.padding = const EdgeInsets.only(bottom: 24),
    this.borderRadius = 28.0,
  });

  final double height;
  final Widget child;
  final Color bottomSurfaceColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  static const SystemUiOverlayStyle _lightStatusOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _lightStatusOverlay,
      child: ColoredBox(
        color: bottomSurfaceColor,
        child: Container(
          height: height,
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: AppTheme.inkBlack,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(borderRadius),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x140E1117),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
