import 'package:flutter/material.dart';

import '../../../core/services/settlement_calculator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shared/widgets/pro_ui.dart';

/// Tabla matriz productores × días (mañana / tarde) con encabezado y primera
/// columna fijos, y totales por fila y por columna.
class DailyMatrixTable extends StatefulWidget {
  const DailyMatrixTable({super.key, required this.matrix});

  final DailyDeliveryMatrix matrix;

  static const double nameWidth = 230;
  static const double shiftWidth = 50;
  static const double totalWidth = 96;
  static const double rowHeight = 38;
  static const double headerHeight = 50;

  @override
  State<DailyMatrixTable> createState() => _DailyMatrixTableState();
}

class _DailyMatrixTableState extends State<DailyMatrixTable> {
  static const List<String> _weekdays = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  final ScrollController _hBody = ScrollController();
  final ScrollController _hHeader = ScrollController();
  final ScrollController _hFooter = ScrollController();
  final ScrollController _vBody = ScrollController();
  final ScrollController _vLeft = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() {
      for (final ScrollController c in <ScrollController>[_hHeader, _hFooter]) {
        if (c.hasClients && c.offset != _hBody.offset) c.jumpTo(_hBody.offset);
      }
    });
    _vBody.addListener(() => _sync(_vBody, _vLeft));
    _vLeft.addListener(() => _sync(_vLeft, _vBody));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    if (to.offset != from.offset) {
      to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    }
    _syncing = false;
  }

  @override
  void dispose() {
    for (final ScrollController c in <ScrollController>[
      _hBody,
      _hHeader,
      _hFooter,
      _vBody,
      _vLeft,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _n(double v) =>
      v <= 0 ? '·' : AppFormatters.formatLiters(v, withUnit: false);

  bool _isSunday(String iso) =>
      DateTime.tryParse(iso)?.weekday == DateTime.sunday;

  @override
  Widget build(BuildContext context) {
    final DailyDeliveryMatrix m = widget.matrix;
    if (m.rows.isEmpty) {
      return const EmptyState(
        title: 'Sin registros en este período',
        message: 'No hay entregas válidas asociadas a esta quincena.',
        icon: Icons.grid_off_rounded,
      );
    }
    const double dayW = DailyMatrixTable.shiftWidth * 2;
    final double contentW = m.days.length * dayW + DailyMatrixTable.totalWidth;
    final Set<String> empty = m.emptyDays.toSet();

    Widget dayBg(String d, Widget child) => Container(
      width: dayW,
      decoration: BoxDecoration(
        color: _isSunday(d) ? AppTheme.surfaceMuted : null,
        border: const Border(left: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: child,
    );

    Widget shiftPair(DailyShiftCell c, {bool strong = false}) => Row(
      children: <Widget>[
        for (final double v in <double>[c.morning, c.afternoon])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _n(v),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.monoStyle(
                  fontSize: 12,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: v > 0 ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ),
          ),
      ],
    );

    final Widget header = SizedBox(
      height: DailyMatrixTable.headerHeight,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: DailyMatrixTable.nameWidth,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DataHeaderCell('Productor'),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _hHeader,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: <Widget>[
                  for (final String d in m.days)
                    dayBg(
                      d,
                      Tooltip(
                        message: empty.contains(d)
                            ? '${AppFormatters.formatIsoDate(d)} · sin registros'
                            : AppFormatters.formatIsoDate(d),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              '${_weekdays[(DateTime.tryParse(d)?.weekday ?? 1) - 1]} ${d.substring(8)}',
                              style: AppTheme.overlineStyle(
                                color: empty.contains(d)
                                    ? AppTheme.textMuted
                                    : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: <Widget>[
                                for (final String s in <String>['M', 'T'])
                                  Expanded(
                                    child: Text(
                                      s,
                                      textAlign: TextAlign.center,
                                      style: AppTheme.overlineStyle(
                                        color: s == 'M'
                                            ? AppTheme.accentDeep
                                            : AppTheme.brand,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    width: DailyMatrixTable.totalWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerRight,
                    decoration: const BoxDecoration(
                      color: AppTheme.brandSoft,
                      border: Border(left: BorderSide(color: AppTheme.border)),
                    ),
                    child: const DataHeaderCell(
                      'Total L',
                      align: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: DailyMatrixTable.nameWidth,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _vLeft,
              itemExtent: DailyMatrixTable.rowHeight,
              itemCount: m.rows.length,
              itemBuilder: (BuildContext context, int i) {
                final DailyMatrixRow r = m.rows[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: i.isOdd ? AppTheme.surfaceMuted : AppTheme.surface,
                    border: const Border(
                      right: BorderSide(color: AppTheme.border),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 58,
                        child: Text(
                          r.codigo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.monoStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStyle(
                            fontSize: 12.5,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _hBody,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hBody,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentW,
                child: ListView.builder(
                  controller: _vBody,
                  itemExtent: DailyMatrixTable.rowHeight,
                  itemCount: m.rows.length,
                  itemBuilder: (BuildContext context, int i) {
                    final DailyMatrixRow r = m.rows[i];
                    return ColoredBox(
                      color: i.isOdd ? AppTheme.surfaceMuted : AppTheme.surface,
                      child: Row(
                        children: <Widget>[
                          for (final String d in m.days)
                            dayBg(d, Center(child: shiftPair(r.cell(d)))),
                          Container(
                            width: DailyMatrixTable.totalWidth,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.centerRight,
                            decoration: const BoxDecoration(
                              color: AppTheme.brandSoft,
                              border: Border(
                                left: BorderSide(color: AppTheme.border),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                AppFormatters.formatLiters(
                                  r.total,
                                  withUnit: false,
                                ),
                                style: AppTheme.monoStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final Widget footer = Container(
      height: DailyMatrixTable.rowHeight + 2,
      decoration: const BoxDecoration(
        color: AppTheme.brandSoft,
        border: Border(top: BorderSide(color: AppTheme.brand, width: 1.2)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: DailyMatrixTable.nameWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Total por día',
                style: AppTheme.bodyStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandDeep,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _hFooter,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: <Widget>[
                  for (final String d in m.days)
                    dayBg(
                      d,
                      Center(child: shiftPair(m.columnTotal(d), strong: true)),
                    ),
                  Container(
                    width: DailyMatrixTable.totalWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        AppFormatters.formatLiters(
                          m.grandTotal,
                          withUnit: false,
                        ),
                        style: AppTheme.monoStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brandDeep,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        const Divider(height: 1),
        Expanded(child: body),
        footer,
      ],
    );
  }
}
