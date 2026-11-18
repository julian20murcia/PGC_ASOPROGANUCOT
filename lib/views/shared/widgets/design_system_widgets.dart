import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

/// Emblema oficial de ASOPROGANUCOT (variante completa o compacta para sidebar).
class AsoproganucotLogo extends StatelessWidget {
  const AsoproganucotLogo({
    super.key,
    this.size = 64,
    this.compact = false,
  });

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String assetPath =
        compact ? AppConstants.iconAssetPath : AppConstants.logoAssetPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 8 : 12),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.cowBlack,
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
          ),
          alignment: Alignment.center,
          child: Text(
            'AS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36,
            ),
          ),
        ),
      ),
    );
  }
}

/// Patrón sutil de manchas orgánicas estilo vaca Holstein sobre fondo claro.
class CowSpotPatternPainter extends CustomPainter {
  const CowSpotPatternPainter({
    this.spotColor = const Color(0x0914161D),
  });

  final Color spotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = spotColor
      ..style = PaintingStyle.fill;

    // Mancha orgánica superior izquierda
    final Path topLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.24, 0)
      ..cubicTo(
        size.width * 0.26,
        size.height * 0.10,
        size.width * 0.14,
        size.height * 0.14,
        size.width * 0.12,
        size.height * 0.22,
      )
      ..cubicTo(
        size.width * 0.09,
        size.height * 0.30,
        0,
        size.height * 0.26,
        0,
        size.height * 0.16,
      )
      ..close();
    canvas.drawPath(topLeft, paint);

    // Pequeña mancha secundaria arriba
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.28, size.height * 0.14),
        width: 36,
        height: 22,
      ),
      paint,
    );

    // Mancha orgánica inferior derecha
    final Path bottomRight = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.72, size.height)
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.88,
        size.width * 0.82,
        size.height * 0.84,
        size.width * 0.85,
        size.height * 0.74,
      )
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.66,
        size.width,
        size.height * 0.68,
        size.width,
        size.height * 0.80,
      )
      ..close();
    canvas.drawPath(bottomRight, paint);
  }

  @override
  bool shouldRepaint(covariant CowSpotPatternPainter oldDelegate) =>
      oldDelegate.spotColor != spotColor;
}

/// Tarjeta métrica KPI del Design System (`ui-design-system`).
class AppKpiCard extends StatelessWidget {
  const AppKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.accentColor = AppTheme.cowBlack,
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
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
              if (icon != null)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 17, color: accentColor),
                ),
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

/// Indicador visual de estado de sincronización o estado operativo.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    super.key,
    required this.isSynced,
    this.syncedLabel = 'Sincronizado',
    this.pendingLabel = 'Local / Offline',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
        border: Border.all(color: dot.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isSynced ? syncedLabel : pendingLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón primario con altura fija y estado de carga integrado (`ui-design-system`).
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isMobile = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isMobile;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final Widget button = SizedBox(
      height: isMobile ? 52 : 48,
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.cowBlack,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.cowBlack.withValues(alpha: 0.65),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
    return button;
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

/// Tabla administrativa limpia (`ui-design-system`).
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
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          horizontalMargin: 20,
          columnSpacing: 24,
          headingRowColor: WidgetStateProperty.all(AppTheme.canvasAlt),
          dividerThickness: 1,
          columns: columns.map((CleanTableColumn col) {
            return DataColumn(
              numeric: col.numeric,
              label: InkWell(
                onTap: col.onSort,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        col.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
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
                          size: 16,
                          color: col.sortAscending == null
                              ? AppTheme.textMuted
                              : AppTheme.cowBlack,
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
                        return AppTheme.surfaceMuted;
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
  }
}
