import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/milk_reception_model.dart';
import '../../shared/widgets/pro_ui.dart';
import 'reception_grid_logic.dart';

/// Lista cronológica de entregas del rango con edición en línea del campo
/// litros (sin modales) y anulación con confirmación en la misma fila.
class ReceptionRecordsTable extends StatefulWidget {
  const ReceptionRecordsTable({
    super.key,
    required this.items,
    required this.canEdit,
    required this.canAnnul,
    required this.onEdit,
    required this.onAnnul,
    this.isCorrected,
    this.operatorName,
  });

  final List<MilkReceptionModel> items;
  final bool canEdit;
  final bool canAnnul;
  final Future<String?> Function(MilkReceptionModel existing, double liters)
  onEdit;
  final Future<String?> Function(MilkReceptionModel existing) onAnnul;
  final bool Function(MilkReceptionModel r)? isCorrected;
  final String Function(String uid)? operatorName;

  static const double rowHeight = 36;

  @override
  State<ReceptionRecordsTable> createState() => _ReceptionRecordsTableState();
}

class _ReceptionRecordsTableState extends State<ReceptionRecordsTable> {
  final TextEditingController _editCtrl = TextEditingController();
  late final FocusNode _editFocus = FocusNode(onKeyEvent: _onEditorKey);
  final ScrollController _scroll = ScrollController();

  String? _editingId;
  String? _editError;
  String? _confirmAnnulId;
  final Map<String, String> _errors = <String, String>{};
  final Set<String> _saving = <String>{};

  @override
  void dispose() {
    _editCtrl.dispose();
    _editFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _lockReason(MilkReceptionModel r) {
    if (r.anulado) return 'Entrega anulada · solo lectura';
    if (r.isLiquidada) return 'Liquidada · solo lectura';
    if (!widget.canEdit) return 'Sin permiso para corregir';
    return null;
  }

  void _startEdit(MilkReceptionModel r) {
    if (_lockReason(r) != null) return;
    final String text = formatLitersCo(r.litros);
    _editCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    setState(() {
      _editingId = r.recepcionId;
      _editError = null;
      _confirmAnnulId = null;
      _errors.remove(r.recepcionId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingId != null) _editFocus.requestFocus();
    });
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _editingId = null;
        _editError = null;
      });
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.tab ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowUp) {
      final int dir =
          (k == LogicalKeyboardKey.arrowUp ||
              (k == LogicalKeyboardKey.tab &&
                  HardwareKeyboard.instance.isShiftPressed))
          ? -1
          : 1;
      _commit(advance: dir);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commit({int advance = 0}) {
    final String? id = _editingId;
    if (id == null) return;
    final int index = widget.items.indexWhere(
      (MilkReceptionModel r) => r.recepcionId == id,
    );
    if (index < 0) return;
    final MilkReceptionModel r = widget.items[index];
    final LitersParseResult parsed = parseLitersInput(_editCtrl.text);
    if (!parsed.isValid) {
      setState(
        () => _editError = parsed.isEmpty
            ? 'Para quitar la entrega usa Anular.'
            : parsed.error,
      );
      return;
    }
    setState(() {
      _editingId = null;
      _editError = null;
    });
    if ((parsed.value! - r.litros).abs() >= 0.005) {
      _track(r.recepcionId, widget.onEdit(r, parsed.value!));
    }
    if (advance != 0) {
      int next = index + advance;
      while (next >= 0 &&
          next < widget.items.length &&
          _lockReason(widget.items[next]) != null) {
        next += advance;
      }
      if (next >= 0 && next < widget.items.length) {
        _startEdit(widget.items[next]);
      }
    }
  }

  Future<void> _track(String id, Future<String?> future) async {
    setState(() {
      _saving.add(id);
      _errors.remove(id);
    });
    String? error;
    try {
      error = await future;
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _saving.remove(id);
      if (error != null) _errors[id] = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const EmptyState(
        icon: Icons.water_drop_outlined,
        title: 'Sin entregas en el período',
        message: 'Cambia el rango de fechas o los filtros para ver registros.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minHeight: 34),
          color: AppTheme.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Row(
            children: <Widget>[
              SizedBox(width: 92, child: DataHeaderCell('Fecha')),
              SizedBox(width: 60, child: DataHeaderCell('Hora')),
              SizedBox(width: 84, child: DataHeaderCell('Código')),
              Expanded(child: DataHeaderCell('Productor')),
              SizedBox(width: 86, child: DataHeaderCell('Jornada')),
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: DataHeaderCell('Litros', align: TextAlign.right),
                ),
              ),
              SizedBox(width: 16),
              SizedBox(width: 118, child: DataHeaderCell('Estado')),
              SizedBox(width: 130, child: DataHeaderCell('Operario')),
              SizedBox(width: 92),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_editingId != null && _editError != null)
          Container(
            color: AppTheme.dangerBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              '${_editError!} · Esc para cancelar',
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: AppTheme.dangerText,
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              itemExtent: ReceptionRecordsTable.rowHeight,
              itemCount: widget.items.length,
              itemBuilder: (BuildContext context, int i) =>
                  _row(widget.items[i], i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(MilkReceptionModel r, int i) {
    final bool afternoon = r.jornada == AppConstants.shiftAfternoon;
    final bool corrected = widget.isCorrected?.call(r) ?? false;
    final String? error = _errors[r.recepcionId];
    final bool confirming = _confirmAnnulId == r.recepcionId;
    final TextStyle mono = AppTheme.monoStyle(
      fontSize: 12.5,
      color: r.anulado ? AppTheme.textMuted : AppTheme.textPrimary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: confirming
            ? AppTheme.dangerBg
            : (i.isOdd ? AppTheme.surfaceMuted.withValues(alpha: 0.6) : null),
        border: const Border(bottom: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(_fmtDate(r.fechaEntrega), style: mono),
          ),
          SizedBox(
            width: 60,
            child: Text(
              r.horaEntrega.length >= 5
                  ? r.horaEntrega.substring(0, 5)
                  : r.horaEntrega,
              style: mono.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              r.codigoAsociadoSnap,
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
              r.nombreProductorSnap,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 13,
                color: r.anulado ? AppTheme.textMuted : AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                afternoon ? 'Tarde' : 'Mañana',
                tone: afternoon ? Tone.accent : Tone.brand,
              ),
            ),
          ),
          SizedBox(width: 100, child: _litersCell(r, error)),
          const SizedBox(width: 16),
          SizedBox(
            width: 118,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _status(r, corrected),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              widget.operatorName?.call(r.operarioUid) ?? r.operarioUid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(fontSize: 12),
            ),
          ),
          SizedBox(width: 92, child: _actions(r, confirming)),
        ],
      ),
    );
  }

  Widget _litersCell(MilkReceptionModel r, String? error) {
    if (_editingId == r.recepcionId) {
      return Container(
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(
            color: _editError != null ? AppTheme.danger : AppTheme.brand,
            width: 1.6,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: TextField(
          key: ValueKey<String>('records-editor-${r.recepcionId}'),
          controller: _editCtrl,
          focusNode: _editFocus,
          onTapOutside: (_) => setState(() {
            _editingId = null;
            _editError = null;
          }),
          inputFormatters: AppInputs.liters(),
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.monoStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixText: 'L',
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          ),
        ),
      );
    }
    final String? lock = _lockReason(r);
    final Widget value = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        if (_saving.contains(r.recepcionId)) ...<Widget>[
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 6),
        ],
        if (error != null) ...<Widget>[
          const Icon(Icons.error_rounded, size: 13, color: AppTheme.danger),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${formatLitersCo(r.litros)} L',
              style:
                  AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: error != null
                        ? AppTheme.dangerText
                        : (r.anulado
                              ? AppTheme.textMuted
                              : AppTheme.textPrimary),
                  ).copyWith(
                    decoration: r.anulado ? TextDecoration.lineThrough : null,
                  ),
            ),
          ),
        ),
      ],
    );
    return Tooltip(
      message: error ?? lock ?? 'Clic para corregir',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: lock == null
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        child: GestureDetector(
          key: ValueKey<String>('records-liters-${r.recepcionId}'),
          behavior: HitTestBehavior.opaque,
          onTap: lock == null ? () => _startEdit(r) : null,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: lock == null
                    ? AppTheme.dividerLight
                    : Colors.transparent,
              ),
            ),
            child: value,
          ),
        ),
      ),
    );
  }

  Widget _status(MilkReceptionModel r, bool corrected) {
    if (r.anulado) {
      return const StatusBadge('Anulada', tone: Tone.danger, dot: true);
    }
    if (r.isLiquidada) {
      return const StatusBadge(
        'Liquidada',
        tone: Tone.neutral,
        icon: Icons.lock_rounded,
      );
    }
    if (!r.isSynced) {
      return const StatusBadge('Pendiente', tone: Tone.warning, dot: true);
    }
    if (corrected) {
      return const StatusBadge('Corregida', tone: Tone.info, dot: true);
    }
    return const StatusBadge('Sincronizada', tone: Tone.success, dot: true);
  }

  Widget _actions(MilkReceptionModel r, bool confirming) {
    if (confirming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          IconButton(
            tooltip: 'Cancelar',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: () => setState(() => _confirmAnnulId = null),
            icon: const Icon(Icons.close_rounded),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.danger,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: () {
              setState(() => _confirmAnnulId = null);
              _track(r.recepcionId, widget.onAnnul(r));
            },
            child: const Text('Anular'),
          ),
        ],
      );
    }
    final bool can = widget.canAnnul && !r.anulado && !r.isLiquidada;
    if (!can) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: 'Anular entrega',
        visualDensity: VisualDensity.compact,
        iconSize: 17,
        color: AppTheme.textMuted,
        onPressed: () => setState(() {
          _confirmAnnulId = r.recepcionId;
          _editingId = null;
        }),
        icon: const Icon(Icons.block_rounded),
      ),
    );
  }

  static String _fmtDate(String iso) {
    final List<String> p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }
}
