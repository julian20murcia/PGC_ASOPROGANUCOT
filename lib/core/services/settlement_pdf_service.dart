import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'file_export_service.dart';
import 'settlement_calculator.dart';

/// Generador del comprobante (desprendible) de pago quincenal y del reporte
/// consolidado de una quincena cerrada en PDF (`RF-14`, `HU-08`).
///
/// API pública reutilizable desde escritorio y móvil:
/// * [buildVoucherPdfBytes] → bytes del comprobante de un productor.
/// * [buildPeriodReportPdfBytes] → reporte consolidado de una quincena.
/// * [printOrPreviewVoucher], [shareOrDownloadVoucher], [shareVoucher].
/// * [voucherFileName] → nombre estándar `Comprobante_COMP-YYYY-XXXX.pdf`.
class SettlementPdfService {
  SettlementPdfService._();

  // Paleta "Pradera".
  static const PdfColor _brand = PdfColor.fromInt(0xFF0F766E);
  static const PdfColor _brandDeep = PdfColor.fromInt(0xFF0B3B37);
  static const PdfColor _brandSoft = PdfColor.fromInt(0xFFE7F5F2);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E7EA);
  static const PdfColor _textPrimary = PdfColor.fromInt(0xFF0F1B1E);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF4B5B61);
  static const PdfColor _textMuted = PdfColor.fromInt(0xFF8A979D);
  static const PdfColor _zebra = PdfColor.fromInt(0xFFF7F9FA);
  static const PdfColor _success = PdfColor.fromInt(0xFF059669);
  static const PdfColor _successBg = PdfColor.fromInt(0xFFE8F7F0);
  static const PdfColor _warning = PdfColor.fromInt(0xFFD97706);
  static const PdfColor _warningBg = PdfColor.fromInt(0xFFFEF5E4);

  static const List<String> _weekdays = <String>['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  static pw.ThemeData? _cachedTheme;
  static bool _themeTried = false;

  /// Nombre estándar del archivo del comprobante.
  static String voucherFileName(SettlementModel settlement) =>
      'Comprobante_${settlement.numeroComprobante.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '-')}.pdf';

  /// Texto sugerido al compartir el comprobante (WhatsApp, correo…).
  static String voucherShareText(SettlementModel settlement) =>
      '${AppConstants.appName} · Comprobante ${settlement.numeroComprobante}\n'
      '${settlement.nombreProductorSnap} — ${settlement.quincenaLabel}\n'
      '${AppFormatters.formatLiters(settlement.totalLitros)} · '
      'Total: ${AppFormatters.formatCurrency(settlement.valorTotalPagar)}'
      '${settlement.isPagada ? ' (pagado)' : ' (pendiente de pago)'}';

  /// Tema con fuente Inter (soporte Unicode). Si no se puede cargar (p. ej.
  /// pruebas sin binding) se usa la fuente por defecto.
  static Future<pw.ThemeData?> _theme() async {
    if (_themeTried) return _cachedTheme;
    _themeTried = true;
    try {
      final pw.Font regular =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      final pw.Font bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      _cachedTheme = pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
    } catch (_) {
      _cachedTheme = null;
    }
    return _cachedTheme;
  }

  static Uint8List? _logoCache;

  /// Carga el logo oficial reducido a ~200 px (el original pesa >1 MB y
  /// inflaría cada comprobante compartido por WhatsApp/correo).
  static Future<Uint8List?> _tryLoadLogoBytes() async {
    if (_logoCache != null) return _logoCache;
    try {
      final ByteData data = await rootBundle.load(AppConstants.darkLogoAssetPath);
      Uint8List out = data.buffer.asUint8List();
      try {
        final ui.Codec codec = await ui.instantiateImageCodec(out, targetWidth: 200);
        final ui.FrameInfo frame = await codec.getNextFrame();
        final ByteData? png = await frame.image
            .toByteData(format: ui.ImageByteFormat.png)
            .timeout(const Duration(seconds: 4));
        if (png != null) out = png.buffer.asUint8List();
      } catch (_) {
        // Si no se puede reducir se usa el original.
      }
      _logoCache = out;
      return out;
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
    final Uint8List bytes = await buildVoucherPdfBytes(
      settlement: settlement,
      receptions: receptions,
      producer: producer,
    );
    await Printing.layoutPdf(
      name: voucherFileName(settlement),
      onLayout: (_) async => bytes,
    );
  }

  /// Abre el diálogo nativo "Compartir en…" con el comprobante PDF.
  static Future<void> shareOrDownloadVoucher({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
  }) =>
      shareVoucher(settlement: settlement, receptions: receptions, producer: producer);

  /// Comparte el comprobante con las apps disponibles (correo, WhatsApp…).
  static Future<void> shareVoucher({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
    Uint8List? bytes,
  }) async {
    final Uint8List data = bytes ??
        await buildVoucherPdfBytes(
          settlement: settlement,
          receptions: receptions,
          producer: producer,
        );
    await FileExportService.share(
      data,
      voucherFileName(settlement),
      mimeType: 'application/pdf',
      text: voucherShareText(settlement),
      subject: 'Comprobante ${settlement.numeroComprobante} · ${settlement.quincenaLabel}',
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Comprobante individual
  // ───────────────────────────────────────────────────────────────────────

  /// Construye los bytes del comprobante PDF de liquidación quincenal.
  ///
  /// * [receptions]: entregas del productor (se ignoran las anuladas). Pueden
  ///   venir todas las del productor: solo se usan las del período.
  /// * [producer]: datos opcionales (código, finca, vereda).
  /// * [logoBytes]: logo opcional; si es null se intenta cargar el oficial.
  static Future<Uint8List> buildVoucherPdfBytes({
    required SettlementModel settlement,
    required List<MilkReceptionModel> receptions,
    ProducerModel? producer,
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData? theme = await _theme();
    final Uint8List? logo = logoBytes ?? await _tryLoadLogoBytes();
    final pw.MemoryImage? logoImage = logo != null ? pw.MemoryImage(logo) : null;

    final List<MilkReceptionModel> scoped = receptions
        .where((MilkReceptionModel r) =>
            !r.anulado &&
            (r.liquidacionId == settlement.liquidacionId ||
                (r.productorId == settlement.productorId &&
                    r.fechaEntrega.compareTo(settlement.periodoInicio) >= 0 &&
                    r.fechaEntrega.compareTo(settlement.periodoFin) <= 0)))
        .toList();

    final DailyDeliveryMatrix matrix = DailyDeliveryMatrix.build(
      startIso: settlement.periodoInicio,
      endIso: settlement.periodoFin,
      receptions: scoped,
      producerOrder: <({String productorId, String codigo, String nombre})>[
        (
          productorId: settlement.productorId,
          codigo: producer?.codigoAsociado ?? '',
          nombre: settlement.nombreProductorSnap,
        ),
      ],
    );
    final DailyMatrixRow row = matrix.rows.first;

    final pw.Document pdf = pw.Document(
      title: 'Comprobante ${settlement.numeroComprobante}',
      author: AppConstants.appName,
      subject: 'Liquidación quincenal de leche cruda',
      theme: theme,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 24),
        footer: (pw.Context ctx) => _footer(
          ctx,
          'Comprobante ${settlement.numeroComprobante} · Código de verificación ${SettlementCalculator.verificationCode(settlement.hashIntegridad)}',
        ),
        build: (pw.Context context) => <pw.Widget>[
          _header(
            logoImage: logoImage,
            docTitle: 'COMPROBANTE DE PAGO',
            docNumber: settlement.numeroComprobante,
            docDate: 'Emitido el ${AppFormatters.formatDateTime(settlement.fechaLiquidacion)}',
          ),
          pw.SizedBox(height: 10),
          _statusRibbon(settlement),
          pw.SizedBox(height: 10),
          _infoGrid(settlement, producer),
          pw.SizedBox(height: 12),
          _sectionTitle('Entregas día a día'),
          pw.SizedBox(height: 6),
          _dailyTable(settlement, matrix, row),
          pw.SizedBox(height: 10),
          _totalsBlock(settlement, row),
          pw.SizedBox(height: 10),
          _paymentAndIntegrity(settlement),
          pw.SizedBox(height: 26),
          _signatures(settlement),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _footer(pw.Context ctx, String left) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              '${AppConstants.appName} · $left',
              style: const pw.TextStyle(fontSize: 7.5, color: _textMuted),
              maxLines: 1,
            ),
          ),
          pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _textMuted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _header({
    required pw.MemoryImage? logoImage,
    required String docTitle,
    required String docNumber,
    required String docDate,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          if (logoImage != null) ...<pw.Widget>[
            pw.SizedBox(width: 46, height: 46, child: pw.Image(logoImage, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  AppConstants.appName,
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _brandDeep),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  AppConstants.appTagline,
                  style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                docTitle,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _brand,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                docNumber,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _textPrimary),
              ),
              pw.SizedBox(height: 2),
              pw.Text(docDate, style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _statusRibbon(SettlementModel s) {
    final bool paid = s.isPagada;
    return pw.Row(
      children: <pw.Widget>[
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: paid ? _successBg : _warningBg,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            paid ? 'PAGADO' : 'PENDIENTE DE PAGO',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: paid ? _success : _warning,
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            'Liquidación de leche cruda · ${s.quincenaLabel}',
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _textPrimary),
          ),
        ),
      ],
    );
  }

  static pw.Widget _infoGrid(SettlementModel s, ProducerModel? p) {
    pw.Widget box(String title, List<(String, String)> rows) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _zebra,
              border: pw.Border.all(color: _border, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  title.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand,
                    letterSpacing: 0.7,
                  ),
                ),
                pw.SizedBox(height: 5),
                for (final (String k, String v) in rows)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        pw.SizedBox(
                          width: 78,
                          child: pw.Text(k, style: const pw.TextStyle(fontSize: 8, color: _textSecondary)),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            v,
                            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        box('Productor', <(String, String)>[
          ('Nombre', s.nombreProductorSnap),
          ('Documento', s.cedulaProductorSnap.isEmpty ? 'No registrado' : s.cedulaProductorSnap),
          if (p != null) ('Código', p.codigoAsociado),
          if (p != null) ('Finca / vereda', '${p.nombreFinca} · ${p.vereda}'),
        ]),
        pw.SizedBox(width: 10),
        box('Período liquidado', <(String, String)>[
          ('Quincena', s.quincenaLabel),
          (
            'Rango',
            '${AppFormatters.formatIsoDate(s.periodoInicio)} al ${AppFormatters.formatIsoDate(s.periodoFin)}'
          ),
          ('Entregas', '${s.cantidadEntregas} registro(s)'),
          ('Fecha de cierre', AppFormatters.formatDate(s.fechaLiquidacion)),
        ]),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text) => pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: _textSecondary,
          letterSpacing: 0.8,
        ),
      );

  static String _dayLabel(String iso) {
    final DateTime? d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return _weekdays[d.weekday - 1];
  }

  static String _litersOrDash(double v) =>
      v <= 0 ? '—' : AppFormatters.formatLiters(v, withUnit: false);

  static pw.Widget _dailyTable(
    SettlementModel s,
    DailyDeliveryMatrix matrix,
    DailyMatrixRow row,
  ) {
    final pw.TextStyle head = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );
    const pw.TextStyle cell = pw.TextStyle(fontSize: 8, color: _textPrimary);
    final pw.TextStyle cellBold =
        pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _textPrimary);

    pw.Widget c(String t, {pw.TextStyle? style, pw.Alignment align = pw.Alignment.centerRight}) =>
        pw.Container(
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.2),
          child: pw.Text(t, style: style ?? cell),
        );

    final List<pw.TableRow> rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _brandDeep),
        children: <pw.Widget>[
          c('Fecha', style: head, align: pw.Alignment.centerLeft),
          c('Día', style: head, align: pw.Alignment.centerLeft),
          c('Mañana (L)', style: head),
          c('Tarde (L)', style: head),
          c('Total día (L)', style: head),
          c('Valor del día', style: head),
        ],
      ),
    ];
    int i = 0;
    for (final String day in matrix.days) {
      final DailyShiftCell dc = row.cell(day);
      final double value = dc.isEmpty
          ? 0
          : SettlementCalculator.calculateTotalAmount(
              totalLiters: dc.total,
              pricePerLiter: s.precioLitroAplicado,
            );
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? _zebra : PdfColors.white),
          children: <pw.Widget>[
            c(AppFormatters.formatIsoDate(day), align: pw.Alignment.centerLeft),
            c(_dayLabel(day), align: pw.Alignment.centerLeft,
                style: const pw.TextStyle(fontSize: 8, color: _textSecondary)),
            c(_litersOrDash(dc.morning)),
            c(_litersOrDash(dc.afternoon)),
            c(_litersOrDash(dc.total), style: cellBold),
            c(dc.isEmpty ? '—' : AppFormatters.formatCurrency(value)),
          ],
        ),
      );
      i++;
    }
    final bool hasDetail = row.morningThousandths + row.afternoonThousandths > 0;
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _brandSoft,
          border: pw.Border(top: pw.BorderSide(color: _brand, width: 0.8)),
        ),
        children: <pw.Widget>[
          c('Subtotales', style: cellBold, align: pw.Alignment.centerLeft),
          c(''),
          c(AppFormatters.formatLiters(hasDetail ? row.totalMorning : 0, withUnit: false), style: cellBold),
          c(AppFormatters.formatLiters(hasDetail ? row.totalAfternoon : 0, withUnit: false), style: cellBold),
          c(AppFormatters.formatLiters(hasDetail ? row.total : s.totalLitros, withUnit: false), style: cellBold),
          c(AppFormatters.formatCurrency(s.valorTotalPagar), style: cellBold),
        ],
      ),
    );

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.4),
        bottom: pw.BorderSide(color: _border, width: 0.6),
      ),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(0.8),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.2),
        5: pw.FlexColumnWidth(1.5),
      },
      children: rows,
    );
  }

  static pw.Widget _totalsBlock(SettlementModel s, DailyMatrixRow row) {
    pw.Widget line(String k, String v, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(k, style: const pw.TextStyle(fontSize: 8.5, color: _textSecondary)),
              pw.Text(
                v,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        );
    final String words = SpanishNumberWords.pesos(s.valorTotalPagar);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border, width: 0.6),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _sectionTitle('Valor en letras'),
                pw.SizedBox(height: 4),
                pw.Text(
                  words.isEmpty ? AppFormatters.formatCurrency(s.valorTotalPagar) : words,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _textPrimary),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: <pw.Widget>[
              line('Litros mañana', AppFormatters.formatLiters(row.totalMorning)),
              line('Litros tarde', AppFormatters.formatLiters(row.totalAfternoon)),
              line('Total litros', AppFormatters.formatLiters(s.totalLitros), strong: true),
              line('Precio aplicado por litro', AppFormatters.formatCurrency(s.precioLitroAplicado)),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: _brand,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: <pw.Widget>[
                    pw.Text(
                      'TOTAL A PAGAR',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                    pw.Text(
                      AppFormatters.formatCurrency(s.valorTotalPagar, alwaysShowDecimals: true),
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _paymentAndIntegrity(SettlementModel s) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(
            flex: 4,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _sectionTitle('Estado de pago'),
                pw.SizedBox(height: 4),
                pw.Text(
                  s.isPagada ? 'Pagado' : 'Pendiente de pago',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: s.isPagada ? _success : _warning,
                  ),
                ),
                if (s.isPagada) ...<pw.Widget>[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Fecha: ${s.fechaPago != null ? AppFormatters.formatDate(s.fechaPago!) : 'N/D'}',
                    style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
                  ),
                  if ((s.observacionPago ?? '').isNotEmpty)
                    pw.Text(
                      'Referencia: ${s.observacionPago}',
                      style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
                    ),
                ] else
                  pw.Text(
                    'El pago se registrará en este comprobante al desembolsarse.',
                    style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
                  ),
              ],
            ),
          ),
          pw.Container(width: 0.6, height: 58, color: _border, margin: const pw.EdgeInsets.symmetric(horizontal: 10)),
          pw.Expanded(
            flex: 7,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                _sectionTitle('Verificación de integridad · Ley 527 de 1999'),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: <pw.Widget>[
                    pw.Text('Código de verificación: ',
                        style: const pw.TextStyle(fontSize: 8, color: _textSecondary)),
                    pw.Text(
                      SettlementCalculator.verificationCode(s.hashIntegridad),
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _brandDeep),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text('Huella SHA-256:', style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
                pw.Text(
                  s.hashIntegridad.isEmpty ? 'N/D' : s.hashIntegridad,
                  style: const pw.TextStyle(fontSize: 6.8, color: _textPrimary),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'ID de liquidación: ${s.liquidacionId}',
                  style: const pw.TextStyle(fontSize: 6.8, color: _textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatures(SettlementModel s) {
    pw.Widget sig(String title, String subtitle) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Container(height: 0.8, color: _textPrimary),
              pw.SizedBox(height: 4),
              pw.Text(title, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _textPrimary)),
              pw.Text(subtitle, style: const pw.TextStyle(fontSize: 7.5, color: _textSecondary)),
            ],
          ),
        );
    return pw.Row(
      children: <pw.Widget>[
        sig('Tesorería / Administración', AppConstants.appName),
        pw.SizedBox(width: 48),
        sig(
          'Recibí conforme: ${s.nombreProductorSnap}',
          'Documento: ${s.cedulaProductorSnap.isEmpty ? '________________' : s.cedulaProductorSnap}',
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Reporte consolidado de una quincena
  // ───────────────────────────────────────────────────────────────────────

  /// Reporte consolidado (horizontal) de una quincena cerrada: resumen,
  /// productores participantes y matriz de registros diarios M/T.
  static Future<Uint8List> buildPeriodReportPdfBytes({
    required SettlementPeriodGroup group,
    required DailyDeliveryMatrix matrix,
    Map<String, String> codesByProducerId = const <String, String>{},
    Uint8List? logoBytes,
  }) async {
    final pw.ThemeData? theme = await _theme();
    final Uint8List? logo = logoBytes ?? await _tryLoadLogoBytes();
    final pw.MemoryImage? logoImage = logo != null ? pw.MemoryImage(logo) : null;
    final pw.Document pdf = pw.Document(
      title: 'Liquidación ${group.label}',
      author: AppConstants.appName,
      subject: 'Consolidado de quincena cerrada',
      theme: theme,
    );
    final String range =
        '${AppFormatters.formatIsoDate(group.periodoInicio)} al ${AppFormatters.formatIsoDate(group.periodoFin)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        footer: (pw.Context ctx) => _footer(ctx, 'Consolidado ${group.label} · $range'),
        build: (pw.Context context) => <pw.Widget>[
          _header(
            logoImage: logoImage,
            docTitle: 'CONSOLIDADO DE QUINCENA',
            docNumber: group.label,
            docDate: '$range · Cerrada el ${AppFormatters.formatDate(group.closedAt)}',
          ),
          pw.SizedBox(height: 10),
          _kpiRow(<(String, String)>[
            ('Productores', '${group.producerCount}'),
            ('Entregas', '${group.deliveries}'),
            ('Litros', AppFormatters.formatLiters(group.totalLiters)),
            ('Precio promedio', AppFormatters.formatCurrency(group.averagePrice)),
            ('Valor total', AppFormatters.formatCurrency(group.totalAmount)),
            ('Pagadas', '${group.paidCount} · ${AppFormatters.formatCurrency(group.paidAmount)}'),
            ('Pendientes', '${group.pendingCount} · ${AppFormatters.formatCurrency(group.pendingAmount)}'),
          ]),
          pw.SizedBox(height: 12),
          _sectionTitle('Productores participantes'),
          pw.SizedBox(height: 5),
          _producersTable(group, codesByProducerId),
          pw.NewPage(),
          _sectionTitle('Registros diarios (litros mañana / tarde)'),
          pw.SizedBox(height: 5),
          _matrixTable(matrix),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _kpiRow(List<(String, String)> items) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        children: <pw.Widget>[
          for (int i = 0; i < items.length; i++)
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: i == 0
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(left: pw.BorderSide(color: _border, width: 0.6)),
                      ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(items[i].$1.toUpperCase(),
                        style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold, color: _textMuted)),
                    pw.SizedBox(height: 2),
                    pw.Text(items[i].$2,
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _producersTable(SettlementPeriodGroup g, Map<String, String> codes) {
    final List<List<String>> data = <List<String>>[];
    int i = 1;
    for (final SettlementModel s in g.settlements) {
      data.add(<String>[
        '${i++}',
        codes[s.productorId] ?? '—',
        s.nombreProductorSnap,
        s.cedulaProductorSnap,
        s.numeroComprobante,
        '${s.cantidadEntregas}',
        AppFormatters.formatLiters(s.totalLitros, withUnit: false),
        AppFormatters.formatCurrency(s.precioLitroAplicado),
        AppFormatters.formatCurrency(s.valorTotalPagar),
        s.isPagada
            ? 'Pagada ${s.fechaPago != null ? AppFormatters.formatDate(s.fechaPago!) : ''}'.trim()
            : 'Pendiente',
      ]);
    }
    data.add(<String>[
      '',
      '',
      'TOTAL',
      '',
      '',
      '${g.deliveries}',
      AppFormatters.formatLiters(g.totalLiters, withUnit: false),
      AppFormatters.formatCurrency(g.averagePrice),
      AppFormatters.formatCurrency(g.totalAmount),
      '${g.paidCount}/${g.producerCount} pagadas',
    ]);
    return pw.TableHelper.fromTextArray(
      headers: const <String>[
        '#', 'Código', 'Productor', 'Documento', 'Comprobante', 'Entregas', 'Litros', 'Precio/L', 'Valor', 'Estado',
      ],
      data: data,
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _brandDeep),
      cellStyle: const pw.TextStyle(fontSize: 7.8, color: _textPrimary),
      oddRowDecoration: const pw.BoxDecoration(color: _zebra),
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _border, width: 0.4)),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FixedColumnWidth(20),
        1: pw.FixedColumnWidth(52),
        2: pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(70),
        4: pw.FixedColumnWidth(92),
        5: pw.FixedColumnWidth(44),
        6: pw.FixedColumnWidth(60),
        7: pw.FixedColumnWidth(56),
        8: pw.FixedColumnWidth(76),
        9: pw.FixedColumnWidth(86),
      },
      headerAlignment: pw.Alignment.centerLeft,
      headerAlignments: const <int, pw.Alignment>{
        0: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: const <int, pw.Alignment>{
        0: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _matrixTable(DailyDeliveryMatrix m) {
    final pw.TextStyle head = pw.TextStyle(fontSize: 6.3, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    const pw.TextStyle small = pw.TextStyle(fontSize: 6.2, color: _textPrimary);
    const pw.TextStyle smallMuted = pw.TextStyle(fontSize: 6.2, color: _textMuted);
    final pw.TextStyle smallBold = pw.TextStyle(fontSize: 6.4, fontWeight: pw.FontWeight.bold, color: _textPrimary);

    String n(double v) => v <= 0 ? '·' : AppFormatters.formatLiters(v, withUnit: false);

    pw.Widget dayCell(DailyShiftCell c, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(n(c.morning), style: bold ? smallBold : (c.morning > 0 ? small : smallMuted)),
              pw.Text(n(c.afternoon), style: bold ? smallBold : (c.afternoon > 0 ? small : smallMuted)),
            ],
          ),
        );

    final Map<int, pw.TableColumnWidth> widths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(120),
      for (int i = 0; i < m.days.length; i++) i + 1: const pw.FlexColumnWidth(1),
      m.days.length + 1: const pw.FixedColumnWidth(48),
    };

    final List<pw.TableRow> rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _brandDeep),
        children: <pw.Widget>[
          pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Text('Productor  (M / T)', style: head),
          ),
          for (final String d in m.days)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 1),
              child: pw.Column(
                children: <pw.Widget>[
                  pw.Text(_dayLabel(d), style: head),
                  pw.Text(d.substring(8), style: head),
                ],
              ),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Total L', style: head)),
          ),
        ],
      ),
    ];
    int i = 0;
    for (final DailyMatrixRow r in m.rows) {
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? _zebra : PdfColors.white),
          children: <pw.Widget>[
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(r.nombre, style: smallBold, maxLines: 1),
                  pw.Text(r.codigo, style: smallMuted),
                ],
              ),
            ),
            for (final String d in m.days) dayCell(r.cell(d)),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(AppFormatters.formatLiters(r.total, withUnit: false), style: smallBold),
              ),
            ),
          ],
        ),
      );
      i++;
    }
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _brandSoft,
          border: pw.Border(top: pw.BorderSide(color: _brand, width: 0.8)),
        ),
        children: <pw.Widget>[
          pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('Total por día', style: smallBold)),
          for (final String d in m.days) dayCell(m.columnTotal(d), bold: true),
          pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(AppFormatters.formatLiters(m.grandTotal, withUnit: false), style: smallBold),
            ),
          ),
        ],
      ),
    );
    return pw.Table(
      columnWidths: widths,
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.3),
        verticalInside: pw.BorderSide(color: _border, width: 0.3),
        bottom: pw.BorderSide(color: _border, width: 0.6),
      ),
      children: rows,
    );
  }
}
