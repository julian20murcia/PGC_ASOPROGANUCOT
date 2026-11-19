import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/report_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/report_export_service.dart';
import '../../core/services/report_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';

/// Módulo administrativo de Reportes Individuales por Ganadero, Exportación PDF/CSV
/// y consulta en solo lectura de la bitácora de auditoría (`RF-17`, `RF-18`, `RNF-07`).
class ReportsModuleView extends StatefulWidget {
  const ReportsModuleView({super.key});

  @override
  State<ReportsModuleView> createState() => _ReportsModuleViewState();
}

class _ReportsModuleViewState extends State<ReportsModuleView> {
  final TextEditingController _auditSearchCtrl = TextEditingController();
  int _tabIndex = 0; // 0: Producción, 1: Liquidaciones, 2: Auditoría

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReportController>().loadAll();
    });
  }

  @override
  void dispose() {
    _auditSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange(ReportController ctrl) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
    );
    if (picked == null || !mounted) return;
    ctrl.setCustomPeriod(picked.start, picked.end);
  }

  String? _selectedProducerLabel(ReportController ctrl) {
    if (ctrl.selectedProducerId == null) return null;
    for (final ProducerModel p in ctrl.producers) {
      if (p.productorId == ctrl.selectedProducerId) {
        return '${p.codigoAsociado} - ${p.nombreCompleto}';
      }
    }
    return null;
  }

  Future<void> _exportPdf(ReportController ctrl) async {
    ctrl.setExporting(true);
    try {
      await ReportExportService.printOrPreviewConsolidatedPdf(
        period: ctrl.selectedPeriod,
        summaries: ctrl.producerSummaries,
        settlements: ctrl.filteredSettlements,
        activePricePerLiter: ctrl.effectivePricePerLiter,
        producerFilterLabel: _selectedProducerLabel(ctrl),
      );
    } catch (_) {
      if (mounted) {
        _showToast(
          'No se pudo abrir la vista previa PDF en este equipo.',
          isError: true,
        );
      }
    } finally {
      if (mounted) ctrl.setExporting(false);
    }
  }

  Future<void> _exportCsv(
    ReportController ctrl, {
    required String kind, // 'produccion' | 'entregas' | 'liquidaciones'
  }) async {
    ctrl.setExporting(true);
    try {
      final period = ctrl.selectedPeriod;
      late final String csvContent;
      late final String fileName;
      if (kind == 'entregas') {
        csvContent = ReportExportService.buildReceptionsCsv(
          ctrl.filteredReceptions,
        );
        fileName = 'Entregas_${period.startDate}_${period.endDate}.csv';
      } else if (kind == 'liquidaciones') {
        csvContent = ReportExportService.buildSettlementsCsv(
          ctrl.filteredSettlements,
        );
        fileName = 'Liquidaciones_${period.startDate}_${period.endDate}.csv';
      } else {
        csvContent = ReportExportService.buildProducerSummaryCsv(
          ctrl.producerSummaries,
        );
        fileName =
            'Produccion_Productores_${period.startDate}_${period.endDate}.csv';
      }

      final String savedPath = await ReportExportService.saveCsvToDocuments(
        fileName: fileName,
        csvContent: csvContent,
      );
      if (!mounted) return;
      _showToast('Archivo CSV guardado en: $savedPath');
    } catch (_) {
      if (mounted) {
        _showToast('No fue posible exportar el archivo CSV.', isError: true);
      }
    } finally {
      if (mounted) ctrl.setExporting(false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.inkBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReportController ctrl = context.watch<ReportController>();
    final bool isNarrow = MediaQuery.of(context).size.width < 940;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 24,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(ctrl, isNarrow),
            const SizedBox(height: 16),
            _buildTabSelector(isNarrow),
            const SizedBox(height: 16),
            if (ctrl.isLoading &&
                ctrl.producers.isEmpty &&
                ctrl.producerSummaries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: DairyLoader(
                    size: DairyLoaderSize.lg,
                    label: 'Consolidando reportes y auditoría…',
                  ),
                ),
              )
            else if (_tabIndex == 0)
              _buildProductionTab(ctrl, isNarrow)
            else if (_tabIndex == 1)
              _buildSettlementsTab(ctrl, isNarrow)
            else
              _buildAuditTab(ctrl, isNarrow),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ReportController ctrl, bool isNarrow) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Reportes y Auditoría',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
        const SizedBox(height: 4),
        const Text(
          'Estadísticas por ganadero, consolidados quincenales exportables en PDF/CSV y bitácora de control.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: ctrl.isLoading ? null : ctrl.loadAll,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Actualizar'),
        ),
        PrimaryActionButton(
          label: 'Exportar PDF',
          icon: Icons.picture_as_pdf_outlined,
          isLoading: ctrl.isExporting,
          fullWidth: false,
          onPressed: () => _exportPdf(ctrl),
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[titleBlock, const SizedBox(height: 12), actions],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }

  Widget _buildTabSelector(bool isNarrow) {
    const List<({IconData icon, String label})> tabs =
        <({IconData icon, String label})>[
          (icon: Icons.agriculture_outlined, label: 'Producción por ganadero'),
          (
            icon: Icons.receipt_long_outlined,
            label: 'Consolidado de liquidaciones',
          ),
          (icon: Icons.shield_outlined, label: 'Bitácora de auditoría'),
        ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < tabs.length; i++)
              _ReportTab(
                icon: tabs[i].icon,
                label: tabs[i].label,
                selected: _tabIndex == i,
                onTap: () => setState(() => _tabIndex = i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel(ReportController ctrl, bool isNarrow) {
    final Widget producerDropdown = AppSelect<String?>(
      value: ctrl.selectedProducerId,
      labelText: 'Filtrar por ganadero (reporte individual)',
      prefixIcon: Icons.person_search_outlined,
      searchable: true,
      searchHint: 'Buscar por nombre, código o cédula…',
      menuMaxHeight: 360,
      options: <AppSelectOption<String?>>[
        const AppSelectOption<String?>(
          value: null,
          label: 'Todos los productores (consolidado)',
          icon: Icons.groups_2_outlined,
        ),
        ...ctrl.producers.map(
          (ProducerModel p) => AppSelectOption<String?>(
            value: p.productorId,
            label: '${p.codigoAsociado} · ${p.nombreCompleto}',
            description: 'C.C. ${p.cedula}',
          ),
        ),
      ],
      onChanged: ctrl.setSelectedProducer,
    );

    final bool custom = ctrl.rangeType == ReportRangeType.custom;
    final Widget periodChips = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        AppSegmentedControl<ReportRangeType>(
          height: 38,
          selected: ctrl.rangeType,
          onChanged: ctrl.setRangeType,
          segments: const <AppSegment<ReportRangeType>>[
            AppSegment<ReportRangeType>(
              value: ReportRangeType.daily,
              label: 'Diario (hoy)',
              icon: Icons.today_rounded,
            ),
            AppSegment<ReportRangeType>(
              value: ReportRangeType.quincenal,
              label: 'Quincenal',
            ),
            AppSegment<ReportRangeType>(
              value: ReportRangeType.monthly,
              label: 'Mensual',
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => _pickCustomRange(ctrl),
          style: custom
              ? OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.inkBlack,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.inkBlack),
                )
              : null,
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: Text(
            custom ? ctrl.selectedPeriod.label : 'Rango personalizado',
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A0C3B24),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isNarrow) ...<Widget>[
            periodChips,
            const SizedBox(height: 12),
            producerDropdown,
          ] else
            Row(
              children: <Widget>[
                Expanded(flex: 3, child: periodChips),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: producerDropdown),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(
                Icons.event_note_outlined,
                size: 15,
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Período activo: '),
                      TextSpan(
                        text: ctrl.selectedPeriod.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text:
                            '  ·  ${AppFormatters.formatIsoDate(ctrl.selectedPeriod.startDate)} → ${AppFormatters.formatIsoDate(ctrl.selectedPeriod.endDate)}',
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductionTab(ReportController ctrl, bool isNarrow) {
    final List<ProducerProductionSummary> summaries = ctrl.producerSummaries;
    final List<MilkReceptionModel> detailReceptions = ctrl.filteredReceptions;

    final List<Widget> kpis = <Widget>[
      AppMetricTile(
        title: 'Total litros del rango',
        value: AppFormatters.formatLiters(ctrl.totalRangeLiters),
        subtitle: '${ctrl.totalRangeDeliveries} entrega(s) válidas',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppMetricTile(
        title: 'Promedio diario',
        value: AppFormatters.formatLiters(ctrl.averageDailyPerProducer),
        subtitle: 'Media por productor y día entregado',
        icon: Icons.analytics_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppMetricTile(
        title: 'Productores incluidos',
        value: '${summaries.length}',
        subtitle: ctrl.selectedProducerId == null
            ? 'Padrón con entregas en el período'
            : 'Filtro individual activo',
        icon: Icons.people_outline,
        accentColor: AppTheme.warmGold,
      ),
      AppMetricTile(
        title: 'Valor total liquidado / est.',
        value: AppFormatters.formatCurrency(ctrl.totalRangeValue),
        subtitle: ctrl.effectivePricePerLiter > 0
            ? 'Tarifa base ${AppFormatters.formatCurrency(ctrl.effectivePricePerLiter)}/L'
            : 'Según comprobantes cerrados',
        icon: Icons.payments_outlined,
        accentColor: AppTheme.indigoAccent,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildFilterPanel(ctrl, isNarrow),
        const SizedBox(height: 14),
        if (isNarrow)
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: kpis[0]),
                  const SizedBox(width: 10),
                  Expanded(child: kpis[1]),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(child: kpis[2]),
                  const SizedBox(width: 10),
                  Expanded(child: kpis[3]),
                ],
              ),
            ],
          )
        else
          Row(
            children: <Widget>[
              for (int i = 0; i < kpis.length; i++) ...<Widget>[
                Expanded(child: kpis[i]),
                if (i < kpis.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        const SizedBox(height: 14),
        _ExportBar(
          title: 'Producción por productor',
          count: summaries.length,
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: ctrl.isExporting
                  ? null
                  : () => _exportCsv(ctrl, kind: 'produccion'),
              icon: const Icon(Icons.table_view_outlined, size: 17),
              label: const Text('Exportar CSV Producción'),
            ),
            OutlinedButton.icon(
              onPressed: ctrl.isExporting
                  ? null
                  : () => _exportCsv(ctrl, kind: 'entregas'),
              icon: const Icon(Icons.download_outlined, size: 17),
              label: const Text('Exportar CSV Entregas'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          _emptyBox(
            'No hay entregas registradas en ${ctrl.selectedPeriod.label} para el filtro actual.',
          )
        else
          CleanDataTable(
            columns: const <CleanTableColumn>[
              CleanTableColumn(label: 'Productor'),
              CleanTableColumn(label: 'Vereda'),
              CleanTableColumn(label: 'Entregas', numeric: true),
              CleanTableColumn(label: 'Mañana', numeric: true),
              CleanTableColumn(label: 'Tarde', numeric: true),
              CleanTableColumn(label: 'Total litros', numeric: true),
              CleanTableColumn(label: 'Prom. diario', numeric: true),
              CleanTableColumn(label: 'Valor total', numeric: true),
            ],
            rows: summaries.map((ProducerProductionSummary s) {
              return <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _InitialsAvatar(name: s.nombreProductor),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          s.nombreProductor,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${s.codigoAsociado} · C.C. ${s.cedula}',
                          style: AppTheme.monoStyle(
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.place_outlined,
                      size: 13,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.vereda,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: '${s.activeDaysCount} día(s) con entrega',
                  child: AppCountPill(
                    text: '${s.deliveryCount} · ${s.activeDaysCount}d',
                  ),
                ),
                _ShiftLiters(
                  liters: s.morningLiters,
                  icon: Icons.wb_sunny_outlined,
                  color: AppTheme.warningText,
                ),
                _ShiftLiters(
                  liters: s.afternoonLiters,
                  icon: Icons.wb_twilight_rounded,
                  color: AppTheme.indigoAccent,
                ),
                Text(
                  AppFormatters.formatLiters(s.totalLiters),
                  style: AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  AppFormatters.formatLiters(s.dailyAverageLiters),
                  style: AppTheme.monoStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  AppFormatters.formatCurrency(s.totalEconomicValue),
                  style: AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ];
            }).toList(),
          ),
        if (ctrl.selectedProducerId != null &&
            detailReceptions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              const Icon(
                Icons.calendar_view_day_outlined,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Detalle diario del ganadero seleccionado',
                  style: AppTheme.subtitleStyle(),
                ),
              ),
              const SizedBox(width: 10),
              AppCountPill(text: '${detailReceptions.length}'),
            ],
          ),
          const SizedBox(height: 10),
          CleanDataTable(
            columns: const <CleanTableColumn>[
              CleanTableColumn(label: 'Fecha'),
              CleanTableColumn(label: 'Hora'),
              CleanTableColumn(label: 'Jornada'),
              CleanTableColumn(label: 'Litros', numeric: true),
              CleanTableColumn(label: 'Estado'),
            ],
            rows: detailReceptions.map((MilkReceptionModel r) {
              final bool isMorning = r.jornada == AppConstants.shiftMorning;
              return <Widget>[
                Text(
                  AppFormatters.formatIsoDate(r.fechaEntrega),
                  style: AppTheme.monoStyle(fontSize: 12.5),
                ),
                Text(r.horaEntrega, style: AppTheme.monoStyle(fontSize: 12.5)),
                _ShiftBadge(isMorning: isMorning),
                Text(
                  AppFormatters.formatLiters(r.litros),
                  style: AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
                _StateBadge(
                  ok: r.isLiquidada,
                  okLabel: 'Liquidada',
                  pendingLabel: 'Por liquidar',
                ),
              ];
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSettlementsTab(ReportController ctrl, bool isNarrow) {
    final List<SettlementModel> items = ctrl.filteredSettlements;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildFilterPanel(ctrl, isNarrow),
        const SizedBox(height: 12),
        _ExportBar(
          title: 'Comprobantes del período',
          count: items.length,
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: ctrl.isExporting
                  ? null
                  : () => _exportCsv(ctrl, kind: 'liquidaciones'),
              icon: const Icon(Icons.table_view_outlined, size: 17),
              label: const Text('Exportar CSV Liquidaciones'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _emptyBox(
            'No hay liquidaciones cerradas que coincidan con el período seleccionado.',
          )
        else
          CleanDataTable(
            columns: const <CleanTableColumn>[
              CleanTableColumn(label: 'Comprobante'),
              CleanTableColumn(label: 'Productor'),
              CleanTableColumn(label: 'Quincena'),
              CleanTableColumn(label: 'Litros', numeric: true),
              CleanTableColumn(label: 'Tarifa / L', numeric: true),
              CleanTableColumn(label: 'Valor neto', numeric: true),
              CleanTableColumn(label: 'Estado'),
            ],
            rows: items.map((SettlementModel s) {
              return <Widget>[
                Text(
                  s.numeroComprobante,
                  style: AppTheme.monoStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  s.nombreProductorSnap,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  s.quincenaLabel,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  AppFormatters.formatLiters(s.totalLitros),
                  style: AppTheme.monoStyle(fontSize: 12.5),
                ),
                Text(
                  AppFormatters.formatCurrency(s.precioLitroAplicado),
                  style: AppTheme.monoStyle(fontSize: 12.5),
                ),
                Text(
                  AppFormatters.formatCurrency(
                    s.valorTotalPagar,
                    alwaysShowDecimals: true,
                  ),
                  style: AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
                _StateBadge(
                  ok: s.isPagada,
                  okLabel: 'Pagada',
                  pendingLabel: 'Pendiente',
                ),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildAuditTab(ReportController ctrl, bool isNarrow) {
    final List<AuditLogModel> logs = ctrl.filteredAuditLogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppInlineNotice(
          icon: Icons.verified_user_outlined,
          background: AppTheme.primaryGreenLight,
          foreground: AppTheme.successText,
          message:
              'Bitácora inmutable de solo lectura: conserva el historial completo de altas, correcciones, cierres quincenales y pagos.',
        ),
        const SizedBox(height: 14),
        if (isNarrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildAuditSearchField(ctrl),
              const SizedBox(height: 10),
              _buildAuditEntityChips(ctrl),
            ],
          )
        else
          Row(
            children: <Widget>[
              Expanded(child: _buildAuditSearchField(ctrl)),
              const SizedBox(width: 12),
              Flexible(child: _buildAuditEntityChips(ctrl)),
            ],
          ),
        const SizedBox(height: 14),
        if (logs.isEmpty)
          _emptyBox('No hay eventos registrados con los filtros actuales.')
        else
          CleanDataTable(
            columns: const <CleanTableColumn>[
              CleanTableColumn(label: 'Fecha y hora'),
              CleanTableColumn(label: 'Módulo'),
              CleanTableColumn(label: 'Acción'),
              CleanTableColumn(label: 'Referencia'),
              CleanTableColumn(label: 'Motivo / Detalle'),
            ],
            rows: logs.map((AuditLogModel log) {
              return <Widget>[
                Text(
                  AppFormatters.formatDateTime(log.timestamp),
                  style: AppTheme.monoStyle(fontSize: 12),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _entityIcon(log.entidadAfectada),
                      size: 15,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _friendlyEntityName(log.entidadAfectada),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                _AuditActionBadge(action: log.accion),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Tooltip(
                    message: 'Ver historial del registro',
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.skyBlue,
                      ),
                      onPressed: () => _showRecordHistory(ctrl, log.registroId),
                      icon: const Icon(Icons.history_rounded, size: 14),
                      label: Text(
                        log.registroId,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.monoStyle(
                          fontSize: 11.5,
                          color: AppTheme.skyBlue,
                        ),
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    log.motivo ?? _summarizeChanges(log),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ];
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildAuditSearchField(ReportController ctrl) {
    return TextField(
      controller: _auditSearchCtrl,
      onChanged: ctrl.setAuditSearchQuery,
      decoration: InputDecoration(
        hintText: 'Buscar por acción, referencia o motivo…',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: IconButton(
          tooltip: 'Consultar historial por ID exacto',
          onPressed: _auditSearchCtrl.text.trim().isEmpty
              ? null
              : () {
                  _showRecordHistory(ctrl, _auditSearchCtrl.text.trim());
                },
          icon: const Icon(Icons.history_rounded, size: 19),
        ),
      ),
    );
  }

  Future<void> _showRecordHistory(ReportController ctrl, String id) {
    final history = ctrl.loadRecordHistory(id);
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 660,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppDialogHeader(
                  icon: Icons.manage_history_rounded,
                  color: AppTheme.skyBlue,
                  title: 'Historial del registro',
                  subtitle: 'Eventos de auditoría asociados al identificador.',
                  onClose: () => Navigator.pop(context),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.canvasAlt,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.fingerprint_rounded,
                        size: 16,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          id,
                          style: AppTheme.monoStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: FutureBuilder<List<AuditLogModel>>(
                    future: history,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const AppInlineNotice.danger(
                          message: 'No se pudo consultar la bitácora.',
                        );
                      }
                      final logs = snapshot.data;
                      if (logs == null) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                            child: LinearProgressIndicator(minHeight: 4),
                          ),
                        );
                      }
                      if (logs.isEmpty) {
                        return const AppInlineNotice(
                          icon: Icons.search_off_rounded,
                          message:
                              'El ID indicado no tiene eventos registrados.',
                        );
                      }
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final log in logs)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusCard,
                                  ),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ExpansionTile(
                                    shape: const Border(),
                                    collapsedShape: const Border(),
                                    leading: _AuditActionBadge(
                                      action: log.accion,
                                    ),
                                    title: Text(
                                      AppFormatters.formatDateTime(
                                        log.timestamp,
                                      ),
                                      style: AppTheme.monoStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: SelectableText(
                                      'Usuario ${log.usuarioUid}${log.motivo == null ? '' : '\n${log.motivo}'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    expandedCrossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      14,
                                      12,
                                    ),
                                    children: <Widget>[
                                      if (log.valorAnterior != null)
                                        _VersionBox(
                                          title: 'Versión anterior',
                                          color: AppTheme.danger,
                                          body: _formatAuditVersion(
                                            log.valorAnterior!,
                                          ),
                                        ),
                                      if (log.valorNuevo != null)
                                        _VersionBox(
                                          title: 'Versión registrada',
                                          color: AppTheme.primaryGreen,
                                          body: _formatAuditVersion(
                                            log.valorNuevo!,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatAuditVersion(Map<String, dynamic> version) => version.entries
      .map((entry) => '${entry.key} · ${entry.value}')
      .join('\n');

  Widget _buildAuditEntityChips(ReportController ctrl) {
    final List<({String value, String label})> filters =
        <({String value, String label})>[
          (value: 'TODOS', label: 'Todos'),
          (value: AppConstants.receptionsCollection, label: 'Recepciones'),
          (value: AppConstants.settlementsCollection, label: 'Liquidaciones'),
          (value: AppConstants.ratesCollection, label: 'Tarifas'),
          (value: AppConstants.producersCollection, label: 'Productores'),
          (value: AppConstants.usersCollection, label: 'Usuarios'),
        ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AppSegmentedControl<String>(
        height: 40,
        selected: ctrl.auditEntityFilter,
        onChanged: ctrl.setAuditEntityFilter,
        segments: filters
            .map((f) => AppSegment<String>(value: f.value, label: f.label))
            .toList(),
      ),
    );
  }

  IconData _entityIcon(String raw) {
    switch (raw) {
      case AppConstants.receptionsCollection:
        return Icons.water_drop_outlined;
      case AppConstants.settlementsCollection:
        return Icons.receipt_long_outlined;
      case AppConstants.ratesCollection:
        return Icons.payments_outlined;
      case AppConstants.producersCollection:
        return Icons.agriculture_outlined;
      case AppConstants.usersCollection:
        return Icons.people_outline_rounded;
      default:
        return Icons.description_outlined;
    }
  }

  String _friendlyEntityName(String raw) {
    switch (raw) {
      case AppConstants.receptionsCollection:
        return 'Recepciones';
      case AppConstants.settlementsCollection:
        return 'Liquidaciones';
      case AppConstants.ratesCollection:
        return 'Tarifas';
      case AppConstants.producersCollection:
        return 'Productores';
      case AppConstants.usersCollection:
        return 'Usuarios';
      default:
        return raw;
    }
  }

  String _summarizeChanges(AuditLogModel log) {
    if (log.valorNuevo != null && log.valorNuevo!.isNotEmpty) {
      return log.valorNuevo!.entries
          .take(3)
          .map((e) => '${e.key}: ${e.value}')
          .join(' · ');
    }
    return 'Evento administrativo registrado';
  }

  Widget _emptyBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: <Widget>[
          const AppIconBadge(
            icon: Icons.insert_chart_outlined_rounded,
            color: AppTheme.skyBlue,
            size: 48,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ReportTab extends StatefulWidget {
  const _ReportTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool sel = widget.selected;
    final Color fg = sel
        ? AppTheme.inkBlack
        : (_hover ? AppTheme.textPrimary : AppTheme.textSecondary);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: _hover && !sel ? AppTheme.surfaceMuted : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: sel ? AppTheme.primaryGreen : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.icon,
                size: 17,
                color: sel ? AppTheme.primaryGreen : fg,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera de sección con contador y acciones de exportación.
class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.title,
    required this.count,
    required this.actions,
  });

  final String title;
  final int count;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.table_chart_outlined,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(title, style: AppTheme.subtitleStyle()),
            const SizedBox(width: 10),
            AppCountPill(text: '$count'),
          ],
        ),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    final String initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first[0].toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenLight,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryGreen,
        ),
      ),
    );
  }
}

class _ShiftLiters extends StatelessWidget {
  const _ShiftLiters({
    required this.liters,
    required this.icon,
    required this.color,
  });

  final double liters;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: liters > 0 ? color : AppTheme.textMuted),
        const SizedBox(width: 5),
        Text(
          AppFormatters.formatLiters(liters),
          style: AppTheme.monoStyle(
            fontSize: 12.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ShiftBadge extends StatelessWidget {
  const _ShiftBadge({required this.isMorning});

  final bool isMorning;

  @override
  Widget build(BuildContext context) {
    final Color fg = isMorning ? AppTheme.warningText : AppTheme.indigoAccent;
    final Color bg = isMorning ? AppTheme.warningBg : AppTheme.indigoLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isMorning ? Icons.wb_sunny_outlined : Icons.wb_twilight_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            isMorning ? 'Mañana' : 'Tarde',
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

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.ok,
    required this.okLabel,
    required this.pendingLabel,
  });

  final bool ok;
  final String okLabel;
  final String pendingLabel;

  @override
  Widget build(BuildContext context) {
    final Color fg = ok ? AppTheme.successText : AppTheme.warningText;
    final Color bg = ok ? AppTheme.successBg : AppTheme.warningBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ok ? Icons.task_alt_rounded : Icons.schedule_rounded,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            ok ? okLabel : pendingLabel,
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

/// Etiqueta de acción de auditoría con color e ícono por tipo de evento.
class _AuditActionBadge extends StatelessWidget {
  const _AuditActionBadge({required this.action});

  final String action;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final Color color;
    switch (action) {
      case 'CREAR':
        icon = Icons.add_circle_outline_rounded;
        color = AppTheme.primaryGreen;
      case 'EDITAR':
        icon = Icons.edit_outlined;
        color = AppTheme.skyBlue;
      case 'ANULAR':
        icon = Icons.block_rounded;
        color = AppTheme.danger;
      case 'LIQUIDAR':
        icon = Icons.lock_clock_outlined;
        color = AppTheme.warmGold;
      case 'SOLICITAR_RECTIFICACION':
        icon = Icons.rate_review_outlined;
        color = AppTheme.indigoAccent;
      default:
        icon = Icons.bolt_rounded;
        color = AppTheme.tealAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            action.replaceAll('_', ' '),
            style: AppTheme.monoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionBox extends StatelessWidget {
  const _VersionBox({
    required this.title,
    required this.color,
    required this.body,
  });

  final String title;
  final Color color;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            body,
            style: AppTheme.monoStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
