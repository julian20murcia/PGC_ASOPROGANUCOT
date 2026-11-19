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
  });

  final String name;
  final String? title;
  final String? subtitle;
  final List<XlsxColumn> columns;
  final List<List<Object?>> rows;

  /// Fila opcional de totales (mismo largo que [columns]).
  final List<Object?>? totals;
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

    final StringBuffer ct = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
    for (int i = 0; i < sheets.length; i++) {
      ct.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    ct.write('</Types>');
    add('[Content_Types].xml', ct.toString());

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
    final Set<String> usedNames = <String>{};
    for (int i = 0; i < sheets.length; i++) {
      String name = sheets[i].name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
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
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }
    wb.write('</sheets></workbook>');
    wbRels.write('<Relationship Id="rId${sheets.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/></Relationships>');
    add('xl/workbook.xml', wb.toString());
    add('xl/_rels/workbook.xml.rels', wbRels.toString());
    add('xl/styles.xml', _stylesXml);

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

  static String _sheetXml(TableSheet sheet) {
    final StringBuffer sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );
    int row = 1;
    final int headerRow = (sheet.title != null ? 1 : 0) + (sheet.subtitle != null ? 1 : 0) +
        ((sheet.title != null || sheet.subtitle != null) ? 1 : 0) + 1;
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
    sb.write('</worksheet>');
    return sb.toString();
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
