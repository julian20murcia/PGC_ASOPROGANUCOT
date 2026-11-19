import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/milk_reception_model.dart';
import '../../models/settlement_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'file_export_service.dart';
import 'report_service.dart';
import 'settlement_calculator.dart';

/// Servicio de exportación consolidada de reportes en CSV y PDF (`RF-18`, `HU-09`).
class ReportExportService {
  ReportExportService._();

  static const CsvEncoder _excelCsvEncoder = CsvEncoder(addBom: true);

  // Paleta "Pradera".
  static const PdfColor _inkBlack = PdfColor.fromInt(0xFF0B3B37);
  static const PdfColor _emerald = PdfColor.fromInt(0xFF0F766E);
  static const PdfColor _mutedBg = PdfColor.fromInt(0xFFE7F5F2);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E7EA);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF4B5B61);
  static const PdfColor _textPrimary = PdfColor.fromInt(0xFF0F1B1E);
  static const PdfColor _zebra = PdfColor.fromInt(0xFFF7F9FA);

  /// Genera CSV UTF-8 con BOM para Excel con el resumen de producción por ganadero (`RF-17`, `RF-18`).
  static String buildProducerSummaryCsv(
    List<ProducerProductionSummary> summaries,
  ) {
    final List<List<dynamic>> rows = <List<dynamic>>[
      <String>[
        'Código Asociado',
        'Nombre Productor',
        'Cédula',
        'Vereda',
        'Entregas',
        'Días con Entrega',
        'Litros Mañana',
        'Litros Tarde',
        'Total Litros',
        'Promedio Diario (L)',
        'Valor Liquidado (COP)',
        'Estimado Pendiente (COP)',
        'Valor Total (COP)',
      ],
      ...summaries.map(
        (ProducerProductionSummary s) => <dynamic>[
          s.codigoAsociado,
          s.nombreProductor,
          s.cedula,
          s.vereda,
          s.deliveryCount,
          s.activeDaysCount,
          s.morningLiters.toStringAsFixed(2),
          s.afternoonLiters.toStringAsFixed(2),
          s.totalLiters.toStringAsFixed(2),
          s.dailyAverageLiters.toStringAsFixed(2),
          s.settledAmount.toStringAsFixed(2),
          s.pendingEstimateAmount.toStringAsFixed(2),
          s.totalEconomicValue.toStringAsFixed(2),
        ],
      ),
    ];
    return _excelCsvEncoder.convert(rows);
  }

  /// Genera CSV UTF-8 con el detalle de entregas de leche en el período.
  static String buildReceptionsCsv(List<MilkReceptionModel> receptions) {
    final List<List<dynamic>> rows = <List<dynamic>>[
      <String>[
        'Fecha Entrega',
        'Hora',
        'Código Asociado',
        'Productor',
        'Jornada',
        'Litros',
        'Estado Liquidación',
        'Respaldo',
      ],
      ...receptions.map(
        (MilkReceptionModel r) => <dynamic>[
          r.fechaEntrega,
          r.horaEntrega,
          r.codigoAsociadoSnap,
          r.nombreProductorSnap,
          r.jornada == AppConstants.shiftMorning ? 'Mañana' : 'Tarde',
          r.litros.toStringAsFixed(2),
          r.isLiquidada ? 'Liquidada' : 'Pendiente por liquidar',
          r.isSynced ? 'Sincronizado' : 'Pendiente local',
        ],
      ),
    ];
    return _excelCsvEncoder.convert(rows);
  }

  /// Genera CSV UTF-8 con el consolidado de liquidaciones quincenales (`RF-18`).
  static String buildSettlementsCsv(List<SettlementModel> settlements) {
    final List<List<dynamic>> rows = <List<dynamic>>[
      <String>[
        'N° Comprobante',
        'Período',
        'Fecha Inicio',
        'Fecha Fin',
        'Productor',
        'Cédula',
        'Entregas',
        'Total Litros',
        'Tarifa / Litro (COP)',
        'Valor Neto (COP)',
        'Estado Pago',
        'Fecha Pago',
        'Observación Pago',
      ],
      ...settlements.map(
        (SettlementModel s) => <dynamic>[
          s.numeroComprobante,
          s.quincenaLabel,
          s.periodoInicio,
          s.periodoFin,
          s.nombreProductorSnap,
          s.cedulaProductorSnap,
          s.cantidadEntregas,
          s.totalLitros.toStringAsFixed(2),
          s.precioLitroAplicado.toStringAsFixed(2),
          s.valorTotalPagar.toStringAsFixed(2),
          s.estadoPago,
          s.fechaPago != null ? AppFormatters.formatDateTime(s.fechaPago!) : '',
          s.observacionPago ?? '',
        ],
      ),
    ];
    return _excelCsvEncoder.convert(rows);
  }

  /// Guarda un archivo CSV localmente en la carpeta de documentos de ASOPROGANUCOTT.
  static Future<String> saveCsvToDocuments({
    required String fileName,
    required String csvContent,
  }) async {
    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = await getTemporaryDirectory();
    }
    final Directory exportDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}ASOPROGANUCOTT_Reportes',
    );
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final File outFile = File(
      '${exportDir.path}${Platform.pathSeparator}$fileName',
    );
    await outFile.writeAsBytes(utf8.encode(csvContent), flush: true);
    return outFile.path;
  }

  static Future<Uint8List?> _tryLoadLogoBytes() async {
    try {
      final ByteData data =
          await rootBundle.load(AppConstants.darkLogoAssetPath);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Genera los bytes PDF del reporte consolidado general o individual (`RF-18`, `HU-09`).
  static Future<Uint8List> buildConsolidatedReportPdfBytes({
    required QuincenaPeriod period,
    required List<ProducerProductionSummary> summaries,
    required List<SettlementModel> settlements,
    required double activePricePerLiter,
    String? producerFilterLabel,
    Uint8List? logoBytes,
  }) async {
    final pw.Document pdf = pw.Document(
      title: 'Reporte Consolidado ASOPROGANUCOTT - ${period.label}',
      author: AppConstants.appName,
    );

    final double totalLiters = summaries.fold<double>(
      0,
      (double sum, ProducerProductionSummary s) => sum + s.totalLiters,
    );
    final int totalDeliveries = summaries.fold<int>(
      0,
      (int sum, ProducerProductionSummary s) => sum + s.deliveryCount,
    );
    final double totalEconomic = summaries.fold<double>(
      0,
      (double sum, ProducerProductionSummary s) => sum + s.totalEconomicValue,
    );

    final pw.MemoryImage? logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 28),
        footer: (pw.Context ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'ASOPROGANUCOTT - Reporte Administrativo | ${period.label}',
                style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
              ),
            ],
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          _buildPdfHeader(
            period: period,
            producerFilterLabel: producerFilterLabel,
            logoImage: logoImage,
          ),
          pw.SizedBox(height: 14),
          _buildPdfKpiRow(
            totalLiters: SettlementCalculator.roundToThousandths(totalLiters),
            totalDeliveries: totalDeliveries,
            producersCount: summaries.length,
            totalEconomic: SettlementCalculator.roundToCents(totalEconomic),
            activePricePerLiter: activePricePerLiter,
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'PRODUCCIÓN CONSOLIDADA POR PRODUCTOR',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _inkBlack,
            ),
          ),
          pw.SizedBox(height: 6),
          _buildProducerSummaryTable(summaries),
          if (settlements.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 18),
            pw.Text(
              'LIQUIDACIONES EN EL PERÍODO',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: _inkBlack,
              ),
            ),
            pw.SizedBox(height: 6),
            _buildSettlementsTable(settlements),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// Abre diálogo nativo para imprimir o guardar PDF del reporte consolidado.
  static Future<void> printOrPreviewConsolidatedPdf({
    required QuincenaPeriod period,
    required List<ProducerProductionSummary> summaries,
    required List<SettlementModel> settlements,
    required double activePricePerLiter,
    String? producerFilterLabel,
  }) async {
    final Uint8List? logoBytes = await _tryLoadLogoBytes();
    final Uint8List bytes = await buildConsolidatedReportPdfBytes(
      period: period,
      summaries: summaries,
      settlements: settlements,
      activePricePerLiter: activePricePerLiter,
      producerFilterLabel: producerFilterLabel,
      logoBytes: logoBytes,
    );
    await Printing.layoutPdf(
      name: 'Reporte_ASOPROGANUCOTT_${period.startDate}_${period.endDate}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  static pw.Widget _buildPdfHeader({
    required QuincenaPeriod period,
    String? producerFilterLabel,
    pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _inkBlack,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          if (logoImage != null) ...<pw.Widget>[
            pw.SizedBox(
              width: 44,
              height: 44,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'ASOPROGANUCOTT - REPORTE CONSOLIDADO DE ACOPIO',
                  style: pw.TextStyle(
                    fontSize: 13.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Período: ${period.label} (${AppFormatters.formatIsoDate(period.startDate)} al ${AppFormatters.formatIsoDate(period.endDate)})',
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColor.fromInt(0xFFD1D5DB),
                  ),
                ),
                if (producerFilterLabel != null &&
                    producerFilterLabel.isNotEmpty)
                  pw.Text(
                    'Filtro de productor: $producerFilterLabel',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColor.fromInt(0xFFCDEAE4),
                    ),
                  ),
              ],
            ),
          ),
          pw.Text(
            'Generado:\n${AppFormatters.formatDateTime(DateTime.now())}',
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: PdfColor.fromInt(0xFFD1D5DB),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfKpiRow({
    required double totalLiters,
    required int totalDeliveries,
    required int producersCount,
    required double totalEconomic,
    required double activePricePerLiter,
  }) {
    pw.Widget tile(String title, String val) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: _mutedBg,
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                title,
                style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                val,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _inkBlack,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: <pw.Widget>[
        tile('Total Acopiado', AppFormatters.formatLiters(totalLiters)),
        pw.SizedBox(width: 8),
        tile('Productores / Entregas', '$producersCount / $totalDeliveries'),
        pw.SizedBox(width: 8),
        tile(
          'Tarifa Vigente',
          activePricePerLiter > 0
              ? AppFormatters.formatCurrency(activePricePerLiter)
              : 'N/A',
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: pw.BoxDecoration(
              color: _mutedBg,
              border: pw.Border.all(color: _emerald),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'Valor Total del Período',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _emerald,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  AppFormatters.formatCurrency(
                    totalEconomic,
                    alwaysShowDecimals: true,
                  ),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _inkBlack,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildProducerSummaryTable(
    List<ProducerProductionSummary> summaries,
  ) {
    if (summaries.isEmpty) {
      return pw.Text(
        'Sin entregas registradas en el período seleccionado.',
        style: const pw.TextStyle(fontSize: 9.5, color: _textSecondary),
      );
    }

    final List<List<String>> rows = summaries.map((ProducerProductionSummary s) {
      return <String>[
        s.codigoAsociado,
        s.nombreProductor,
        '${s.deliveryCount}',
        AppFormatters.formatLiters(s.morningLiters),
        AppFormatters.formatLiters(s.afternoonLiters),
        AppFormatters.formatLiters(s.totalLiters),
        AppFormatters.formatLiters(s.dailyAverageLiters),
        AppFormatters.formatCurrency(s.totalEconomicValue),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: const <String>[
        'Código',
        'Productor',
        'Ent.',
        'Mañana',
        'Tarde',
        'Total',
        'Prom/Día',
        'Valor Total',
      ],
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _inkBlack),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _inkBlack),
      oddRowDecoration: const pw.BoxDecoration(color: _mutedBg),
      border: pw.TableBorder.all(color: _border, width: 0.6),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      cellAlignments: const <int, pw.Alignment>{
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _buildSettlementsTable(List<SettlementModel> settlements) {
    final List<List<String>> rows = settlements.map((SettlementModel s) {
      return <String>[
        s.numeroComprobante,
        s.nombreProductorSnap,
        s.quincenaLabel,
        AppFormatters.formatLiters(s.totalLitros),
        AppFormatters.formatCurrency(s.valorTotalPagar),
        s.estadoPago,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: const <String>[
        'Comprobante',
        'Productor',
        'Quincena',
        'Litros',
        'Valor',
        'Estado',
      ],
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _inkBlack),
      cellStyle: const pw.TextStyle(fontSize: 8, color: _inkBlack),
      oddRowDecoration: const pw.BoxDecoration(color: _mutedBg),
      border: pw.TableBorder.all(color: _border, width: 0.6),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }
  // ════════════════════════════════════════════════════════════════════
  // Exportación genérica de un [ReportDataset] (PDF, Excel y CSV).
  // ════════════════════════════════════════════════════════════════════

  static pw.ThemeData? _cachedTheme;

  /// Tipografía Inter (incluye tildes, ñ, flechas y signos). Si no se puede
  /// cargar (p. ej. en pruebas sin assets) se usa la fuente estándar.
  static Future<pw.ThemeData?> _pdfTheme() async {
    if (_cachedTheme != null) return _cachedTheme;
    try {
      final ByteData regular = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final ByteData bold = await rootBundle.load('assets/fonts/Inter-SemiBold.ttf');
      _cachedTheme = pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
    } catch (_) {
      _cachedTheme = null;
    }
    return _cachedTheme;
  }

  static XlsxCellType _xlsxType(ReportColumnType t) => switch (t) {
        ReportColumnType.text => XlsxCellType.text,
        ReportColumnType.integer => XlsxCellType.integer,
        ReportColumnType.liters => XlsxCellType.liters,
        ReportColumnType.money => XlsxCellType.money,
        ReportColumnType.date => XlsxCellType.date,
        ReportColumnType.percent => XlsxCellType.number,
      };

  /// Nombre base del archivo: "consolidado_de_recepcion_1ra_Quincena_Nov_2026".
  static String datasetFileName(ReportDataset d, {String? suffix}) {
    String clean(String s) => s
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final String base = clean(d.title.toLowerCase());
    final String period = clean(d.periodLabel);
    final String extra = suffix == null ? '' : '_${clean(suffix)}';
    final String name = '${base}_$period$extra';
    return name.length > 90 ? name.substring(0, 90) : name;
  }

  /// Hoja tabular para Excel/CSV. Los porcentajes se exportan en 0–100.
  static TableSheet datasetToSheet(ReportDataset d, {String? filterLabel}) {
    List<Object?> normalize(List<Object?> row) {
      final List<Object?> out = <Object?>[];
      for (int i = 0; i < d.columns.length; i++) {
        final Object? v = i < row.length ? row[i] : null;
        if (v is num && d.columns[i].type == ReportColumnType.percent) {
          out.add(double.parse((v * 100).toStringAsFixed(1)));
        } else {
          out.add(v);
        }
      }
      return out;
    }

    return TableSheet(
      name: d.title,
      title: '${AppConstants.appName} · ${d.title}',
      subtitle: <String>[
        'Período: ${d.periodLabel}',
        if (filterLabel != null && filterLabel.isNotEmpty) filterLabel,
        if (d.subtitle != null) d.subtitle!,
        'Generado: ${AppFormatters.formatDateTime(DateTime.now())}',
      ].join(' · '),
      columns: <XlsxColumn>[
        for (final ReportColumn c in d.columns)
          XlsxColumn(
            c.type == ReportColumnType.percent ? '${c.header} (%)' : c.header,
            type: _xlsxType(c.type),
            width: (10 + c.flex * 5).toDouble().clamp(10, 48),
          ),
      ],
      rows: d.rows.map(normalize).toList(),
      totals: d.totals == null ? null : normalize(d.totals!),
    );
  }

  static Future<Uint8List> exportDataset(
    ReportDataset d,
    ExportFormat format, {
    String? filterLabel,
    String? generatedBy,
  }) async {
    switch (format) {
      case ExportFormat.pdf:
        return buildDatasetPdf(d, filterLabel: filterLabel, generatedBy: generatedBy);
      case ExportFormat.xlsx:
        return XlsxBuilder.build(<TableSheet>[datasetToSheet(d, filterLabel: filterLabel)]);
      case ExportFormat.csv:
        return CsvBuilder.build(datasetToSheet(d, filterLabel: filterLabel));
    }
  }

  /// PDF institucional de cualquier reporte del catálogo.
  static Future<Uint8List> buildDatasetPdf(
    ReportDataset d, {
    String? filterLabel,
    String? generatedBy,
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData? theme = await _pdfTheme();
    final Uint8List? logo = logoBytes ?? await _tryLoadLogoBytes();
    final pw.MemoryImage? logoImage = logo == null ? null : pw.MemoryImage(logo);
    final bool landscape = d.columns.length > 7;
    final pw.Document pdf = pw.Document(
      title: '${d.title} · ${d.periodLabel}',
      author: AppConstants.appName,
      theme: theme,
    );

    final int totalFlex = d.columns.fold<int>(0, (int s, ReportColumn c) => s + c.flex);
    final Map<int, pw.TableColumnWidth> widths = <int, pw.TableColumnWidth>{
      for (int i = 0; i < d.columns.length; i++) i: pw.FlexColumnWidth(d.columns[i].flex / totalFlex * 10),
    };
    final Map<int, pw.Alignment> aligns = <int, pw.Alignment>{
      for (int i = 0; i < d.columns.length; i++)
        i: d.columns[i].alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    };
    List<String> fmt(List<Object?> row) => <String>[
          for (int i = 0; i < d.columns.length; i++)
            ReportDataset.formatCell(i < row.length ? row[i] : null, d.columns[i].type),
        ];
    final int totalsRow = d.rows.length + 1;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: landscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        footer: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                '${AppConstants.appName} · ${d.title} · ${d.periodLabel}',
                style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary),
              ),
            ],
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          _institutionalHeader(
            title: d.title,
            lines: <String>[
              'Período: ${d.periodLabel}',
              if (filterLabel != null && filterLabel.isNotEmpty) filterLabel,
              if (d.subtitle != null) d.subtitle!,
            ],
            generatedBy: generatedBy,
            logo: logoImage,
          ),
          if (d.kpis.isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _kpiStrip(d.kpis),
          ],
          pw.SizedBox(height: 14),
          if (d.rows.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(d.emptyMessage, style: const pw.TextStyle(fontSize: 9.5, color: _textSecondary)),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: d.columns.map((ReportColumn c) => c.header.toUpperCase()).toList(),
              data: <List<String>>[
                ...d.rows.map(fmt),
                if (d.totals != null) fmt(d.totals!),
              ],
              columnWidths: widths,
              headerAlignments: aligns,
              cellAlignments: aligns,
              headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: _emerald),
              cellStyle: const pw.TextStyle(fontSize: 7.8, color: _textPrimary),
              oddRowDecoration: const pw.BoxDecoration(color: _zebra),
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _border, width: 0.5),
                bottom: pw.BorderSide(color: _border, width: 0.5),
              ),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              cellDecoration: (int index, dynamic data, int rowNum) =>
                  d.totals != null && rowNum == totalsRow
                      ? const pw.BoxDecoration(color: _mutedBg)
                      : const pw.BoxDecoration(),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _institutionalHeader({
    required String title,
    required List<String> lines,
    String? generatedBy,
    pw.MemoryImage? logo,
  }) {
    const PdfColor soft = PdfColor.fromInt(0xFFCDEAE4);
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(color: _inkBlack, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          if (logo != null) ...<pw.Widget>[
            pw.SizedBox(width: 40, height: 40, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  '${AppConstants.appName} · ${AppConstants.appTagline}',
                  style: const pw.TextStyle(fontSize: 7.5, color: soft),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
                pw.SizedBox(height: 3),
                for (final String l in lines) pw.Text(l, style: const pw.TextStyle(fontSize: 8.5, color: soft)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text('Generado', style: const pw.TextStyle(fontSize: 7.5, color: soft)),
              pw.Text(
                AppFormatters.formatDateTime(DateTime.now()),
                style: pw.TextStyle(fontSize: 8.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              ),
              if (generatedBy != null && generatedBy.isNotEmpty)
                pw.Text(generatedBy, style: const pw.TextStyle(fontSize: 7.5, color: soft)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _kpiStrip(List<ReportKpi> kpis) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          for (int i = 0; i < kpis.length; i++)
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: i == 0
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(left: pw.BorderSide(color: _border, width: 0.6)),
                      ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(kpis[i].label, style: const pw.TextStyle(fontSize: 7.2, color: _textSecondary)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      kpis[i].value,
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _inkBlack),
                    ),
                    if (kpis[i].hint != null)
                      pw.Text(kpis[i].hint!, style: const pw.TextStyle(fontSize: 6.8, color: _textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
