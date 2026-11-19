import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/report_controller.dart';
import '../../../controllers/user_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/security/permissions.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/report_export_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/producer_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/pro_ui.dart';
import '../../shared/widgets/ui_kit.dart';
import 'report_preview_table.dart';

IconData reportIcon(ReportKind k) => switch (k) {
      ReportKind.consolidated => Icons.water_drop_outlined,
      ReportKind.producerSummary => Icons.groups_outlined,
      ReportKind.settlements => Icons.receipt_long_outlined,
      ReportKind.shiftComparison => Icons.wb_twilight_rounded,
      ReportKind.inactiveProducers => Icons.person_off_outlined,
      ReportKind.corrections => Icons.edit_note_rounded,
    };

/// Pestaña "Reportes": catálogo + filtros + KPIs + vista previa + descarga.
class ReportCatalogTab extends StatelessWidget {
  const ReportCatalogTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ReportController ctrl = context.watch<ReportController>();
    final UserModel? me = context.watch<AuthController>().currentUser;
    final Map<String, String> names = context.watch<UserController>().userNamesByUid;
    final ReportDataset dataset = ctrl.buildDataset(userNames: names);
    final bool canExport = me?.can(Permissions.reportes, PermAction.exportar) ?? false;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool wide = c.maxWidth >= 1000;
        final Widget detail = _ReportDetail(ctrl: ctrl, dataset: dataset, canExport: canExport, me: me);
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CatalogChips(selected: ctrl.selectedReport, onSelect: ctrl.selectReport),
              const SizedBox(height: 12),
              detail,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 272,
              child: _CatalogList(selected: ctrl.selectedReport, onSelect: ctrl.selectReport),
            ),
            const SizedBox(width: 12),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.selected, required this.onSelect});
  final ReportKind selected;
  final ValueChanged<ReportKind> onSelect;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Catálogo de reportes',
      icon: Icons.library_books_outlined,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          for (final ReportKind k in ReportKind.values)
            _CatalogItem(kind: k, selected: k == selected, onTap: () => onSelect(k)),
        ],
      ),
    );
  }
}

class _CatalogItem extends StatelessWidget {
  const _CatalogItem({required this.kind, required this.selected, required this.onTap});
  final ReportKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected ? AppTheme.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          hoverColor: AppTheme.surfaceMuted,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(reportIcon(kind), size: 17, color: selected ? AppTheme.brand : AppTheme.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        kind.title,
                        style: AppTheme.bodyStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? AppTheme.brandDeep : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kind.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogChips extends StatelessWidget {
  const _CatalogChips({required this.selected, required this.onSelect});
  final ReportKind selected;
  final ValueChanged<ReportKind> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final ReportKind k in ReportKind.values)
          ChoiceChip(
            avatar: Icon(reportIcon(k), size: 15, color: k == selected ? AppTheme.brand : AppTheme.textMuted),
            label: Text(k.title),
            selected: k == selected,
            onSelected: (_) => onSelect(k),
          ),
      ],
    );
  }
}

class _ReportDetail extends StatelessWidget {
  const _ReportDetail({required this.ctrl, required this.dataset, required this.canExport, required this.me});

  final ReportController ctrl;
  final ReportDataset dataset;
  final bool canExport;
  final UserModel? me;

  DateRangeValue get _range {
    final DateTime? a = DateTime.tryParse(ctrl.selectedPeriod.startDate);
    final DateTime? b = DateTime.tryParse(ctrl.selectedPeriod.endDate);
    if (a == null || b == null) return DateRangePresets.quincenaOf(DateTime.now());
    return DateRangeValue(a, b);
  }

  String? get _filterLabel {
    final List<String> parts = <String>[];
    final String? pid = ctrl.selectedProducerId;
    if (pid != null && ctrl.selectedReport.usesProducerFilter) {
      final ProducerModel? p = ctrl.producers.where((ProducerModel x) => x.productorId == pid).firstOrNull;
      if (p != null) parts.add('Productor: ${p.nombreCompleto} (${p.codigoAsociado})');
    }
    if (ctrl.selectedReport.usesShiftFilter && ctrl.shiftFilter != null) {
      parts.add('Jornada: ${ctrl.shiftFilter == AppConstants.shiftMorning ? 'Mañana' : 'Tarde'}');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ReportKind kind = ctrl.selectedReport;
    final List<ProducerModel> producers = List<ProducerModel>.from(ctrl.producers)
      ..sort((ProducerModel a, ProducerModel b) => a.nombreCompleto.compareTo(b.nombreCompleto));

    final Widget filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppDateRangeField(
          value: _range,
          dense: true,
          lastDate: DateTime.now().add(const Duration(days: 1)),
          onChanged: (DateRangeValue v) => ctrl.setPeriodRange(v.start, v.end, label: v.label),
        ),
        if (kind.usesProducerFilter)
          SizedBox(
            width: 260,
            child: AppSelect<String?>(
              dense: true,
              value: ctrl.selectedProducerId,
              prefixIcon: Icons.person_outline_rounded,
              searchable: true,
              searchHint: 'Buscar productor…',
              options: <AppSelectOption<String?>>[
                const AppSelectOption<String?>(value: null, label: 'Todos los productores'),
                for (final ProducerModel p in producers)
                  AppSelectOption<String?>(
                    value: p.productorId,
                    label: p.nombreCompleto,
                    description: '${p.codigoAsociado} · ${p.cedula}',
                  ),
              ],
              onChanged: ctrl.setSelectedProducer,
            ),
          ),
        if (kind.usesShiftFilter)
          AppSegmentedControl<String?>(
            selected: ctrl.shiftFilter,
            onChanged: ctrl.setShiftFilter,
            segments: const <AppSegment<String?>>[
              AppSegment<String?>(value: null, label: 'Ambas jornadas'),
              AppSegment<String?>(value: AppConstants.shiftMorning, label: 'Mañana'),
              AppSegment<String?>(value: AppConstants.shiftAfternoon, label: 'Tarde'),
            ],
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Panel(
          title: kind.title,
          subtitle: kind.description,
          icon: reportIcon(kind),
          trailing: canExport
              ? ExportButton(
                  label: 'Descargar',
                  title: 'Descargar ${kind.title.toLowerCase()}',
                  subtitle: '${dataset.rows.length} filas · ${dataset.periodLabel}',
                  build: (ExportFormat f) async => (
                    bytes: await ReportExportService.exportDataset(
                      dataset,
                      f,
                      filterLabel: _filterLabel,
                      generatedBy: me?.nombreCompleto,
                    ),
                    baseName: ReportExportService.datasetFileName(dataset),
                  ),
                )
              : Tooltip(
                  message: 'Tu cuenta no tiene permiso para descargar reportes',
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text('Descargar'),
                  ),
                ),
          child: filters,
        ),
        const SizedBox(height: 12),
        if (dataset.kpis.isNotEmpty)
          StatStrip(
            minItemWidth: 180,
            items: <StatItem>[
              for (int i = 0; i < dataset.kpis.length; i++)
                StatItem(
                  label: dataset.kpis[i].label,
                  value: dataset.kpis[i].value,
                  hint: dataset.kpis[i].hint,
                  tone: const <Tone>[Tone.brand, Tone.info, Tone.accent, Tone.success][i % 4],
                ),
            ],
          ),
        const SizedBox(height: 12),
        Panel(
          title: 'Vista previa',
          subtitle: dataset.subtitle ??
              '${dataset.rows.length} ${dataset.rows.length == 1 ? 'fila' : 'filas'} · ${dataset.periodLabel}',
          icon: Icons.table_chart_outlined,
          padding: EdgeInsets.zero,
          trailing: ctrl.isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          child: ReportPreviewTable(dataset: dataset),
        ),
      ],
    );
  }
}
