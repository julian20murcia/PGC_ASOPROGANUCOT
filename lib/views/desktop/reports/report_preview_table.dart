import 'package:flutter/material.dart';

import '../../../core/services/report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/pro_ui.dart';

/// Tabla compacta de vista previa de un [ReportDataset] (filas de 36 px,
/// cifras a la derecha en fuente tabular, totales y paginación).
class ReportPreviewTable extends StatefulWidget {
  const ReportPreviewTable({super.key, required this.dataset, this.pageSize = 25});

  final ReportDataset dataset;
  final int pageSize;

  @override
  State<ReportPreviewTable> createState() => _ReportPreviewTableState();
}

class _ReportPreviewTableState extends State<ReportPreviewTable> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant ReportPreviewTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset != widget.dataset) {
      final int pages = _pages;
      if (_page >= pages) _page = 0;
      if (oldWidget.dataset.kind != widget.dataset.kind) _page = 0;
    }
  }

  int get _pages {
    final int n = widget.dataset.rows.length;
    return n == 0 ? 1 : (n / widget.pageSize).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final ReportDataset d = widget.dataset;
    if (d.isEmpty) {
      return EmptyState(
        icon: Icons.table_rows_outlined,
        title: 'Sin resultados',
        message: d.emptyMessage,
      );
    }
    final int start = _page * widget.pageSize;
    final int end = (start + widget.pageSize).clamp(0, d.rows.length);
    final List<List<Object?>> pageRows = d.rows.sublist(start, end);
    final bool lastPage = _page >= _pages - 1;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int totalFlex = d.columns.fold<int>(0, (int s, ReportColumn col) => s + col.flex);
        final double minWidth = totalFlex * 46.0 + 32;
        final double width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
        final Widget table = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _row(
                d.columns,
                <Widget>[
                  for (final ReportColumn col in d.columns)
                    DataHeaderCell(col.header, align: col.alignRight ? TextAlign.end : TextAlign.start),
                ],
                header: true,
              ),
              for (int i = 0; i < pageRows.length; i++)
                _HoverRow(
                  zebra: i.isOdd,
                  child: _row(d.columns, <Widget>[
                    for (int j = 0; j < d.columns.length; j++) _cell(pageRows[i], j, d.columns[j]),
                  ]),
                ),
              if (d.totals != null && lastPage)
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.brandSoft,
                    border: Border(top: BorderSide(color: AppTheme.brandMuted)),
                  ),
                  child: _row(d.columns, <Widget>[
                    for (int j = 0; j < d.columns.length; j++) _cell(d.totals!, j, d.columns[j], bold: true),
                  ]),
                ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (width > c.maxWidth)
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
            else
              table,
            if (_pages > 1)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Filas ${start + 1}–$end de ${d.rows.length}',
                        style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Página anterior',
                      visualDensity: VisualDensity.compact,
                      onPressed: _page == 0 ? null : () => setState(() => _page--),
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    ),
                    Text('${_page + 1} / $_pages', style: AppTheme.monoStyle(fontSize: 12)),
                    IconButton(
                      tooltip: 'Página siguiente',
                      visualDensity: VisualDensity.compact,
                      onPressed: lastPage ? null : () => setState(() => _page++),
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(List<ReportColumn> cols, List<Widget> cells, {bool header = false}) {
    return Container(
      height: header ? 34 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: header ? AppTheme.surfaceMuted : null,
        border: const Border(bottom: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: Row(
        children: <Widget>[
          for (int j = 0; j < cols.length; j++) ...<Widget>[
            if (j > 0) const SizedBox(width: 12),
            Expanded(
              flex: cols[j].flex,
              child: Align(
                alignment: cols[j].alignRight ? Alignment.centerRight : Alignment.centerLeft,
                child: cells[j],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(List<Object?> row, int j, ReportColumn col, {bool bold = false}) {
    final Object? v = j < row.length ? row[j] : null;
    final String text = ReportDataset.formatCell(v, col.type);
    final bool numeric = col.alignRight || col.type == ReportColumnType.date;
    final TextStyle style = numeric
        ? AppTheme.monoStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)
        : AppTheme.bodyStyle(
            fontSize: 12.5,
            color: AppTheme.textPrimary,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          );
    final Widget t = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: col.alignRight ? TextAlign.end : TextAlign.start,
      style: style,
    );
    if (text.length > 28) return Tooltip(message: text, waitDuration: const Duration(milliseconds: 500), child: t);
    if (col.alignRight) return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: t);
    return t;
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, required this.zebra});
  final Widget child;
  final bool zebra;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ColoredBox(
        color: _hover
            ? AppTheme.surfaceMuted
            : (widget.zebra ? Color.lerp(AppTheme.surface, AppTheme.surfaceMuted, 0.5)! : AppTheme.surface),
        child: widget.child,
      ),
    );
  }
}
