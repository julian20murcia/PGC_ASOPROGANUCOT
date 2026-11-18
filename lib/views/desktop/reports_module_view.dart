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
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';

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
        csvContent =
            ReportExportService.buildReceptionsCsv(ctrl.filteredReceptions);
        fileName = 'Entregas_${period.startDate}_${period.endDate}.csv';
      } else if (kind == 'liquidaciones') {
        csvContent =
            ReportExportService.buildSettlementsCsv(ctrl.filteredSettlements);
        fileName = 'Liquidaciones_${period.startDate}_${period.endDate}.csv';
      } else {
        csvContent =
            ReportExportService.buildProducerSummaryCsv(ctrl.producerSummaries);
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
        children: <Widget>[
          titleBlock,
          const SizedBox(height: 12),
          actions,
        ],
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _TabChip(
          label: 'Producción por ganadero',
          icon: Icons.agriculture_outlined,
          selected: _tabIndex == 0,
          onTap: () => setState(() => _tabIndex = 0),
        ),
        _TabChip(
          label: 'Consolidado de liquidaciones',
          icon: Icons.receipt_long_outlined,
          selected: _tabIndex == 1,
          onTap: () => setState(() => _tabIndex = 1),
        ),
        _TabChip(
          label: 'Bitácora de auditoría',
          icon: Icons.shield_outlined,
          selected: _tabIndex == 2,
          onTap: () => setState(() => _tabIndex = 2),
        ),
      ],
    );
  }

  Widget _buildFilterPanel(ReportController ctrl, bool isNarrow) {
    final Widget producerDropdown = DropdownButtonFormField<String?>(
      initialValue: ctrl.selectedProducerId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Filtrar por ganadero (reporte individual)',
        prefixIcon: Icon(Icons.person_search_outlined, size: 18),
      ),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos los productores (consolidado)'),
        ),
        ...ctrl.producers.map(
          (ProducerModel p) => DropdownMenuItem<String?>(
            value: p.productorId,
            child: Text(
              '${p.codigoAsociado} · ${p.nombreCompleto} (C.C. ${p.cedula})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: ctrl.setSelectedProducer,
    );

    final Widget periodChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _FilterChip(
          label: 'Diario (hoy)',
          selected: ctrl.rangeType == ReportRangeType.daily,
          onTap: () => ctrl.setRangeType(ReportRangeType.daily),
        ),
        _FilterChip(
          label: 'Quincenal',
          selected: ctrl.rangeType == ReportRangeType.quincenal,
          onTap: () => ctrl.setRangeType(ReportRangeType.quincenal),
        ),
        _FilterChip(
          label: 'Mensual',
          selected: ctrl.rangeType == ReportRangeType.monthly,
          onTap: () => ctrl.setRangeType(ReportRangeType.monthly),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickCustomRange(ctrl),
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: Text(
            ctrl.rangeType == ReportRangeType.custom
                ? ctrl.selectedPeriod.label
                : 'Rango personalizado',
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
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
          const SizedBox(height: 10),
          Text(
            'Período activo: ${ctrl.selectedPeriod.label} (${AppFormatters.formatIsoDate(ctrl.selectedPeriod.startDate)} al ${AppFormatters.formatIsoDate(ctrl.selectedPeriod.endDate)})',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductionTab(ReportController ctrl, bool isNarrow) {
    final List<ProducerProductionSummary> summaries = ctrl.producerSummaries;
    final List<MilkReceptionModel> detailReceptions = ctrl.filteredReceptions;

    final List<Widget> kpis = <Widget>[
      AppKpiCard(
        title: 'Total litros del rango',
        value: AppFormatters.formatLiters(ctrl.totalRangeLiters),
        subtitle: '${ctrl.totalRangeDeliveries} entrega(s) válidas',
        icon: Icons.water_drop_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppKpiCard(
        title: 'Promedio diario',
        value: AppFormatters.formatLiters(ctrl.averageDailyPerProducer),
        subtitle: 'Media por productor y día entregado',
        icon: Icons.analytics_outlined,
        accentColor: AppTheme.skyBlue,
      ),
      AppKpiCard(
        title: 'Productores incluidos',
        value: '${summaries.length}',
        subtitle: ctrl.selectedProducerId == null
            ? 'Padrón con entregas en el período'
            : 'Filtro individual activo',
        icon: Icons.people_outline,
        accentColor: AppTheme.warmGold,
      ),
      AppKpiCard(
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
            children: kpis
                .map(
                  (Widget c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: c,
                  ),
                )
                .toList(),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: <Widget>[
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                Text(
                  s.vereda,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  '${s.deliveryCount} (${s.activeDaysCount}d)',
                  style: AppTheme.monoStyle(fontSize: 12.5),
                ),
                Text(
                  AppFormatters.formatLiters(s.morningLiters),
                  style: AppTheme.monoStyle(fontSize: 12.5),
                ),
                Text(
                  AppFormatters.formatLiters(s.afternoonLiters),
                  style: AppTheme.monoStyle(fontSize: 12.5),
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
          Text(
            'Detalle diario del ganadero seleccionado (${detailReceptions.length} entrega(s))',
            style: AppTheme.serifStyle(fontSize: 17),
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
                Text(
                  isMorning ? 'Mañana' : 'Tarde',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppFormatters.formatLiters(r.litros),
                  style: AppTheme.monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
                SyncStatusBadge(
                  isSynced: r.isLiquidada,
                  syncedLabel: 'Liquidada',
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
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: ctrl.isExporting
                ? null
                : () => _exportCsv(ctrl, kind: 'liquidaciones'),
            icon: const Icon(Icons.table_view_outlined, size: 17),
            label: const Text('Exportar CSV Liquidaciones'),
          ),
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
                SyncStatusBadge(
                  isSynced: s.isPagada,
                  syncedLabel: 'Pagada',
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Row(
            children: <Widget>[
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: AppTheme.primaryGreen,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bitácora inmutable de solo lectura: conserva el historial completo de altas, correcciones, cierres quincenales y pagos.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
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
              _buildAuditEntityChips(ctrl),
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
                Text(
                  _friendlyEntityName(log.entidadAfectada),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                HeaderPropertyChip(
                  label: log.accion,
                  value: '',
                  dotColor: log.accion == 'ANULAR'
                      ? AppTheme.danger
                      : AppTheme.primaryGreen,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: TextButton(
                    onPressed: () => _showRecordHistory(ctrl, log.registroId),
                    child: Text(log.registroId, overflow: TextOverflow.ellipsis,
                        style: AppTheme.monoStyle(fontSize: 11.5)),
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
          onPressed: _auditSearchCtrl.text.trim().isEmpty ? null : () {
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
      builder: (context) => AlertDialog(
        title: const Text('Historial del registro'),
        content: SizedBox(
          width: 620,
          child: FutureBuilder<List<AuditLogModel>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('No se pudo consultar la bitácora.');
              final logs = snapshot.data;
              if (logs == null) return const LinearProgressIndicator();
              if (logs.isEmpty) return const Text('El ID indicado no tiene eventos registrados.');
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(id),
                    for (final log in logs)
                      ExpansionTile(
                        title: Text('${log.accion} · ${AppFormatters.formatDateTime(log.timestamp)}'),
                        subtitle: SelectableText('Usuario ${log.usuarioUid}${log.motivo == null ? '' : '\n${log.motivo}'}'),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (log.valorAnterior != null)
                            SelectableText('Versión anterior\n${_formatAuditVersion(log.valorAnterior!)}'),
                          if (log.valorNuevo != null)
                            SelectableText('Versión registrada\n${_formatAuditVersion(log.valorNuevo!)}'),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  String _formatAuditVersion(Map<String, dynamic> version) =>
      version.entries.map((entry) => '${entry.key} · ${entry.value}').join('\n');

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

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: filters
          .map(
            (f) => _FilterChip(
              label: f.label,
              selected: ctrl.auditEntityFilter == f.value,
              onTap: () => ctrl.setAuditEntityFilter(f.value),
            ),
          )
          .toList(),
    );
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
      child: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.inkBlack : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: selected ? AppTheme.inkBlack : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textSecondary,
        ),
      ),
      selected: selected,
      selectedColor: AppTheme.inkBlack,
      backgroundColor: AppTheme.surfaceMuted,
      side: BorderSide(
        color: selected ? AppTheme.inkBlack : AppTheme.border,
      ),
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}
