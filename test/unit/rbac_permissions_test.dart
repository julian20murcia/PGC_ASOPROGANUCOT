import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/cow_balloon_3d_widget.dart';

class _MockFirebaseUserService extends Mock implements FirebaseUserService {}

class _MockFcmService extends Mock implements FcmService {}

void main() {
  group('UserModel RBAC y serialización', () {
    final DateTime now = DateTime.utc(2026, 11, 17, 12, 0);

    test('ADMIN tiene acceso completo administrativo y de planta', () {
      final UserModel admin = UserModel(
        uid: 'u-admin',
        nombreCompleto: 'Carlos Administrador',
        documento: '1073500100',
        correo: 'admin@asoproganucot.com',
        telefono: '3100000000',
        rol: AppConstants.roleAdmin,
        activo: true,
        fcmTokens: const <String>[],
        fechaCreacion: now,
      );

      expect(admin.isAdmin, isTrue);
      expect(admin.canAccessDesktopAdmin, isTrue);
      expect(admin.canManageUsers, isTrue);
      expect(admin.canConfigureRatesOrSettle, isTrue);
      expect(admin.canRecordReceptions, isTrue);
    });

    test('OPERARIO puede registrar recepciones pero no administrar usuarios ni tarifas', () {
      final UserModel operario = UserModel(
        uid: 'u-op',
        nombreCompleto: 'Luis Operario',
        documento: '1073500200',
        correo: 'operario@asoproganucot.com',
        telefono: '3110000000',
        rol: AppConstants.roleOperario,
        activo: true,
        fcmTokens: const <String>[],
        fechaCreacion: now,
      );

      expect(operario.isOperario, isTrue);
      expect(operario.canAccessDesktopAdmin, isTrue);
      expect(operario.canRecordReceptions, isTrue);
      expect(operario.canManageUsers, isFalse);
      expect(operario.canConfigureRatesOrSettle, isFalse);
    });

    test('PRODUCTOR está aislado de la app administrativa y métodos de escritura', () {
      final UserModel productor = UserModel(
        uid: 'u-prod',
        nombreCompleto: 'Ana Ganadera',
        documento: '1073500300',
        correo: 'ana@asoproganucot.com',
        telefono: '3120000000',
        rol: AppConstants.roleProductor,
        activo: true,
        fcmTokens: const <String>['token-1'],
        fechaCreacion: now,
      );

      expect(productor.isProductor, isTrue);
      expect(productor.canAccessDesktopAdmin, isFalse);
      expect(productor.canManageUsers, isFalse);
      expect(productor.canConfigureRatesOrSettle, isFalse);
      expect(productor.canRecordReceptions, isFalse);

      final UserModel roundTrip = UserModel.fromMap(productor.toMap());
      expect(roundTrip.uid, productor.uid);
      expect(roundTrip.rol, AppConstants.roleProductor);
      expect(roundTrip.documento, '1073500300');
      expect(roundTrip.fcmTokens, <String>['token-1']);
    });
  });

  group('AuthController validación estricta y login real', () {
    late _MockFirebaseUserService mockUserService;
    late _MockFcmService mockFcmService;
    late HiveService memoryHive;
    late AuthController controller;

    setUp(() {
      mockUserService = _MockFirebaseUserService();
      mockFcmService = _MockFcmService();
      memoryHive = HiveService(enablePersistence: false);
      controller = AuthController(
        userService: mockUserService,
        hiveService: memoryHive,
        fcmService: mockFcmService,
      );
    });

    test('Rechaza ingreso si campos están vacíos o incompletos', () async {
      final bool emptyBoth = await controller.signIn(
        identifier: '',
        password: '',
        rememberMe: true,
      );
      expect(emptyBoth, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.errorMessage, isNotNull);

      final bool missingPass = await controller.signIn(
        identifier: 'admin@asoproganucot.com',
        password: '',
        rememberMe: false,
      );
      expect(missingPass, isFalse);
      expect(controller.isAuthenticated, isFalse);

      verifyNever(
        () => mockUserService.signInWithIdentifier(
          identifier: any(named: 'identifier'),
          password: any(named: 'password'),
        ),
      );
    });

    test('Inicia sesión correctamente con credenciales válidas de ADMIN', () async {
      final UserModel admin = UserModel(
        uid: 'u-admin',
        nombreCompleto: 'Administrador Principal',
        documento: '1073500100',
        correo: 'admin@asoproganucot.com',
        telefono: '3100000000',
        rol: AppConstants.roleAdmin,
        activo: true,
        fcmTokens: const <String>[],
        fechaCreacion: DateTime.utc(2026, 11, 17),
      );

      when(
        () => mockUserService.signInWithIdentifier(
          identifier: 'admin@asoproganucot.com',
          password: 'SecretPassword123',
        ),
      ).thenAnswer((_) async => admin);
      when(() => mockFcmService.fetchDeviceTokenIfSupported())
          .thenAnswer((_) async => null);

      final bool ok = await controller.signIn(
        identifier: 'admin@asoproganucot.com',
        password: 'SecretPassword123',
        rememberMe: true,
      );

      expect(ok, isTrue);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.currentUser?.uid, 'u-admin');
      expect(controller.currentUser?.isAdmin, isTrue);
    });
  });

  group('Modelo 3D GLB oficial de ASOPROGANUCOTT', () {
    test('Parsea la malla subdividida con colores horneados de spot_holstein_cow.glb', () {
      final File glbFile = File('assets/models/spot_holstein_cow.glb');
      expect(glbFile.existsSync(), isTrue);

      final Uint8List raw = glbFile.readAsBytesSync();
      final GlbCowMesh mesh = GlbCowMesh.fromGlbBytes(ByteData.sublistView(raw));

      expect(mesh.vertexCount, 48009);
      expect(mesh.triangleCount, 93696);
      expect(mesh.positions.length, mesh.vertexCount * 3);
      expect(mesh.normals.length, mesh.vertexCount * 3);
      expect(mesh.linearRgb.length, mesh.vertexCount * 3);
    });
  });
}
