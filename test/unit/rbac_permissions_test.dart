import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/security/permissions.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/desktop/users/user_form_rules.dart';
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
      when(() => mockFcmService.onTokenRefresh)
          .thenAnswer((_) => const Stream<String>.empty());

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

      expect(mesh.vertexCount, 38999);
      expect(mesh.triangleCount, 76356);
      expect(mesh.positions.length, mesh.vertexCount * 3);
      expect(mesh.normals.length, mesh.vertexCount * 3);
      expect(mesh.linearRgb.length, mesh.vertexCount * 3);
    });
  });
  group('Árbol de permisos (dependencias ver ↔ otras acciones)', () {
    test('marcar otra acción marca "ver" automáticamente', () {
      final Map<String, List<String>> p = PermissionTree.toggleAction(
        PermissionTree.none(), Permissions.recepcion, PermAction.editar, true);
      expect(p[Permissions.recepcion], <String>[PermAction.ver, PermAction.editar]);
      expect(PermissionTree.moduleGrant(p, Permissions.recepcion), ModuleGrant.partial);
    });

    test('desmarcar "ver" quita todo el módulo', () {
      Map<String, List<String>> p = PermissionTree.setModule(PermissionTree.none(), Permissions.productores, true);
      expect(PermissionTree.moduleGrant(p, Permissions.productores), ModuleGrant.all);
      p = PermissionTree.toggleAction(p, Permissions.productores, PermAction.ver, false);
      expect(p.containsKey(Permissions.productores), isFalse);
      expect(PermissionTree.moduleGrant(p, Permissions.productores), ModuleGrant.none);
    });

    test('desmarcar otra acción conserva "ver"', () {
      Map<String, List<String>> p = PermissionTree.setModule(PermissionTree.none(), Permissions.usuarios, true);
      p = PermissionTree.toggleAction(p, Permissions.usuarios, PermAction.eliminar, false);
      expect(p[Permissions.usuarios], <String>[PermAction.ver, PermAction.crear, PermAction.editar]);
    });

    test('interruptor maestro: parcial → todo → nada', () {
      Map<String, List<String>> p = PermissionTree.toggleAction(
        PermissionTree.none(), Permissions.liquidaciones, PermAction.exportar, true);
      expect(PermissionTree.moduleGrant(p, Permissions.liquidaciones), ModuleGrant.partial);
      p = PermissionTree.tapModule(p, Permissions.liquidaciones);
      expect(PermissionTree.moduleGrant(p, Permissions.liquidaciones), ModuleGrant.all);
      p = PermissionTree.tapModule(p, Permissions.liquidaciones);
      expect(PermissionTree.moduleGrant(p, Permissions.liquidaciones), ModuleGrant.none);
    });

    test('acciones inexistentes en el módulo se ignoran', () {
      final Map<String, List<String>> p = PermissionTree.toggleAction(
        PermissionTree.none(), Permissions.tarifas, PermAction.eliminar, true);
      expect(p, isEmpty);
      expect(PermissionTree.toggleAction(p, 'modulo_falso', PermAction.ver, true), isEmpty);
    });

    test('Todo / Nada y comparación independiente del orden', () {
      expect(Permissions.countGranted(PermissionTree.all()), Permissions.totalActions);
      expect(PermissionTree.none(), isEmpty);
      expect(
        PermissionTree.equals(
          <String, List<String>>{'recepcion': <String>['crear', 'ver']},
          <String, List<String>>{'recepcion': <String>['ver', 'crear']},
        ),
        isTrue,
      );
    });

    test('solo los operarios envían permisos personalizados al servidor', () {
      final Map<String, List<String>> defaults = Permissions.defaultsFor(AppConstants.roleOperario);
      expect(UserFormRules.permissionsToSend(AppConstants.roleOperario, defaults), isNull);
      final Map<String, List<String>> custom = PermissionTree.toggleAction(
        defaults, Permissions.recepcion, PermAction.editar, true);
      expect(UserFormRules.permissionsToSend(AppConstants.roleOperario, custom)![Permissions.recepcion],
          contains(PermAction.editar));
      expect(UserFormRules.permissionsToSend(AppConstants.roleAdmin, custom), isNull);
      expect(UserFormRules.permissionsToSend(AppConstants.roleProductor, custom), isNull);
    });

    test('el administrador siempre tiene todo aunque tenga permisos guardados', () {
      final UserModel admin = UserModel(
        uid: 'a', nombreCompleto: 'Ana Gómez', documento: '12345', correo: 'a@b.co', telefono: '',
        rol: AppConstants.roleAdmin, activo: true, fcmTokens: const <String>[], fechaCreacion: DateTime.utc(2026),
        permisos: const <String, List<String>>{},
      );
      expect(admin.can(Permissions.usuarios, PermAction.eliminar), isTrue);
      final UserModel op = admin.copyWith(rol: AppConstants.roleOperario,
          permisos: const <String, List<String>>{'recepcion': <String>['ver']});
      expect(op.can(Permissions.recepcion, PermAction.editar), isFalse);
      expect(op.can(Permissions.recepcion), isTrue);
    });
  });
}
