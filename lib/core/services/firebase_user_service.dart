import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
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

  static const String _secondaryAppName = 'SecondaryUserCreator';
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

    final String resolvedEmail = await _resolveEmailFromIdentifier(cleanIdentifier);

    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: resolvedEmail,
        password: password,
      );
      final String uid = credential.user?.uid ?? '';
      if (uid.isEmpty) {
        throw UserServiceException(
          'No se pudo obtener el identificador de sesión en Firebase Auth.',
        );
      }

      UserModel? profile = await getUserProfileByUid(
        uid,
        fallbackEmail: resolvedEmail,
      );

      if (profile == null) {
        await _auth.signOut();
        throw UserServiceException(
          'La cuenta existe en Authentication, pero no tiene perfil asignado en la colección usuarios.',
        );
      }

      if (!profile.activo) {
        await _auth.signOut();
        throw UserServiceException(
          'Tu usuario está suspendido. Comunícate con el Administrador Central.',
        );
      }

      final DateTime now = DateTime.now().toUtc();
      profile = profile.copyWith(ultimoAcceso: now);

      try {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(profile.uid)
            .update(<String, dynamic>{
          'ultimoAcceso': now.toIso8601String(),
        });
      } catch (_) {
        // Si está sin conexión temporalmente, se conserva el perfil en caché.
      }

      await _hiveService.upsertUser(profile);
      return profile;
    } on FirebaseAuthException catch (e) {
      throw UserServiceException(_mapAuthError(e));
    }
  }

  Future<String> _resolveEmailFromIdentifier(String identifier) async {
    if (identifier.contains('@')) {
      return identifier.toLowerCase();
    }

    try {
      final QuerySnapshot<Map<String, dynamic>> query = await _firestore
          .collection(AppConstants.usersCollection)
          .where('documento', isEqualTo: identifier)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final String email =
            (query.docs.first.data()['correo'] ?? '').toString().trim();
        if (email.isNotEmpty) {
          return email.toLowerCase();
        }
      }
    } catch (_) {
      // Fallback a caché Hive si hay intermitencia de red.
    }

    final UserModel? cached =
        await _hiveService.findCachedUserByDocument(identifier);
    if (cached != null && cached.correo.isNotEmpty) {
      return cached.correo.toLowerCase();
    }

    throw UserServiceException(
      'No encontramos un usuario registrado con el documento "$identifier".',
    );
  }

  Future<UserModel?> getUserProfileByUid(
    String uid, {
    String? fallbackEmail,
  }) async {
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

      if (fallbackEmail != null && fallbackEmail.isNotEmpty) {
        final QuerySnapshot<Map<String, dynamic>> byEmail = await _firestore
            .collection(AppConstants.usersCollection)
            .where('correo', isEqualTo: fallbackEmail.toLowerCase())
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) {
          final UserModel user = UserModel.fromMap(
            byEmail.docs.first.data(),
            documentId: byEmail.docs.first.id,
          );
          await _hiveService.upsertUser(user);
          return user;
        }
      }
    } catch (_) {
      final List<UserModel> cached = await _hiveService.getCachedUsers();
      for (final UserModel user in cached) {
        if (user.uid == uid ||
            (fallbackEmail != null &&
                user.correo.toLowerCase() == fallbackEmail.toLowerCase())) {
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

  /// Crea una cuenta real en Firebase Auth usando una instancia secundaria
  /// (para no cerrar la sesión administrativa activa) y guarda el perfil en Firestore + Hive.
  Future<UserModel> createUser({
    required String nombreCompleto,
    required String documento,
    required String correo,
    required String telefono,
    required String rol,
    required String password,
    required bool activo,
    required String actorUid,
  }) async {
    final String cleanName = nombreCompleto.trim();
    final String cleanDoc = documento.trim();
    final String cleanEmail = correo.trim().toLowerCase();
    final String cleanPhone = telefono.trim();
    final String cleanRole = rol.trim().toUpperCase();

    if (cleanName.isEmpty ||
        cleanDoc.isEmpty ||
        cleanEmail.isEmpty ||
        password.isEmpty) {
      throw UserServiceException(
        'Completa nombre, documento, correo y contraseña para crear el usuario.',
      );
    }

    if (password.length < 6) {
      throw UserServiceException(
        'La contraseña debe tener al menos 6 caracteres.',
      );
    }

    await _ensureUniqueDocumentAndEmail(
      documento: cleanDoc,
      correo: cleanEmail,
    );

    final FirebaseApp secondaryApp = await _getOrCreateSecondaryApp();
    final FirebaseAuth secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    try {
      final UserCredential credential =
          await secondaryAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final User? createdAuthUser = credential.user;
      if (createdAuthUser == null) {
        throw UserServiceException(
          'Firebase Auth no devolvió el usuario creado.',
        );
      }

      await createdAuthUser.updateDisplayName(cleanName);

      final DateTime now = DateTime.now().toUtc();
      final UserModel newUser = UserModel(
        uid: createdAuthUser.uid,
        nombreCompleto: cleanName,
        documento: cleanDoc,
        correo: cleanEmail,
        telefono: cleanPhone,
        rol: cleanRole,
        activo: activo,
        fcmTokens: const <String>[],
        fechaCreacion: now,
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(newUser.uid)
          .set(newUser.toMap());

      await _hiveService.upsertUser(newUser);

      await _appendAuditLog(
        registroId: newUser.uid,
        accion: 'CREAR',
        valorAnterior: null,
        valorNuevo: newUser.toMap(),
        usuarioUid: actorUid,
      );

      return newUser;
    } on FirebaseAuthException catch (e) {
      throw UserServiceException(_mapAuthError(e));
    } finally {
      await secondaryAuth.signOut();
    }
  }

  Future<UserModel> updateUser({
    required UserModel previousUser,
    required String nombreCompleto,
    required String documento,
    required String telefono,
    required String rol,
    required bool activo,
    required String actorUid,
  }) async {
    final String cleanDoc = documento.trim();
    if (cleanDoc != previousUser.documento.trim()) {
      await _ensureUniqueDocumentAndEmail(
        documento: cleanDoc,
        correo: previousUser.correo,
        ignoreUid: previousUser.uid,
      );
    }

    final UserModel updated = previousUser.copyWith(
      nombreCompleto: nombreCompleto.trim(),
      documento: cleanDoc,
      telefono: telefono.trim(),
      rol: rol.trim().toUpperCase(),
      activo: activo,
    );

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(updated.uid)
        .update(<String, dynamic>{
      'nombreCompleto': updated.nombreCompleto,
      'documento': updated.documento,
      'telefono': updated.telefono,
      'rol': updated.rol,
      'activo': updated.activo,
    });

    await _hiveService.upsertUser(updated);

    await _appendAuditLog(
      registroId: updated.uid,
      accion: 'EDITAR',
      valorAnterior: previousUser.toMap(),
      valorNuevo: updated.toMap(),
      usuarioUid: actorUid,
    );

    return updated;
  }

  Future<UserModel> toggleUserStatus({
    required UserModel user,
    required bool newStatus,
    required String actorUid,
  }) async {
    final UserModel updated = user.copyWith(activo: newStatus);

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .update(<String, dynamic>{'activo': newStatus});

    await _hiveService.upsertUser(updated);

    await _appendAuditLog(
      registroId: user.uid,
      accion: 'EDITAR',
      valorAnterior: <String, dynamic>{'activo': user.activo},
      valorNuevo: <String, dynamic>{'activo': newStatus},
      usuarioUid: actorUid,
    );

    return updated;
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

  Future<void> _ensureUniqueDocumentAndEmail({
    required String documento,
    required String correo,
    String? ignoreUid,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> docMatches = await _firestore
        .collection(AppConstants.usersCollection)
        .where('documento', isEqualTo: documento)
        .get();

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docMatches.docs) {
      if (doc.id != ignoreUid) {
        throw UserServiceException(
          'Ya existe un usuario registrado con el documento "$documento".',
        );
      }
    }

    if (ignoreUid == null) {
      final QuerySnapshot<Map<String, dynamic>> emailMatches = await _firestore
          .collection(AppConstants.usersCollection)
          .where('correo', isEqualTo: correo.toLowerCase())
          .get();
      if (emailMatches.docs.isNotEmpty) {
        throw UserServiceException(
          'Ya existe un usuario registrado con el correo "$correo".',
        );
      }
    }
  }

  Future<FirebaseApp> _getOrCreateSecondaryApp() async {
    try {
      return Firebase.app(_secondaryAppName);
    } on FirebaseException {
      return Firebase.initializeApp(
        name: _secondaryAppName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  Future<void> _appendAuditLog({
    required String registroId,
    required String accion,
    required Map<String, dynamic>? valorAnterior,
    required Map<String, dynamic> valorNuevo,
    required String usuarioUid,
  }) async {
    final String logId = _uuid.v4();
    try {
      await _firestore
          .collection(AppConstants.auditLogsCollection)
          .doc(logId)
          .set(<String, dynamic>{
        'logId': logId,
        'entidadAfectada': AppConstants.usersCollection,
        'registroId': registroId,
        'accion': accion,
        'valorAnterior': valorAnterior,
        'valorNuevo': valorNuevo,
        'usuarioUid': usuarioUid,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Si hay error temporal en auditoría, no revertir la operación principal ya creada.
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada en Firebase Authentication.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Credenciales incorrectas. Verifica tu correo/documento y contraseña.';
      case 'email-already-in-use':
        return 'Ese correo electrónico ya se encuentra registrado en Firebase Auth.';
      case 'weak-password':
        return 'La contraseña es demasiado débil (mínimo 6 caracteres).';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Espera unos minutos e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión a internet para validar las credenciales en Firebase.';
      default:
        return e.message ?? 'Error de autenticación (${e.code}).';
    }
  }
}
