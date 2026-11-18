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
import 'package:pgc_asoproganucot/main.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:provider/provider.dart';

class _MockFirebaseUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Login permite ingresar sin credenciales y abre el menú lateral y módulo Usuarios',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _MockFirebaseUserService mockUserService = _MockFirebaseUserService();
    final _MockFcmService mockFcmService = _MockFcmService();
    final HiveService memoryHive = HiveService(enablePersistence: false);

    when(() => mockUserService.currentFirebaseUser).thenReturn(null);
    when(() => mockUserService.listUsers()).thenAnswer(
      (_) async => (users: <UserModel>[], fromCache: false),
    );
    when(() => mockUserService.signOut()).thenAnswer((_) async {});

    final AuthController authController = AuthController(
      userService: mockUserService,
      hiveService: memoryHive,
      fcmService: mockFcmService,
    );
    await authController.initialize();

    final UserController userController = UserController(
      userService: mockUserService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: authController),
          ChangeNotifierProvider<UserController>.value(value: userController),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const AuthGate(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Gestión de Usuarios'), findsOneWidget);
    expect(find.text('Usuarios'), findsOneWidget);
    expect(find.text('Recepción de Leche'), findsOneWidget);
    expect(find.text('Nuevo usuario'), findsOneWidget);
  });
}
