// Resumen de cobertura de código (pruebas de caja blanca).
//
// Lee coverage/lcov.info, calcula la cobertura de líneas total y por capa
// (lib/core, lib/controllers, lib/models, lib/views) y la escribe en
// Markdown. Falla (código 1) si la cobertura de la lógica de negocio
// (lib/core + lib/controllers + lib/models) queda por debajo del mínimo.
//
// Uso: dart run tool/coverage_summary.dart [lcov.info] [salida.md] [minimo%]
import 'dart:io';

void main(List<String> args) {
  final String lcovPath = args.isNotEmpty ? args[0] : 'coverage/lcov.info';
  final String? outPath = args.length > 1 ? args[1] : null;
  final double minimum = args.length > 2 ? double.parse(args[2]) : 0;

  final Map<String, int> total = <String, int>{};
  final Map<String, int> hit = <String, int>{};
  final Map<String, (int, int)> perFile = <String, (int, int)>{};
  String? file;
  for (final String line in File(lcovPath).readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      file = line.substring(3).trim().replaceAll(r'\', '/');
      final int i = file.indexOf('lib/');
      if (i > 0) file = file.substring(i);
    } else if (line.startsWith('DA:') && file != null) {
      final bool covered = int.parse(line.split(',')[1]) > 0;
      final List<String> parts = file.split('/');
      final String layer = parts.length > 2 ? '${parts[0]}/${parts[1]}' : parts[0];
      for (final String k in <String>['TOTAL', layer]) {
        total[k] = (total[k] ?? 0) + 1;
        if (covered) hit[k] = (hit[k] ?? 0) + 1;
      }
      final (int h, int t) prev = perFile[file] ?? (0, 0);
      perFile[file] = (prev.$1 + (covered ? 1 : 0), prev.$2 + 1);
    }
  }

  double pct(String k) => (total[k] ?? 0) == 0 ? 0 : 100 * (hit[k] ?? 0) / total[k]!;
  int businessHit = 0;
  int businessTotal = 0;
  for (final String k in <String>['lib/core', 'lib/controllers', 'lib/models']) {
    businessHit += hit[k] ?? 0;
    businessTotal += total[k] ?? 0;
  }
  final double business = businessTotal == 0 ? 0 : 100 * businessHit / businessTotal;

  final StringBuffer md = StringBuffer()
    ..writeln('### Cobertura de código (caja blanca)')
    ..writeln()
    ..writeln('| Capa | Líneas cubiertas | Total | Cobertura |')
    ..writeln('|---|---:|---:|---:|');
  final List<String> layers = total.keys.where((String k) => k != 'TOTAL').toList()..sort();
  for (final String k in layers) {
    md.writeln('| `$k` | ${hit[k] ?? 0} | ${total[k]} | ${pct(k).toStringAsFixed(1)} % |');
  }
  md
    ..writeln('| **Lógica de negocio** (core + controllers + models) | $businessHit | $businessTotal | **${business.toStringAsFixed(1)} %** |')
    ..writeln('| **Total** | ${hit['TOTAL'] ?? 0} | ${total['TOTAL']} | **${pct('TOTAL').toStringAsFixed(1)} %** |')
    ..writeln()
    ..writeln('Mínimo exigido para la lógica de negocio: **${minimum.toStringAsFixed(0)} %**.')
    ..writeln();

  final List<MapEntry<String, (int, int)>> best = perFile.entries
      .where((MapEntry<String, (int, int)> e) => e.key.startsWith('lib/core') && e.value.$2 >= 40)
      .toList()
    ..sort((MapEntry<String, (int, int)> a, MapEntry<String, (int, int)> b) =>
        (b.value.$1 / b.value.$2).compareTo(a.value.$1 / a.value.$2));
  md
    ..writeln('<details><summary>Módulos críticos con mayor cobertura</summary>')
    ..writeln()
    ..writeln('| Archivo | Cobertura |')
    ..writeln('|---|---:|');
  for (final MapEntry<String, (int, int)> e in best.take(12)) {
    md.writeln('| `${e.key}` | ${(100 * e.value.$1 / e.value.$2).toStringAsFixed(1)} % |');
  }
  md.writeln('</details>');

  stdout.write(md);
  if (outPath != null) File(outPath).writeAsStringSync(md.toString());
  if (business < minimum) {
    stderr.writeln('::error::Cobertura de la lógica de negocio ${business.toStringAsFixed(1)} % < mínimo $minimum %.');
    exitCode = 1;
  }
}
