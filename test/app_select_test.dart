import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/app_select.dart';

void main() {
  testWidgets('AppSelect dentro de un diálogo abre el menú encima del modal', (
    WidgetTester tester,
  ) async {
    String value = 'A';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StatefulBuilder(
                    builder: (BuildContext ctx, StateSetter setState) =>
                        AlertDialog(
                          content: SizedBox(
                            width: 300,
                            child: AppSelect<String>(
                              value: value,
                              labelText: 'Opción',
                              options: const <AppSelectOption<String>>[
                                AppSelectOption<String>(
                                  value: 'A',
                                  label: 'Alfa',
                                ),
                                AppSelectOption<String>(
                                  value: 'B',
                                  label: 'Beta',
                                ),
                              ],
                              onChanged: (String v) =>
                                  setState(() => value = v),
                            ),
                          ),
                        ),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alfa'));
    await tester.pumpAndSettle();

    // El menú es visible y recibe toques aunque esté sobre el diálogo.
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(value, 'B');
    expect(find.byType(AlertDialog), findsOneWidget);

    // Esc cierra sólo el menú, no el diálogo.
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('AppSelect filtra opciones con el buscador', (
    WidgetTester tester,
  ) async {
    final List<AppSelectOption<int>> options =
        List<AppSelectOption<int>>.generate(
          12,
          (int i) => AppSelectOption<int>(value: i, label: 'Productor $i'),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelect<int>(value: 0, options: options, onChanged: (_) {}),
        ),
      ),
    );
    await tester.tap(find.text('Productor 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tor 11');
    await tester.pumpAndSettle();
    // Disparador ("Productor 0") + única coincidencia ("Productor 11").
    expect(
      find.textContaining('Productor', findRichText: true),
      findsNWidgets(2),
    );
    expect(find.text('Productor 5'), findsNothing);
  });
}
