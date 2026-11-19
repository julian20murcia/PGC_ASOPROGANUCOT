import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../controllers/producer_controller.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/producer_model.dart';

/// Generación del directorio de productores en PDF, Excel o CSV.
class ProducerDirectoryExport {
  ProducerDirectoryExport._();

  static const PdfColor _brand = PdfColor.fromInt(0xFF0F766E);
  static const PdfColor _dark = PdfColor.fromInt(0xFF0B3B37);
  static const PdfColor _soft = PdfColor.fromInt(0xFFE7F5F2);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E7EA);
  static const PdfColor _muted = PdfColor.fromInt(0xFF4B5B61);

  static String _date(DateTime d) => AppFormatters.formatDate(d);

  static String _iso(String? iso) =>
      iso == null || iso.isEmpty ? '' : AppFormatters.formatIsoDate(iso);

  /// Hoja tabular (Excel / CSV) del directorio.
  static TableSheet sheet({
    required List<ProducerModel> producers,
    required ProducerDeliveryStats Function(String productorId) statsFor,
    required String periodLabel,
    DateTime? generatedAt,
  }) {
    double total = 0;
    int deliveries = 0;
    final List<List<Object?>> rows = <List<Object?>>[];
    for (final ProducerModel p in producers) {
      final ProducerDeliveryStats s = statsFor(p.productorId);
      total += s.liters;
      deliveries += s.deliveries;
      rows.add(<Object?>[
        p.codigoAsociado,
        p.nombres,
        p.apellidos,
        p.cedula,
        p.telefono,
        p.nombreFinca,
        p.vereda,
        p.isActivo ? 'Activo' : 'Inactivo',
        double.parse(s.liters.toStringAsFixed(2)),
        s.deliveries,
        _iso(s.lastDeliveryIso),
        ProducerController.hasAppAccess(p) ? 'Sí' : 'No',
        p.hasValidHabeasData ? 'Autorizado' : 'Pendiente',
        _date(p.fechaCreacion),
      ]);
    }
    return TableSheet(
      name: 'Productores',
      title: 'Directorio de productores — ASOPROGANUCOTT',
      subtitle:
          'Litros del período: $periodLabel · Generado ${AppFormatters.formatDateTime(generatedAt ?? DateTime.now())}',
      columns: const <XlsxColumn>[
        XlsxColumn('Código', width: 11),
        XlsxColumn('Nombres', width: 20),
        XlsxColumn('Apellidos', width: 20),
        XlsxColumn('Cédula', width: 14),
        XlsxColumn('Teléfono', width: 13),
        XlsxColumn('Finca', width: 22),
        XlsxColumn('Vereda', width: 18),
        XlsxColumn('Estado', width: 10),
        XlsxColumn('Litros período', type: XlsxCellType.liters, width: 14),
        XlsxColumn('Entregas', type: XlsxCellType.integer, width: 10),
        XlsxColumn('Última entrega', width: 14),
        XlsxColumn('App móvil', width: 10),
        XlsxColumn('Habeas Data', width: 12),
        XlsxColumn('Registrado', width: 12),
      ],
      rows: rows,
      totals: <Object?>[
        'Total',
        '${producers.length} productores',
        null,
        null,
        null,
        null,
        null,
        null,
        double.parse(total.toStringAsFixed(2)),
        deliveries,
        null,
        null,
        null,
        null,
      ],
    );
  }

  static Future<Uint8List> pdf({
    required List<ProducerModel> producers,
    required ProducerDeliveryStats Function(String productorId) statsFor,
    required String periodLabel,
    DateTime? generatedAt,
  }) async {
    final pw.Document doc = pw.Document(
      title: 'Directorio de productores',
      author: 'ASOPROGANUCOTT',
    );
    double total = 0;
    final List<List<String>> data = <List<String>>[];
    for (final ProducerModel p in producers) {
      final ProducerDeliveryStats s = statsFor(p.productorId);
      total += s.liters;
      data.add(<String>[
        p.codigoAsociado,
        p.nombreCompleto,
        p.cedula,
        p.telefono,
        '${p.nombreFinca} · ${p.vereda}',
        p.isActivo ? 'Activo' : 'Inactivo',
        AppFormatters.formatLiters(s.liters),
        _iso(s.lastDeliveryIso),
        ProducerController.hasAppAccess(p) ? 'Sí' : 'No',
      ]);
    }
    final String stamp = AppFormatters.formatDateTime(
      generatedAt ?? DateTime.now(),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        header: (pw.Context ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          margin: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 1.4)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      'Directorio de productores',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _dark,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'ASOPROGANUCOTT · Litros del período $periodLabel',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: <pw.Widget>[
                  pw.Text(
                    '${producers.length} productores · ${AppFormatters.formatLiters(total)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                  pw.Text(
                    'Generado $stamp',
                    style: const pw.TextStyle(fontSize: 8, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (pw.Context ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        build: (pw.Context ctx) => <pw.Widget>[
          if (data.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text(
                'No hay productores con los filtros seleccionados.',
                style: const pw.TextStyle(fontSize: 10, color: _muted),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Código',
                'Productor',
                'Cédula',
                'Teléfono',
                'Finca · Vereda',
                'Estado',
                'Litros',
                'Última entrega',
                'App',
              ],
              data: data,
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _dark),
              cellStyle: const pw.TextStyle(fontSize: 8, color: _dark),
              oddRowDecoration: const pw.BoxDecoration(color: _soft),
              border: pw.TableBorder.all(color: _border, width: 0.6),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 4,
              ),
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FixedColumnWidth(52),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FixedColumnWidth(66),
                3: pw.FixedColumnWidth(64),
                4: pw.FlexColumnWidth(2.4),
                5: pw.FixedColumnWidth(46),
                6: pw.FixedColumnWidth(60),
                7: pw.FixedColumnWidth(62),
                8: pw.FixedColumnWidth(28),
              },
              cellAlignments: const <int, pw.Alignment>{
                6: pw.Alignment.centerRight,
                8: pw.Alignment.center,
              },
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Punto de entrada para [ExportButton].
  static Future<({Uint8List bytes, String baseName})> build(
    ExportFormat format, {
    required List<ProducerModel> producers,
    required ProducerDeliveryStats Function(String productorId) statsFor,
    required String periodLabel,
  }) async {
    final DateTime now = DateTime.now();
    final String baseName =
        'directorio_productores_${AppFormatters.toIsoDate(now)}';
    switch (format) {
      case ExportFormat.pdf:
        return (
          bytes: await pdf(
            producers: producers,
            statsFor: statsFor,
            periodLabel: periodLabel,
            generatedAt: now,
          ),
          baseName: baseName,
        );
      case ExportFormat.xlsx:
        return (
          bytes: XlsxBuilder.build(<TableSheet>[
            sheet(
              producers: producers,
              statsFor: statsFor,
              periodLabel: periodLabel,
              generatedAt: now,
            ),
          ]),
          baseName: baseName,
        );
      case ExportFormat.csv:
        return (
          bytes: CsvBuilder.build(
            sheet(
              producers: producers,
              statsFor: statsFor,
              periodLabel: periodLabel,
              generatedAt: now,
            ),
          ),
          baseName: baseName,
        );
    }
  }
}
