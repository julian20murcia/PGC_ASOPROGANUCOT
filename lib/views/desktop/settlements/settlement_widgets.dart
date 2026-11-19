import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/settlement_model.dart';
import '../../shared/widgets/pro_ui.dart';

/// Estado de pago de un comprobante.
class PaymentBadge extends StatelessWidget {
  const PaymentBadge(this.settlement, {super.key});
  final SettlementModel settlement;

  @override
  Widget build(BuildContext context) {
    return settlement.isPagada
        ? const StatusBadge('Pagada', tone: Tone.success, dot: true)
        : const StatusBadge('Pendiente', tone: Tone.warning, dot: true);
  }
}

/// Barra de progreso fina de pagos (pagadas / total).
class PaymentProgress extends StatelessWidget {
  const PaymentProgress({
    super.key,
    required this.paid,
    required this.total,
    this.showLabel = true,
  });

  final int paid;
  final int total;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final double ratio = total == 0 ? 0 : (paid / total).clamp(0, 1).toDouble();
    final bool done = total > 0 && paid >= total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$paid de $total pagadas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 11.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: AppTheme.surfaceSunken,
            valueColor: AlwaysStoppedAnimation<Color>(
              done ? AppTheme.success : AppTheme.brand,
            ),
          ),
        ),
      ],
    );
  }
}

/// Métrica en línea (sin borde) para usar dentro de un [Panel].
class InlineMetric {
  const InlineMetric(this.label, this.value, {this.hint, this.valueColor});
  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;
}

/// Fila de métricas separadas por divisores verticales, sin contenedor propio.
class InlineMetricRow extends StatelessWidget {
  const InlineMetricRow({super.key, required this.items, this.trailing});

  final List<InlineMetric> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wrap = c.maxWidth < 640;
        final List<Widget> cells = <Widget>[
          for (final InlineMetric m in items) _MetricCell(m),
          ?trailing,
        ];
        if (wrap) {
          return Wrap(spacing: 24, runSpacing: 12, children: cells);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < cells.length; i++) ...<Widget>[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppTheme.dividerLight,
                    ),
                  ),
                Expanded(child: cells[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell(this.m);
  final InlineMetric m;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          m.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.overlineStyle(),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            m.value,
            maxLines: 1,
            style: AppTheme.monoStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: m.valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ),
        if (m.hint != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            m.hint!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyStyle(
              fontSize: 11.5,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Línea de verificación con icono y tono (usada en el asistente de cierre).
class CheckLine extends StatelessWidget {
  const CheckLine({
    super.key,
    required this.tone,
    required this.title,
    this.detail,
    this.icon,
  });

  final Tone tone;
  final String title;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final IconData ic =
        icon ??
        switch (tone) {
          Tone.success => Icons.check_circle_rounded,
          Tone.danger => Icons.error_rounded,
          Tone.warning => Icons.warning_amber_rounded,
          _ => Icons.info_rounded,
        };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(ic, size: 15, color: tone.fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppTheme.bodyStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail!,
                      style: AppTheme.bodyStyle(fontSize: 12, height: 1.35),
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

/// Celda de texto para tablas compactas.
class CellText extends StatelessWidget {
  const CellText(
    this.text, {
    super.key,
    this.align = TextAlign.start,
    this.mono = false,
    this.strong = false,
    this.color,
    this.size = 13,
  });

  final String text;
  final TextAlign align;
  final bool mono;
  final bool strong;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = mono
        ? AppTheme.monoStyle(
            fontSize: size,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: color ?? AppTheme.textPrimary,
          )
        : AppTheme.bodyStyle(
            fontSize: size,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            color: color ?? AppTheme.textPrimary,
          );
    return Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// Encabezado de columna con alineación real (izquierda o derecha).
class HeaderCell extends StatelessWidget {
  const HeaderCell(this.text, {super.key, this.right = false});
  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) => Align(
    alignment: right ? Alignment.centerRight : Alignment.centerLeft,
    child: DataHeaderCell(
      text,
      align: right ? TextAlign.right : TextAlign.start,
    ),
  );
}
