import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Formatos de descarga disponibles en toda la plataforma.
enum ExportFormat { pdf, xlsx, csv }

extension ExportFormatX on ExportFormat {
  String get extension => switch (this) {
        ExportFormat.pdf => 'pdf',
        ExportFormat.xlsx => 'xlsx',
        ExportFormat.csv => 'csv',
      };

  String get mimeType => switch (this) {
        ExportFormat.pdf => 'application/pdf',
        ExportFormat.xlsx =>
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ExportFormat.csv => 'text/csv',
      };

  String get label => switch (this) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.xlsx => 'Excel',
        ExportFormat.csv => 'CSV',
      };
}

/// Tipo de celda para el libro de Excel.
enum XlsxCellType { text, number, integer, money, liters, date }

class XlsxColumn {
  const XlsxColumn(this.header, {this.type = XlsxCellType.text, this.width = 16});
  final String header;
  final XlsxCellType type;
  final double width;
}

/// Hoja tabular genérica (sirve para Excel y CSV).
class TableSheet {
  const TableSheet({
    required this.name,
    required this.columns,
    required this.rows,
    this.title,
    this.subtitle,
    this.totals,
    this.charts = const <XlsxChart>[],
  });

  /// Gráficas nativas de Excel construidas sobre las filas de esta hoja.
  final List<XlsxChart> charts;

  final String name;
  final String? title;
  final String? subtitle;
  final List<XlsxColumn> columns;
  final List<List<Object?>> rows;

  /// Fila opcional de totales (mismo largo que [columns]).
  final List<Object?>? totals;
}

enum XlsxChartType { bar, horizontalBar, line, pie }

/// Gráfica nativa de Excel (DrawingML). Las categorías salen de la columna
/// [categoryColumn] y cada serie de una columna de [seriesColumns] de la
/// misma hoja, en las filas de datos (sin la fila de totales).
class XlsxChart {
  const XlsxChart({
    required this.type,
    required this.title,
    this.categoryColumn = 0,
    required this.seriesColumns,
  });

  final XlsxChartType type;
  final String title;
  final int categoryColumn;
  final List<int> seriesColumns;
}

/// Generador de .xlsx (Office Open XML) sin dependencias nativas.
class XlsxBuilder {
  XlsxBuilder._();

  static Uint8List build(List<TableSheet> sheets) {
    final Archive archive = Archive();
    void add(String path, String content) {
      final List<int> bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );

    final StringBuffer wb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>',
    );
    final StringBuffer wbRels = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    final StringBuffer overrides = StringBuffer();
    final Set<String> usedNames = <String>{};
    int drawingCount = 0;
    int chartCount = 0;
    for (int i = 0; i < sheets.length; i++) {
      String name = sheets[i].name.replaceAll(RegExp(r'[\/?*\[\]:]'), ' ').trim();
      if (name.isEmpty) name = 'Hoja ${i + 1}';
      if (name.length > 31) name = name.substring(0, 31);
      while (usedNames.contains(name)) {
        name = '${name.substring(0, name.length.clamp(0, 28))}_${i + 1}';
      }
      usedNames.add(name);
      wb.write('<sheet name="${_esc(name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
      wbRels.write('<Relationship Id="rId${i + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet${i + 1}.xml"/>');
      overrides.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');

      final TableSheet sheet = sheets[i];
      final List<XlsxChart> charts = sheet.rows.isEmpty
          ? const <XlsxChart>[]
          : sheet.charts
              .where((XlsxChart c) =>
                  c.seriesColumns.isNotEmpty &&
                  c.categoryColumn < sheet.columns.length &&
                  c.seriesColumns.every((int col) => col < sheet.columns.length))
              .toList();
      final bool hasDrawing = charts.isNotEmpty;
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheet, withDrawing: hasDrawing));
      if (!hasDrawing) continue;

      drawingCount++;
      final int d = drawingCount;
      add(
        'xl/worksheets/_rels/sheet${i + 1}.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" '
            'Target="../drawings/drawing$d.xml"/></Relationships>',
      );
      overrides.write('<Override PartName="/xl/drawings/drawing$d.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>');

      final int headerRow = _headerRow(sheet);
      final StringBuffer drawing = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">',
      );
      final StringBuffer drawingRels = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
      );
      final int anchorCol = sheet.columns.length + 1;
      for (int k = 0; k < charts.length; k++) {
        chartCount++;
        final int fromRow = headerRow - 1 + k * 20;
        drawing.write('<xdr:twoCellAnchor editAs="oneCell">'
            '<xdr:from><xdr:col>$anchorCol</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>$fromRow</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
            '<xdr:to><xdr:col>${anchorCol + 9}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${fromRow + 18}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
            '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="${k + 2}" name="Gráfica ${k + 1}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
            '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
            '<c:chart r:id="rId${k + 1}"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>');
        drawingRels.write('<Relationship Id="rId${k + 1}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" '
            'Target="../charts/chart$chartCount.xml"/>');
        overrides.write('<Override PartName="/xl/charts/chart$chartCount.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>');
        add('xl/charts/chart$chartCount.xml', _chartXml(sheet, name, headerRow, charts[k]));
      }
      drawing.write('</xdr:wsDr>');
      drawingRels.write('</Relationships>');
      add('xl/drawings/drawing$d.xml', drawing.toString());
      add('xl/drawings/_rels/drawing$d.xml.rels', drawingRels.toString());
    }
    wb.write('</sheets></workbook>');
    wbRels.write('<Relationship Id="rId${sheets.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/></Relationships>');
    add('xl/workbook.xml', wb.toString());
    add('xl/_rels/workbook.xml.rels', wbRels.toString());
    add('xl/styles.xml', _stylesXml);
    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '$overrides</Types>',
    );

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // Estilos: 0 normal · 1 encabezado · 2 número 2 dec · 3 entero · 4 moneda
  // · 5 título · 6 subtítulo · 7 total texto · 8 total moneda · 9 total número
  static const String _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="2">'
      '<numFmt numFmtId="164" formatCode="&quot;\$&quot;\\ #,##0"/>'
      '<numFmt numFmtId="165" formatCode="#,##0.00"/>'
      '</numFmts>'
      '<fonts count="5">'
      '<font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><color rgb="FF0B3B37"/><name val="Calibri"/></font>'
      '<font><sz val="10"/><color rgb="FF4B5B61"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font>'
      '</fonts>'
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF0F766E"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFE7F5F2"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left/><right/><top style="thin"><color rgb="FF0F766E"/></top><bottom/><diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="10">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
      '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="164" fontId="4" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      '<xf numFmtId="165" fontId="4" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      '</cellXfs>'
      '</styleSheet>';

  /// Fila (1-based) del encabezado de columnas.
  static int _headerRow(TableSheet sheet) =>
      (sheet.title != null ? 1 : 0) +
      (sheet.subtitle != null ? 1 : 0) +
      ((sheet.title != null || sheet.subtitle != null) ? 1 : 0) +
      1;

  static String _sheetXml(TableSheet sheet, {bool withDrawing = false}) {
    final StringBuffer sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    );
    int row = 1;
    final int headerRow = _headerRow(sheet);
    sb.write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="$headerRow" topLeftCell="A${headerRow + 1}" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
    sb.write('<cols>');
    for (int c = 0; c < sheet.columns.length; c++) {
      sb.write('<col min="${c + 1}" max="${c + 1}" width="${sheet.columns[c].width}" customWidth="1"/>');
    }
    sb.write('</cols><sheetData>');

    if (sheet.title != null) {
      sb.write('<row r="$row">${_str('A$row', sheet.title!, 5)}</row>');
      row++;
    }
    if (sheet.subtitle != null) {
      sb.write('<row r="$row">${_str('A$row', sheet.subtitle!, 6)}</row>');
      row++;
    }
    if (sheet.title != null || sheet.subtitle != null) row++;

    sb.write('<row r="$row">');
    for (int c = 0; c < sheet.columns.length; c++) {
      sb.write(_str('${_col(c)}$row', sheet.columns[c].header, 1));
    }
    sb.write('</row>');
    row++;

    for (final List<Object?> values in sheet.rows) {
      sb.write('<row r="$row">');
      for (int c = 0; c < sheet.columns.length; c++) {
        final Object? v = c < values.length ? values[c] : null;
        sb.write(_cell('${_col(c)}$row', v, sheet.columns[c].type, false));
      }
      sb.write('</row>');
      row++;
    }
    if (sheet.totals != null) {
      sb.write('<row r="$row">');
      for (int c = 0; c < sheet.columns.length; c++) {
        final Object? v = c < sheet.totals!.length ? sheet.totals![c] : null;
        sb.write(_cell('${_col(c)}$row', v, sheet.columns[c].type, true));
      }
      sb.write('</row>');
    }
    sb.write('</sheetData>');
    final int lastDataRow = row - (sheet.totals != null ? 0 : 1);
    if (sheet.rows.isNotEmpty) {
      sb.write('<autoFilter ref="A$headerRow:${_col(sheet.columns.length - 1)}${lastDataRow > headerRow ? lastDataRow : headerRow}"/>');
    }
    if (withDrawing) sb.write('<drawing r:id="rId1"/>');
    sb.write('</worksheet>');
    return sb.toString();
  }

  static const List<String> _chartColors = <String>['0F766E', 'E59E0B', '4F6BED', 'E15D7A', '7C8B91', '14B8A6', '9A5B00', '1E40AF'];

  static String _num(Object? v) => v is num && v.isFinite ? v.toString() : '0';

  /// Gráfica DrawingML con referencias a la hoja y valores en caché
  /// (Excel la muestra de inmediato y se actualiza si se editan las celdas).
  static String _chartXml(TableSheet sheet, String sheetName, int headerRow, XlsxChart chart) {
    final String q = "'${sheetName.replaceAll("'", "''")}'";
    final int first = headerRow + 1;
    final int last = headerRow + sheet.rows.length;
    final int n = sheet.rows.length;
    String ref(int col, int a, int b) => '$q!\$${_col(col)}\$$a:\$${_col(col)}\$$b';

    final StringBuffer cat = StringBuffer('<c:cat><c:strRef><c:f>${_esc(ref(chart.categoryColumn, first, last))}</c:f>'
        '<c:strCache><c:ptCount val="$n"/>');
    for (int r = 0; r < n; r++) {
      final List<Object?> row = sheet.rows[r];
      final Object? v = chart.categoryColumn < row.length ? row[chart.categoryColumn] : null;
      cat.write('<c:pt idx="$r"><c:v>${_esc(v?.toString() ?? '')}</c:v></c:pt>');
    }
    cat.write('</c:strCache></c:strRef></c:cat>');

    final bool pie = chart.type == XlsxChartType.pie;
    final bool line = chart.type == XlsxChartType.line;
    final StringBuffer series = StringBuffer();
    final List<int> cols = pie ? chart.seriesColumns.take(1).toList() : chart.seriesColumns;
    for (int s = 0; s < cols.length; s++) {
      final int col = cols[s];
      final String color = _chartColors[s % _chartColors.length];
      series.write('<c:ser><c:idx val="$s"/><c:order val="$s"/>'
          '<c:tx><c:strRef><c:f>${_esc('$q!\$${_col(col)}\$$headerRow')}</c:f>'
          '<c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>${_esc(sheet.columns[col].header)}</c:v></c:pt></c:strCache></c:strRef></c:tx>');
      if (pie) {
        for (int r = 0; r < n; r++) {
          series.write('<c:dPt><c:idx val="$r"/><c:bubble3D val="0"/><c:spPr><a:solidFill>'
              '<a:srgbClr val="${_chartColors[r % _chartColors.length]}"/></a:solidFill></c:spPr></c:dPt>');
        }
        series.write('<c:dLbls><c:numFmt formatCode="0.0%" sourceLinked="0"/><c:showLegendKey val="0"/><c:showVal val="0"/>'
            '<c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="1"/><c:showBubbleSize val="0"/></c:dLbls>');
      } else if (line) {
        series.write('<c:spPr><a:ln w="28575"><a:solidFill><a:srgbClr val="$color"/></a:solidFill></a:ln></c:spPr>'
            '<c:marker><c:symbol val="circle"/><c:size val="5"/></c:marker>');
      } else {
        series.write('<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill></c:spPr><c:invertIfNegative val="0"/>');
      }
      series.write(cat);
      series.write('<c:val><c:numRef><c:f>${_esc(ref(col, first, last))}</c:f>'
          '<c:numCache><c:formatCode>General</c:formatCode><c:ptCount val="$n"/>');
      for (int r = 0; r < n; r++) {
        final List<Object?> row = sheet.rows[r];
        series.write('<c:pt idx="$r"><c:v>${_num(col < row.length ? row[col] : null)}</c:v></c:pt>');
      }
      series.write('</c:numCache></c:numRef></c:val>');
      if (line) series.write('<c:smooth val="0"/>');
      series.write('</c:ser>');
    }

    const String axes = '<c:catAx><c:axId val="5001"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
        '<c:axPos val="b"/><c:numFmt formatCode="General" sourceLinked="0"/><c:tickLblPos val="nextTo"/>'
        '<c:crossAx val="5002"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/></c:catAx>'
        '<c:valAx><c:axId val="5002"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
        '<c:axPos val="l"/><c:majorGridlines><c:spPr><a:ln w="6350"><a:solidFill><a:srgbClr val="E2E7EA"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>'
        '<c:numFmt formatCode="#,##0" sourceLinked="0"/><c:tickLblPos val="nextTo"/><c:crossAx val="5001"/>'
        '<c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>';

    final String plot = switch (chart.type) {
      XlsxChartType.pie => '<c:pieChart><c:varyColors val="1"/>$series<c:firstSliceAng val="0"/></c:pieChart>',
      XlsxChartType.line => '<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>$series'
          '<c:marker val="1"/><c:axId val="5001"/><c:axId val="5002"/></c:lineChart>$axes',
      _ => '<c:barChart><c:barDir val="${chart.type == XlsxChartType.horizontalBar ? 'bar' : 'col'}"/>'
          '<c:grouping val="clustered"/><c:varyColors val="0"/>$series<c:gapWidth val="80"/>'
          '<c:axId val="5001"/><c:axId val="5002"/></c:barChart>$axes',
    };
    final bool legend = pie || cols.length > 1;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<c:roundedCorners val="0"/>'
        '<c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1300" b="1"/></a:pPr>'
        '<a:r><a:rPr lang="es-CO" sz="1300" b="1"/><a:t>${_esc(chart.title)}</a:t></a:r></a:p></c:rich></c:tx>'
        '<c:overlay val="0"/></c:title>'
        '<c:autoTitleDeleted val="0"/><c:plotArea><c:layout/>$plot</c:plotArea>'
        '${legend ? '<c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>' : ''}'
        '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>';
  }

  static String _cell(String ref, Object? v, XlsxCellType type, bool total) {
    if (v == null) {
      return total ? '<c r="$ref" s="7"/>' : '';
    }
    if (v is num && v.isFinite && type != XlsxCellType.text && type != XlsxCellType.date) {
      final int style = switch (type) {
        XlsxCellType.money => total ? 8 : 4,
        XlsxCellType.integer => total ? 9 : 3,
        _ => total ? 9 : 2,
      };
      return '<c r="$ref" s="$style"><v>$v</v></c>';
    }
    return _str(ref, v.toString(), total ? 7 : 0);
  }

  static String _str(String ref, String text, int style) =>
      '<c r="$ref" t="inlineStr" s="$style"><is><t xml:space="preserve">${_esc(text)}</t></is></c>';

  static String _col(int index) {
    String s = '';
    int n = index + 1;
    while (n > 0) {
      final int m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
}

/// CSV UTF-8 con BOM y separador ";" (Excel en español lo abre directo).
class CsvBuilder {
  CsvBuilder._();

  static Uint8List build(TableSheet sheet) {
    final StringBuffer sb = StringBuffer('﻿');
    String esc(Object? v) {
      if (v == null) return '';
      String s;
      if (v is double) {
        s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',');
      } else {
        s = v.toString();
      }
      // Neutraliza inyección de fórmulas al abrir en Excel.
      if (s.isNotEmpty && '=+-@'.contains(s[0]) && v is! num) s = "'$s";
      if (s.contains(';') || s.contains('"') || s.contains('\n')) {
        s = '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    sb.writeln(sheet.columns.map((XlsxColumn c) => esc(c.header)).join(';'));
    for (final List<Object?> r in sheet.rows) {
      sb.writeln(r.map(esc).join(';'));
    }
    if (sheet.totals != null) sb.writeln(sheet.totals!.map(esc).join(';'));
    return Uint8List.fromList(utf8.encode(sb.toString()));
  }
}

/// Resultado de guardar un archivo en disco.
class SavedFile {
  const SavedFile(this.path);
  final String path;
  String get directory => File(path).parent.path;
}

/// Guarda o comparte archivos generados de forma uniforme en escritorio y móvil.
class FileExportService {
  FileExportService._();

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Nombre de archivo seguro: sin tildes problemáticas ni caracteres prohibidos.
  static String safeFileName(String base, ExportFormat format) {
    final String clean = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final String trimmed = clean.length > 80 ? clean.substring(0, 80) : clean;
    return '$trimmed.${format.extension}';
  }

  /// Guarda en Descargas (escritorio) o en documentos de la app (móvil).
  static Future<SavedFile> save(Uint8List bytes, String fileName) async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {
      dir = null;
    }
    dir ??= await getApplicationDocumentsDirectory();
    final Directory target = Directory('${dir.path}${Platform.pathSeparator}ASOPROGANUCOTT');
    if (!target.existsSync()) target.createSync(recursive: true);
    String path = '${target.path}${Platform.pathSeparator}$fileName';
    int n = 1;
    while (File(path).existsSync()) {
      final int dot = fileName.lastIndexOf('.');
      final String name = dot > 0 ? fileName.substring(0, dot) : fileName;
      final String ext = dot > 0 ? fileName.substring(dot) : '';
      path = '${target.path}${Platform.pathSeparator}$name ($n)$ext';
      n++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return SavedFile(path);
  }

  /// Abre el diálogo nativo "Compartir en…" (WhatsApp, correo, Drive, etc.).
  static Future<void> share(
    Uint8List bytes,
    String fileName, {
    required String mimeType,
    String? text,
    String? subject,
  }) async {
    final Directory tmp = await getTemporaryDirectory();
    final File f = File('${tmp.path}${Platform.pathSeparator}$fileName');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(f.path, mimeType: mimeType, name: fileName)],
        text: text,
        subject: subject,
      ),
    );
  }

  /// Muestra el archivo guardado en el explorador del sistema.
  static Future<void> reveal(SavedFile file) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', <String>['/select,', file.path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>['-R', file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', <String>[file.directory]);
      }
    } catch (_) {}
  }
}
