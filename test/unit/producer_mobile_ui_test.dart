import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pgc_asoproganucot/controllers/producer_portal_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/views/mobile/producer/mobile_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/portal_fakes.dart';

class _Env {
  _Env(this.portal, this.remote, this.auth);
  final ProducerPortalController portal;
  final InMemoryNotificationRemote remote;
  final FakeAuthController auth;
}

String _iso(DateTime d) => ReceptionService.formatDate(d);

Future<_Env> _pumpShell(
  WidgetTester tester, {
  required Size size,
  PortalPreferences? prefs,
  bool tourDone = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime other = today.day > 1 ? DateTime(today.year, today.month, 1) : today;

  final HiveService hive = HiveService(enablePersistence: false);
  final InMemoryNotificationRemote remote = InMemoryNotificationRemote();
  await remote.upsertNotification(
    notice('n-general', titulo: 'Aviso de asamblea', at: now.toUtc().subtract(const Duration(minutes: 5))),
  );
  await remote.upsertNotification(
    notice('n-pago', dest: 'prod-a', tipo: 'PAGO', titulo: 'Pago realizado', at: now.toUtc().subtract(const Duration(days: 3))),
  );

  final MemoryPortalPreferences mem = MemoryPortalPreferences();
  if (tourDone) mem.tour['uid-prod-a'] = true;

  final ProducerPortalController portal = buildPortalController(
    hive: hive,
    receptions: <MilkReceptionModel>[
      reception('r-today-m', _iso(today), 33.5, hora: '07:10:00'),
      reception('r-other-t', _iso(other), 12, jornada: AppConstants.shiftAfternoon, hora: '16:30:00', liquidacionId: 'liq-ui-1'),
      // Valor gigante: nunca debe desbordar la UI.
      reception('r-big', _iso(today), 4999.99, jornada: AppConstants.shiftAfternoon, hora: '17:00:00'),
    ],
    settlements: <SettlementModel>[
      settlement(
        id: 'liq-ui-1',
        inicio: _iso(DateTime(other.year, other.month, 1)),
        fin: _iso(DateTime(other.year, other.month, 15)),
        valor: 9999999999,
        comprobante: 'LIQ-2026-0009',
      ),
    ],
    notifRemote: remote,
    preferences: prefs ?? mem,
  );
  final FakeAuthController auth = FakeAuthController(producerUserA, hive: hive);

  await tester.pumpWidget(wrapShell(auth: auth, portal: portal));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 1200));
  return _Env(portal, remote, auth);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final Size size in const <Size>[Size(360, 640), Size(412, 915)]) {
    testWidgets('Navega las 5 pestañas sin desbordes en ${size.width.toInt()}×${size.height.toInt()}', (WidgetTester tester) async {
      final _Env env = await _pumpShell(tester, size: size);
      expect(env.portal.hasLoaded, isTrue);

      // Inicio
      expect(find.byKey(const ValueKey<String>('home-greeting')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('home-kpi-carousel')), findsOneWidget);
      expect(find.text('Leche esta quincena'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('nav-notices-badge')), findsOneWidget);

      // El carrusel avanza solo.
      await tester.pump(const Duration(seconds: 4));
      await _settle(tester);
      expect(find.text('Valor estimado a recibir'), findsOneWidget);

      // Mis entregas
      await tester.tap(find.text('Mis entregas'));
      await _settle(tester);
      expect(find.byKey(const ValueKey<String>('deliveries-calendar')), findsOneWidget);
      expect(find.text('Días con entrega'), findsOneWidget);

      // Liquidaciones
      await tester.tap(find.text('Liquidaciones').last);
      await _settle(tester);
      expect(find.byKey(const ValueKey<String>('settlement-liq-ui-1')), findsOneWidget);

      // Avisos
      await tester.tap(find.text('Avisos').last);
      await _settle(tester);
      expect(find.text('Aviso de asamblea'), findsOneWidget);
      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('ESTA SEMANA'), findsOneWidget);

      // Perfil (botón central)
      await tester.tap(find.text('Perfil'));
      await _settle(tester);
      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('La Pradera'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey<String>('profile-logout')), 200,
          scrollable: find.descendant(of: find.byKey(const PageStorageKey<String>('profile-list')), matching: find.byType(Scrollable)));
      expect(find.byKey(const ValueKey<String>('profile-replay-tour')), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Calendario: mapea M/T por día y abre el detalle al tocar', (WidgetTester tester) async {
    await _pumpShell(tester, size: const Size(360, 640));
    final DateTime now = DateTime.now();
    final String today = _iso(now);

    await tester.tap(find.text('Mis entregas'));
    await _settle(tester);

    expect(find.byKey(ValueKey<String>('cal-m-$today')), findsOneWidget);
    expect(find.byKey(ValueKey<String>('cal-t-$today')), findsOneWidget);
    if (now.day > 1) {
      final String first = _iso(DateTime(now.year, now.month, 1));
      expect(find.byKey(ValueKey<String>('cal-t-$first')), findsOneWidget);
      expect(find.byKey(ValueKey<String>('cal-m-$first')), findsNothing);
    }

    await tester.tap(find.byKey(ValueKey<String>('cal-day-$today')));
    await _settle(tester);
    expect(find.text(MobileDates.longDay(now)), findsWidgets);
    expect(find.text('Jornada mañana'), findsOneWidget);
    expect(find.text('Jornada tarde'), findsOneWidget);
    expect(find.text('Sincronizada'), findsNWidgets(2));
    expect(find.text('Total del día'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Liquidación: abre la quincena, su calendario y el detalle de un día', (WidgetTester tester) async {
    await _pumpShell(tester, size: const Size(360, 640));
    await tester.tap(find.text('Liquidaciones').last);
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('settlement-liq-ui-1')));
    await _settle(tester);

    expect(find.byKey(const ValueKey<String>('settlement-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('btn-view-voucher')), findsOneWidget);
    expect(find.text('Datos del pago'), findsOneWidget);

    final DateTime now = DateTime.now();
    final String first = _iso(DateTime(now.year, now.month, 1));
    await tester.tap(find.byKey(ValueKey<String>('cal-day-$first')));
    await _settle(tester);
    expect(find.text('Liquidada'), findsWidgets);
    expect(find.text('Comprobante LIQ-2026-0009'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Avisos: deslizar borra UNO con deshacer, y "Borrar todas" pide confirmación', (WidgetTester tester) async {
    final _Env env = await _pumpShell(tester, size: const Size(412, 915));
    await tester.tap(find.text('Avisos').last);
    await _settle(tester);

    // Deslizar → deshacer.
    await tester.drag(find.text('Pago realizado'), const Offset(-500, 0));
    await _settle(tester);
    expect(find.text('Aviso borrado'), findsOneWidget);
    expect(find.text('Pago realizado'), findsNothing);
    await tester.tap(find.text('Deshacer'));
    await _settle(tester);
    expect(find.text('Pago realizado'), findsOneWidget);
    expect(env.remote.deletedIds, isEmpty);

    // Deslizar y dejar expirar → se borra en la nube (aviso personal).
    await tester.drag(find.text('Pago realizado'), const Offset(-500, 0));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    expect(env.remote.deletedIds, <String>['n-pago']);
    expect(env.portal.allNotifications.length, 1);

    // Borrar todas (con confirmación).
    await tester.tap(find.byKey(const ValueKey<String>('notices-clear-all')));
    await _settle(tester);
    expect(find.text('¿Borrar todos los avisos?'), findsOneWidget);
    await tester.tap(find.text('Borrar todos'));
    await _settle(tester);
    expect(env.portal.allNotifications, isEmpty);
    expect(find.text('No tienes avisos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recorrido de bienvenida: aparece solo la primera vez (SharedPreferences)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPrefsPortalPreferences prefs = SharedPrefsPortalPreferences();

    await _pumpShell(tester, size: const Size(412, 915), prefs: prefs, tourDone: false);
    await _settle(tester);
    expect(find.text('Tu quincena de un vistazo'), findsOneWidget);
    expect(find.text('Saltar'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('tour_done_uid-prod-a'), isTrue);

    // Avanza un paso y luego salta.
    await tester.tap(find.byKey(const ValueKey<String>('tour-next')));
    await _settle(tester);
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Tu producción día a día'), findsOneWidget);
    await tester.tap(find.text('Saltar'));
    await _settle(tester);
    expect(find.text('Tu producción día a día'), findsNothing);

    // Nueva sesión del mismo usuario: ya no se muestra.
    await tester.pumpWidget(const SizedBox());
    await _pumpShell(tester, size: const Size(412, 915), prefs: SharedPrefsPortalPreferences(), tourDone: false);
    await _settle(tester);
    expect(find.text('Tu quincena de un vistazo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
