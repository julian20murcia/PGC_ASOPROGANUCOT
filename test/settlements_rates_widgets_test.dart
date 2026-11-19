import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/finance_config_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/views/desktop/rates/finance_params_form.dart';
import 'package:pgc_asoproganucot/views/desktop/rates/new_rate_form.dart';
import 'package:pgc_asoproganucot/views/desktop/settlements/daily_matrix_table.dart';
import 'package:pgc_asoproganucot/views/desktop/settlements/settlements_overview.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: child,
    ),
  ),
);

Future<void> _desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MilkReceptionModel _rec(
  String id,
  String p,
  String day,
  String shift,
  double l,
) => MilkReceptionModel(
  recepcionId: id,
  productorId: p,
  codigoAsociadoSnap: 'ASO-$p',
  nombreProductorSnap: 'Productor con un nombre bastante largo $p',
  litros: l,
  fechaEntrega: day,
  horaEntrega: '06:00:00',
  jornada: shift,
  operarioUid: 'op',
  createdAt: DateTime.utc(2026, 11, 1),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('NewRateForm', () {
    testWidgets(
      'precio: rechaza letras y números gigantes, formatea miles y muestra impacto',
      (WidgetTester tester) async {
        await _desktop(tester);
        int submits = 0;
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 520,
              child: NewRateForm(
                currentPrice: 1850,
                currentPeriodLiters: 1000,
                currentPeriodLabel: '2da Quincena Nov 2026',
                onSubmit: (double p, DateTime d, String o) async {
                  submits++;
                  return true;
                },
              ),
            ),
          ),
        );

        final Finder price = find.descendant(
          of: find.byKey(const ValueKey<String>('rate-price-field')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(price, 'abc');
        await tester.pump();
        expect(tester.widget<EditableText>(price).controller.text, '');

        await tester.enterText(price, '10000000000000000000000000');
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(price)
              .controller
              .text
              .replaceAll('.', '')
              .length,
          lessThanOrEqualTo(5),
        );

        await tester.enterText(price, '1900');
        await tester.pump();
        expect(tester.widget<EditableText>(price).controller.text, '1.900');
        expect(
          find.textContaining('Con este precio, la quincena actual costaría'),
          findsOneWidget,
        );
        expect(find.textContaining(r'$ 1.900.000'), findsOneWidget);
        expect(find.textContaining('+2,7 %'), findsOneWidget);

        // Motivo: límite de caracteres y mínimo de 5.
        final Finder obs = find.descendant(
          of: find.byKey(const ValueKey<String>('rate-obs-field')),
          matching: find.byType(EditableText),
        );
        await tester.enterText(obs, 'x' * 400);
        await tester.pump();
        expect(
          tester.widget<EditableText>(obs).controller.text.length,
          lessThanOrEqualTo(120),
        );

        await tester.enterText(obs, 'abc');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('rate-submit')));
        await tester.pump();
        expect(find.text('Mínimo 5 caracteres'), findsOneWidget);
        expect(submits, 0);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('FinanceParamsForm', () {
    testWidgets('calcula margen por litro y ganancia mensual; limita dígitos', (
      WidgetTester tester,
    ) async {
      await _desktop(tester);
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 480,
            child: FinanceParamsForm(
              config: FinanceConfig.empty,
              purchasePrice: 1850,
              monthlyLiters: 10000,
              onSave: (double a, double b) async => true,
            ),
          ),
        ),
      );
      expect(find.textContaining('Ingresa el precio de venta'), findsOneWidget);

      final Finder sale = find.descendant(
        of: find.byKey(const ValueKey<String>('finance-sale-field')),
        matching: find.byType(EditableText),
      );
      final Finder cost = find.descendant(
        of: find.byKey(const ValueKey<String>('finance-cost-field')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(sale, '2300');
      await tester.enterText(cost, '9999999999999999999');
      await tester.pump();
      expect(tester.widget<EditableText>(cost).controller.text, '');
      await tester.enterText(cost, '1000000');
      await tester.pump();
      expect(tester.widget<EditableText>(cost).controller.text, '1.000.000');
      // Margen 450/L × 10.000 L = 4.500.000; menos 1.000.000 = 3.500.000.
      expect(find.text(r'$ 450'), findsOneWidget);
      expect(find.text(r'$ 4.500.000'), findsOneWidget);
      expect(find.text(r'$ 3.500.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DailyMatrixTable', () {
    testWidgets(
      'renderiza 16 días con encabezado y totales sin desbordes a 1280×720',
      (WidgetTester tester) async {
        await _desktop(tester);
        final List<MilkReceptionModel> recs = <MilkReceptionModel>[
          for (int p = 0; p < 30; p++)
            for (int d = 16; d <= 30; d++) ...<MilkReceptionModel>[
              _rec(
                'm$p-$d',
                'P$p',
                '2026-11-$d',
                AppConstants.shiftMorning,
                12.5 + p,
              ),
              _rec(
                't$p-$d',
                'P$p',
                '2026-11-$d',
                AppConstants.shiftAfternoon,
                9999.99,
              ),
            ],
        ];
        final DailyDeliveryMatrix m = DailyDeliveryMatrix.build(
          startIso: '2026-11-16',
          endIso: '2026-11-30',
          receptions: recs,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: SizedBox(height: 500, child: DailyMatrixTable(matrix: m)),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Total por día'), findsOneWidget);
        expect(find.text('Lun 16'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // El desplazamiento horizontal del cuerpo arrastra el encabezado.
        await tester.drag(find.byType(Scrollbar).first, const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ClosedPeriodsPanel', () {
    testWidgets('lista quincenas con totales y abre el detalle al tocar', (
      WidgetTester tester,
    ) async {
      await _desktop(tester);
      final List<SettlementPeriodGroup> groups =
          SettlementPeriodGroup.groupAll(<SettlementModel>[
            for (int i = 0; i < 3; i++)
              SettlementModel(
                liquidacionId: 'L$i',
                productorId: 'P$i',
                nombreProductorSnap: 'Productor $i',
                cedulaProductorSnap: '100$i',
                periodoInicio: '2026-11-01',
                periodoFin: '2026-11-15',
                quincenaLabel: '1ra Quincena Nov 2026',
                totalLitros: 100,
                cantidadEntregas: 10,
                precioLitroAplicado: 1850,
                valorTotalPagar: 185000,
                estadoPago: i == 0 ? 'PAGADA' : 'PENDIENTE',
                fechaLiquidacion: DateTime.utc(2026, 11, 16),
                numeroComprobante: 'COMP-2026-000$i',
                hashIntegridad: 'abc',
                creadoPorUid: 'u',
              ),
          ]);
      SettlementPeriodGroup? opened;
      await tester.pumpWidget(
        _host(
          ClosedPeriodsPanel(
            groups: groups,
            range: null,
            onRangeChanged: (_) {},
            onClearRange: () {},
            onQueryChanged: (_) {},
            onOpen: (SettlementPeriodGroup g) => opened = g,
          ),
        ),
      );
      expect(find.text('Quincenas cerradas'), findsOneWidget);
      expect(find.text('1ra Quincena Nov 2026'), findsOneWidget);
      expect(find.text('1 de 3 pagadas'), findsOneWidget);
      expect(find.text('2 pendiente(s)'), findsOneWidget);
      await tester.tap(find.text('1ra Quincena Nov 2026'));
      expect(opened?.key, '2026-11-01_2026-11-15');
      expect(tester.takeException(), isNull);
    });
  });
}
