import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/producer_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/pro_ui.dart';

/// Tabla compacta del padrón con barra de búsqueda, filtros y orden.
class ProducerTable extends StatelessWidget {
  const ProducerTable({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.onCreate,
  });

  final String? selectedId;
  final ValueChanged<ProducerModel> onSelect;
  final VoidCallback? onCreate;

  static const double rowHeight = 44;

  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();
    final List<ProducerModel> rows = ctrl.filteredProducers;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final _Cols cols = _Cols.forWidth(c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Toolbar(ctrl: ctrl, narrow: c.maxWidth < 860),
              const Divider(height: 1),
              if (ctrl.isLoading && ctrl.allProducers.isEmpty)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              else if (rows.isEmpty)
                Expanded(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.groups_outlined,
                      title: ctrl.hasActiveFilters
                          ? 'Ningún productor coincide con la búsqueda'
                          : 'Aún no hay productores registrados',
                      message: ctrl.hasActiveFilters
                          ? 'Prueba con otro nombre, cédula o código, o limpia los filtros.'
                          : 'Registra el primer ganadero asociado con su autorización de datos.',
                      action: ctrl.hasActiveFilters
                          ? OutlinedButton(
                              onPressed: ctrl.clearFilters,
                              child: const Text('Limpiar filtros'),
                            )
                          : (onCreate == null
                                ? null
                                : FilledButton.icon(
                                    onPressed: onCreate,
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Registrar productor'),
                                  )),
                    ),
                  ),
                )
              else ...<Widget>[
                _HeaderRow(cols: cols, ctrl: ctrl),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemExtent: rowHeight,
                    itemBuilder: (BuildContext context, int i) => _ProducerRow(
                      producer: rows[i],
                      stats: ctrl.statsFor(rows[i].productorId),
                      cols: cols,
                      selected: rows[i].productorId == selectedId,
                      zebra: i.isOdd,
                      loadingStats:
                          ctrl.isLoadingDeliveries && !ctrl.deliveriesLoaded,
                      onTap: () => onSelect(rows[i]),
                    ),
                  ),
                ),
              ],
              const Divider(height: 1),
              _Footer(ctrl: ctrl, shown: rows.length),
            ],
          );
        },
      ),
    );
  }
}

/// Qué columnas caben según el ancho disponible.
class _Cols {
  const _Cols({
    required this.cedula,
    required this.telefono,
    required this.ultima,
    required this.app,
    required this.finca,
  });

  factory _Cols.forWidth(double w) => _Cols(
    finca: w >= 620,
    cedula: w >= 900,
    telefono: w >= 1020,
    ultima: w >= 760,
    app: w >= 700,
  );

  final bool cedula;
  final bool telefono;
  final bool ultima;
  final bool app;
  final bool finca;

  static const double code = 84;
  static const double cedulaW = 104;
  static const double telefonoW = 104;
  static const double estado = 84;
  static const double litros = 104;
  static const double ultimaW = 100;
  static const double appW = 48;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.ctrl, required this.narrow});
  final ProducerController ctrl;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final Widget status = SizedBox(
      width: 150,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.statusFilter,
        prefixIcon: Icons.toggle_on_outlined,
        options: const <AppSelectOption<String>>[
          AppSelectOption<String>(value: 'ALL', label: 'Todos'),
          AppSelectOption<String>(
            value: 'ACTIVO',
            label: 'Activos',
            icon: Icons.check_circle_outline_rounded,
          ),
          AppSelectOption<String>(
            value: 'INACTIVO',
            label: 'Inactivos',
            icon: Icons.pause_circle_outline_rounded,
          ),
        ],
        onChanged: ctrl.setStatusFilter,
      ),
    );
    final Widget vereda = SizedBox(
      width: 180,
      child: AppSelect<String>(
        dense: true,
        value: ctrl.veredaFilter,
        prefixIcon: Icons.place_outlined,
        searchHint: 'Buscar vereda…',
        options: <AppSelectOption<String>>[
          const AppSelectOption<String>(
            value: 'ALL',
            label: 'Todas las veredas',
          ),
          for (final String v in ctrl.availableVeredas)
            AppSelectOption<String>(value: v, label: v),
        ],
        onChanged: ctrl.setVeredaFilter,
      ),
    );
    final Widget sort = SizedBox(
      width: 220,
      child: AppSelect<ProducerSortOption>(
        key: const Key('producer-sort-select'),
        dense: true,
        value: ctrl.sort,
        prefixIcon: Icons.sort_rounded,
        searchable: false,
        options: <AppSelectOption<ProducerSortOption>>[
          for (final ProducerSortOption o in ProducerSortOption.values)
            AppSelectOption<ProducerSortOption>(
              value: o,
              label: o.label,
              icon: switch (o) {
                ProducerSortOption.recientes => Icons.fiber_new_outlined,
                ProducerSortOption.antiguos => Icons.history_rounded,
                ProducerSortOption.masLeche => Icons.trending_up_rounded,
                ProducerSortOption.menosLeche => Icons.trending_down_rounded,
                ProducerSortOption.nombre => Icons.sort_by_alpha_rounded,
                ProducerSortOption.codigo => Icons.tag_rounded,
              },
              description: o.usesDeliveries
                  ? 'Según litros del período elegido'
                  : null,
            ),
        ],
        onChanged: ctrl.setSort,
      ),
    );
    final Widget search = AppSearchField(
      key: ValueKey<int>(ctrl.filtersVersion),
      width: null,
      hint: 'Buscar por nombre, cédula, código, finca…',
      initialValue: ctrl.searchQuery,
      onChanged: ctrl.setSearchQuery,
    );
    final Widget clear = ctrl.hasActiveFilters
        ? IconButton(
            tooltip: 'Limpiar filtros',
            onPressed: ctrl.clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(10),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                search,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[status, vereda, sort, clear],
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: search),
                const SizedBox(width: 8),
                status,
                const SizedBox(width: 8),
                vereda,
                const SizedBox(width: 8),
                sort,
                clear,
              ],
            ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.cols, required this.ctrl});
  final _Cols cols;
  final ProducerController ctrl;

  @override
  Widget build(BuildContext context) {
    final ProducerSortOption s = ctrl.sort;
    bool? dir(ProducerSortOption asc, ProducerSortOption desc) =>
        s == asc ? true : (s == desc ? false : null);
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      color: AppTheme.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _Cols.code,
            child: DataHeaderCell(
              'Código',
              sortAscending: s == ProducerSortOption.codigo ? true : null,
              onTap: () => ctrl.setSort(ProducerSortOption.codigo),
            ),
          ),
          Expanded(
            flex: 3,
            child: DataHeaderCell(
              'Productor',
              sortAscending: s == ProducerSortOption.nombre ? true : null,
              onTap: () => ctrl.setSort(ProducerSortOption.nombre),
            ),
          ),
          if (cols.cedula)
            const SizedBox(
              width: _Cols.cedulaW,
              child: DataHeaderCell('Cédula'),
            ),
          if (cols.finca)
            const Expanded(flex: 3, child: DataHeaderCell('Finca / vereda')),
          if (cols.telefono)
            const SizedBox(
              width: _Cols.telefonoW,
              child: DataHeaderCell('Celular'),
            ),
          const SizedBox(width: _Cols.estado, child: DataHeaderCell('Estado')),
          SizedBox(
            width: _Cols.litros,
            child: Align(
              alignment: Alignment.centerRight,
              child: DataHeaderCell(
                'Litros',
                align: TextAlign.right,
                sortAscending: dir(
                  ProducerSortOption.menosLeche,
                  ProducerSortOption.masLeche,
                ),
                onTap: () => ctrl.setSort(
                  s == ProducerSortOption.masLeche
                      ? ProducerSortOption.menosLeche
                      : ProducerSortOption.masLeche,
                ),
              ),
            ),
          ),
          if (cols.ultima)
            const SizedBox(
              width: _Cols.ultimaW,
              child: Padding(
                padding: EdgeInsets.only(left: 16),
                child: DataHeaderCell('Últ. entrega'),
              ),
            ),
          if (cols.app)
            const SizedBox(
              width: _Cols.appW,
              child: Center(child: DataHeaderCell('App')),
            ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }
}

class _ProducerRow extends StatefulWidget {
  const _ProducerRow({
    required this.producer,
    required this.stats,
    required this.cols,
    required this.selected,
    required this.zebra,
    required this.loadingStats,
    required this.onTap,
  });

  final ProducerModel producer;
  final ProducerDeliveryStats stats;
  final _Cols cols;
  final bool selected;
  final bool zebra;
  final bool loadingStats;
  final VoidCallback onTap;

  @override
  State<_ProducerRow> createState() => _ProducerRowState();
}

class _ProducerRowState extends State<_ProducerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ProducerModel p = widget.producer;
    final ProducerDeliveryStats s = widget.stats;
    final bool hasApp = ProducerController.hasAppAccess(p);
    final Color bg = widget.selected
        ? AppTheme.brandSoft
        : (_hover
              ? AppTheme.surfaceMuted
              : (widget.zebra
                    ? AppTheme.surfaceMuted.withValues(alpha: 0.45)
                    : AppTheme.surface));
    final TextStyle cell = AppTheme.bodyStyle(
      fontSize: 12.5,
      color: AppTheme.textSecondary,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: const BorderSide(color: AppTheme.dividerLight),
              left: BorderSide(
                color: widget.selected ? AppTheme.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 14),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: _Cols.code,
                child: Text(
                  p.codigoAsociado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brand,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: <Widget>[
                    InitialsAvatar(p.nombreCompleto, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.nombreCompleto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              if (widget.cols.cedula)
                SizedBox(
                  width: _Cols.cedulaW,
                  child: Text(
                    p.cedula,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              if (widget.cols.finca)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          p.nombreFinca,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: cell.copyWith(color: AppTheme.textPrimary),
                        ),
                        Text(
                          p.vereda,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.cols.telefono)
                SizedBox(
                  width: _Cols.telefonoW,
                  child: Text(
                    p.telefono.isEmpty ? '—' : p.telefono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              SizedBox(
                width: _Cols.estado,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    p.isActivo ? 'Activo' : 'Inactivo',
                    tone: p.isActivo ? Tone.success : Tone.neutral,
                    dot: true,
                  ),
                ),
              ),
              SizedBox(
                width: _Cols.litros,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: widget.loadingStats
                      ? Text(
                          '…',
                          style: AppTheme.monoStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMuted,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            s.liters <= 0
                                ? '—'
                                : AppFormatters.formatLiters(s.liters),
                            style: AppTheme.monoStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: s.liters <= 0
                                  ? AppTheme.textMuted
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                ),
              ),
              if (widget.cols.ultima)
                SizedBox(
                  width: _Cols.ultimaW,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      s.lastDeliveryIso == null
                          ? '—'
                          : AppFormatters.formatIsoDate(s.lastDeliveryIso!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              if (widget.cols.app)
                SizedBox(
                  width: _Cols.appW,
                  child: Center(
                    child: Tooltip(
                      message: hasApp
                          ? 'Tiene acceso a la app móvil'
                          : 'Sin acceso a la app',
                      child: Icon(
                        hasApp
                            ? Icons.smartphone_rounded
                            : Icons.remove_rounded,
                        size: 16,
                        color: hasApp ? AppTheme.brand : AppTheme.borderStrong,
                      ),
                    ),
                  ),
                ),
              const SizedBox(
                width: 20,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.ctrl, required this.shown});
  final ProducerController ctrl;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final int total = ctrl.allProducers.length;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: AppTheme.surfaceMuted,
      child: Row(
        children: <Widget>[
          Text(
            shown == total
                ? '$total ${total == 1 ? 'productor' : 'productores'}'
                : '$shown de $total productores',
            style: AppTheme.bodyStyle(fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Orden: ${ctrl.sort.label}${ctrl.sort.usesDeliveries ? ' · ${ctrl.period.label}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          if (ctrl.isLoadingDeliveries) ...<Widget>[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            const SizedBox(width: 6),
            Text(
              'Calculando litros…',
              style: AppTheme.bodyStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ] else if (ctrl.deliveriesFromCache)
            Tooltip(
              message:
                  'Sin conexión: los litros se calcularon con las entregas guardadas en este equipo.',
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 14,
                    color: AppTheme.warningText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Datos locales',
                    style: AppTheme.bodyStyle(
                      fontSize: 12,
                      color: AppTheme.warningText,
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
