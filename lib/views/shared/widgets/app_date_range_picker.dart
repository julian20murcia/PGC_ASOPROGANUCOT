import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Rango de fechas (solo día, sin hora). [end] es inclusivo.
@immutable
class DateRangeValue {
  DateRangeValue(DateTime start, DateTime end)
      : start = _d(start.isAfter(end) ? end : start),
        end = _d(start.isAfter(end) ? start : end);

  factory DateRangeValue.single(DateTime day) => DateRangeValue(day, day);

  final DateTime start;
  final DateTime end;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  int get days => end.difference(start).inDays + 1;

  bool contains(DateTime day) {
    final DateTime d = _d(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Contiene una fecha ISO 'YYYY-MM-DD'.
  bool containsIso(String iso) {
    final DateTime? d = DateTime.tryParse(iso);
    return d != null && contains(d);
  }

  String get startIso => _iso(start);
  String get endIso => _iso(end);

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// El rango inmediatamente anterior con la misma duración (para comparar).
  DateRangeValue get previous => DateRangeValue(
        start.subtract(Duration(days: days)),
        start.subtract(const Duration(days: 1)),
      );

  /// Etiqueta corta: "18 nov 2026", "1 – 15 nov 2026", "28 oct – 3 nov 2026".
  String get label {
    if (start == end) return '${start.day} ${_m(start.month)} ${start.year}';
    if (start.year == end.year && start.month == end.month) {
      return '${start.day} – ${end.day} ${_m(end.month)} ${end.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${_m(start.month)} – ${end.day} ${_m(end.month)} ${end.year}';
    }
    return '${start.day} ${_m(start.month)} ${start.year} – ${end.day} ${_m(end.month)} ${end.year}';
  }

  static String _m(int m) => DateRangePresets.monthsShort[m - 1];

  @override
  bool operator ==(Object other) =>
      other is DateRangeValue && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRangeValue($startIso..$endIso)';
}

/// Atajos de rango estándar de la plataforma.
class DateRangePreset {
  const DateRangePreset(this.label, this.build);
  final String label;
  final DateRangeValue Function(DateTime today) build;
}

class DateRangePresets {
  DateRangePresets._();

  static const List<String> monthsShort = <String>[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  static const List<String> monthsLong = <String>[
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  static DateRangeValue today([DateTime? now]) =>
      DateRangeValue.single(now ?? DateTime.now());

  /// Quincena que contiene [day]: 1–15 o 16–fin de mes.
  static DateRangeValue quincenaOf(DateTime day) {
    if (day.day <= 15) {
      return DateRangeValue(DateTime(day.year, day.month, 1), DateTime(day.year, day.month, 15));
    }
    return DateRangeValue(
      DateTime(day.year, day.month, 16),
      DateTime(day.year, day.month + 1, 0),
    );
  }

  static DateRangeValue monthOf(DateTime day) =>
      DateRangeValue(DateTime(day.year, day.month, 1), DateTime(day.year, day.month + 1, 0));

  static final List<DateRangePreset> standard = <DateRangePreset>[
    DateRangePreset('Hoy', (DateTime t) => DateRangeValue.single(t)),
    DateRangePreset('Ayer', (DateTime t) => DateRangeValue.single(t.subtract(const Duration(days: 1)))),
    DateRangePreset('Últimos 7 días', (DateTime t) => DateRangeValue(t.subtract(const Duration(days: 6)), t)),
    DateRangePreset('Esta quincena', (DateTime t) => quincenaOf(t)),
    DateRangePreset('Quincena anterior', (DateTime t) {
      final DateRangeValue q = quincenaOf(t);
      return quincenaOf(q.start.subtract(const Duration(days: 1)));
    }),
    DateRangePreset('Este mes', (DateTime t) => monthOf(t)),
    DateRangePreset('Mes anterior', (DateTime t) => monthOf(DateTime(t.year, t.month, 0))),
    DateRangePreset('Últimos 30 días', (DateTime t) => DateRangeValue(t.subtract(const Duration(days: 29)), t)),
    DateRangePreset('Últimos 90 días', (DateTime t) => DateRangeValue(t.subtract(const Duration(days: 89)), t)),
    DateRangePreset('Este año', (DateTime t) => DateRangeValue(DateTime(t.year, 1, 1), t)),
  ];
}

/// Botón compacto que muestra el rango actual y abre el selector.
///
/// En pantallas anchas abre un popover anclado (no ocupa la pantalla); en
/// pantallas angostas abre una hoja inferior.
class AppDateRangeField extends StatelessWidget {
  const AppDateRangeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.presets,
    this.dense = false,
    this.expand = false,
    this.label,
  });

  final DateRangeValue value;
  final ValueChanged<DateRangeValue> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final List<DateRangePreset>? presets;
  final bool dense;
  final bool expand;
  final String? label;

  String? _presetLabel() {
    final DateTime now = DateTime.now();
    for (final DateRangePreset p in presets ?? DateRangePresets.standard) {
      if (p.build(now) == value) return p.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? preset = _presetLabel();
    return Builder(
      builder: (BuildContext anchorContext) {
        return Material(
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            side: const BorderSide(color: AppTheme.inputBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            onTap: () async {
              final DateRangeValue? picked = await showAppDateRangePicker(
                anchorContext,
                initial: value,
                firstDate: firstDate,
                lastDate: lastDate,
                presets: presets,
              );
              if (picked != null && picked != value) onChanged(picked);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 7 : 9),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.brand),
                  const SizedBox(width: 8),
                  if (label != null) ...<Widget>[
                    Text('${label!}: ', style: AppTheme.bodyStyle(fontSize: 12.5)),
                  ],
                  if (preset != null) ...<Widget>[
                    Text(
                      preset,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 1,
                      height: 14,
                      color: AppTheme.border,
                    ),
                  ],
                  Flexible(
                    child: Text(
                      value.label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: preset == null ? FontWeight.w600 : FontWeight.w500,
                        color: preset == null ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more_rounded, size: 18, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Campo compacto para una sola fecha (reutiliza el mismo calendario).
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.placeholder = 'Seleccionar fecha',
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (BuildContext anchorContext) {
      return Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          side: const BorderSide(color: AppTheme.inputBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          onTap: () async {
            final DateTime? picked = await showAppDatePicker(
              anchorContext,
              initial: value,
              firstDate: firstDate,
              lastDate: lastDate,
            );
            if (picked != null) onChanged(picked);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                const Icon(Icons.event_rounded, size: 16, color: AppTheme.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? placeholder : DateRangeValue.single(value!).label,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: value == null ? AppTheme.textMuted : AppTheme.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more_rounded, size: 18, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Abre el selector de rango. Devuelve null si se cancela.
Future<DateRangeValue?> showAppDateRangePicker(
  BuildContext anchorContext, {
  required DateRangeValue initial,
  DateTime? firstDate,
  DateTime? lastDate,
  List<DateRangePreset>? presets,
}) {
  return _showPicker<DateRangeValue>(
    anchorContext,
    (BuildContext ctx, bool compact) => _RangePickerPanel(
      initial: initial,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 366)),
      presets: presets ?? DateRangePresets.standard,
      compact: compact,
      singleDate: false,
    ),
    wide: true,
  );
}

/// Abre el selector de una sola fecha.
Future<DateTime?> showAppDatePicker(
  BuildContext anchorContext, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final DateRangeValue? r = await _showPicker<DateRangeValue>(
    anchorContext,
    (BuildContext ctx, bool compact) => _RangePickerPanel(
      initial: DateRangeValue.single(initial ?? DateTime.now()),
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 366)),
      presets: const <DateRangePreset>[],
      compact: true,
      singleDate: true,
    ),
    wide: false,
  );
  return r?.start;
}

Future<T?> _showPicker<T>(
  BuildContext anchorContext,
  Widget Function(BuildContext, bool compact) builder, {
  required bool wide,
}) {
  final Size screen = MediaQuery.sizeOf(anchorContext);
  if (screen.width < 640) {
    return showModalBottomSheet<T>(
      context: anchorContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: builder(ctx, true),
      ),
    );
  }
  final RenderBox box = anchorContext.findRenderObject()! as RenderBox;
  final RenderBox overlay =
      Navigator.of(anchorContext).overlay!.context.findRenderObject()! as RenderBox;
  final Rect anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  return Navigator.of(anchorContext).push<T>(
    _PopoverRoute<T>(
      anchor: anchor,
      builder: (BuildContext ctx) => builder(ctx, !wide),
      barrierLabel: MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel,
    ),
  );
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.barrierLabel,
  });

  final Rect anchor;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => const Color(0x0F0F1B1E);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(BuildContext context, Animation<double> a, Animation<double> b) {
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor),
      child: builder(context),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final CurvedAnimation c = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: c,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.015), end: Offset.zero).animate(c),
        child: child,
      ),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor);
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth - 24, constraints.maxHeight - 24));

  @override
  Offset getPositionForChild(Size size, Size child) {
    double x = anchor.left;
    if (x + child.width > size.width - 12) x = size.width - 12 - child.width;
    x = math.max(12, x);
    double y = anchor.bottom + 6;
    if (y + child.height > size.height - 12) {
      final double above = anchor.top - 6 - child.height;
      y = above >= 12 ? above : math.max(12, size.height - 12 - child.height);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor;
}

class _RangePickerPanel extends StatefulWidget {
  const _RangePickerPanel({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.presets,
    required this.compact,
    required this.singleDate,
  });

  final DateRangeValue initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<DateRangePreset> presets;
  final bool compact;
  final bool singleDate;

  @override
  State<_RangePickerPanel> createState() => _RangePickerPanelState();
}

class _RangePickerPanelState extends State<_RangePickerPanel> {
  late DateTime _start = widget.initial.start;
  DateTime? _end;
  late DateTime _month; // primer mes visible
  DateTime? _hover;

  @override
  void initState() {
    super.initState();
    _end = widget.initial.end;
    final DateTime base = widget.compact || widget.singleDate
        ? widget.initial.end
        : (widget.initial.start.month == widget.initial.end.month &&
                widget.initial.start.year == widget.initial.end.year
            ? DateTime(widget.initial.end.year, widget.initial.end.month - 1)
            : widget.initial.start);
    _month = DateTime(base.year, base.month);
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _tapDay(DateTime day) {
    if (widget.singleDate) {
      Navigator.of(context).pop(DateRangeValue.single(day));
      return;
    }
    setState(() {
      if (_end != null) {
        _start = day;
        _end = null;
      } else {
        if (day.isBefore(_start)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  void _applyPreset(DateRangePreset p) {
    final DateRangeValue r = p.build(DateTime.now());
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final bool twoMonths = !widget.compact;
    final DateTime today = _day(DateTime.now());
    final String? activePreset = _end == null
        ? null
        : widget.presets
            .where((DateRangePreset p) => p.build(today) == DateRangeValue(_start, _end!))
            .map((DateRangePreset p) => p.label)
            .firstOrNull;

    final Widget calendars = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _MonthGrid(
              month: _month,
              start: _start,
              end: _end,
              hover: _hover,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onTap: _tapDay,
              onHover: (DateTime? d) => setState(() => _hover = d),
              showPrev: true,
              showNext: !twoMonths,
              onPrev: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
            if (twoMonths) ...<Widget>[
              const SizedBox(width: 20),
              _MonthGrid(
                month: DateTime(_month.year, _month.month + 1),
                start: _start,
                end: _end,
                hover: _hover,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onTap: _tapDay,
                onHover: (DateTime? d) => setState(() => _hover = d),
                showPrev: false,
                showNext: true,
                onPrev: () {},
                onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ],
        ),
      ],
    );

    final Widget footer = widget.singleDate
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.dividerLight)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _end == null
                        ? 'Selecciona la fecha final'
                        : '${DateRangeValue(_start, _end!).label} · ${DateRangeValue(_start, _end!).days} días',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _end == null ? AppTheme.textMuted : AppTheme.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _end == null
                      ? null
                      : () => Navigator.of(context).pop(DateRangeValue(_start, _end!)),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          );

    final Widget presetsList = widget.presets.isEmpty
        ? const SizedBox.shrink()
        : widget.compact
            ? SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.presets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (BuildContext ctx, int i) {
                    final DateRangePreset p = widget.presets[i];
                    final bool on = p.label == activePreset;
                    return ChoiceChip(
                      label: Text(p.label),
                      selected: on,
                      onSelected: (_) => _applyPreset(p),
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on ? Colors.white : AppTheme.textSecondary,
                      ),
                      selectedColor: AppTheme.brand,
                      backgroundColor: AppTheme.surfaceSunken,
                      side: BorderSide.none,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              )
            : Container(
                width: 168,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  border: Border(right: BorderSide(color: AppTheme.dividerLight)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final DateRangePreset p in widget.presets)
                      _PresetTile(
                        label: p.label,
                        selected: p.label == activePreset,
                        onTap: () => _applyPreset(p),
                      ),
                  ],
                ),
              );

    final Widget body = widget.compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.presets.isNotEmpty) ...<Widget>[
                Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: presetsList),
              ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: calendars),
              ),
              footer,
            ],
          )
        : IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                presetsList,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Padding(padding: const EdgeInsets.all(14), child: calendars),
                    SizedBox(width: 2 * 252 + 20 + 28, child: footer),
                  ],
                ),
              ],
            ),
          );

    return Material(
      color: AppTheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: widget.compact ? null : AppTheme.shadowMd),
        child: body,
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppTheme.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.brand : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.start,
    required this.end,
    required this.hover,
    required this.firstDate,
    required this.lastDate,
    required this.onTap,
    required this.onHover,
    required this.showPrev,
    required this.showNext,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final DateTime start;
  final DateTime? end;
  final DateTime? hover;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime?> onHover;
  final bool showPrev;
  final bool showNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const double cell = 36;
  static const List<String> _dow = <String>['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final DateTime first = DateTime(month.year, month.month, 1);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final int lead = first.weekday - 1; // lunes = 0
    final DateTime today = DateTime.now();
    final DateTime todayD = DateTime(today.year, today.month, today.day);
    final DateTime fd = DateTime(firstDate.year, firstDate.month, firstDate.day);
    final DateTime ld = DateTime(lastDate.year, lastDate.month, lastDate.day);

    // Rango "virtual" mientras se elige el final (vista previa al pasar el mouse).
    DateTime rs = start;
    DateTime? re = end;
    if (end == null && hover != null) {
      re = hover!.isBefore(start) ? start : hover;
      rs = hover!.isBefore(start) ? hover! : start;
    }

    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < lead; i++) {
      cells.add(const SizedBox(width: cell, height: cell));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final DateTime day = DateTime(month.year, month.month, d);
      final bool disabled = day.isBefore(fd) || day.isAfter(ld);
      final bool isStart = day == rs;
      final bool isEnd = re != null && day == re;
      final bool inRange = re != null && day.isAfter(rs) && day.isBefore(re);
      final bool edge = isStart || isEnd;
      final bool isToday = day == todayD;
      final bool hasRange = re != null && rs != re;

      cells.add(
        MouseRegion(
          onEnter: (_) => disabled ? null : onHover(day),
          child: GestureDetector(
            onTap: disabled ? null : () => onTap(day),
            child: SizedBox(
              width: cell,
              height: cell,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  if (hasRange && (inRange || edge))
                    Positioned.fill(
                      top: 3,
                      bottom: 3,
                      left: isStart ? cell / 2 : 0,
                      right: isEnd ? cell / 2 : 0,
                      child: const ColoredBox(color: AppTheme.brandSoft),
                    ),
                  Container(
                    width: cell - 4,
                    height: cell - 4,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: edge ? AppTheme.brand : null,
                      shape: BoxShape.circle,
                      border: isToday && !edge
                          ? Border.all(color: AppTheme.brand.withValues(alpha: 0.6))
                          : null,
                    ),
                    child: Text(
                      '$d',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: edge || isToday ? FontWeight.w700 : FontWeight.w500,
                        color: disabled
                            ? AppTheme.borderStrong
                            : edge
                                ? Colors.white
                                : inRange
                                    ? AppTheme.brandHover
                                    : AppTheme.textPrimary,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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

    return MouseRegion(
      onExit: (_) => onHover(null),
      child: SizedBox(
        width: cell * 7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 32,
              child: Row(
                children: <Widget>[
                  _NavBtn(icon: Icons.chevron_left_rounded, onTap: showPrev ? onPrev : null),
                  Expanded(
                    child: Text(
                      '${DateRangePresets.monthsLong[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _NavBtn(icon: Icons.chevron_right_rounded, onTap: showNext ? onNext : null),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                for (final String d in _dow)
                  SizedBox(
                    width: cell,
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: AppTheme.overlineStyle(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: cell * 6,
              child: Wrap(children: cells),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return const SizedBox(width: 28);
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: onTap,
        icon: Icon(icon, color: AppTheme.textSecondary),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
