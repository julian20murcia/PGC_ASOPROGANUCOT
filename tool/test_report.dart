// Informe consolidado de pruebas (para el resumen de GitHub Actions y el
// documento del trabajo de grado).
//
// Lee la carpeta de resultados descargada de los jobs:
//   <tipo>__*.json  → reporter JSON de `flutter test --file-reporter json:...`
//   <tipo>__*.xml   → reporter JUnit de `node --test --test-reporter=junit`
//   <tipo>__*.log   → salida de consola (se extraen las líneas `METRICA {...}`)
//   *.md            → secciones extra (cobertura, búsqueda de secretos, auditoría)
// donde <tipo> ∈ caja-blanca | caja-negra | seguridad | estres | integracion.
//
// Uso: dart run tool/test_report.dart <carpeta_resultados> <salida.md>
import 'dart:convert';
import 'dart:io';

class Suite {
  Suite(this.tipo, this.nombre);
  final String tipo;
  final String nombre;
  final List<(String, bool)> casos = <(String, bool)>[];
  int ms = 0;
  int get pasaron => casos.where(((String, bool) c) => c.$2).length;
  int get fallaron => casos.length - pasaron;
}

const Map<String, String> kTipos = <String, String>{
  'caja-blanca': 'Caja blanca (unitarias, widgets y cobertura)',
  'caja-negra': 'Caja negra (particiones de equivalencia y valores límite)',
  'seguridad': 'Seguridad (reglas de acceso, entradas maliciosas, secretos, dependencias)',
  'estres': 'Estrés y rendimiento (carga y tiempos de respuesta)',
  'integracion': 'Integración (Cloud Functions + Auth + Firestore emulados)',
};

const Map<String, String> kTecnica = <String, String>{
  'caja-blanca': 'Pruebas unitarias y de widgets con conocimiento del código; cobertura de líneas medida con `lcov`.',
  'caja-negra': 'Casos diseñados desde los requisitos (RF) sin mirar la implementación: clases válidas/inválidas y límites.',
  'seguridad': 'Ataques simulados contra `firestore.rules` en el emulador oficial, fuzzing de entradas del asistente IA, escaneo de secretos y `npm audit`.',
  'estres': 'Volúmenes ≈ 17× la operación anual real (122.000 entregas, 1.000 productores, 300.000 registros en backend) con presupuesto de tiempo.',
  'integracion': 'Funciones reales del backend ejecutadas contra Firebase Auth y Firestore emulados, verificando reglas, auditoría y cierre.',
};

String tipoDe(String fileName) {
  final int i = fileName.indexOf('__');
  return i > 0 ? fileName.substring(0, i) : 'otros';
}

void parseFlutterJson(File f, String tipo, Map<String, Suite> suites, List<Map<String, dynamic>> metricas) {
  final Map<int, String> suitePath = <int, String>{};
  final Map<int, (String, int, int)> tests = <int, (String, int, int)>{}; // id → (nombre, suite, inicio)
  for (final String line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final dynamic e;
    try {
      e = jsonDecode(line);
    } catch (_) {
      continue;
    }
    if (e is! Map) continue;
    switch (e['type']) {
      case 'suite':
        suitePath[e['suite']['id'] as int] = (e['suite']['path'] ?? '').toString();
      case 'testStart':
        final Map<dynamic, dynamic> t = e['test'] as Map<dynamic, dynamic>;
        tests[t['id'] as int] = ((t['name'] ?? '').toString(), t['suiteID'] as int, e['time'] as int);
      case 'print':
        final String msg = (e['message'] ?? '').toString();
        final int k = msg.indexOf('METRICA ');
        if (k >= 0) {
          try {
            metricas.add(jsonDecode(msg.substring(k + 8)) as Map<String, dynamic>);
          } catch (_) {}
        }
      case 'testDone':
        if (e['hidden'] == true || e['skipped'] == true) break;
        final (String, int, int)? t = tests[e['testID'] as int];
        if (t == null || t.$1.startsWith('loading ')) break;
        String path = suitePath[t.$2] ?? 'suite';
        final int lib = path.replaceAll(r'\', '/').lastIndexOf('test/');
        if (lib >= 0) path = path.replaceAll(r'\', '/').substring(lib);
        final Suite s = suites.putIfAbsent('$tipo|$path', () => Suite(tipo, path));
        s.casos.add((t.$1, e['result'] == 'success'));
        s.ms += (e['time'] as int) - t.$3;
    }
  }
}

void parseJUnit(File f, String tipo, Map<String, Suite> suites) {
  final String xml = f.readAsStringSync();
  final RegExp tc = RegExp(r'<testcase\b([^>]*?)(/>|>([\s\S]*?)</testcase>)');
  String attr(String attrs, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1)?.replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>') ?? '';
  final String name = f.uri.pathSegments.last.split('__').last.replaceAll('.xml', '');
  final Suite s = suites.putIfAbsent('$tipo|$name', () => Suite(tipo, 'functions/test · $name'));
  for (final RegExpMatch m in tc.allMatches(xml)) {
    final String attrs = m.group(1) ?? '';
    final String body = m.group(3) ?? '';
    final String clase = attr(attrs, 'classname');
    final String caso = attr(attrs, 'name');
    final bool ok = !body.contains('<failure') && !body.contains('<error');
    s.casos.add((clase.isEmpty || clase == 'test' ? caso : '$clase › $caso', ok));
    s.ms += ((double.tryParse(attr(attrs, 'time')) ?? 0) * 1000).round();
  }
}

void main(List<String> args) {
  final Directory dir = Directory(args.isNotEmpty ? args[0] : 'resultados');
  final File out = File(args.length > 1 ? args[1] : 'informe_pruebas.md');
  final Map<String, Suite> suites = <String, Suite>{};
  final List<Map<String, dynamic>> metricas = <Map<String, dynamic>>[];
  final List<String> extras = <String>[];

  final List<File> files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  for (final File f in files) {
    final String name = f.uri.pathSegments.last;
    final String tipo = tipoDe(name);
    if (name.endsWith('.json')) {
      parseFlutterJson(f, tipo, suites, metricas);
    } else if (name.endsWith('.xml')) {
      parseJUnit(f, tipo, suites);
    } else if (name.endsWith('.log')) {
      for (final String line in f.readAsLinesSync()) {
        final int k = line.indexOf('METRICA ');
        if (k < 0) continue;
        try {
          metricas.add(jsonDecode(line.substring(k + 8)) as Map<String, dynamic>);
        } catch (_) {}
      }
    } else if (name.endsWith('.md')) {
      extras.add(f.readAsStringSync());
    }
  }

  int totalCasos = 0;
  int totalOk = 0;
  final StringBuffer md = StringBuffer()
    ..writeln('# Informe de pruebas — ASOPROGANUCOTT')
    ..writeln()
    ..writeln('Generado automáticamente por GitHub Actions el '
        '${DateTime.now().toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC'
        '${Platform.environment['GITHUB_SHA'] != null ? ' · commit `${Platform.environment['GITHUB_SHA']!.substring(0, 7)}`' : ''}.')
    ..writeln()
    ..writeln('## Resumen por tipo de prueba')
    ..writeln()
    ..writeln('| Tipo de prueba | Suites | Casos | Aprobados | Fallidos | Resultado |')
    ..writeln('|---|---:|---:|---:|---:|:---:|');
  for (final String tipo in kTipos.keys) {
    final List<Suite> ss = suites.values.where((Suite s) => s.tipo == tipo).toList();
    final int casos = ss.fold<int>(0, (int a, Suite s) => a + s.casos.length);
    final int ok = ss.fold<int>(0, (int a, Suite s) => a + s.pasaron);
    totalCasos += casos;
    totalOk += ok;
    final String res = casos == 0 ? '⚠️ sin datos' : (ok == casos ? '✅ Aprobado' : '❌ Falló');
    md.writeln('| ${kTipos[tipo]} | ${ss.length} | $casos | $ok | ${casos - ok} | $res |');
  }
  md
    ..writeln('| **Total** | ${suites.length} | **$totalCasos** | **$totalOk** | **${totalCasos - totalOk}** | '
        '${totalCasos > 0 && totalOk == totalCasos ? '✅' : '❌'} |')
    ..writeln();

  for (final String tipo in kTipos.keys) {
    final List<Suite> ss = suites.values.where((Suite s) => s.tipo == tipo).toList()
      ..sort((Suite a, Suite b) => a.nombre.compareTo(b.nombre));
    if (ss.isEmpty) continue;
    md
      ..writeln('## ${kTipos[tipo]}')
      ..writeln()
      ..writeln('**Técnica:** ${kTecnica[tipo]}')
      ..writeln()
      ..writeln('| Suite | Casos | Aprobados | Duración |')
      ..writeln('|---|---:|---:|---:|');
    for (final Suite s in ss) {
      md.writeln('| `${s.nombre}` | ${s.casos.length} | ${s.pasaron} | ${(s.ms / 1000).toStringAsFixed(1)} s |');
    }
    md
      ..writeln()
      ..writeln('<details><summary>Ver los ${ss.fold<int>(0, (int a, Suite s) => a + s.casos.length)} casos</summary>')
      ..writeln();
    for (final Suite s in ss) {
      md.writeln('**${s.nombre}**');
      md.writeln();
      for (final (String, bool) c in s.casos) {
        md.writeln('- ${c.$2 ? '✅' : '❌'} ${c.$1.replaceAll('|', '/')}');
      }
      md.writeln();
    }
    md
      ..writeln('</details>')
      ..writeln();
    if (tipo == 'estres' && metricas.isNotEmpty) {
      md
        ..writeln('### Tiempos medidos bajo carga')
        ..writeln()
        ..writeln('| Escenario | Tiempo | Presupuesto | Margen |')
        ..writeln('|---|---:|---:|---:|');
      for (final Map<String, dynamic> m in metricas) {
        final num ms = (m['ms'] as num?) ?? 0;
        final num budget = (m['presupuesto_ms'] as num?) ?? 0;
        final String margen = ms == 0 ? '—' : '${(budget / ms).toStringAsFixed(1)}×';
        md.writeln('| ${m['prueba']} | $ms ms | $budget ms | $margen |');
      }
      md.writeln();
    }
  }

  if (extras.isNotEmpty) {
    md
      ..writeln('## Evidencias adicionales')
      ..writeln();
    for (final String e in extras) {
      md
        ..writeln(e.trim())
        ..writeln();
    }
  }

  out.writeAsStringSync(md.toString());
  stdout.writeln('Informe: ${out.path} · $totalOk/$totalCasos casos aprobados');
  if (totalCasos == 0 || totalOk != totalCasos) exitCode = 1;
}
