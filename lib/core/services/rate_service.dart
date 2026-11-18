import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_rate_model.dart';
import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import '../utils/formatters.dart';
import 'hive_service.dart';

class RateServiceException implements Exception {
  RateServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Fuente remota abstracta para `tarifas_leche` y bitácora de tarifas.
abstract class RemoteRateDataSource {
  Future<List<MilkRateModel>> fetchRates();
  Future<void> saveRatesBatch(List<MilkRateModel> rates);
  Future<void> appendAuditLog(AuditLogModel log);
}

class FirestoreRateDataSource implements RemoteRateDataSource {
  FirestoreRateDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<MilkRateModel>> fetchRates() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.ratesCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MilkRateModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {
    if (rates.isEmpty) return;
    final WriteBatch batch = _db.batch();
    for (final MilkRateModel rate in rates) {
      final DocumentReference<Map<String, dynamic>> ref =
          _db.collection(AppConstants.ratesCollection).doc(rate.tarifaId);
      batch.set(ref, rate.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {
    try {
      await _db
          .collection(AppConstants.auditLogsCollection)
          .doc(log.logId)
          .set(log.toMap());
    } catch (_) {
      // La auditoría remota no debe revertir operaciones ya confirmadas localmente.
    }
  }
}

/// Servicio MVC de gestión de tarifa histórica por litro (`RF-12`, `HU-06`).
class RateService {
  RateService({
    HiveService? hiveService,
    RemoteRateDataSource? remoteDataSource,
  })  : _hiveService = hiveService ?? HiveService(),
        _remoteDataSource = remoteDataSource ?? FirestoreRateDataSource();

  static const Uuid _uuid = Uuid();

  final HiveService _hiveService;
  final RemoteRateDataSource _remoteDataSource;

  /// Lista las vigencias de tarifa ordenadas de la más reciente a la más antigua.
  Future<({List<MilkRateModel> rates, bool fromCache})> listRates() async {
    try {
      final List<MilkRateModel> remote = await _remoteDataSource.fetchRates();
      await _hiveService.cacheMilkRates(remote);
      return (rates: _sortedRates(remote), fromCache: false);
    } catch (_) {
      final List<MilkRateModel> cached = await _hiveService.getCachedMilkRates();
      return (rates: _sortedRates(cached), fromCache: true);
    }
  }

  /// Obtiene la tarifa vigente para [atDate] (o la tarifa activa actual).
  Future<MilkRateModel?> getActiveRate({DateTime? atDate}) async {
    final result = await listRates();
    return resolveRateForDate(result.rates, atDate ?? DateTime.now());
  }

  /// Resuelve en memoria qué tarifa histórica corresponde a [atDate].
  static MilkRateModel? resolveRateForDate(
    List<MilkRateModel> rates,
    DateTime atDate,
  ) {
    if (rates.isEmpty) return null;
    final List<MilkRateModel> sorted = _sortedRates(rates);
    final DateTime target = atDate.toUtc();
    for (final MilkRateModel rate in sorted) {
      if (rate.isVigenteEn(target)) {
        return rate;
      }
    }
    for (final MilkRateModel rate in sorted) {
      if (rate.activa) {
        return rate;
      }
    }
    return sorted.first;
  }

  /// Crea una nueva vigencia de tarifa por litro sin sobrescribir ni alterar precios históricos (`RF-12`).
  Future<MilkRateModel> createNewRate({
    required UserModel actor,
    required double precioPorLitro,
    required DateTime fechaInicioVigencia,
    required String observacion,
  }) async {
    if (!actor.isAdmin) {
      throw RateServiceException(
        'Solo el Administrador Central puede actualizar la tarifa por litro.',
      );
    }

    final double normalizedPrice = (precioPorLitro * 100).roundToDouble() / 100;
    if (normalizedPrice <= 0) {
      throw RateServiceException(
        'El precio por litro debe ser mayor a cero.',
      );
    }

    final String trimmedObs = observacion.trim();
    if (trimmedObs.length < 5) {
      throw RateServiceException(
        'Ingresa una observación o justificación de al menos 5 caracteres.',
      );
    }

    final List<MilkRateModel> existingRates =
        (await listRates()).rates;

    final DateTime startUtc = fechaInicioVigencia.toUtc();
    final DateTime closingStamp =
        startUtc.subtract(const Duration(milliseconds: 1));

    MilkRateModel? previousActive;
    final List<MilkRateModel> closedRates = <MilkRateModel>[];
    for (final MilkRateModel existing in existingRates) {
      if (existing.activa) {
        previousActive ??= existing;
        final DateTime endUtc = closingStamp.isAfter(existing.fechaInicioVigencia)
            ? closingStamp
            : existing.fechaInicioVigencia;
        closedRates.add(
          existing.copyWith(
            activa: false,
            fechaFinVigencia: endUtc,
          ),
        );
      }
    }

    final MilkRateModel created = MilkRateModel(
      tarifaId: _uuid.v4(),
      precioPorLitro: normalizedPrice,
      fechaInicioVigencia: startUtc,
      fechaFinVigencia: null,
      observacion: trimmedObs,
      registradoPorUid: actor.uid,
      activa: true,
    );

    final List<MilkRateModel> toSave = <MilkRateModel>[
      ...closedRates,
      created,
    ];

    try {
      await _remoteDataSource.saveRatesBatch(toSave);
    } catch (_) {
      throw RateServiceException(
        'No se pudo guardar la nueva tarifa. Verifica la conexión e intenta de nuevo.',
      );
    }

    for (final MilkRateModel rate in toSave) {
      await _hiveService.upsertMilkRate(rate);
    }

    await _remoteDataSource.appendAuditLog(
      AuditLogModel(
        logId: _uuid.v4(),
        modulo: 'TARIFAS',
        accion: 'ACTUALIZAR_TARIFA_LITRO',
        referenciaId: created.tarifaId,
        valorAnterior: previousActive == null
            ? null
            : <String, dynamic>{
                'tarifaId': previousActive.tarifaId,
                'precioPorLitro': previousActive.precioPorLitro,
              },
        valorNuevo: <String, dynamic>{
          'tarifaId': created.tarifaId,
          'precioPorLitro': created.precioPorLitro,
          'fechaInicioVigencia': AppFormatters.formatDate(startUtc),
        },
        motivo: trimmedObs,
        usuarioUid: actor.uid,
        usuarioNombre: actor.nombreCompleto,
        fechaEvento: DateTime.now().toUtc(),
      ),
    );

    return created;
  }

  static List<MilkRateModel> _sortedRates(List<MilkRateModel> items) {
    final List<MilkRateModel> copy = List<MilkRateModel>.from(items);
    copy.sort((MilkRateModel a, MilkRateModel b) {
      if (a.activa != b.activa) {
        return a.activa ? -1 : 1;
      }
      return b.fechaInicioVigencia.compareTo(a.fechaInicioVigencia);
    });
    return copy;
  }
}
