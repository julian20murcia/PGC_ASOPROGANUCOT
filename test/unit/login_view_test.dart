import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/views/shared/login_view.dart';
import 'package:provider/provider.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcm extends Mock implements FcmService {}

class _Auth extends AuthController {
  _Auth({super.userService, super.hiveService, super.fcmService, this.reason});
  String? reason;
  @override
  String? get sessionEndedReason => reason;
  @override
  void clearSessionEndedReason() {
    reason = null;
    notifyListeners();
  }
}

Future<_Auth> _pump(WidgetTester tester, Size size, {String? reason}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final _MockUserService us = _MockUserService();
  when(() => us.currentFirebaseUser).thenReturn(null);
  final _Auth auth = _Auth(
    userService: us,
    hiveService: HiveService(enablePersistence: false),
    fcmService: _MockFcm(),
    reason: reason,
  );
  await tester.pumpWidget(MultiProvider(
    providers: <ChangeNotifierProvider<dynamic>>[
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<UserController>.value(value: UserController(userService: us)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme().copyWith(splashFactory: InkRipple.splashFactory),
      home: const LoginView(),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
  return auth;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('escritorio 1280×720: dos paneles, textos clave y aviso de sesión', (WidgetTester tester) async {
    final _Auth auth = await _pump(tester, const Size(1280, 720), reason: SessionEndReason.inactivity);
    expect(tester.takeException(), isNull);
    expect(find.text('ACCESO AL SISTEMA'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Ingresar al sistema'), findsOneWidget);
    expect(find.text(SessionEndReason.inactivity), findsOneWidget);
    expect(find.text('decisiones con datos.'), findsOneWidget);

    // Escribir limpia el aviso de sesión.
    await tester.enterText(find.byKey(const Key('login-identifier')), 'a');
    await tester.pump();
    expect(auth.reason, isNull);
    expect(find.text(SessionEndReason.inactivity), findsNothing);
  });

  testWidgets('filtros: identificador sin espacios ni símbolos raros (máx 80) y contraseña máx 64', (WidgetTester tester) async {
    await _pump(tester, const Size(1280, 720));
    final Finder id = find.byKey(const Key('login-identifier'));
    await tester.enterText(id, 'juan pérez<>#!@correo.com');
    await tester.pump();
    expect(tester.widget<TextField>(id).controller!.text, 'juanprez@correo.com');
    await tester.enterText(id, 'a' * 200);
    await tester.pump();
    expect(tester.widget<TextField>(id).controller!.text.length, 80);
    await tester.enterText(id, 'user.name_1-x+tag@dominio.co');
    await tester.pump();
    expect(tester.widget<TextField>(id).controller!.text, 'user.name_1-x+tag@dominio.co');

    final Finder pw = find.byKey(const Key('login-password'));
    await tester.enterText(pw, 'x' * 100);
    await tester.pump();
    expect(tester.widget<TextField>(pw).controller!.text.length, 64);
  });

  testWidgets('móvil 390×844 sin overflow', (WidgetTester tester) async {
    await _pump(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
