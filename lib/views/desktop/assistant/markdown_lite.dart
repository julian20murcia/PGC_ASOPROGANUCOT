import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Tipos de bloque soportados por el render ligero de markdown.
enum MdBlockType { heading, paragraph, bullet, ordered, table, code, rule }

class MdBlock {
  const MdBlock(this.type, {this.text = '', this.level = 0, this.number = 0, this.rows = const <List<String>>[]});
  final MdBlockType type;
  final String text;

  /// Nivel de encabezado (1–6) o sangría de la lista.
  final int level;
  final int number;
  final List<List<String>> rows;
}

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$');
final RegExp _ordered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final RegExp _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final RegExp _tableSep = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

List<String> _cells(String line) {
  String l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|')) l = l.substring(0, l.length - 1);
  return l.split('|').map((String c) => c.trim()).toList();
}

/// Convierte texto markdown sencillo en bloques. Nunca lanza excepciones.
List<MdBlock> parseMarkdownLite(String source) {
  final List<String> lines = source.replaceAll('\r\n', '\n').split('\n');
  final List<MdBlock> out = <MdBlock>[];
  final List<String> para = <String>[];

  void flushPara() {
    if (para.isNotEmpty) {
      out.add(MdBlock(MdBlockType.paragraph, text: para.join('\n')));
      para.clear();
    }
  }

  int i = 0;
  while (i < lines.length) {
    final String line = lines[i];
    final String trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      flushPara();
      final List<String> code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      out.add(MdBlock(MdBlockType.code, text: code.join('\n')));
      i++; // cierre
      continue;
    }
    if (trimmed.isEmpty) {
      flushPara();
      i++;
      continue;
    }
    if (trimmed.startsWith('|')) {
      flushPara();
      final List<List<String>> rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        if (!_tableSep.hasMatch(lines[i].trim())) rows.add(_cells(lines[i]));
        i++;
      }
      if (rows.isNotEmpty) {
        int cols = 0;
        for (final List<String> r in rows) {
          if (r.length > cols) cols = r.length;
        }
        out.add(MdBlock(
          MdBlockType.table,
          rows: <List<String>>[
            for (final List<String> r in rows) <String>[...r, for (int k = r.length; k < cols; k++) ''],
          ],
        ));
      }
      continue;
    }
    final RegExpMatch? h = _heading.firstMatch(trimmed);
    if (h != null) {
      flushPara();
      out.add(MdBlock(MdBlockType.heading, text: h.group(2)!.trim(), level: h.group(1)!.length));
      i++;
      continue;
    }
    if (_rule.hasMatch(trimmed)) {
      flushPara();
      out.add(const MdBlock(MdBlockType.rule));
      i++;
      continue;
    }
    final RegExpMatch? b = _bullet.firstMatch(line);
    if (b != null) {
      flushPara();
      out.add(MdBlock(MdBlockType.bullet, text: b.group(2)!.trim(), level: (b.group(1)!.length ~/ 2).clamp(0, 3)));
      i++;
      continue;
    }
    final RegExpMatch? o = _ordered.firstMatch(line);
    if (o != null) {
      flushPara();
      out.add(MdBlock(
        MdBlockType.ordered,
        text: o.group(3)!.trim(),
        number: int.tryParse(o.group(2)!) ?? 1,
        level: (o.group(1)!.length ~/ 2).clamp(0, 3),
      ));
      i++;
      continue;
    }
    para.add(trimmed);
    i++;
  }
  flushPara();
  return out;
}

final RegExp _inline = RegExp(r'(\*\*[^*\n]+?\*\*|__[^_\n]+?__|`[^`\n]+`|\*[^*\s][^*\n]*?\*)');

/// Convierte **negritas**, *cursivas* y `código` en spans.
List<InlineSpan> inlineSpans(String text, TextStyle base) {
  final List<InlineSpan> spans = <InlineSpan>[];
  int last = 0;
  for (final RegExpMatch m in _inline.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final String t = m.group(0)!;
    if (t.startsWith('**') || t.startsWith('__')) {
      spans.add(TextSpan(text: t.substring(2, t.length - 2), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)));
    } else if (t.startsWith('`')) {
      spans.add(TextSpan(
        text: t.substring(1, t.length - 1),
        style: AppTheme.monoStyle(fontSize: (base.fontSize ?? 14) - 1, color: AppTheme.brandDeep)
            .copyWith(backgroundColor: AppTheme.surfaceSunken),
      ));
    } else {
      spans.add(TextSpan(text: t.substring(1, t.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Render ligero de markdown para respuestas del asistente.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.data, {super.key, this.fontSize = 14});
  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = AppTheme.bodyStyle(fontSize: fontSize, color: AppTheme.textPrimary, height: 1.55);
    final List<MdBlock> blocks = parseMarkdownLite(data);
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < blocks.length; i++) {
      final MdBlock b = blocks[i];
      final bool listItem = b.type == MdBlockType.bullet || b.type == MdBlockType.ordered;
      final bool prevList = i > 0 && (blocks[i - 1].type == MdBlockType.bullet || blocks[i - 1].type == MdBlockType.ordered);
      if (i > 0) children.add(SizedBox(height: listItem && prevList ? 3 : 10));
      children.add(_block(b, base));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _block(MdBlock b, TextStyle base) {
    switch (b.type) {
      case MdBlockType.heading:
        final double size = switch (b.level) { 1 => fontSize + 4, 2 => fontSize + 2, _ => fontSize + 0.5 };
        return Text.rich(
          TextSpan(children: inlineSpans(b.text, base)),
          style: base.copyWith(fontSize: size, fontWeight: FontWeight.w700, height: 1.3),
        );
      case MdBlockType.paragraph:
        return Text.rich(TextSpan(children: inlineSpans(b.text, base)), style: base);
      case MdBlockType.bullet:
      case MdBlockType.ordered:
        return Padding(
          padding: EdgeInsets.only(left: 4.0 + b.level * 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: b.type == MdBlockType.ordered ? 22 : 16,
                child: b.type == MdBlockType.ordered
                    ? Text('${b.number}.', style: AppTheme.monoStyle(fontSize: fontSize - 0.5, color: AppTheme.brand, fontWeight: FontWeight.w600, height: 1.55))
                    : Padding(
                        padding: EdgeInsets.only(top: fontSize * 0.62),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(color: AppTheme.brand, shape: BoxShape.circle),
                        ),
                      ),
              ),
              Expanded(child: Text.rich(TextSpan(children: inlineSpans(b.text, base)), style: base)),
            ],
          ),
        );
      case MdBlockType.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSunken,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppTheme.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(b.text, style: AppTheme.monoStyle(fontSize: fontSize - 1.5, color: AppTheme.brandInk, height: 1.45)),
          ),
        );
      case MdBlockType.rule:
        return const Divider(height: 8);
      case MdBlockType.table:
        final bool header = b.rows.length > 1;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            clipBehavior: Clip.antiAlias,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppTheme.dividerLight),
                verticalInside: BorderSide(color: AppTheme.dividerLight),
              ),
              children: <TableRow>[
                for (int r = 0; r < b.rows.length; r++)
                  TableRow(
                    decoration: BoxDecoration(color: header && r == 0 ? AppTheme.surfaceMuted : null),
                    children: <Widget>[
                      for (final String cell in b.rows[r])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text.rich(
                              TextSpan(children: inlineSpans(cell, base)),
                              style: header && r == 0
                                  ? base.copyWith(fontSize: fontSize - 1, fontWeight: FontWeight.w600, height: 1.3)
                                  : base.copyWith(fontSize: fontSize - 1, height: 1.35),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
    }
  }
}
