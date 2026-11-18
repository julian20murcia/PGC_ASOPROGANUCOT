import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/audit_log_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import 'firebase_user_service.dart';
import 'hive_service.dart';

class ProducerServiceException implements Exception {
  ProducerServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fuente remota abstracta de productores y auditoría para soportar pruebas unitarias.
abstract class RemoteProducerDataSource {
  Future<List<ProducerModel>> fetchProducers();
  Future<void> upsertProducer(ProducerModel producer);
  Future<void> appendAuditLog(AuditLogModel log);
}

/// Implementación por defecto en Cloud Firestore.
class FirestoreProducerDataSource implements RemoteProducerDataSource {
  FirestoreProducerDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<ProducerModel>> fetchProducers() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.producersCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              ProducerModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  /// Consulta acotada por `uidUsuario` para cumplir reglas estrictas de aislamiento móvil (`RNF-05`).
  Future<ProducerModel?> fetchProducerByUid(String uid) async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.producersCollection)
        .where('uidUsuario', isEqualTo: uid.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      return null;
    }
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = snap.docs.first;
    return ProducerModel.fromMap(doc.data(), documentId: doc.id);
  }

  @override
  Future<void> upsertProducer(ProducerModel producer) async {
    await _db
        .collection(AppConstants.producersCollection)
        .doc(producer.productorId)
        .set(producer.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    try {
      await _db
          .collection(AppConstants.auditLogsCollection)
          .doc(log.logId)
          .set(log.toMap());
    } catch (_) {
      // No revertir el registro principal ante fallo temporal en bitácora.
    }
  }
}

/// Abstracción para vincular o crear automáticamente la cuenta móvil del productor (`RF-07`).
abstract class ProducerAccountLinker {
  Future<String> linkOrCreateProducerAccount({
    required String nombreCompleto,
    required String cedula,
    required String correo,
    required String telefono,
    required String password,
    required bool activo,
    required String actorUid,
  });
}

class FirebaseProducerAccountLinker implements ProducerAccountLinker {
  FirebaseProducerAccountLinker({
    required this.hiveService,
    this.userService,
  });

  final HiveService hiveService;
  final FirebaseUserService? userService;

  FirebaseUserService get _service =>
      userService ?? FirebaseUserService(hiveService: hiveService);

  @override
  Future<String> linkOrCreateProducerAccount({
    required String nombreCompleto,
    required String cedula,
    required String correo,
    required String telefono,
    required String password,
    required bool activo,
    required String actorUid,
  }) async {
    // Reutiliza la cuenta existente si la cédula ya tiene un usuario PRODUCTOR registrado.
    try {
      final result = await _service.listUsers();
      for (final UserModel user in result.users) {
        if (user.documento.trim() == cedula.trim()) {
          if (!user.isProductor) {
            throw ProducerServiceException(
              'La cédula $cedula ya pertenece a un usuario con perfil ${AppConstants.roleShortLabel(user.rol)}.',
            );
          }
          return user.uid;
        }
      }
    } on ProducerServiceException {
      rethrow;
    } catch (_) {
      // Si falla consulta remota, intentar creación directa.
    }

    try {
      final UserModel created = await _service.createUser(
        nombreCompleto: nombreCompleto,
        documento: cedula,
        correo: correo,
        telefono: telefono,
        rol: AppConstants.roleProductor,
        password: password,
        activo: activo,
        actorUid: actorUid,
      );
      return created.uid;
    } on UserServiceException catch (e) {
      throw ProducerServiceException(e.message);
    }
  }
}

/// Servicio MVC cliente-servidor + Hive para Gestión de Productores y Habeas Data (`RF-04` a `RF-07`).
class ProducerService {
  ProducerService({
    HiveService? hiveService,
    RemoteProducerDataSource? remoteDataSource,
    ProducerAccountLinker? accountLinker,
  })  : _hiveService = hiveService ?? HiveService(),
        _remoteDataSource = remoteDataSource ?? FirestoreProducerDataSource(),
        _accountLinkerOverride = accountLinker;

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteProducerDataSource _remoteDataSource;
  final ProducerAccountLinker? _accountLinkerOverride;

  ProducerAccountLinker get _accountLinker =>
      _accountLinkerOverride ??
      FirebaseProducerAccountLinker(hiveService: _hiveService);

  Future<({List<ProducerModel> producers, bool fromCache})> listProducers() async {
    try {
      final List<ProducerModel> remote =
          await _remoteDataSource.fetchProducers();
      remote.sort(
        (ProducerModel a, ProducerModel b) =>
            a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
      );
      await _hiveService.cacheProducers(remote);
      return (producers: remote, fromCache: false);
    } catch (_) {
      final List<ProducerModel> cached =
          await _hiveService.getCachedProducers();
      return (producers: cached, fromCache: true);
    }
  }

  /// Resuelve el productor vinculado estrictamente al usuario autenticado (`Paso 7.1`, `RF-19`).
  Future<ProducerModel?> findProducerForUser(UserModel user) async {
    ProducerModel? matchFromList(List<ProducerModel> items) {
      for (final ProducerModel p in items) {
        if (p.uidUsuario != null && p.uidUsuario!.trim() == user.uid.trim()) {
          return p;
        }
      }
      final String doc = user.documento.trim();
      if (doc.isNotEmpty) {
        for (final ProducerModel p in items) {
          if (p.cedula.trim() == doc &&
              (p.uidUsuario == null ||
                  p.uidUsuario!.isEmpty ||
                  p.uidUsuario!.trim() == user.uid.trim())) {
            return p;
          }
        }
      }
      return null;
    }

    if (_remoteDataSource is FirestoreProducerDataSource) {
      try {
        final ProducerModel? remote =
            await _remoteDataSource.fetchProducerByUid(user.uid);
        if (remote != null) {
          await _hiveService.upsertProducer(remote);
          return remote;
        }
      } catch (_) {
        // Sin red: consultar caché local cifrada.
      }
      final List<ProducerModel> cached =
          await _hiveService.getCachedProducers();
      return matchFromList(cached);
    }

    final result = await listProducers();
    return matchFromList(result.producers);
  }

  /// Valida unicidad estricta de `cedula` y `codigoAsociado` en caché local y en la nube.
  Future<void> validateUniqueCedulaAndCode({
    required String cedula,
    required String codigoAsociado,
    String? excludeProducerId,
  }) async {
    final String cleanCedula = cedula.trim();
    final String cleanCode = codigoAsociado.trim().toUpperCase();

    final Map<String, ProducerModel> pool = <String, ProducerModel>{};
    for (final ProducerModel local in await _hiveService.getCachedProducers()) {
      pool[local.productorId] = local;
    }
    try {
      for (final ProducerModel remote
          in await _remoteDataSource.fetchProducers()) {
        pool[remote.productorId] = remote;
      }
    } catch (_) {
      // Offline: validar al menos contra el padrón cacheado en Hive.
    }

    for (final ProducerModel candidate in pool.values) {
      if (excludeProducerId != null &&
          candidate.productorId == excludeProducerId) {
        continue;
      }
      if (candidate.cedula.trim() == cleanCedula) {
        throw ProducerServiceException(
          'Ya existe un productor registrado con la cédula $cleanCedula (${candidate.nombreCompleto}).',
        );
      }
      if (candidate.codigoAsociado.trim().toUpperCase() == cleanCode) {
        throw ProducerServiceException(
          'El código de asociado "$cleanCode" ya está asignado a ${candidate.nombreCompleto}.',
        );
      }
    }
  }

  Future<ProducerModel> createProducer({
    required String codigoAsociado,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String nombreFinca,
    required String vereda,
    required String estado,
    required bool aceptoHabeasData,
    required String actorUid,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    final String cleanCode = codigoAsociado.trim().toUpperCase();
    final String cleanCedula = cedula.trim();
    final String cleanNombres = nombres.trim();
    final String cleanApellidos = apellidos.trim();
    final String cleanPhone = telefono.trim();
    final String cleanFinca = nombreFinca.trim();
    final String cleanVereda = vereda.trim();
    final String cleanEstado = estado.trim().toUpperCase();

    if (cleanCode.isEmpty ||
        cleanCedula.length < 5 ||
        cleanNombres.isEmpty ||
        cleanApellidos.isEmpty ||
        cleanFinca.isEmpty ||
        cleanVereda.isEmpty) {
      throw ProducerServiceException(
        'Completa código, cédula, nombres, apellidos, finca y vereda del productor.',
      );
    }

    if (!aceptoHabeasData) {
      throw ProducerServiceException(
        'Debes confirmar la autorización de tratamiento de datos personales del productor (Ley 1581 de 2012).',
      );
    }

    await validateUniqueCedulaAndCode(
      cedula: cleanCedula,
      codigoAsociado: cleanCode,
    );

    String? linkedUid;
    if (createMobileAccount) {
      final String email = (mobileEmail ?? '').trim().toLowerCase();
      final String pass = mobilePassword ?? '';
      if (!email.contains('@') || pass.length < 6) {
        throw ProducerServiceException(
          'Para habilitar acceso móvil ingresa un correo válido y contraseña de al menos 6 caracteres.',
        );
      }
      linkedUid = await _accountLinker.linkOrCreateProducerAccount(
        nombreCompleto: '$cleanNombres $cleanApellidos'.trim(),
        cedula: cleanCedula,
        correo: email,
        telefono: cleanPhone,
        password: pass,
        activo: cleanEstado == 'ACTIVO',
        actorUid: actorUid,
      );
    }

    final DateTime now = DateTime.now().toUtc();
    ProducerModel model = ProducerModel(
      productorId: _uuid.v4(),
      uidUsuario: linkedUid,
      codigoAsociado: cleanCode,
      cedula: cleanCedula,
      nombres: cleanNombres,
      apellidos: cleanApellidos,
      telefono: cleanPhone,
      nombreFinca: cleanFinca,
      vereda: cleanVereda,
      estado: cleanEstado == 'INACTIVO' ? 'INACTIVO' : 'ACTIVO',
      aceptoHabeasData: true,
      fechaAutorizacionDatos: now,
      autorizadoPorUid: actorUid,
      fechaCreacion: now,
      isSynced: false,
    );

    try {
      await _remoteDataSource.upsertProducer(model);
      model = model.copyWith(isSynced: true);
      await _remoteDataSource.appendAuditLog(
        AuditLogModel(
          logId: _uuid.v4(),
          entidadAfectada: AppConstants.producersCollection,
          registroId: model.productorId,
          accion: 'CREAR',
          valorNuevo: model.toMap(),
          usuarioUid: actorUid,
          timestamp: now,
        ),
      );
    } catch (_) {
      // Se conserva marcado localmente como pendiente cuando no hay red.
      model = model.copyWith(isSynced: false);
    }

    await _hiveService.upsertProducer(model);
    return model;
  }

  Future<ProducerModel> updateProducer({
    required ProducerModel previous,
    required String codigoAsociado,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String nombreFinca,
    required String vereda,
    required String estado,
    required bool aceptoHabeasData,
    required String actorUid,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    final String cleanCode = codigoAsociado.trim().toUpperCase();
    final String cleanCedula = cedula.trim();
    final String cleanNombres = nombres.trim();
    final String cleanApellidos = apellidos.trim();
    final String cleanPhone = telefono.trim();
    final String cleanFinca = nombreFinca.trim();
    final String cleanVereda = vereda.trim();
    final String cleanEstado = estado.trim().toUpperCase();

    if (cleanCode.isEmpty ||
        cleanCedula.length < 5 ||
        cleanNombres.isEmpty ||
        cleanApellidos.isEmpty ||
        cleanFinca.isEmpty ||
        cleanVereda.isEmpty) {
      throw ProducerServiceException(
        'Completa código, cédula, nombres, apellidos, finca y vereda del productor.',
      );
    }

    if (!aceptoHabeasData) {
      throw ProducerServiceException(
        'La autorización de tratamiento de datos personales es obligatoria (Ley 1581 de 2012).',
      );
    }

    await validateUniqueCedulaAndCode(
      cedula: cleanCedula,
      codigoAsociado: cleanCode,
      excludeProducerId: previous.productorId,
    );

    String? linkedUid = previous.uidUsuario;
    if (createMobileAccount && (linkedUid == null || linkedUid.isEmpty)) {
      final String email = (mobileEmail ?? '').trim().toLowerCase();
      final String pass = mobilePassword ?? '';
      if (!email.contains('@') || pass.length < 6) {
        throw ProducerServiceException(
          'Para habilitar acceso móvil ingresa un correo válido y contraseña de al menos 6 caracteres.',
        );
      }
      linkedUid = await _accountLinker.linkOrCreateProducerAccount(
        nombreCompleto: '$cleanNombres $cleanApellidos'.trim(),
        cedula: cleanCedula,
        correo: email,
        telefono: cleanPhone,
        password: pass,
        activo: cleanEstado == 'ACTIVO',
        actorUid: actorUid,
      );
    }

    final DateTime now = DateTime.now().toUtc();
    ProducerModel updated = previous.copyWith(
      uidUsuario: linkedUid,
      codigoAsociado: cleanCode,
      cedula: cleanCedula,
      nombres: cleanNombres,
      apellidos: cleanApellidos,
      telefono: cleanPhone,
      nombreFinca: cleanFinca,
      vereda: cleanVereda,
      estado: cleanEstado == 'INACTIVO' ? 'INACTIVO' : 'ACTIVO',
      aceptoHabeasData: true,
      fechaAutorizacionDatos: previous.fechaAutorizacionDatos ?? now,
      autorizadoPorUid: previous.autorizadoPorUid ?? actorUid,
      isSynced: false,
    );

    try {
      await _remoteDataSource.upsertProducer(updated);
      updated = updated.copyWith(isSynced: true);
      await _remoteDataSource.appendAuditLog(
        AuditLogModel(
          logId: _uuid.v4(),
          entidadAfectada: AppConstants.producersCollection,
          registroId: updated.productorId,
          accion: 'EDITAR',
          valorAnterior: previous.toMap(),
          valorNuevo: updated.toMap(),
          usuarioUid: actorUid,
          timestamp: now,
        ),
      );
    } catch (_) {
      updated = updated.copyWith(isSynced: false);
    }

    await _hiveService.upsertProducer(updated);
    return updated;
  }

  Future<ProducerModel> toggleProducerStatus({
    required ProducerModel producer,
    required String actorUid,
  }) async {
    final String nextStatus = producer.isActivo ? 'INACTIVO' : 'ACTIVO';
    final DateTime now = DateTime.now().toUtc();
    ProducerModel updated = producer.copyWith(
      estado: nextStatus,
      isSynced: false,
    );

    try {
      await _remoteDataSource.upsertProducer(updated);
      updated = updated.copyWith(isSynced: true);
      await _remoteDataSource.appendAuditLog(
        AuditLogModel(
          logId: _uuid.v4(),
          entidadAfectada: AppConstants.producersCollection,
          registroId: updated.productorId,
          accion: 'EDITAR',
          valorAnterior: <String, dynamic>{'estado': producer.estado},
          valorNuevo: <String, dynamic>{'estado': nextStatus},
          motivo: 'Cambio de estado operativo del productor.',
          usuarioUid: actorUid,
          timestamp: now,
        ),
      );
    } catch (_) {
      updated = updated.copyWith(isSynced: false);
    }

    await _hiveService.upsertProducer(updated);
    return updated;
  }

  String suggestNextCodigoAsociado(List<ProducerModel> existing) {
    int maxNumber = 0;
    final RegExp digitsRegex = RegExp(r'(\d+)$');
    for (final ProducerModel p in existing) {
      final Match? match = digitsRegex.firstMatch(p.codigoAsociado.trim());
      if (match != null) {
        final int? numVal = int.tryParse(match.group(1)!);
        if (numVal != null && numVal > maxNumber) {
          maxNumber = numVal;
        }
      }
    }
    final int next = maxNumber + 1;
    return 'ASO-${next.toString().padLeft(3, '0')}';
  }
}
