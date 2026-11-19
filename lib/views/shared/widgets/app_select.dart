import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Opción individual de un [AppSelect].
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.searchText,
  });

  final T value;
  final String label;

  /// Texto secundario mostrado debajo de la etiqueta (p. ej. cédula).
  final String? description;
  final IconData? icon;

  /// Texto adicional usado sólo para la búsqueda.
  final String? searchText;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final String haystack = '$label ${description ?? ''} ${searchText ?? ''}'
        .toLowerCase();
    return haystack.contains(query);
  }
}

/// Selector personalizado del sistema de diseño.
///
/// El menú se pinta con [OverlayPortal], por lo que siempre aparece encima
/// del contenido que lo contiene, incluidos diálogos y bottom sheets, y no
/// queda recortado por los límites del modal. `Esc` cierra sólo el menú
/// (no el diálogo), y soporta navegación completa por teclado.
class AppSelect<T> extends StatefulWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelText,
    this.hintText = 'Seleccionar…',
    this.prefixIcon,
    this.dense = false,
    this.searchable,
    this.searchHint = 'Buscar…',
    this.emptyText = 'Sin resultados',
    this.menuMaxHeight = 320,
    this.menuMinWidth = 220,
    this.enabled = true,
  });

  final T value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String? labelText;
  final String hintText;
  final IconData? prefixIcon;

  /// Variante compacta para barras de filtros (altura ~36 px).
  final bool dense;

  /// Muestra un buscador. Por defecto se activa con más de 8 opciones.
  final bool? searchable;
  final String searchHint;
  final String emptyText;
  final double menuMaxHeight;
  final double menuMinWidth;
  final bool enabled;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>>
    with SingleTickerProviderStateMixin {
  static const double _gap = 6;
  static const double _screenMargin = 12;

  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  final FocusNode _triggerFocus = FocusNode(debugLabel: 'AppSelect');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'AppSelect.search');
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Object _tapGroup = Object();

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 110),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  int _highlight = -1;
  bool _hovering = false;
  bool _openUp = false;
  double _menuMaxHeight = 320;
  double _menuWidth = 220;
  double _dx = 0;

  bool get _enabled => widget.enabled && widget.onChanged != null;
  bool get _isOpen => _portal.isShowing;
  bool get _isSearchable => widget.searchable ?? widget.options.length > 8;
  bool get _hasDescriptions =>
      widget.options.any((AppSelectOption<T> o) => o.description != null);
  double get _itemExtent => _hasDescriptions ? 52 : 40;

  String get _query => _searchCtrl.text.trim().toLowerCase();

  List<AppSelectOption<T>> get _filtered => widget.options
      .where((AppSelectOption<T> o) => o.matches(_query))
      .toList(growable: false);

  AppSelectOption<T>? get _selected {
    for (final AppSelectOption<T> o in widget.options) {
      if (o.value == widget.value) return o;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _triggerFocus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && _isOpen) _hide();
  }

  @override
  void dispose() {
    _triggerFocus.removeListener(_onFocusChanged);
    _triggerFocus.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Apertura / cierre
  // ---------------------------------------------------------------------------

  void _toggle() => _isOpen ? _close() : _open();

  void _open() {
    if (!_enabled || _isOpen) return;
    _searchCtrl.clear();
    _highlight = _filtered.indexWhere(
      (AppSelectOption<T> o) => o.value == widget.value,
    );
    _computePlacement();
    _portal.show();
    _anim.forward(from: 0);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isOpen) return;
      if (_isSearchable) {
        _searchFocus.requestFocus();
      } else {
        _triggerFocus.requestFocus();
      }
      _scrollToHighlight(center: true);
    });
  }

  Future<void> _close({bool refocus = true}) async {
    if (!_isOpen) return;
    if (refocus) _triggerFocus.requestFocus();
    await _anim.reverse();
    if (!mounted) return;
    if (_anim.status == AnimationStatus.dismissed) _hide();
  }

  void _hide() {
    if (_isOpen) _portal.hide();
    if (mounted) setState(() {});
  }

  void _select(AppSelectOption<T> option) {
    widget.onChanged?.call(option.value);
    _close();
  }

  void _computePlacement() {
    final RenderBox? box =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final MediaQueryData mq = MediaQuery.of(context);
    final Offset origin = box.localToGlobal(Offset.zero);
    final Size size = box.size;

    final double screenW = mq.size.width;
    _menuWidth = math.min(
      math.max(size.width, widget.menuMinWidth),
      screenW - _screenMargin * 2,
    );
    final double overflowRight =
        origin.dx + _menuWidth - (screenW - _screenMargin);
    _dx = overflowRight > 0 ? -overflowRight : 0;
    if (origin.dx + _dx < _screenMargin) _dx = _screenMargin - origin.dx;

    final double below =
        mq.size.height -
        mq.viewInsets.bottom -
        (origin.dy + size.height) -
        _gap -
        _screenMargin;
    final double above = origin.dy - mq.padding.top - _gap - _screenMargin;
    final double desired = math.min(
      widget.menuMaxHeight,
      widget.options.length * _itemExtent + 12 + (_isSearchable ? 53 : 0),
    );
    _openUp = below < desired && above > below;
    _menuMaxHeight = math.max(
      140,
      math.min(widget.menuMaxHeight, _openUp ? above : below),
    );
  }

  // ---------------------------------------------------------------------------
  // Teclado
  // ---------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;

    if (!_isOpen) {
      if (!_enabled) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space) {
        _open();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final List<AppSelectOption<T>> items = _filtered;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _close(refocus: false);
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1, items.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1, items.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        (key == LogicalKeyboardKey.space && !_isSearchable)) {
      if (_highlight >= 0 && _highlight < items.length) {
        _select(items[_highlight]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveHighlight(int delta, int count) {
    if (count == 0) return;
    setState(() {
      _highlight = _highlight < 0
          ? (delta > 0 ? 0 : count - 1)
          : (_highlight + delta).clamp(0, count - 1);
    });
    _scrollToHighlight();
  }

  void _scrollToHighlight({bool center = false}) {
    if (!_scroll.hasClients || _highlight < 0) return;
    final ScrollPosition pos = _scroll.position;
    final double itemTop = _highlight * _itemExtent + 6;
    final double itemBottom = itemTop + _itemExtent;
    double? target;
    if (center) {
      target = itemTop - (pos.viewportDimension - _itemExtent) / 2;
    } else if (itemTop < pos.pixels) {
      target = itemTop - 6;
    } else if (itemBottom > pos.pixels + pos.viewportDimension) {
      target = itemBottom - pos.viewportDimension + 6;
    }
    if (target == null) return;
    final double clamped = target.clamp(0.0, pos.maxScrollExtent);
    if (center) {
      _scroll.jumpTo(clamped);
    } else {
      _scroll.animateTo(
        clamped,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppSelectOption<T>? selected = _selected;
    final bool focused = _triggerFocus.hasFocus || _isOpen;
    final InputDecorationThemeData inputTheme = Theme.of(
      context,
    ).inputDecorationTheme;

    final InputDecoration decoration = InputDecoration(
      labelText: widget.labelText,
      hintText: widget.hintText,
      enabled: _enabled,
      isDense: true,
      contentPadding: widget.dense
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : null,
      prefixIcon: widget.prefixIcon == null
          ? null
          : Icon(widget.prefixIcon, size: widget.dense ? 16 : 18),
      prefixIconConstraints: widget.dense
          ? const BoxConstraints(minWidth: 34, minHeight: 20)
          : null,
      suffixIcon: RotationTransition(
        turns: Tween<double>(begin: 0, end: 0.5).animate(_curve),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: widget.dense ? 18 : 20,
          color: focused ? AppTheme.primaryGreen : AppTheme.textSecondary,
        ),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
    ).applyDefaults(inputTheme);

    final Widget field = InputDecorator(
      decoration: decoration,
      isFocused: focused,
      isHovering: _hovering && _enabled,
      isEmpty: selected == null,
      textAlignVertical: TextAlignVertical.center,
      child: selected == null
          ? const SizedBox.shrink()
          : Row(
              children: <Widget>[
                if (selected.icon != null &&
                    widget.prefixIcon == null) ...<Widget>[
                  Icon(selected.icon, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.dense ? 13.5 : 14,
                      fontWeight: FontWeight.w500,
                      color: _enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
    );

    return Focus(
      focusNode: _triggerFocus,
      canRequestFocus: _enabled,
      onKeyEvent: _onKey,
      child: TapRegion(
        groupId: _tapGroup,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _buildOverlay,
          child: CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              key: _targetKey,
              cursor: _enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.forbidden,
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _enabled ? _toggle : null,
                child: Semantics(
                  button: true,
                  enabled: _enabled,
                  expanded: _isOpen,
                  label: widget.labelText,
                  value: selected?.label,
                  child: field,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final Alignment scaleAlign = _openUp
        ? Alignment.bottomCenter
        : Alignment.topCenter;
    return Positioned(
      left: 0,
      top: 0,
      width: _menuWidth,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: _openUp ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(_dx, _openUp ? -_gap : _gap),
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _close(refocus: false),
          child: FadeTransition(
            opacity: _curve,
            child: ScaleTransition(
              alignment: scaleAlign,
              scale: Tween<double>(begin: 0.96, end: 1).animate(_curve),
              child: _buildPanel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final List<AppSelectOption<T>> items = _filtered;
    return Container(
      constraints: BoxConstraints(maxHeight: _menuMaxHeight),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A0C3B24),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x0F0C3B24),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_isSearchable) _buildSearchField(),
              Flexible(
                child: items.isEmpty
                    ? _buildEmpty()
                    : Scrollbar(
                        controller: _scroll,
                        thumbVisibility:
                            items.length * _itemExtent > _menuMaxHeight,
                        child: ListView.builder(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(6),
                          itemExtent: _itemExtent,
                          itemCount: items.length,
                          itemBuilder: (BuildContext context, int i) =>
                              _buildOption(items[i], i),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.dividerLight)),
      ),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(60)],
          style: const TextStyle(fontSize: 13.5),
          onChanged: (_) {
            setState(() => _highlight = _filtered.isEmpty ? -1 : 0);
            if (_scroll.hasClients) _scroll.jumpTo(0);
          },
          decoration: InputDecoration(
            hintText: widget.searchHint,
            fillColor: AppTheme.canvas,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 17),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 20,
            ),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar',
                    splashRadius: 14,
                    iconSize: 16,
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _highlight = 0);
                      _searchFocus.requestFocus();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.search_off_rounded,
            size: 22,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 6),
          Text(
            widget.emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(AppSelectOption<T> option, int index) {
    final bool isSelected = option.value == widget.value;
    final bool isHighlighted = index == _highlight;

    final Color bg = isHighlighted
        ? (isSelected ? const Color(0xFFD5F0DE) : AppTheme.surfaceMuted)
        : (isSelected ? AppTheme.primaryGreenLight : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (_highlight != index) {
          setState(() => _highlight = index);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(option),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Row(
            children: <Widget>[
              if (option.icon != null) ...<Widget>[
                Icon(
                  option.icon,
                  size: 17,
                  color: isSelected
                      ? AppTheme.primaryGreen
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _highlightedText(
                      option.label,
                      TextStyle(
                        fontSize: 13.5,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.successText
                            : AppTheme.textPrimary,
                      ),
                    ),
                    if (option.description != null) ...<Widget>[
                      const SizedBox(height: 2),
                      _highlightedText(
                        option.description!,
                        const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: isSelected ? 1 : 0,
                child: const Icon(
                  Icons.check_rounded,
                  size: 17,
                  color: AppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resalta en negrita la coincidencia de la búsqueda dentro del texto.
  Widget _highlightedText(String text, TextStyle style) {
    final String q = _query;
    final int start = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    if (start < 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final int end = start + q.length;
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryGreen,
              backgroundColor: Color(0x1F168A3E),
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
