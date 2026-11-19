import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/producer_model.dart';
import '../../models/privacy_notice.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import '../utils/input_rules.dart';
import 'firebase_user_service.dart';
import 'firestore_audit.dart';
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
    final QuerySnapshot<Map<String, dynamic>> snap = await _db
        .collection(AppConstants.producersCollection)
        .get();
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
        .get(const GetOptions(source: Source.server));
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

  Future<ProducerModel> saveAuditedProducer(
    ProducerModel producer,
    AuditLogModel event, {
    ProducerModel? previous,
  }) async {
    final record = _db
        .collection(AppConstants.producersCollection)
        .doc(producer.productorId);
    final saved = producer.copyWith(isSynced: true, auditLogId: event.logId);
    await _db.runTransaction((Transaction transaction) async {
      final before = (await transaction.get(record)).data();
      if ((before == null) != (previous == null) ||
          before?['auditLogId'] != previous?.auditLogId) {
        throw ProducerServiceException(
          'El productor cambió. Actualiza el padrón e intenta de nuevo.',
        );
      }
      final after = <String, dynamic>{...?before, ...saved.toMap()};
      if (before != null) {
        for (final key in <String>[
          'fechaCreacion',
          'fechaAutorizacionDatos',
          'autorizadoPorUid',
        ]) {
          if (before.containsKey(key)) {
            after[key] = before[key];
          } else {
            after.remove(key);
          }
        }
      }
      writeAuditedVersion(
        db: _db,
        transaction: transaction,
        record: record,
        before: before,
        after: after,
        event: event,
      );
    });
    return saved;
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
  FirebaseProducerAccountLinker({required this.hiveService, this.userService});

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

/// Datos de un productor ya normalizados (espacios colapsados, mayúsculas en
/// el código, nombres capitalizados) y validados con las reglas oficiales.
class ProducerInput {
  const ProducerInput({
    required this.codigoAsociado,
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    required this.telefono,
    required this.nombreFinca,
    required this.vereda,
    required this.estado,
  });

  final String codigoAsociado;
  final String cedula;
  final String nombres;
  final String apellidos;
  final String telefono;
  final String nombreFinca;
  final String vereda;
  final String estado;
}

/// Reglas de validación del padrón compartidas por servicio, controlador y UI.
class ProducerRules {
  ProducerRules._();

  static final RegExp _codePattern = RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$');
  static final RegExp _placeChars = RegExp(
    r"^[\p{L}\p{M}\p{N} .,'#°()/&\-]+$",
    unicode: true,
  );
  static final RegExp _hasLetter = RegExp(r'\p{L}', unicode: true);

  /// Quita espacios al inicio/fin y colapsa espacios internos repetidos.
  static String collapse(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// "jUAN  carlos" -> "Juan Carlos" (respeta guiones y apóstrofos).
  static String titleCase(String value) {
    final String clean = collapse(value).toLowerCase();
    final StringBuffer out = StringBuffer();
    bool upperNext = true;
    for (final int rune in clean.runes) {
      final String ch = String.fromCharCode(rune);
      out.write(upperNext ? ch.toUpperCase() : ch);
      upperNext = ch == ' ' || ch == '-' || ch == "'";
    }
    return out.toString();
  }

  static String digitsOnly(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s'), '');

  static String? code(String? value) {
    final String s = collapse(value).toUpperCase();
    if (s.isEmpty) return 'El código de asociado es obligatorio';
    if (s.length > FieldLimits.code) {
      return 'Máximo ${FieldLimits.code} caracteres';
    }
    if (!_codePattern.hasMatch(s)) {
      return 'Usa letras, números y guion (ej. ASO-001)';
    }
    return null;
  }

  static String? place(
    String? value, {
    required String label,
    required int max,
  }) {
    final String s = collapse(value);
    final String? base = AppValidators.text(s, label: label, max: max);
    if (base != null) return base;
    if (!_placeChars.hasMatch(s)) {
      return 'Solo letras, números y puntuación básica';
    }
    if (!_hasLetter.hasMatch(s)) return '$label debe contener letras';
    return null;
  }

  static String? farm(String? value) =>
      place(value, label: 'El nombre de la finca', max: FieldLimits.farmName);

  static String? vereda(String? value) =>
      place(value, label: 'La vereda', max: FieldLimits.vereda);

  static String? names(String? value) =>
      AppValidators.personName(collapse(value), label: 'Los nombres');

  static String? surnames(String? value) =>
      AppValidators.personName(collapse(value), label: 'Los apellidos');

  static String? document(String? value) =>
      AppValidators.document(digitsOnly(value));

  static String? phone(String? value) => AppValidators.phone(digitsOnly(value));

  static String? authorizationReference(String? value) {
    final String s = collapse(value);
    if (s.isEmpty) return null; // Opcional: se genera una constancia automática.
    if (s.length < 3) return 'Mínimo 3 caracteres';
    if (s.length > FieldLimits.shortText) {
      return 'Máximo ${FieldLimits.shortText} caracteres';
    }
    if (RegExp(r'(.)\1{4,}').hasMatch(s)) return 'Revisa caracteres repetidos';
    return null;
  }

  /// Normaliza y valida todos los campos. Lanza [ProducerServiceException]
  /// con el primer error encontrado (campo + motivo).
  static ProducerInput normalize({
    required String codigoAsociado,
    required String cedula,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String nombreFinca,
    required String vereda,
    required String estado,
  }) {
    void check(String field, String? error) {
      if (error != null) throw ProducerServiceException('$field: $error.');
    }

    check('Nombres', names(nombres));
    check('Apellidos', surnames(apellidos));
    check('Cédula', document(cedula));
    check('Teléfono', phone(telefono));
    check('Código de asociado', code(codigoAsociado));
    check('Finca', farm(nombreFinca));
    check('Vereda', ProducerRules.vereda(vereda));

    final String cleanEstado = collapse(estado).toUpperCase();
    return ProducerInput(
      codigoAsociado: collapse(codigoAsociado).toUpperCase(),
      cedula: digitsOnly(cedula),
      nombres: titleCase(nombres),
      apellidos: titleCase(apellidos),
      telefono: digitsOnly(telefono),
      nombreFinca: collapse(nombreFinca),
      vereda: collapse(vereda),
      estado: cleanEstado == 'INACTIVO' ? 'INACTIVO' : 'ACTIVO',
    );
  }
}

/// Fuente de entregas de leche por rango de fechas (estadísticas del padrón).
abstract class ProducerDeliverySource {
  Future<List<MilkReceptionModel>> fetchDeliveries({
    required String startIso,
    required String endIso,
  });
}

/// Consulta `recepciones_leche` acotada por `fechaEntrega` (índice simple).
class FirestoreProducerDeliverySource implements ProducerDeliverySource {
  FirestoreProducerDeliverySource({this.firestore});

  final FirebaseFirestore? firestore;

  @override
  Future<List<MilkReceptionModel>> fetchDeliveries({
    required String startIso,
    required String endIso,
  }) async {
    final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
    final QuerySnapshot<Map<String, dynamic>> snap = await db
        .collection(AppConstants.receptionsCollection)
        .where('fechaEntrega', isGreaterThanOrEqualTo: startIso)
        .where('fechaEntrega', isLessThanOrEqualTo: endIso)
        .get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MilkReceptionModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }
}

/// Servicio MVC cliente-servidor + Hive para Gestión de Productores y Habeas Data (`RF-04` a `RF-07`).
class ProducerService {
  ProducerService({
    HiveService? hiveService,
    RemoteProducerDataSource? remoteDataSource,
    ProducerAccountLinker? accountLinker,
    ProducerDeliverySource? deliverySource,
  }) : _hiveService = hiveService ?? HiveService(),
       _remoteDataSource = remoteDataSource ?? FirestoreProducerDataSource(),
       _accountLinkerOverride = accountLinker,
       _deliverySourceOverride = deliverySource;

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteProducerDataSource _remoteDataSource;
  final ProducerAccountLinker? _accountLinkerOverride;
  final ProducerDeliverySource? _deliverySourceOverride;

  ProducerAccountLinker get _accountLinker =>
      _accountLinkerOverride ??
      FirebaseProducerAccountLinker(hiveService: _hiveService);

  ProducerDeliverySource? get _deliverySource {
    final ProducerDeliverySource? override = _deliverySourceOverride;
    if (override != null) return override;
    final RemoteProducerDataSource remote = _remoteDataSource;
    if (remote is FirestoreProducerDataSource) {
      return FirestoreProducerDeliverySource(firestore: remote.firestore);
    }
    return null;
  }

  /// Entregas no anuladas entre [startIso] y [endIso] (YYYY-MM-DD, inclusive).
  /// Combina la nube con las entregas locales pendientes; sin red usa Hive.
  Future<({List<MilkReceptionModel> deliveries, bool fromCache})>
  listDeliveries({required String startIso, required String endIso}) async {
    bool inRange(MilkReceptionModel r) =>
        !r.anulado &&
        r.fechaEntrega.compareTo(startIso) >= 0 &&
        r.fechaEntrega.compareTo(endIso) <= 0;

    List<MilkReceptionModel> local = const <MilkReceptionModel>[];
    try {
      local = (await _hiveService.getReceptions()).where(inRange).toList();
    } catch (_) {
      // Caché no disponible: continuar solo con la nube.
    }

    final ProducerDeliverySource? source = _deliverySource;
    if (source == null) {
      return (deliveries: local, fromCache: false);
    }
    try {
      final List<MilkReceptionModel> remote = await source.fetchDeliveries(
        startIso: startIso,
        endIso: endIso,
      );
      final Map<String, MilkReceptionModel> merged =
          <String, MilkReceptionModel>{
            for (final MilkReceptionModel r in remote) r.recepcionId: r,
          };
      for (final MilkReceptionModel r in local) {
        if (!r.isSynced || r.syncStatus != AppConstants.syncSynced) {
          merged[r.recepcionId] = r;
        }
      }
      return (
        deliveries: merged.values.where(inRange).toList(),
        fromCache: false,
      );
    } catch (_) {
      return (deliveries: local, fromCache: true);
    }
  }

  Future<({List<ProducerModel> producers, bool fromCache})>
  listProducers() async {
    try {
      final List<ProducerModel> remote = await _remoteDataSource
          .fetchProducers();
      remote.sort(
        (ProducerModel a, ProducerModel b) => a.nombreCompleto
            .toLowerCase()
            .compareTo(b.nombreCompleto.toLowerCase()),
      );
      await _hiveService.cacheProducers(remote);
      return (producers: remote, fromCache: false);
    } catch (_) {
      final List<ProducerModel> cached = await _hiveService
          .getCachedProducers();
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
        final ProducerModel? remote = await _remoteDataSource
            .fetchProducerByUid(user.uid);
        if (remote != null) {
          await _hiveService.upsertProducer(remote);
        }
        return remote;
      } on FirebaseException catch (error) {
        if (error.code != 'unavailable' && error.code != 'deadline-exceeded') {
          rethrow;
        }
      }
      final List<ProducerModel> cached = await _hiveService
          .getCachedProducers();
      for (final producer in cached) {
        if (producer.uidUsuario == user.uid) return producer;
      }
      return null;
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

  static String _pad2(int value) => value < 10 ? '0$value' : '$value';

  /// Genera una constancia digital automática y auditable conforme a `firestore.rules` y Ley 1581 de 2012.
  static String buildAutomaticAuthorizationReference({
    required String codigoAsociado,
    required DateTime timestampUtc,
  }) {
    final DateTime local = timestampUtc.toLocal();
    final String stamp =
        '${local.year}${_pad2(local.month)}${_pad2(local.day)}-${_pad2(local.hour)}${_pad2(local.minute)}';
    final String cleanCode = codigoAsociado
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '-');
    final String safeCode =
        cleanCode.length > 80 ? cleanCode.substring(0, 80) : cleanCode;
    return 'AUT-PLANTA-$safeCode-$stamp';
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
    PrivacyNotice? privacyNotice,
    String? authorizationReference,
    bool createMobileAccount = false,
    String? mobileEmail,
    String? mobilePassword,
  }) async {
    final ProducerInput input = ProducerRules.normalize(
      codigoAsociado: codigoAsociado,
      cedula: cedula,
      nombres: nombres,
      apellidos: apellidos,
      telefono: telefono,
      nombreFinca: nombreFinca,
      vereda: vereda,
      estado: estado,
    );
    final String cleanCode = input.codigoAsociado;
    final String cleanCedula = input.cedula;
    final String cleanNombres = input.nombres;
    final String cleanApellidos = input.apellidos;
    final String cleanPhone = input.telefono;
    final String cleanFinca = input.nombreFinca;
    final String cleanVereda = input.vereda;
    final String cleanEstado = input.estado;

    if (!aceptoHabeasData) {
      throw ProducerServiceException(
        'Debes confirmar la autorización de tratamiento de datos personales del productor (Ley 1581 de 2012).',
      );
    }

    final String? rawReference = authorizationReference == null
        ? null
        : ProducerRules.collapse(authorizationReference);
    if (rawReference != null && rawReference.length > FieldLimits.shortText) {
      throw ProducerServiceException(
        'El soporte de autorización admite máximo ${FieldLimits.shortText} caracteres.',
      );
    }
    if (_remoteDataSource is FirestoreProducerDataSource && privacyNotice == null) {
      throw ProducerServiceException(
        'No se pudo cargar el aviso de privacidad vigente. Reintenta antes de guardar.',
      );
    }
    // Sin referencia escrita se genera una constancia digital automática (AUT-PLANTA-…).
    final String reference = (rawReference == null || rawReference.isEmpty)
        ? buildAutomaticAuthorizationReference(
            codigoAsociado: cleanCode,
            timestampUtc: DateTime.now().toUtc(),
          )
        : rawReference;

    await validateUniqueCedulaAndCode(
      cedula: cleanCedula,
      codigoAsociado: cleanCode,
    );

    String? linkedUid;
    if (createMobileAccount) {
      final String email = (mobileEmail ?? '').trim().toLowerCase();
      final String pass = mobilePassword ?? '';
      if (AppValidators.email(email) != null ||
          AppValidators.password(pass) != null) {
        throw ProducerServiceException(
          'Para habilitar acceso móvil ingresa un correo válido y una contraseña de al menos 8 caracteres con letras y números.',
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
      avisoPrivacidad: privacyNotice?.data,
      soporteAutorizacion: reference,
      fechaCreacion: now,
      isSynced: false,
    );

    if (_remoteDataSource is FirestoreProducerDataSource) {
      return _saveAuditedProducer(model, actorUid: actorUid);
    }

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
    final ProducerInput input = ProducerRules.normalize(
      codigoAsociado: codigoAsociado,
      cedula: cedula,
      nombres: nombres,
      apellidos: apellidos,
      telefono: telefono,
      nombreFinca: nombreFinca,
      vereda: vereda,
      estado: estado,
    );
    final String cleanCode = input.codigoAsociado;
    final String cleanCedula = input.cedula;
    final String cleanNombres = input.nombres;
    final String cleanApellidos = input.apellidos;
    final String cleanPhone = input.telefono;
    final String cleanFinca = input.nombreFinca;
    final String cleanVereda = input.vereda;
    final String cleanEstado = input.estado;

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
      if (AppValidators.email(email) != null ||
          AppValidators.password(pass) != null) {
        throw ProducerServiceException(
          'Para habilitar acceso móvil ingresa un correo válido y una contraseña de al menos 8 caracteres con letras y números.',
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
      isSynced: false,
    );

    if (_remoteDataSource is FirestoreProducerDataSource) {
      return _saveAuditedProducer(
        updated,
        previous: previous,
        actorUid: actorUid,
      );
    }

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

    if (_remoteDataSource is FirestoreProducerDataSource) {
      return _saveAuditedProducer(
        updated,
        previous: producer,
        actorUid: actorUid,
        reason: 'Cambio de estado operativo del productor.',
      );
    }

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

  Future<ProducerModel> _saveAuditedProducer(
    ProducerModel producer, {
    ProducerModel? previous,
    required String actorUid,
    String? reason,
  }) async {
    final source = _remoteDataSource as FirestoreProducerDataSource;
    final saved = await source.saveAuditedProducer(
      producer,
      AuditLogModel(
        logId: _uuid.v4(),
        entidadAfectada: AppConstants.producersCollection,
        registroId: producer.productorId,
        accion: previous == null ? 'CREAR' : 'EDITAR',
        usuarioUid: actorUid,
        motivo: reason,
        timestamp: DateTime.now().toUtc(),
      ),
      previous: previous,
    );
    await _hiveService.upsertProducer(saved);
    return saved;
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
