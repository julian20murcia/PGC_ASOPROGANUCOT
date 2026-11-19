import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import 'firebase_callable.dart';
import 'hive_service.dart';

class UserServiceException implements Exception {
  UserServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Servicio cliente-servidor para autenticación y administración de usuarios
/// sobre Firebase Auth, Cloud Firestore y caché local Hive.
class FirebaseUserService {
  FirebaseUserService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    HiveService? hiveService,
  })  : _authOverride = auth,
        _firestoreOverride = firestore,
        _hiveService = hiveService ?? HiveService();

  static const Uuid _uuid = Uuid();

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  final HiveService _hiveService;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  User? get currentFirebaseUser => _auth.currentUser;

  /// Autentica por correo electrónico o número de documento/cédula.
  Future<UserModel> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final String cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty || password.isEmpty) {
      throw UserServiceException(
        'Debes ingresar tu correo o documento y tu contraseña.',
      );
    }

    try {
      final UserCredential credential;
      if (cleanIdentifier.contains('@')) {
        credential = await _auth.signInWithEmailAndPassword(
          email: cleanIdentifier.toLowerCase(), password: password,
        );
      } else {
        final String email;
        try {
          final result = await callFirebaseFunction('signInByDocument', <String, dynamic>{
            'documento': cleanIdentifier, 'password': password,
          });
          email = result['email'] as String;
        } catch (_) {
          throw UserServiceException('No fue posible ingresar con ese documento y contraseña. Verifica tus datos o utiliza tu correo.');
        }
        credential = await _auth.signInWithEmailAndPassword(
          email: email, password: password,
        );
      }
      final String uid = credential.user?.uid ?? '';
      if (uid.isEmpty) {
        throw UserServiceException(
          'No se pudo validar tu sesión. Intenta ingresar nuevamente.',
        );
      }

      UserModel? profile = await getUserProfileByUid(uid);

      if (profile == null) {
        await _auth.signOut();
        throw UserServiceException(
          'Tu cuenta aún no tiene un perfil asignado en la plataforma. Comunícate con el administrador.',
        );
      }

      if (!profile.activo) {
        await _auth.signOut();
        throw UserServiceException(
          'Tu usuario está suspendido. Comunícate con el Administrador Central.',
        );
      }

      try {
        profile = await recordLogin(profile);
      } catch (_) {
        await _auth.signOut();
        throw UserServiceException('No se pudo registrar el acceso de forma segura. Intenta nuevamente.');
      }

      await _hiveService.upsertUser(profile);
      return profile;
    } on FirebaseAuthException catch (e) {
      throw UserServiceException(_mapAuthError(e));
    }
  }

  Future<UserModel> recordLogin(UserModel user) async {
    final String id = _uuid.v4();
    final WriteBatch batch = _firestore.batch();
    batch.update(_firestore.collection(AppConstants.usersCollection).doc(user.uid), <String, dynamic>{
      'ultimoAcceso': FieldValue.serverTimestamp(),
      'ultimoAccesoLogId': id,
    });
    batch.set(_firestore.collection(AppConstants.auditLogsCollection).doc(id), <String, dynamic>{
      'logId': id,
      'entidadAfectada': AppConstants.usersCollection,
      'registroId': user.uid,
      'accion': 'INICIAR_SESION',
      'usuarioUid': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return user.copyWith(ultimoAcceso: DateTime.now().toUtc());
  }

  Future<UserModel?> getUserProfileByUid(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final UserModel user =
            UserModel.fromMap(doc.data()!, documentId: doc.id);
        await _hiveService.upsertUser(user);
        return user;
      }

    } catch (_) {
      final List<UserModel> cached = await _hiveService.getCachedUsers();
      for (final UserModel user in cached) {
        if (user.uid == uid) {
          return user;
        }
      }
    }
    return null;
  }

  Future<({List<UserModel> users, bool fromCache})> listUsers() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .get();

      final List<UserModel> users = snapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                UserModel.fromMap(doc.data(), documentId: doc.id),
          )
          .toList()
        ..sort(
          (UserModel a, UserModel b) => a.nombreCompleto
              .toLowerCase()
              .compareTo(b.nombreCompleto.toLowerCase()),
        );

      await _hiveService.cacheUsers(users);
      return (users: users, fromCache: false);
    } catch (_) {
      final List<UserModel> cached = await _hiveService.getCachedUsers();
      return (users: cached, fromCache: true);
    }
  }

  Future<Map<String, dynamic>> _callAdmin(String name, Map<String, dynamic> data) async {
    final User? me = _auth.currentUser;
    if (me == null) {
      throw UserServiceException('Tu sesión expiró. Vuelve a iniciar sesión.');
    }
    try {
      final String? token = await me.getIdToken();
      return await callFirebaseFunction(name, data, idToken: token, timeout: const Duration(seconds: 30));
    } on StateError catch (e) {
      throw UserServiceException(e.message);
    } on FormatException {
      throw UserServiceException('El servicio de usuarios no está disponible en este momento. Intenta más tarde.');
    } on TimeoutException {
      throw UserServiceException('El servidor tardó demasiado en responder. Intenta de nuevo.');
    } catch (e) {
      throw UserServiceException('No hay conexión con el servidor. Verifica tu internet e intenta de nuevo.');
    }
  }

  /// Crea la cuenta (Auth + perfil + auditoría) en el servidor de forma
  /// atómica mediante la función `adminCreateUser`. Si algo falla, el servidor
  /// revierte la cuenta de Auth para no dejar usuarios huérfanos.
  Future<UserModel> createUser({
    required String nombreCompleto,
    required String documento,
    required String correo,
    required String telefono,
    required String rol,
    required String password,
    required bool activo,
    required String actorUid,
    Map<String, List<String>>? permisos,
    String? productorId,
  }) async {
    final String cleanName = nombreCompleto.trim().replaceAll(RegExp(r'\s+'), ' ');
    final String cleanDoc = documento.trim();
    final String cleanEmail = correo.trim().toLowerCase();
    final String cleanRole = rol.trim().toUpperCase();
    if (cleanName.isEmpty || cleanDoc.isEmpty || cleanEmail.isEmpty || password.isEmpty) {
      throw UserServiceException('Completa nombre, documento, correo y contraseña para crear el usuario.');
    }
    if (password.length < 8) {
      throw UserServiceException('La contraseña debe tener al menos 8 caracteres.');
    }
    final Map<String, dynamic> result = await _callAdmin('adminCreateUser', <String, dynamic>{
      'nombreCompleto': cleanName,
      'documento': cleanDoc,
      'correo': cleanEmail,
      'telefono': telefono.trim(),
      'rol': cleanRole,
      'password': password,
      'activo': activo,
      'permisos': ?permisos,
      if (productorId != null && productorId.isNotEmpty) 'productorId': productorId,
    });
    final Map<String, dynamic> profile = Map<String, dynamic>.from(result['user'] as Map);
    final UserModel created = UserModel.fromMap(profile, documentId: profile['uid'] as String?);
    await _hiveService.upsertUser(created);
    return created;
  }

  /// Actualiza perfil, rol, estado, permisos y opcionalmente la contraseña.
  Future<UserModel> updateUser({
    required UserModel previousUser,
    required String nombreCompleto,
    required String documento,
    required String telefono,
    required String rol,
    required bool activo,
    required String actorUid,
    Map<String, List<String>>? permisos,
    bool resetPermisosToRole = false,
    String? newPassword,
  }) async {
    final Map<String, dynamic> result = await _callAdmin('adminUpdateUser', <String, dynamic>{
      'uid': previousUser.uid,
      'nombreCompleto': nombreCompleto.trim().replaceAll(RegExp(r'\s+'), ' '),
      'documento': documento.trim(),
      'telefono': telefono.trim(),
      'rol': rol.trim().toUpperCase(),
      'activo': activo,
      'permisos': ?permisos,
      if (resetPermisosToRole) 'resetPermisos': true,
      if (newPassword != null && newPassword.isNotEmpty) 'password': newPassword,
    });
    final Map<String, dynamic> profile = Map<String, dynamic>.from(result['user'] as Map);
    final UserModel updated = UserModel.fromMap(profile, documentId: previousUser.uid);
    await _hiveService.upsertUser(updated);
    return updated;
  }

  Future<UserModel> toggleUserStatus({
    required UserModel user,
    required bool newStatus,
    required String actorUid,
  }) {
    return updateUser(
      previousUser: user,
      nombreCompleto: user.nombreCompleto,
      documento: user.documento,
      telefono: user.telefono,
      rol: user.rol,
      activo: newStatus,
      actorUid: actorUid,
      permisos: user.permisos,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    final String cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      throw UserServiceException('El correo electrónico no es válido.');
    }
    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      throw UserServiceException(_mapAuthError(e));
    }
  }

  Future<void> appendFcmToken({
    required String uid,
    required String token,
  }) async {
    if (token.isEmpty) {
      return;
    }
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update(<String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion(<String>[token]),
      });
    } catch (_) {
      // No bloquear el login si falla el registro del token push.
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Esta cuenta se encuentra deshabilitada.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Credenciales incorrectas. Verifica tu correo/documento y contraseña.';
      case 'email-already-in-use':
        return 'Ese correo electrónico ya se encuentra registrado.';
      case 'weak-password':
        return 'La contraseña es demasiado débil (mínimo 6 caracteres).';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Espera unos minutos e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión a internet para validar tus credenciales.';
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }
}
