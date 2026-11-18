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
import 'report_service.dart';
import 'settlement_calculator.dart';

/// Servicio de exportación consolidada de reportes en CSV y PDF (`RF-18`, `HU-09`).
class ReportExportService {
  ReportExportService._();

  static const CsvEncoder _excelCsvEncoder = CsvEncoder(addBom: true);

  static const PdfColor _inkBlack = PdfColor.fromInt(0xFF0E1117);
  static const PdfColor _emerald = PdfColor.fromInt(0xFF0D7A5F);
  static const PdfColor _mutedBg = PdfColor.fromInt(0xFFF5F6F8);
  static const PdfColor _border = PdfColor.fromInt(0xFFD9DEE7);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF475162);

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
      final ByteData data = await rootBundle.load(AppConstants.logoAssetPath);
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
            pw.Container(
              width: 42,
              height: 42,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(6),
              ),
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
                      color: PdfColor.fromInt(0xFFA7F3D0),
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
              color: const PdfColor.fromInt(0xFFE8F6F1),
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
}
