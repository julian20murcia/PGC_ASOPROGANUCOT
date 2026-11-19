import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/milk_reception_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import 'reception_grid_logic.dart';

/// Resultado de una operación de guardado de celda: null = éxito; texto = error.
typedef CellSaveResult = Future<String?>;

/// Planilla tipo hoja de cálculo (productores × días con subcolumnas M / T).
///
/// * Edición in-place sin diálogos: clic sobre la celda seleccionada, doble
///   clic, Enter, F2 o escribir un número directamente.
/// * Flechas / Tab / Shift+Tab / Enter mueven la selección; Esc cancela.
/// * Supr / Retroceso sobre una celda con valor pide anular con una
///   confirmación en línea (barra superior), no un modal.
/// * Encabezados, primera columna y columna de totales fijos; filas y
///   columnas se construyen de forma perezosa (solo lo visible).
class ReceptionSpreadsheet extends StatefulWidget {
  const ReceptionSpreadsheet({
    super.key,
    required this.matrix,
    required this.canCreate,
    required this.canEdit,
    required this.canAnnul,
    required this.onCreate,
    required this.onEdit,
    required this.onAnnul,
    this.isCorrected,
    this.now,
  });

  final PlanillaMatrix matrix;
  final bool canCreate;
  final bool canEdit;
  final bool canAnnul;
  final CellSaveResult Function(
    PlanillaRow row,
    DateTime day,
    String jornada,
    double liters,
  )
  onCreate;
  final CellSaveResult Function(MilkReceptionModel existing, double liters)
  onEdit;
  final CellSaveResult Function(MilkReceptionModel existing) onAnnul;
  final bool Function(MilkReceptionModel r)? isCorrected;

  /// Reloj inyectable para pruebas.
  final DateTime? now;

  static const double rowHeight = 34;
  static const double cellWidth = 62;
  static const double leftWidth = 232;
  static const double totalWidth = 92;
  static const double headerDayHeight = 24;
  static const double headerShiftHeight = 22;
  static const double footerRowHeight = 30;

  @override
  State<ReceptionSpreadsheet> createState() => ReceptionSpreadsheetState();
}

class ReceptionSpreadsheetState extends State<ReceptionSpreadsheet> {
  final FocusNode _gridFocus = FocusNode(debugLabel: 'planilla');
  late final FocusNode _editFocus = FocusNode(
    debugLabel: 'planilla-editor',
    onKeyEvent: _onEditorKey,
  );
  final TextEditingController _editCtrl = TextEditingController();
  final ScrollController _vCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  final ValueNotifier<double> _hOffset = ValueNotifier<double>(0);

  GridPos _sel = const GridPos(0, 0);
  bool _editing = false;
  String? _editError;

  /// Celda bajo el mouse. ValueNotifier: el hover solo repinta el fondo de
  /// las celdas, no reconstruye toda la planilla.
  final ValueNotifier<GridPos?> _hover = ValueNotifier<GridPos?>(null);

  /// Confirmación en línea de anulación.
  ({MilkReceptionModel reception, GridPos pos})? _pendingAnnul;

  final Map<String, String> _errors = <String, String>{};
  final Set<String> _saving = <String>{};

  double _viewportW = 0;
  double _viewportH = 0;

  PlanillaMatrix get _m => widget.matrix;
  int get _rows => _m.rows.length;
  int get _cols => _m.columnCount;

  bool get isEditing => _editing;
  GridPos get selection => _sel;

  @override
  void initState() {
    super.initState();
    _hCtrl.addListener(() => _hOffset.value = _hCtrl.offset);
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus && _editing) {
        _commit(null, refocusGrid: false);
      }
    });
    // Arranca en la jornada actual del último día visible (normalmente hoy).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cols == 0) return;
      final DateTime now = widget.now ?? DateTime.now();
      int col = 0;
      for (int d = 0; d < _m.days.length; d++) {
        if (!isFutureDay(_m.days[d], now)) col = d * 2;
      }
      if (now.hour >= 12) col = math.min(col + 1, _cols - 1);
      setState(() => _sel = GridPos(0, col));
      _ensureVisible();
    });
  }

  @override
  void didUpdateWidget(covariant ReceptionSpreadsheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_rows == 0 || _cols == 0) {
      _sel = const GridPos(0, 0);
    } else if (_sel.row >= _rows || _sel.col >= _cols) {
      _sel = GridPos(
        _sel.row.clamp(0, _rows - 1),
        _sel.col.clamp(0, _cols - 1),
      );
    }
  }

  @override
  void dispose() {
    _gridFocus.dispose();
    _editFocus.dispose();
    _editCtrl.dispose();
    _vCtrl.dispose();
    _hCtrl.dispose();
    _hOffset.dispose();
    _hover.dispose();
    super.dispose();
  }

  // ── Estado por celda ──────────────────────────────────────────────────────

  String _key(int row, int col) =>
      '${_m.rows[row].productorId}|${isoOf(_m.dayOf(col))}|$col';

  /// Motivo por el que la celda es de solo lectura (null = editable).
  String? _readOnlyReason(int row, int col) {
    final PlanillaRow r = _m.rows[row];
    final PlanillaCell cell = r.cells[col];
    final DateTime now = widget.now ?? DateTime.now();
    if (cell.isSettled) return 'Liquidada · solo lectura';
    if (cell.hasMultiple) {
      return '${cell.active.length} entregas en esta jornada · corrígelas en Registros';
    }
    if (cell.isEmpty) {
      if (isFutureDay(_m.dayOf(col), now)) return 'Fecha futura';
      if (r.producer == null) return 'Productor inactivo · solo lectura';
      if (!widget.canCreate) return 'Sin permiso para registrar entregas';
      return null;
    }
    if (!widget.canEdit) return 'Sin permiso para corregir entregas';
    return null;
  }

  String _cellTooltip(int row, int col) {
    final PlanillaRow r = _m.rows[row];
    final PlanillaCell cell = r.cells[col];
    final String shift = col.isOdd ? 'Tarde' : 'Mañana';
    final DateTime d = _m.dayOf(col);
    final List<String> lines = <String>[
      '${r.codigo} · ${r.nombre}',
      '${d.day} ${DateRangePresets.monthsShort[d.month - 1]} · $shift',
    ];
    final String? err = _errors[_key(row, col)];
    if (err != null) lines.add('Error: $err');
    for (final MilkReceptionModel e in cell.active) {
      lines.add(
        '${formatLitersCo(e.litros)} L · ${e.horaEntrega.length >= 5 ? e.horaEntrega.substring(0, 5) : e.horaEntrega}'
        '${e.isLiquidada ? ' · liquidada' : ''}'
        '${!e.isSynced ? ' · pendiente de sincronizar' : ''}'
        '${(widget.isCorrected?.call(e) ?? false) ? ' · corregida' : ''}',
      );
    }
    for (final MilkReceptionModel e in cell.annulled) {
      lines.add(
        'Anulada: ${formatLitersCo(e.litros)} L${e.motivoAnulacion != null ? ' (${e.motivoAnulacion})' : ''}',
      );
    }
    final String? ro = _readOnlyReason(row, col);
    if (ro != null) lines.add(ro);
    return lines.join('\n');
  }

  // ── Navegación ────────────────────────────────────────────────────────────

  void _select(GridPos p, {bool ensureVisible = true}) {
    if (_rows == 0 || _cols == 0) return;
    setState(() {
      _sel = GridPos(p.row.clamp(0, _rows - 1), p.col.clamp(0, _cols - 1));
      _pendingAnnul = null;
    });
    if (ensureVisible) _ensureVisible();
  }

  void _move(GridMove m) =>
      _select(moveInGrid(_sel, m, rows: _rows, cols: _cols));

  void _ensureVisible() {
    if (_vCtrl.hasClients && _viewportH > 0) {
      final double top = _sel.row * ReceptionSpreadsheet.rowHeight;
      final double bottom = top + ReceptionSpreadsheet.rowHeight;
      final double off = _vCtrl.offset;
      if (top < off) {
        _vCtrl.jumpTo(top);
      } else if (bottom > off + _viewportH) {
        _vCtrl.jumpTo(
          math.min(bottom - _viewportH, _vCtrl.position.maxScrollExtent),
        );
      }
    }
    if (_hCtrl.hasClients && _viewportW > 0) {
      final double left = _sel.col * ReceptionSpreadsheet.cellWidth;
      final double right = left + ReceptionSpreadsheet.cellWidth;
      final double off = _hCtrl.offset;
      if (left < off) {
        _hCtrl.jumpTo(left);
      } else if (right > off + _viewportW) {
        _hCtrl.jumpTo(
          math.min(right - _viewportW, _hCtrl.position.maxScrollExtent),
        );
      }
    }
  }

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_editing || _rows == 0 || _cols == 0) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;

    if (_pendingAnnul != null) {
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter) {
        _confirmAnnul();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        setState(() => _pendingAnnul = null);
        return KeyEventResult.handled;
      }
    }

    if (k == LogicalKeyboardKey.arrowUp) {
      _move(GridMove.up);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _move(GridMove.down);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _move(GridMove.left);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _move(GridMove.right);
    } else if (k == LogicalKeyboardKey.tab) {
      _move(shift ? GridMove.previous : GridMove.next);
    } else if (k == LogicalKeyboardKey.home) {
      _move(GridMove.home);
    } else if (k == LogicalKeyboardKey.end) {
      _move(GridMove.end);
    } else if (k == LogicalKeyboardKey.pageDown) {
      final int step = math.max(
        1,
        (_viewportH / ReceptionSpreadsheet.rowHeight).floor() - 1,
      );
      _select(GridPos(_sel.row + step, _sel.col));
    } else if (k == LogicalKeyboardKey.pageUp) {
      final int step = math.max(
        1,
        (_viewportH / ReceptionSpreadsheet.rowHeight).floor() - 1,
      );
      _select(GridPos(_sel.row - step, _sel.col));
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.f2) {
      _startEdit();
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      _requestAnnul(_sel);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_errors.remove(_key(_sel.row, _sel.col)) != null) setState(() {});
    } else if (startsDirectEdit(event.character)) {
      _startEdit(initial: event.character);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── Edición ───────────────────────────────────────────────────────────────

  void _startEdit({String? initial}) {
    if (_rows == 0 || _cols == 0) return;
    final String? ro = _readOnlyReason(_sel.row, _sel.col);
    if (ro != null) {
      setState(() => _errors[_key(_sel.row, _sel.col)] = ro);
      return;
    }
    final PlanillaCell cell = _m.rows[_sel.row].cells[_sel.col];
    final String text =
        initial ?? (cell.isEmpty ? '' : formatLitersCo(cell.liters));
    _editCtrl.value = TextEditingValue(
      text: text,
      selection: initial != null
          ? TextSelection.collapsed(offset: text.length)
          : TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    setState(() {
      _editing = true;
      _editError = null;
      _pendingAnnul = null;
      _errors.remove(_key(_sel.row, _sel.col));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _editFocus.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editError = null;
    });
    _gridFocus.requestFocus();
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    if (k == LogicalKeyboardKey.escape) {
      _cancelEdit();
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _commit(shift ? GridMove.up : GridMove.down);
    } else if (k == LogicalKeyboardKey.tab) {
      _commit(shift ? GridMove.previous : GridMove.next);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _commit(GridMove.up);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _commit(GridMove.down);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Valida, sale de edición, mueve la selección y guarda en segundo plano.
  void _commit(GridMove? then, {bool refocusGrid = true}) {
    if (!_editing) return;
    final GridPos pos = _sel;
    final PlanillaRow row = _m.rows[pos.row];
    final PlanillaCell cell = row.cells[pos.col];
    final LitersParseResult parsed = parseLitersInput(_editCtrl.text);

    if (!parsed.isEmpty && !parsed.isValid) {
      if (!refocusGrid) {
        // Perdió el foco con un valor inválido: se descarta (como Esc).
        setState(() {
          _editing = false;
          _editError = null;
        });
        return;
      }
      setState(() => _editError = parsed.error);
      return;
    }

    setState(() {
      _editing = false;
      _editError = null;
    });
    if (refocusGrid) {
      _gridFocus.requestFocus();
      if (then != null) _move(then);
    }

    if (parsed.isEmpty) {
      if (!cell.isEmpty) _requestAnnul(pos);
      return;
    }
    final double liters = parsed.value!;
    if (!cell.isEmpty && (cell.liters - liters).abs() < 0.005) return;

    final String key = _key(pos.row, pos.col);
    final CellSaveResult future;
    if (cell.isEmpty) {
      future = widget.onCreate(
        row,
        _m.dayOf(pos.col),
        PlanillaMatrix.shiftOf(pos.col),
        liters,
      );
    } else {
      final MilkReceptionModel? single = cell.single;
      if (single == null) return;
      future = widget.onEdit(single, liters);
    }
    _track(key, future);
  }

  Future<void> _track(String key, CellSaveResult future) async {
    setState(() {
      _saving.add(key);
      _errors.remove(key);
    });
    String? error;
    try {
      error = await future;
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _saving.remove(key);
      if (error != null) _errors[key] = error;
    });
  }

  void _requestAnnul(GridPos pos) {
    final PlanillaCell cell = _m.rows[pos.row].cells[pos.col];
    final MilkReceptionModel? single = cell.single;
    if (cell.isEmpty) return;
    String? reason;
    if (!widget.canAnnul) {
      reason = 'Sin permiso para anular entregas';
    } else if (single == null) {
      reason = cell.hasMultiple
          ? 'Varias entregas: anúlalas desde Registros'
          : null;
    } else if (single.isLiquidada) {
      reason = 'Liquidada · no se puede anular';
    }
    if (reason != null || single == null) {
      setState(
        () => _errors[_key(pos.row, pos.col)] = reason ?? 'No se puede anular',
      );
      return;
    }
    setState(() => _pendingAnnul = (reception: single, pos: pos));
    _gridFocus.requestFocus();
  }

  void _confirmAnnul() {
    final ({MilkReceptionModel reception, GridPos pos})? p = _pendingAnnul;
    if (p == null) return;
    setState(() => _pendingAnnul = null);
    _gridFocus.requestFocus();
    _track(_key(p.pos.row, p.pos.col), widget.onAnnul(p.reception));
  }

  void _onCellTap(int row, int col) {
    final GridPos p = GridPos(row, col);
    final bool wasSelected = p == _sel && _gridFocus.hasFocus;
    if (_editing) _commit(null, refocusGrid: false);
    _select(p, ensureVisible: false);
    _gridFocus.requestFocus();
    if (wasSelected) _startEdit();
  }

  // ── Construcción ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final double contentW = _cols * ReceptionSpreadsheet.cellWidth;
    return Focus(
      focusNode: _gridFocus,
      onKeyEvent: _onGridKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_pendingAnnul != null) _annulBar(),
          if (_editing && _editError != null)
            Container(
              key: const ValueKey<String>('planilla-edit-error'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: AppTheme.dangerBg,
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: AppTheme.dangerText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_editError!} · Esc para cancelar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        color: AppTheme.dangerText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final double middleW = math.max(
                  0,
                  c.maxWidth -
                      ReceptionSpreadsheet.leftWidth -
                      ReceptionSpreadsheet.totalWidth,
                );
                _viewportW = middleW;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _header(middleW),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.border,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints bc) {
                          _viewportH = bc.maxHeight;
                          return Listener(
                            onPointerSignal: (PointerSignalEvent e) {
                              if (e is PointerScrollEvent &&
                                  e.scrollDelta.dx != 0 &&
                                  _hCtrl.hasClients) {
                                _hCtrl.jumpTo(
                                  (_hCtrl.offset + e.scrollDelta.dx).clamp(
                                    0,
                                    _hCtrl.position.maxScrollExtent,
                                  ),
                                );
                              }
                            },
                            child: Scrollbar(
                              controller: _vCtrl,
                              child: ListView.builder(
                                controller: _vCtrl,
                                itemExtent: ReceptionSpreadsheet.rowHeight,
                                itemCount: _rows,
                                itemBuilder: (BuildContext context, int i) =>
                                    _row(i, middleW),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.border,
                    ),
                    _footer(middleW),
                    Row(
                      children: <Widget>[
                        const SizedBox(width: ReceptionSpreadsheet.leftWidth),
                        Expanded(
                          child: Scrollbar(
                            controller: _hCtrl,
                            thumbVisibility: contentW > middleW,
                            child: SingleChildScrollView(
                              controller: _hCtrl,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(width: contentW, height: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: ReceptionSpreadsheet.totalWidth),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _annulBar() {
    final MilkReceptionModel r = _pendingAnnul!.reception;
    final String shift = r.jornada == AppConstants.shiftAfternoon
        ? 'Tarde'
        : 'Mañana';
    return Container(
      key: const ValueKey<String>('planilla-annul-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppTheme.dangerBg,
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppTheme.dangerText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '¿Anular ${formatLitersCo(r.litros)} L de ${r.codigoAsociadoSnap} · ${r.fechaEntrega} · $shift? '
              'Enter confirma · Esc cancela',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: AppTheme.dangerText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _pendingAnnul = null);
              _gridFocus.requestFocus();
            },
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _confirmAnnul,
            child: const Text('Anular'),
          ),
        ],
      ),
    );
  }

  /// Franja desplazable horizontalmente que solo construye las columnas
  /// visibles.
  Widget _strip({
    required double width,
    required double height,
    required Widget Function(int col) cell,
    int span = 1,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: ValueListenableBuilder<double>(
          valueListenable: _hOffset,
          builder: (BuildContext context, double offset, _) {
            final double w = ReceptionSpreadsheet.cellWidth * span;
            final int count = span == 1 ? _cols : _m.days.length;
            final int first = (offset / w).floor().clamp(0, count);
            final int last = ((offset + width) / w).ceil().clamp(0, count);
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (int i = first; i < last; i++)
                  Positioned(
                    left: i * w - offset,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: cell(i),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const List<String> _dow = <String>[
    'Lu',
    'Ma',
    'Mi',
    'Ju',
    'Vi',
    'Sá',
    'Do',
  ];

  Widget _header(double middleW) {
    final DateTime now = widget.now ?? DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final TextStyle over = AppTheme.overlineStyle();
    return Container(
      color: AppTheme.surfaceMuted,
      height:
          ReceptionSpreadsheet.headerDayHeight +
          ReceptionSpreadsheet.headerShiftHeight,
      child: Row(
        children: <Widget>[
          Container(
            width: ReceptionSpreadsheet.leftWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppTheme.border)),
            ),
            child: Text('PRODUCTOR', style: over),
          ),
          Column(
            children: <Widget>[
              _strip(
                width: middleW,
                height: ReceptionSpreadsheet.headerDayHeight,
                span: 2,
                cell: (int d) {
                  final DateTime day = _m.days[d];
                  final bool isToday = day == today;
                  final bool sunday = day.weekday == DateTime.sunday;
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppTheme.brandSoft
                          : (sunday ? AppTheme.surfaceSunken : null),
                      border: const Border(
                        right: BorderSide(color: AppTheme.border),
                        bottom: BorderSide(color: AppTheme.dividerLight),
                      ),
                    ),
                    child: Text(
                      '${_dow[day.weekday - 1]} ${day.day}${day.day == 1 || d == 0 ? ' ${DateRangePresets.monthsShort[day.month - 1]}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.overlineStyle(
                        color: isToday
                            ? AppTheme.brand
                            : AppTheme.textSecondary,
                      ),
                    ),
                  );
                },
              ),
              _strip(
                width: middleW,
                height: ReceptionSpreadsheet.headerShiftHeight,
                cell: (int col) => Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: col == _sel.col
                        ? AppTheme.brandMuted.withValues(alpha: 0.5)
                        : null,
                    border: Border(
                      right: BorderSide(
                        color: col.isOdd
                            ? AppTheme.border
                            : AppTheme.dividerLight,
                      ),
                    ),
                  ),
                  child: Text(
                    col.isOdd ? 'T' : 'M',
                    style: AppTheme.overlineStyle(
                      color: col.isOdd ? AppTheme.accentDeep : AppTheme.brand,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Container(
            width: ReceptionSpreadsheet.totalWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerRight,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.border)),
            ),
            child: Text('TOTAL L', style: over),
          ),
        ],
      ),
    );
  }

  Widget _row(int i, double middleW) {
    final PlanillaRow r = _m.rows[i];
    final bool selectedRow = i == _sel.row;
    final Color? zebra = i.isOdd
        ? AppTheme.surfaceMuted.withValues(alpha: 0.6)
        : null;
    return Container(
      decoration: BoxDecoration(
        color: zebra,
        border: const Border(bottom: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: ReceptionSpreadsheet.leftWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selectedRow ? AppTheme.brandSoft : null,
              border: const Border(right: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 62,
                  child: Text(
                    r.codigo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brand,
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
                      color: r.isActiveProducer
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _strip(
            width: middleW,
            height: ReceptionSpreadsheet.rowHeight - 1,
            cell: (int col) => _cell(i, col),
          ),
          Container(
            width: ReceptionSpreadsheet.totalWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(
              color: selectedRow ? AppTheme.brandSoft : AppTheme.surfaceMuted,
              border: const Border(left: BorderSide(color: AppTheme.border)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                r.total == 0 ? '—' : formatLitersCo(r.total),
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
  }

  Widget _cell(int row, int col) {
    final PlanillaCell cell = _m.rows[row].cells[col];
    final GridPos pos = GridPos(row, col);
    final bool selected = pos == _sel;
    final String key = _key(row, col);
    final String? error = _errors[key];
    final bool saving = _saving.contains(key);
    final bool readOnly = cell.isSettled || cell.hasMultiple;
    final bool future =
        cell.isEmpty &&
        isFutureDay(_m.dayOf(col), widget.now ?? DateTime.now());
    final bool corrected = cell.active.any(
      (MilkReceptionModel e) => widget.isCorrected?.call(e) ?? false,
    );

    if (selected && _editing) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(
            color: _editError != null ? AppTheme.danger : AppTheme.brand,
            width: 2,
          ),
        ),
        child: TextField(
          key: const ValueKey<String>('planilla-editor'),
          controller: _editCtrl,
          focusNode: _editFocus,
          inputFormatters: AppInputs.liters(),
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.monoStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          cursorHeight: 14,
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
        ),
      );
    }

    Color? bg;
    Color fg = AppTheme.textPrimary;
    if (error != null) {
      bg = AppTheme.dangerBg;
      fg = AppTheme.dangerText;
    } else if (cell.isSettled) {
      bg = AppTheme.surfaceSunken;
      fg = AppTheme.textMuted;
    } else if (cell.isAnnulledOnly) {
      fg = AppTheme.textMuted;
    } else if (future) {
      bg = AppTheme.surfaceSunken.withValues(alpha: 0.6);
    }
    final bool hoverable = bg == null && !selected;
    if (selected && error == null) {
      bg = AppTheme.brandSoft.withValues(alpha: 0.55);
    }

    final String text = cell.isEmpty
        ? (cell.isAnnulledOnly ? 'anul.' : '')
        : formatLitersCo(cell.liters);

    return MouseRegion(
      cursor: SystemMouseCursors.cell,
      onEnter: (_) => _hover.value = pos,
      onExit: (_) {
        if (_hover.value == pos) _hover.value = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Sin onDoubleTap para que el clic seleccione al instante; el segundo
        // clic sobre la celda seleccionada (o doble clic) entra a editar.
        onTap: () => _onCellTap(row, col),
        child: Tooltip(
          message: _cellTooltip(row, col),
          waitDuration: const Duration(milliseconds: 600),
          child: _hoverTint(
            hoverable,
            pos,
            Container(
              key: ValueKey<String>('planilla-cell-$row-$col'),
              decoration: BoxDecoration(
                color: bg,
                border: selected
                    ? Border.all(
                        color: error != null ? AppTheme.danger : AppTheme.brand,
                        width: 2,
                      )
                    : Border(
                        right: BorderSide(
                          color: col.isOdd
                              ? AppTheme.border
                              : AppTheme.dividerLight,
                        ),
                      ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            text,
                            maxLines: 1,
                            style:
                                AppTheme.monoStyle(
                                  fontSize: cell.isAnnulledOnly ? 10.5 : 12.5,
                                  fontWeight: readOnly
                                      ? FontWeight.w500
                                      : FontWeight.w600,
                                  color: fg,
                                ).copyWith(
                                  decoration: cell.isAnnulledOnly
                                      ? TextDecoration.lineThrough
                                      : null,
                                  fontStyle: cell.isSettled
                                      ? FontStyle.italic
                                      : null,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (cell.isPending)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        key: ValueKey<String>('pending-dot-$row-$col'),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (corrected)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: CustomPaint(
                        size: const Size(7, 7),
                        painter: _CornerMarkPainter(AppTheme.info),
                      ),
                    ),
                  if (cell.isSettled)
                    const Positioned(
                      left: 3,
                      bottom: 2,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 9,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  if (error != null)
                    const Positioned(
                      left: 3,
                      top: 2,
                      child: Icon(
                        Icons.error_rounded,
                        size: 10,
                        color: AppTheme.danger,
                      ),
                    ),
                  if (saving)
                    const Positioned(
                      left: 4,
                      bottom: 4,
                      child: SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(strokeWidth: 1.4),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fondo de hover escuchando solo [_hover] (el contenido de la celda se reutiliza).
  Widget _hoverTint(bool enabled, GridPos pos, Widget cell) {
    if (!enabled) return cell;
    return ValueListenableBuilder<GridPos?>(
      valueListenable: _hover,
      child: cell,
      builder: (BuildContext context, GridPos? h, Widget? child) => ColoredBox(
        color: h == pos ? AppTheme.surfaceMuted : const Color(0x00000000),
        child: child,
      ),
    );
  }

  Widget _footer(double middleW) {
    final TextStyle label = AppTheme.overlineStyle(
      color: AppTheme.textSecondary,
    );
    Widget num(double v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            v == 0 ? '—' : formatLitersCo(v),
            style: AppTheme.monoStyle(
              fontSize: 12,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: v == 0 ? AppTheme.textMuted : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
    return Container(
      color: AppTheme.surfaceMuted,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: ReceptionSpreadsheet.leftWidth,
                height: ReceptionSpreadsheet.footerRowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: AppTheme.border)),
                ),
                child: Text('TOTAL POR JORNADA', style: label),
              ),
              _strip(
                width: middleW,
                height: ReceptionSpreadsheet.footerRowHeight,
                cell: (int col) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: col.isOdd
                            ? AppTheme.border
                            : AppTheme.dividerLight,
                      ),
                    ),
                  ),
                  child: num(_m.columnTotal(col)),
                ),
              ),
              Container(
                width: ReceptionSpreadsheet.totalWidth,
                height: ReceptionSpreadsheet.footerRowHeight,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppTheme.border)),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: AppTheme.dividerLight),
          Row(
            children: <Widget>[
              Container(
                width: ReceptionSpreadsheet.leftWidth,
                height: ReceptionSpreadsheet.footerRowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: AppTheme.border)),
                ),
                child: Text('TOTAL DEL DÍA', style: label),
              ),
              _strip(
                width: middleW,
                height: ReceptionSpreadsheet.footerRowHeight,
                span: 2,
                cell: (int d) => DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AppTheme.border)),
                  ),
                  child: Center(child: num(_m.dayTotal(d), strong: true)),
                ),
              ),
              Container(
                key: const ValueKey<String>('planilla-grand-total'),
                width: ReceptionSpreadsheet.totalWidth,
                height: ReceptionSpreadsheet.footerRowHeight,
                decoration: const BoxDecoration(
                  color: AppTheme.brandSoft,
                  border: Border(left: BorderSide(color: AppTheme.border)),
                ),
                child: num(_m.grandTotal, strong: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CornerMarkPainter extends CustomPainter {
  _CornerMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CornerMarkPainter old) => old.color != color;
}
