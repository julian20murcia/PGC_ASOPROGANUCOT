import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/privacy_notice.dart';
import 'package:pgc_asoproganucot/views/mobile/producer_registration_view.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/design_system_widgets.dart';

void main() {
  testWidgets(
    'ProducerRegistrationView abre vista previa integrada de la política, requiere scroll al final para aceptar y conserva el formulario móvil',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final PrivacyNotice notice = PrivacyNotice.fromMap(
        const <String, dynamic>{
          'version': '1.1 de prueba',
          'responsable': 'ASOPROGANUCOTT Susa',
          'direccion': 'Vereda Timinguita, sector Casaloma, Susa',
          'correo': 'asoproganucott@hotmail.com',
          'telefono': '+57 310 302 2857',
          'politicaUrl': 'https://example.com/politica.pdf',
          'finalidades': 'Registro diario de entregas de leche y liquidaciones.',
          'derechos': 'Consulta, actualización, rectificación y supresión.',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: ProducerRegistrationView(
            privacyNoticeLoader: () async => notice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Leer política aquí y aceptar'), findsOneWidget);
      expect(find.text('Abrir enlace en navegador'), findsOneWidget);

      final Finder sendSmsButton = find.widgetWithText(
        PrimaryActionButton,
        'Enviar código por SMS',
      );
      expect(sendSmsButton, findsOneWidget);
      expect(
        tester.widget<PrimaryActionButton>(sendSmsButton).onPressed,
        isNull,
      );

      final Finder docFieldBefore = find.widgetWithText(
        TextFormField,
        'Número de identificación',
      );
      expect(tester.widget<TextFormField>(docFieldBefore).enabled, isFalse);

      // Abrir la vista previa integrada dentro de la app
      await tester.tap(find.text('Leer política aquí y aceptar'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Política de tratamiento de datos'), findsOneWidget);
      expect(find.text('Responsable y canales de atención'), findsOneWidget);

      final Finder acceptButton = find.widgetWithText(
        PrimaryActionButton,
        'Aceptar política y continuar',
      );
      expect(acceptButton, findsOneWidget);
      expect(
        tester.widget<PrimaryActionButton>(acceptButton).onPressed,
        isNull,
      );

      // Deslizar hasta el final del documento dentro del sheet
      final Finder sheetScrollable = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Fin del documento · Ya puedes aceptar la política'),
        320,
        scrollable: sheetScrollable,
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<PrimaryActionButton>(acceptButton).onPressed,
        isNotNull,
      );

      await tester.tap(acceptButton);
      await tester.pumpAndSettle();

      // Al volver al formulario móvil se conserva la vista y se habilitan campos y botón SMS
      expect(tester.takeException(), isNull);
      expect(find.text('Política leída y autorización aceptada'), findsOneWidget);

      final Finder docFieldAfter = find.widgetWithText(
        TextFormField,
        'Número de identificación',
      );
      final Finder phoneFieldAfter = find.widgetWithText(
        TextFormField,
        'Celular registrado',
      );
      expect(tester.widget<TextFormField>(docFieldAfter).enabled, isTrue);
      expect(tester.widget<TextFormField>(phoneFieldAfter).enabled, isTrue);
      expect(
        tester.widget<PrimaryActionButton>(sendSmsButton).onPressed,
        isNotNull,
      );
    },
  );
}
