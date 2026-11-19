import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/views/desktop/reception/reception_grid_logic.dart';
import 'package:pgc_asoproganucot/views/desktop/reception/reception_spreadsheet.dart';

ProducerModel _producer(String id, String code) => ProducerModel(
  productorId: id,
  codigoAsociado: code,
  cedula: '1073500$id',
  nombres: 'Productor',
  apellidos: code,
  telefono: '3101112233',
  nombreFinca: 'Finca',
  vereda: 'Vereda',
  estado: 'ACTIVO',
  aceptoHabeasData: true,
  fechaAutorizacionDatos: DateTime.utc(2026, 1, 1),
  fechaCreacion: DateTime.utc(2026, 1, 1),
);

MilkReceptionModel _rec(
  String id,
  String productorId,
  String fecha,
  String jornada,
  double litros, {
  String? liquidacionId,
}) => MilkReceptionModel(
  recepcionId: id,
  productorId: productorId,
  codigoAsociadoSnap: 'C',
  nombreProductorSnap: 'N',
  litros: litros,
  fechaEntrega: fecha,
  horaEntrega: '06:00:00',
  jornada: jornada,
  operarioUid: 'op',
  isSynced: true,
  syncStatus: AppConstants.syncSynced,
  liquidacionId: liquidacionId,
  createdAt: DateTime.utc(2026, 11, 1),
);

class _Calls {
  final List<String> created = <String>[];
  final List<String> edited = <String>[];
  final List<String> annulled = <String>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  List<MilkReceptionModel> receptions = const <MilkReceptionModel>[],
  int producers = 3,
  int days = 3,
  bool canEdit = true,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final _Calls calls = _Calls();
  final PlanillaMatrix m = PlanillaMatrix.build(
    activeProducers: <ProducerModel>[
      for (int i = 1; i <= producers; i++)
        _producer('p$i', 'ASO-${i.toString().padLeft(3, '0')}'),
    ],
    receptions: receptions,
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 11, days),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: ReceptionSpreadsheet(
          matrix: m,
          canCreate: true,
          canEdit: canEdit,
          canAnnul: true,
          now: DateTime(2026, 11, 18, 8),
          onCreate:
              (
                PlanillaRow row,
                DateTime day,
                String jornada,
                double liters,
              ) async {
                calls.created.add(
                  '${row.productorId}|${isoOf(day)}|$jornada|$liters',
                );
                return null;
              },
          onEdit: (MilkReceptionModel r, double liters) async {
            calls.edited.add('${r.recepcionId}|$liters');
            return null;
          },
          onAnnul: (MilkReceptionModel r) async {
            calls.annulled.add(r.recepcionId);
            return null;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Edita con teclado sin abrir diálogos (Enter, escribir, Enter)', (
    WidgetTester tester,
  ) async {
    final _Calls calls = await _pump(
      tester,
      receptions: <MilkReceptionModel>[
        _rec('r1', 'p1', '2026-11-01', AppConstants.shiftMorning, 12.5),
      ],
    );
    // Selecciona la primera celda (p1, 1 nov, mañana).
    await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-0')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-editor')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('planilla-editor')),
      '14',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls.edited, <String>['r1|14.0']);
    expect(find.byKey(const ValueKey<String>('planilla-editor')), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    // Enter movió la selección a la fila siguiente; escribir un dígito inicia la edición.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit7, character: '7');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-editor')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('planilla-editor')),
          )
          .controller!
          .text,
      '7',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(calls.created, <String>[
      'p2|2026-11-01|${AppConstants.shiftMorning}|7.0',
    ]);
  });

  testWidgets(
    'Esc cancela, letras no entran y valores > 5.000 muestran error en línea',
    (WidgetTester tester) async {
      final _Calls calls = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-1')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final Finder editor = find.byKey(
        const ValueKey<String>('planilla-editor'),
      );
      await tester.enterText(editor, 'abc');
      expect(tester.widget<TextField>(editor).controller!.text, isEmpty);
      await tester.enterText(editor, '10000000000000');
      expect(
        tester
            .widget<TextField>(editor)
            .controller!
            .text
            .replaceAll('.', '')
            .length,
        lessThanOrEqualTo(4),
      );
      await tester.enterText(editor, '9.999');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('planilla-edit-error')),
        findsOneWidget,
      );
      expect(calls.created, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editor, findsNothing);
      expect(calls.created, isEmpty);
    },
  );

  testWidgets('Flechas mueven la selección y Supr pide anular en línea', (
    WidgetTester tester,
  ) async {
    final _Calls calls = await _pump(
      tester,
      receptions: <MilkReceptionModel>[
        _rec('r9', 'p2', '2026-11-02', AppConstants.shiftAfternoon, 8),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-0')));
    await tester.pump();
    final ReceptionSpreadsheetState state = tester
        .state<ReceptionSpreadsheetState>(find.byType(ReceptionSpreadsheet));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(state.selection, const GridPos(1, 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-annul-bar')),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls.annulled, <String>['r9']);
  });

  testWidgets('Celdas liquidadas son de solo lectura', (
    WidgetTester tester,
  ) async {
    final _Calls calls = await _pump(
      tester,
      receptions: <MilkReceptionModel>[
        _rec(
          'r1',
          'p1',
          '2026-11-01',
          AppConstants.shiftMorning,
          12.5,
          liquidacionId: 'liq-1',
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-0')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('planilla-editor')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-annul-bar')),
      findsNothing,
    );
    expect(calls.edited, isEmpty);
    expect(calls.annulled, isEmpty);
  });

  testWidgets('100 productores × 31 días renderiza sin errores (perezoso)', (
    WidgetTester tester,
  ) async {
    await _pump(tester, producers: 100, days: 30);
    expect(tester.takeException(), isNull);
    // Arranca en la jornada de "hoy" (18 nov, mañana) y solo construye lo visible.
    expect(
      find.byKey(const ValueKey<String>('planilla-cell-0-34')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('planilla-cell-99-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('planilla-cell-0-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey<String>('planilla-cell-0-34')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-cell-0-0')),
      findsOneWidget,
    );
    // Navegar al final con teclado desplaza la vista.
    for (int i = 0; i < 99; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('planilla-cell-99-59')),
      findsOneWidget,
    );
  });
}
