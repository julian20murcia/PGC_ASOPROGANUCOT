import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/device_session_service.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/idle_session_guard.dart';

class _MockUserService extends Mock implements FirebaseUserService {}

class _MockFcm extends Mock implements FcmService {}

/// Sesión de dispositivo controlable desde la prueba.
class _FakeDeviceSession extends DeviceSessionService {
  int claims = 0;
  bool current = true;
  bool failClaim = false;
  void Function(bool suspended)? listener;
  int stops = 0;

  @override
  Future<void> claim(String uid) async {
    if (failClaim) throw Exception('sin red');
    claims++;
  }

  @override
  Future<bool> isCurrent(String uid) async => current;

  @override
  Future<void> watch(String uid, void Function(bool suspended) onTakenOver) async => listener = onTakenOver;

  @override
  Future<void> stop() async {
    stops++;
    listener = null;
  }
}

UserModel _user({String rol = AppConstants.roleProductor}) => UserModel(
      uid: 'u1',
      nombreCompleto: 'Ana Prueba',
      documento: '1012345678',
      correo: 'ana@example.com',
      telefono: '3101234567',
      rol: rol,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: DateTime.utc(2026),
    );

Widget _guardApp({required VoidCallback onTimeout, Duration timeout = const Duration(minutes: 10)}) {
  return MaterialApp(
    theme: AppTheme.lightTheme(),
    home: IdleSessionGuard(
      onTimeout: onTimeout,
      timeout: timeout,
      child: const Scaffold(body: Center(child: Text('Panel'))),
    ),
  );
}

void main() {
  group('Cierre de sesión por inactividad (escritorio)', () {
    testWidgets('muestra aviso al minuto 9 y cierra al minuto 10 sin actividad', (WidgetTester tester) async {
      int timeouts = 0;
      await tester.pumpWidget(_guardApp(onTimeout: () => timeouts++));
      await tester.pump(const Duration(minutes: 8, seconds: 59));
      expect(find.text('¿Sigues ahí?'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('¿Sigues ahí?'), findsOneWidget);
      expect(timeouts, 0);
      for (int i = 0; i < 61; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(timeouts, 1);
      expect(find.text('¿Sigues ahí?'), findsNothing);
    });

    testWidgets('"Seguir conectado" reinicia el contador', (WidgetTester tester) async {
      int timeouts = 0;
      await tester.pumpWidget(_guardApp(onTimeout: () => timeouts++));
      await tester.pump(const Duration(minutes: 9, seconds: 10));
      expect(find.text('¿Sigues ahí?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('idle_stay_button')));
      await tester.pump();
      expect(find.text('¿Sigues ahí?'), findsNothing);
      await tester.pump(const Duration(minutes: 8));
      expect(timeouts, 0);
      expect(find.text('¿Sigues ahí?'), findsNothing);
    });

    testWidgets('mover el mouse o escribir mantiene la sesión activa', (WidgetTester tester) async {
      int timeouts = 0;
      await tester.pumpWidget(_guardApp(onTimeout: () => timeouts++));
      final TestGesture mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(minutes: 3));
        if (i.isEven) {
          await mouse.moveTo(Offset(20.0 + i, 20));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        }
      }
      await tester.pump(const Duration(minutes: 5));
      expect(timeouts, 0, reason: '18 minutos de uso continuo no deben cerrar la sesión');
      await mouse.removePointer();
    });

    testWidgets('"Cerrar sesión" en el aviso cierra inmediatamente y solo una vez', (WidgetTester tester) async {
      int timeouts = 0;
      await tester.pumpWidget(_guardApp(onTimeout: () => timeouts++));
      await tester.pump(const Duration(minutes: 9, seconds: 30));
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pump(const Duration(minutes: 5));
      expect(timeouts, 1);
    });

    testWidgets('desactivado no hace nada', (WidgetTester tester) async {
      int timeouts = 0;
      await tester.pumpWidget(MaterialApp(
        home: IdleSessionGuard(enabled: false, onTimeout: () => timeouts++, child: const Text('x')),
      ));
      await tester.pump(const Duration(minutes: 30));
      expect(timeouts, 0);
    });
  });

  group('Sesión única en móvil (AuthController)', () {
    late _MockUserService users;
    late _MockFcm fcm;
    late _FakeDeviceSession device;
    late AuthController auth;

    setUp(() async {
      users = _MockUserService();
      fcm = _MockFcm();
      device = _FakeDeviceSession();
      when(() => users.currentFirebaseUser).thenReturn(null);
      when(() => users.signOut()).thenAnswer((_) async {});
      when(() => users.signInWithIdentifier(identifier: any(named: 'identifier'), password: any(named: 'password')))
          .thenAnswer((_) async => _user());
      when(() => users.appendFcmToken(uid: any(named: 'uid'), token: any(named: 'token'))).thenAnswer((_) async {});
      when(() => fcm.fetchDeviceTokenIfSupported()).thenAnswer((_) async => null);
      auth = AuthController(
        userService: users,
        hiveService: HiveService(enablePersistence: false),
        fcmService: fcm,
        deviceSession: device,
      );
      await auth.initialize();
    });

    test('al iniciar sesión el dispositivo reclama la sesión y la vigila', () async {
      expect(await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true), isTrue);
      expect(device.claims, 1);
      expect(device.listener, isNotNull);
    });

    test('si otro dispositivo inicia sesión, este se cierra con el motivo correcto', () async {
      await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true);
      device.listener!(false);
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
      expect(auth.sessionEndedReason, SessionEndReason.otherDevice);
      verify(() => users.signOut()).called(1);
    });

    test('si el administrador suspende la cuenta, se cierra con motivo de suspensión', () async {
      await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true);
      device.listener!(true);
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);
      expect(auth.sessionEndedReason, SessionEndReason.suspended);
    });

    test('si no se puede reclamar la sesión, el ingreso falla de forma segura', () async {
      device.failClaim = true;
      expect(await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true), isFalse);
      expect(auth.currentUser, isNull);
      expect(auth.errorMessage, contains('dispositivo'));
      verify(() => users.signOut()).called(1);
    });

    test('al reabrir la app con la sesión tomada por otro teléfono, no entra', () async {
      final _FakeDeviceSession other = _FakeDeviceSession()..current = false;
      final _MockUserService u = _MockUserService();
      when(() => u.currentFirebaseUser).thenReturn(_FakeFirebaseUser());
      when(() => u.getUserProfileByUid(any())).thenAnswer((_) async => _user());
      when(() => u.signOut()).thenAnswer((_) async {});
      final HiveService hive = HiveService(enablePersistence: false);
      await hive.init();
      await hive.saveSessionState(rememberMe: true, lastIdentifier: 'ana', bootstrapMode: false, cachedUser: _user());
      final AuthController a = AuthController(userService: u, hiveService: hive, fcmService: fcm, deviceSession: other);
      await a.initialize();
      expect(a.currentUser, isNull);
      expect(a.sessionEndedReason, SessionEndReason.otherDevice);
    });

    test('el cierre por inactividad guarda el motivo y un nuevo ingreso lo limpia', () async {
      await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true);
      await auth.signOut(reason: SessionEndReason.inactivity);
      expect(auth.sessionEndedReason, SessionEndReason.inactivity);
      expect(device.stops, greaterThan(0));
      await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true);
      expect(auth.sessionEndedReason, isNull);
    });

    test('un cierre automático tardío sin sesión activa no hace nada', () async {
      await auth.signOut(reason: SessionEndReason.otherDevice);
      expect(auth.sessionEndedReason, isNull);
    });

    group('celular: sesión persistente', () {
      setUp(() => AuthController.debugPersistentMobileSession = true);
      tearDown(() => AuthController.debugPersistentMobileSession = null);

      test('se recuerda aunque no se marque "Recordar acceso" y deja un solo token push', () async {
        when(() => fcm.fetchDeviceTokenIfSupported()).thenAnswer((_) async => 'tok-nuevo');
        when(() => users.replaceFcmTokens(uid: any(named: 'uid'), token: any(named: 'token')))
            .thenAnswer((_) async {});
        expect(await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: false), isTrue);
        expect(auth.rememberMe, isTrue);
        verify(() => users.replaceFcmTokens(uid: 'u1', token: 'tok-nuevo')).called(1);
        verifyNever(() => users.appendFcmToken(uid: any(named: 'uid'), token: any(named: 'token')));
      });

      test('al reabrir la app sigue la sesión aunque lo guardado diga no recordar', () async {
        final _FakeDeviceSession same = _FakeDeviceSession();
        final _MockUserService u = _MockUserService();
        when(() => u.currentFirebaseUser).thenReturn(_FakeFirebaseUser());
        when(() => u.getUserProfileByUid(any())).thenAnswer((_) async => _user());
        when(() => u.signOut()).thenAnswer((_) async {});
        final HiveService hive = HiveService(enablePersistence: false);
        await hive.init();
        await hive.saveSessionState(rememberMe: false, lastIdentifier: 'ana', bootstrapMode: false, cachedUser: _user());
        final AuthController a = AuthController(userService: u, hiveService: hive, fcmService: fcm, deviceSession: same);
        await a.initialize();
        expect(a.currentUser?.uid, 'u1');
        verifyNever(() => u.signOut());
      });

      test('al cerrar sesión se quita el token push de este teléfono', () async {
        when(() => fcm.unregisterDevice(removeToken: any(named: 'removeToken'))).thenAnswer((Invocation inv) async {
          final Future<void> Function(String) remove =
              inv.namedArguments[#removeToken] as Future<void> Function(String);
          await remove('tok-viejo');
        });
        when(() => users.removeFcmToken(uid: any(named: 'uid'), token: any(named: 'token'))).thenAnswer((_) async {});
        await auth.signIn(identifier: 'ana@example.com', password: 'x', rememberMe: true);
        await auth.signOut();
        verify(() => users.removeFcmToken(uid: 'u1', token: 'tok-viejo')).called(1);
        expect(auth.currentUser, isNull);
      });
    });
  });
}

class _FakeFirebaseUser extends Fake implements User {
  @override
  String get uid => 'u1';
}
