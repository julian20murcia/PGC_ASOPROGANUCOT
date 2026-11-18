import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/user_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/main.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/dairy_loader.dart';
import 'package:provider/provider.dart';

class _MockFirebaseUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Login valida credenciales, muestra DairyLoader y abre AdminShellView con sidebar Holstein',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final UserModel adminUser = UserModel(
      uid: 'uid-admin-1',
      nombreCompleto: 'Bradley Ballen',
      documento: '1073500123',
      correo: 'bradley@asoproganucot.com',
      telefono: '3101234567',
      rol: AppConstants.roleAdmin,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: DateTime.utc(2026, 11, 17),
    );

    final _MockFirebaseUserService mockUserService = _MockFirebaseUserService();
    final _MockFcmService mockFcmService = _MockFcmService();
    final HiveService memoryHive = HiveService(enablePersistence: false);

    when(() => mockUserService.currentFirebaseUser).thenReturn(null);
    when(
      () => mockUserService.signInWithIdentifier(
        identifier: 'bradley@asoproganucot.com',
        password: 'Password123',
      ),
    ).thenAnswer((_) async => adminUser);
    when(() => mockUserService.listUsers()).thenAnswer(
      (_) async => (users: <UserModel>[adminUser], fromCache: false),
    );
    when(() => mockUserService.signOut()).thenAnswer((_) async {});
    when(() => mockFcmService.fetchDeviceTokenIfSupported())
        .thenAnswer((_) async => null);

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
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.byType(DairyLoader), findsWidgets);

    // Intento vacío debe mostrar mensaje de validación
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(
      find.text('Ingresa tu correo electrónico o número de documento.'),
      findsOneWidget,
    );

    // Ingresar credenciales válidas
    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'bradley@asoproganucot.com');
    await tester.enterText(fields.at(1), 'Password123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Usuarios'), findsAtLeastNWidgets(1));
    expect(find.text('Recepción de Leche'), findsOneWidget);
    expect(find.text('Nuevo usuario'), findsOneWidget);
    expect(find.text('Bradley Ballen'), findsAtLeastNWidgets(1));
  });
}
