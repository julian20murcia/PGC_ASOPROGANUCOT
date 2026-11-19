import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/core/services/assistant_service.dart';
import 'package:pgc_asoproganucot/models/assistant_report.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/views/desktop/assistant/markdown_lite.dart';
import 'package:pgc_asoproganucot/views/desktop/assistant_module_view.dart';

class _FakeAssistant extends AssistantService {
  _FakeAssistant(this.handler, {this.report});
  final Future<String> Function(String q, List<AssistantMessage> history) handler;
  final AssistantReport? report;
  final List<String> questions = <String>[];
  final List<int> historyLengths = <int>[];

  @override
  Future<AssistantAnswer> ask(String question, {List<AssistantMessage> history = const <AssistantMessage>[]}) async {
    questions.add(question);
    historyLengths.add(history.length);
    return AssistantAnswer(await handler(question, history), report: report);
  }
}

Future<void> _pump(WidgetTester tester, AssistantService service, {Size size = const Size(1280, 720)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme().copyWith(splashFactory: InkRipple.splashFactory),
    home: Scaffold(body: AssistantModuleView(service: service)),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('parseMarkdownLite', () {
    test('reconoce encabezados, listas, tablas, código y párrafos', () {
      final List<MdBlock> b = parseMarkdownLite(
        '# Resumen\n'
        'Texto con **negrita** y `codigo`.\n'
        'segunda línea\n\n'
        '- uno\n'
        '  - anidado\n'
        '1. primero\n'
        '| Productor | Litros |\n'
        '|---|---:|\n'
        '| Ana | 120 |\n'
        '| Beto |\n'
        '```\nx = 1\n```\n'
        '---\n',
      );
      expect(b.map((MdBlock x) => x.type).toList(), <MdBlockType>[
        MdBlockType.heading,
        MdBlockType.paragraph,
        MdBlockType.bullet,
        MdBlockType.bullet,
        MdBlockType.ordered,
        MdBlockType.table,
        MdBlockType.code,
        MdBlockType.rule,
      ]);
      expect(b[0].level, 1);
      expect(b[1].text, 'Texto con **negrita** y `codigo`.\nsegunda línea');
      expect(b[3].level, 1);
      final MdBlock table = b[5];
      expect(table.rows.length, 3); // separador omitido
      expect(table.rows[2], <String>['Beto', '']); // filas normalizadas
      expect(b[6].text, 'x = 1');
    });

    test('entradas raras no lanzan', () {
      for (final String s in <String>['', '|', '```', '**', '#', '|---|', '* * *', '1.', 'a' * 5000]) {
        expect(() => parseMarkdownLite(s), returnsNormally);
      }
    });

    test('spans inline', () {
      final List<InlineSpan> spans = inlineSpans('a **b** c `d` *e*', const TextStyle(fontSize: 14));
      expect(spans.length, 6);
      expect((spans[1] as TextSpan).text, 'b');
      expect((spans[3] as TextSpan).text, 'd');
      expect((spans[5] as TextSpan).text, 'e');
    });
  });

  test('detección de límite de frecuencia', () {
    expect(AssistantModuleView.isRateLimitMessage('Alcanzaste el límite de preguntas por hora. Intenta más tarde.'), isTrue);
    expect(AssistantModuleView.isRateLimitMessage('El asistente alcanzó su cupo diario.'), isTrue);
    expect(AssistantModuleView.isRateLimitMessage('No hay conexión con el asistente.'), isFalse);
  });

  testWidgets('bienvenida con sugerencias, envío por chip y render de la respuesta', (WidgetTester tester) async {
    final Completer<String> answer = Completer<String>();
    final _FakeAssistant svc = _FakeAssistant((_, _) => answer.future);
    await _pump(tester, svc);

    expect(find.text('¿En qué te ayudo hoy?'), findsOneWidget);
    for (final String s in AssistantModuleView.suggestions) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text(AssistantModuleView.disclaimer), findsOneWidget);

    await tester.tap(find.text('¿Quién entregó más leche este mes?'));
    await tester.pump();
    expect(find.text('Pensando…'), findsOneWidget);
    expect(svc.questions, <String>['¿Quién entregó más leche este mes?']);

    answer.complete('## Top\n- **Ana**: 1.200 L\n| A | B |\n|---|---|\n| 1 | 2 |');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pensando…'), findsNothing);
    expect(find.text('Copiar'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Copiar al portapapeles.
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
      if (c.method == 'Clipboard.setData') clip = (c.arguments as Map<Object?, Object?>)['text'] as String?;
      return null;
    });
    await tester.tap(find.text('Copiar'));
    await tester.pump();
    expect(clip, contains('**Ana**'));
    await tester.pump(const Duration(seconds: 5));

    // Nueva conversación limpia todo.
    await tester.tap(find.text('Nueva conversación'));
    await tester.pump();
    expect(find.text('¿En qué te ayudo hoy?'), findsOneWidget);
  });

  testWidgets('límite de caracteres, contador y Enter envía con historial', (WidgetTester tester) async {
    final _FakeAssistant svc = _FakeAssistant((String q, _) async => 'Respuesta a $q');
    await _pump(tester, svc);

    final Finder input = find.byKey(const Key('assistant-input'));
    await tester.enterText(input, 'x' * 3000);
    await tester.pump();
    final TextField field = tester.widget<TextField>(input);
    expect(field.controller!.text.length, lessThanOrEqualTo(AssistantService.maxQuestionLength));
    expect(field.inputFormatters, isNotEmpty);

    await tester.enterText(input, 'Hola asistente');
    await tester.pump();
    expect(find.text('14/${AssistantService.maxQuestionLength}'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.questions.last, 'Hola asistente');
    expect(find.text('Respuesta a Hola asistente'), findsOneWidget);
    expect(find.text('0/${AssistantService.maxQuestionLength}'), findsOneWidget);

    await tester.enterText(input, 'Segunda');
    await tester.pump();
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(svc.historyLengths, <int>[0, 2]);
  });

  testWidgets('error genérico permite reintentar; límite muestra mensaje amable y pausa', (WidgetTester tester) async {
    int calls = 0;
    final _FakeAssistant svc = _FakeAssistant((_, _) async {
      calls++;
      if (calls == 1) throw AssistantException('No hay conexión con el asistente. Verifica tu internet.');
      if (calls == 2) throw AssistantException('Alcanzaste el límite de preguntas por hora. Intenta más tarde.');
      return 'ok';
    });
    await _pump(tester, svc);

    await tester.enterText(find.byKey(const Key('assistant-input')), 'Pregunta');
    await tester.pump();
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pump();
    await tester.pump();
    expect(find.text('No pude responder'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No pude responder'), findsNothing);
    expect(find.text('Pausa breve: se alcanzó el límite de uso'), findsOneWidget);
    expect(find.text('Pregunta'), findsOneWidget); // sin duplicar la pregunta
    final FilledButton send = tester.widget<FilledButton>(find.byKey(const Key('assistant-send')));
    expect(send.onPressed, isNull);

    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ventana angosta sin overflow', (WidgetTester tester) async {
    final _FakeAssistant svc = _FakeAssistant((_, _) async => '- a\n- b');
    await _pump(tester, svc, size: const Size(420, 760));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Compara la producción de mañana vs tarde'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('respuesta con informe muestra tarjeta con gráfica y botones de descarga', (WidgetTester tester) async {
    final AssistantReport report = AssistantReport.tryParse(<String, dynamic>{
      'titulo': 'Top productores',
      'subtitulo': 'Noviembre 2026',
      'formato': 'excel',
      'secciones': <Object?>[
        <String, Object?>{
          'tipo': 'grafica',
          'titulo': 'Litros por productor',
          'grafica': <String, Object?>{
            'tipo': 'barras',
            'etiquetas': <String>['Ana', 'Beto'],
            'series': <Object?>[
              <String, Object?>{'nombre': 'Litros', 'valores': <num>[120, 80.5]},
            ],
            'eje_y': 'Litros',
          },
        },
        <String, Object?>{
          'tipo': 'tabla',
          'columnas': <String>['Productor', 'Litros'],
          'tipos_columna': <String>['texto', 'litros'],
          'filas': <Object?>[
            <String>['Ana', '120'],
          ],
        },
      ],
    })!;
    final _FakeAssistant svc = _FakeAssistant((_, _) async => 'Aquí está tu informe.', report: report);
    await _pump(tester, svc);
    expect(find.byKey(const Key('assistant-mic')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('assistant-input')), 'Hazme un informe en Excel');
    await tester.pump();
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('assistant-report-card')), findsOneWidget);
    expect(find.text('Top productores'), findsOneWidget);
    expect(find.text('Descargar Excel'), findsOneWidget);
    expect(find.text('Descargar PDF'), findsOneWidget);
    expect(find.byKey(const Key('report-download-xlsx')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
