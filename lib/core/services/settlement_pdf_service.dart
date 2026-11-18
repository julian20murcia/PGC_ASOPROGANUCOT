import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'settlement_calculator.dart';

/// Generador de factura / comprobante interno de pago quincenal en PDF (`RF-14`, `HU-08`).
/// Incluye desglose diario de entregas, valor neto y sello íntegro Ley 527 de 1999.
class SettlementPdfService {
  SettlementPdfService._();

  static const PdfColor _inkBlack = PdfColor.fromInt(0xFF0E1117);
  static const PdfColor _emerald = PdfColor.fromInt(0xFF0D7A5F);
  static const PdfColor _emeraldLight = PdfColor.fromInt(0xFFE8F6F1);
  static const PdfColor _mutedBg = PdfColor.fromInt(0xFFF5F6F8);
  static const PdfColor _border = PdfColor.fromInt(0xFFD9DEE7);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF475162);

  static Future<Uint8List?> _tryLoadLogoBytes() async {
    try {
      final ByteData data = await rootBundle.load(AppConstants.logoAssetPath);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Abre vista previa / diálogo de impresión nativa del sistema operativo.
  static Future<void> printOrPreviewVoucher({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
  }) async {
    final Uint8List? logoBytes = await _tryLoadLogoBytes();
    final Uint8List bytes = await buildVoucherPdfBytes(
      settlement: settlement,
      receptions: receptions,
      producer: producer,
      logoBytes: logoBytes,
    );
    await Printing.layoutPdf(
      name: 'Comprobante_${settlement.numeroComprobante}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  /// Comparte o descarga directamente el archivo PDF generado.
  static Future<void> shareOrDownloadVoucher({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
  }) async {
    final Uint8List? logoBytes = await _tryLoadLogoBytes();
    final Uint8List bytes = await buildVoucherPdfBytes(
      settlement: settlement,
      receptions: receptions,
      producer: producer,
      logoBytes: logoBytes,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Comprobante_${settlement.numeroComprobante}.pdf',
    );
  }

  /// Construye los bytes del comprobante PDF de liquidación quincenal.
  static Future<Uint8List> buildVoucherPdfBytes({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
    Uint8List? logoBytes,
  }) async {
    final pw.Document pdf = pw.Document(
      title: 'Comprobante ${settlement.numeroComprobante}',
      author: AppConstants.appName,
      subject: 'Liquidación quincenal de leche cruda',
    );

    final List<MilkReceptionModel> sortedReceptions =
        List<MilkReceptionModel>.from(
      receptions.where((MilkReceptionModel r) => !r.anulado),
    )..sort((MilkReceptionModel a, MilkReceptionModel b) {
            final int dateCmp = a.fechaEntrega.compareTo(b.fechaEntrega);
            if (dateCmp != 0) return dateCmp;
            return a.horaEntrega.compareTo(b.horaEntrega);
          });

    double morningLiters = 0;
    double afternoonLiters = 0;
    for (final MilkReceptionModel r in sortedReceptions) {
      if (r.jornada.toUpperCase() == AppConstants.shiftMorning) {
        morningLiters += r.litros;
      } else {
        afternoonLiters += r.litros;
      }
    }

    final pw.MemoryImage? logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
        footer: (pw.Context ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'ASOPROGANUCOTT - Susa, Cundinamarca | Comprobante ${settlement.numeroComprobante}',
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
          _buildHeader(settlement, logoImage),
          pw.SizedBox(height: 14),
          _buildProducerAndPeriodBox(settlement, producer),
          pw.SizedBox(height: 12),
          _buildSummaryStrip(
            settlement: settlement,
            morningLiters: SettlementCalculator.roundToThousandths(morningLiters),
            afternoonLiters:
                SettlementCalculator.roundToThousandths(afternoonLiters),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'DETALLE DE ENTREGAS DEL PERÍODO',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _inkBlack,
              letterSpacing: 0.7,
            ),
          ),
          pw.SizedBox(height: 6),
          _buildDeliveriesTable(settlement, sortedReceptions),
          pw.SizedBox(height: 14),
          _buildPaymentAndIntegrityBox(settlement),
          pw.SizedBox(height: 28),
          _buildSignaturesRow(),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(
    SettlementModel settlement,
    pw.MemoryImage? logoImage,
  ) {
    final bool isPaid = settlement.isPagada;
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _inkBlack,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          if (logoImage != null) ...<pw.Widget>[
            pw.Container(
              width: 46,
              height: 46,
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
                  AppConstants.appName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Asociación de Productores y Ganaderos - Susa, Cundinamarca',
                  style: const pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColor.fromInt(0xFFD1D5DB),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'COMPROBANTE INTERNO DE LIQUIDACIÓN DE LECHE CRUDA',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: const PdfColor.fromInt(0xFFA7F3D0),
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                settlement.numeroComprobante,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Emisión: ${AppFormatters.formatDateTime(settlement.fechaLiquidacion)}',
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColor.fromInt(0xFFD1D5DB),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: isPaid
                      ? _emerald
                      : const PdfColor.fromInt(0xFFD97706),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  isPaid ? 'ESTADO: PAGADA' : 'ESTADO: PENDIENTE DE PAGO',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildProducerAndPeriodBox(
    SettlementModel settlement,
    ProducerModel? producer,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _mutedBg,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _labelValue('PRODUCTOR', settlement.nombreProductorSnap),
                pw.SizedBox(height: 4),
                _labelValue('CÉDULA DE CIUDADANÍA', settlement.cedulaProductorSnap),
                if (producer != null) ...<pw.Widget>[
                  pw.SizedBox(height: 4),
                  _labelValue(
                    'FINCA / VEREDA',
                    '${producer.nombreFinca} - Vereda ${producer.vereda} (${producer.codigoAsociado})',
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _labelValue('PERÍODO LIQUIDADO', settlement.quincenaLabel),
                pw.SizedBox(height: 4),
                _labelValue(
                  'RANGO DE FECHAS',
                  '${AppFormatters.formatIsoDate(settlement.periodoInicio)} al ${AppFormatters.formatIsoDate(settlement.periodoFin)}',
                ),
                pw.SizedBox(height: 4),
                _labelValue(
                  'ENTREGAS VALIDADAS',
                  '${settlement.cantidadEntregas} registro(s)',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _labelValue(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: _textSecondary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _inkBlack,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryStrip({
    required SettlementModel settlement,
    required double morningLiters,
    required double afternoonLiters,
  }) {
    return pw.Row(
      children: <pw.Widget>[
        _summaryTile(
          'Litros Mañana / Tarde',
          '${AppFormatters.formatLiters(morningLiters)} / ${AppFormatters.formatLiters(afternoonLiters)}',
        ),
        pw.SizedBox(width: 8),
        _summaryTile(
          'Total Litros',
          AppFormatters.formatLiters(settlement.totalLitros),
        ),
        pw.SizedBox(width: 8),
        _summaryTile(
          'Tarifa Aplicada / L',
          AppFormatters.formatCurrency(settlement.precioLitroAplicado),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _emeraldLight,
              border: pw.Border.all(color: _emerald),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  'VALOR NETO A PAGAR',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _emerald,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  AppFormatters.formatCurrency(
                    settlement.valorTotalPagar,
                    alwaysShowDecimals: true,
                  ),
                  style: pw.TextStyle(
                    fontSize: 13.5,
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

  static pw.Widget _summaryTile(String title, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
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
              value,
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

  static pw.Widget _buildDeliveriesTable(
    SettlementModel settlement,
    List<MilkReceptionModel> receptions,
  ) {
    if (receptions.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          'Resumen consolidado: ${settlement.cantidadEntregas} entregas por ${AppFormatters.formatLiters(settlement.totalLitros)}.',
          style: const pw.TextStyle(fontSize: 9.5, color: _textSecondary),
        ),
      );
    }

    final List<List<String>> dataRows = receptions.map((MilkReceptionModel r) {
      final double subtotal = SettlementCalculator.calculateTotalAmount(
        totalLiters: r.litros,
        pricePerLiter: settlement.precioLitroAplicado,
      );
      final String shiftLabel = r.jornada.toUpperCase() == AppConstants.shiftMorning
          ? 'Mañana'
          : 'Tarde';
      return <String>[
        AppFormatters.formatIsoDate(r.fechaEntrega),
        r.horaEntrega,
        shiftLabel,
        AppFormatters.formatLiters(r.litros),
        AppFormatters.formatCurrency(settlement.precioLitroAplicado),
        AppFormatters.formatCurrency(subtotal, alwaysShowDecimals: true),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: const <String>[
        'Fecha',
        'Hora',
        'Jornada',
        'Litros',
        'Tarifa / L',
        'Subtotal',
      ],
      data: dataRows,
      headerStyle: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _inkBlack),
      cellStyle: const pw.TextStyle(fontSize: 8.5, color: _inkBlack),
      oddRowDecoration: const pw.BoxDecoration(color: _mutedBg),
      border: pw.TableBorder.all(color: _border, width: 0.6),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      cellAlignments: const <int, pw.Alignment>{
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _buildPaymentAndIntegrityBox(SettlementModel settlement) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          if (settlement.isPagada) ...<pw.Widget>[
            pw.Text(
              'CONFIRMACIÓN DE DESEMBOLSO',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: _emerald,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Pagada el ${settlement.fechaPago != null ? AppFormatters.formatDateTime(settlement.fechaPago!) : 'N/A'} - ${settlement.observacionPago ?? 'Desembolso confirmado.'}',
              style: const pw.TextStyle(fontSize: 9, color: _inkBlack),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: _border, height: 1),
            pw.SizedBox(height: 8),
          ],
          pw.Text(
            'SELLO DE INTEGRIDAD ELECTRÓNICA (LEY 527 DE 1999)',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _textSecondary,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Identificador: ${settlement.liquidacionId}',
            style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
          ),
          pw.Text(
            'Huella SHA-256: ${settlement.hashIntegridad}',
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: 7.5,
              color: _inkBlack,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSignaturesRow() {
    return pw.Row(
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            children: <pw.Widget>[
              pw.Divider(color: _inkBlack, thickness: 0.8),
              pw.SizedBox(height: 4),
              pw.Text(
                'Administración / Tesorería ASOPROGANUCOTT',
                style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 48),
        pw.Expanded(
          child: pw.Column(
            children: <pw.Widget>[
              pw.Divider(color: _inkBlack, thickness: 0.8),
              pw.SizedBox(height: 4),
              pw.Text(
                'Recibí conforme - Productor Asociado',
                style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
