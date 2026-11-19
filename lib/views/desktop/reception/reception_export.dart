import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/app_constants.dart';
import '../../../core/services/file_export_service.dart';
import '../../../models/milk_reception_model.dart';
import 'reception_grid_logic.dart';

/// Construye los archivos de descarga de la planilla de recepción.
class ReceptionExport {
  ReceptionExport._();

  static const PdfColor _brand = PdfColor.fromInt(0xFF0F766E);
  static const PdfColor _dark = PdfColor.fromInt(0xFF0B3B37);
  static const PdfColor _soft = PdfColor.fromInt(0xFFE7F5F2);
  static const PdfColor _border = PdfColor.fromInt(0xFFE2E7EA);
  static const PdfColor _muted = PdfColor.fromInt(0xFF4B5B61);

  static String _dayLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// Hoja "Planilla": productor × (día M / T) + total.
  static TableSheet planillaSheet(PlanillaMatrix m, String rangeLabel) {
    final List<XlsxColumn> cols = <XlsxColumn>[
      const XlsxColumn('Código', width: 12),
      const XlsxColumn('Productor', width: 30),
      for (final DateTime d in m.days) ...<XlsxColumn>[
        XlsxColumn('${_dayLabel(d)} M', type: XlsxCellType.liters, width: 9),
        XlsxColumn('${_dayLabel(d)} T', type: XlsxCellType.liters, width: 9),
      ],
      const XlsxColumn('Mañana', type: XlsxCellType.liters, width: 11),
      const XlsxColumn('Tarde', type: XlsxCellType.liters, width: 11),
      const XlsxColumn('Total L', type: XlsxCellType.liters, width: 12),
    ];
    final List<List<Object?>> rows = <List<Object?>>[
      for (final PlanillaRow r in m.rows)
        <Object?>[
          r.codigo,
          r.nombre,
          for (final PlanillaCell c in r.cells) c.isEmpty ? null : c.liters,
          r.shiftTotal(0),
          r.shiftTotal(1),
          r.total,
        ],
    ];
    double shiftSum(int s) => m.rows.fold<double>(
      0,
      (double a, PlanillaRow r) => a + r.shiftTotal(s),
    );
    return TableSheet(
      name: 'Planilla',
      title: 'Planilla de recepción de leche',
      subtitle: 'Período: $rangeLabel · ${m.rows.length} productores',
      columns: cols,
      rows: rows,
      totals: <Object?>[
        'TOTAL',
        '',
        for (int c = 0; c < m.columnCount; c++) m.columnTotal(c),
        shiftSum(0),
        shiftSum(1),
        m.grandTotal,
      ],
    );
  }

  /// Hoja "Registros": lista cronológica.
  static TableSheet recordsSheet(
    List<MilkReceptionModel> items,
    String rangeLabel, {
    String Function(String uid)? operatorName,
  }) {
    final List<MilkReceptionModel> sorted = List<MilkReceptionModel>.of(items)
      ..sort((MilkReceptionModel a, MilkReceptionModel b) {
        final int d = a.fechaEntrega.compareTo(b.fechaEntrega);
        return d != 0 ? d : a.horaEntrega.compareTo(b.horaEntrega);
      });
    final double total = sorted
        .where((MilkReceptionModel r) => !r.anulado)
        .fold<double>(0, (double a, MilkReceptionModel r) => a + r.litros);
    return TableSheet(
      name: 'Registros',
      title: 'Registros de entregas',
      subtitle: 'Período: $rangeLabel · ${sorted.length} registros',
      columns: const <XlsxColumn>[
        XlsxColumn('Fecha', width: 12),
        XlsxColumn('Hora', width: 10),
        XlsxColumn('Código', width: 12),
        XlsxColumn('Productor', width: 30),
        XlsxColumn('Jornada', width: 10),
        XlsxColumn('Litros', type: XlsxCellType.liters, width: 11),
        XlsxColumn('Estado', width: 14),
        XlsxColumn('Sincronización', width: 14),
        XlsxColumn('Operario', width: 22),
      ],
      rows: <List<Object?>>[
        for (final MilkReceptionModel r in sorted)
          <Object?>[
            r.fechaEntrega,
            r.horaEntrega,
            r.codigoAsociadoSnap,
            r.nombreProductorSnap,
            r.jornada == AppConstants.shiftAfternoon ? 'Tarde' : 'Mañana',
            r.litros,
            statusLabel(r),
            r.isSynced ? 'Sincronizada' : 'Pendiente',
            operatorName?.call(r.operarioUid) ?? r.operarioUid,
          ],
      ],
      totals: <Object?>['TOTAL', '', '', '', '', total, '', '', ''],
    );
  }

  static String statusLabel(MilkReceptionModel r) {
    if (r.anulado) return 'Anulada';
    if (r.isLiquidada) return 'Liquidada';
    return 'Activa';
  }

  static Future<({Uint8List bytes, String baseName})> build({
    required ExportFormat format,
    required PlanillaMatrix matrix,
    required List<MilkReceptionModel> records,
    required String rangeLabel,
    required String rangeKey,
    String Function(String uid)? operatorName,
  }) async {
    final String base = 'Recepcion_leche_$rangeKey';
    final TableSheet planilla = planillaSheet(matrix, rangeLabel);
    switch (format) {
      case ExportFormat.xlsx:
        return (
          bytes: XlsxBuilder.build(<TableSheet>[
            planilla,
            recordsSheet(records, rangeLabel, operatorName: operatorName),
          ]),
          baseName: base,
        );
      case ExportFormat.csv:
        return (bytes: CsvBuilder.build(planilla), baseName: base);
      case ExportFormat.pdf:
        return (bytes: await _pdf(matrix, rangeLabel), baseName: base);
    }
  }

  static Future<Uint8List> _pdf(PlanillaMatrix m, String rangeLabel) async {
    // Con muchos días se agrupa por día (M + T) para que quepa en la hoja.
    final bool split = m.days.length <= 8;
    final List<String> headers = <String>[
      'Código',
      'Productor',
      for (final DateTime d in m.days)
        if (split) ...<String>['${_dayLabel(d)} M', '${_dayLabel(d)} T'] else
          _dayLabel(d),
      'Total',
    ];
    String n(double v) => v == 0 ? '' : formatLitersCo(v);
    final List<List<String>> data = <List<String>>[
      for (final PlanillaRow r in m.rows)
        <String>[
          r.codigo,
          r.nombre.length > 28 ? '${r.nombre.substring(0, 27)}…' : r.nombre,
          for (int d = 0; d < m.days.length; d++)
            if (split) ...<String>[
              n(r.cells[d * 2].liters),
              n(r.cells[d * 2 + 1].liters),
            ] else
              n(r.cells[d * 2].liters + r.cells[d * 2 + 1].liters),
          formatLitersCo(r.total),
        ],
      <String>[
        'TOTAL',
        '',
        for (int d = 0; d < m.days.length; d++)
          if (split) ...<String>[
            n(m.columnTotal(d * 2)),
            n(m.columnTotal(d * 2 + 1)),
          ] else
            n(m.dayTotal(d)),
        formatLitersCo(m.grandTotal),
      ],
    ];
    final int numericCols = headers.length - 2;
    final double fontSize = numericCols > 20
        ? 5.5
        : (numericCols > 12 ? 6.5 : 8);

    final pw.Document doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              'ASOPROGANUCOTT · Planilla de recepción de leche',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _dark,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Período: $rangeLabel · ${m.rows.length} productores · Total ${formatLitersCo(m.grandTotal)} L',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (pw.Context ctx) => <pw.Widget>[
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: _brand),
            cellStyle: pw.TextStyle(fontSize: fontSize),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 2,
            ),
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _border, width: 0.5),
              bottom: pw.BorderSide(color: _border, width: 0.5),
            ),
            oddRowDecoration: const pw.BoxDecoration(color: _soft),
            cellAlignments: <int, pw.Alignment>{
              for (int i = 2; i < headers.length; i++)
                i: pw.Alignment.centerRight,
            },
            columnWidths: <int, pw.TableColumnWidth>{
              0: const pw.FixedColumnWidth(40),
              1: const pw.FixedColumnWidth(110),
            },
          ),
        ],
      ),
    );
    return doc.save();
  }
}
