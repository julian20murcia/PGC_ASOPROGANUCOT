import '../core/constants/app_constants.dart';
import 'model_parse_helpers.dart';

/// Registro diario de recepción de leche cruda (`recepciones_leche` / `deliveries_box`).
class MilkReceptionModel {
  const MilkReceptionModel({
    required this.recepcionId,
    required this.productorId,
    required this.codigoAsociadoSnap,
    required this.nombreProductorSnap,
    required this.litros,
    required this.fechaEntrega,
    required this.horaEntrega,
    required this.jornada,
    required this.operarioUid,
    this.syncStatus = AppConstants.syncPending,
    this.isSynced = false,
    this.liquidacionId,
    this.anulado = false,
    this.motivoAnulacion,
    required this.createdAt,
    this.auditLogId,
    this.updatedAt,
    this.updatedByUid,
  });

  final String recepcionId; // UUID v4 idempotente
  final String productorId;
  final String codigoAsociadoSnap;
  final String nombreProductorSnap;
  final double litros;
  final String fechaEntrega; // YYYY-MM-DD
  final String horaEntrega; // HH:mm:ss
  final String jornada; // MANANA | TARDE
  final String operarioUid;
  final String syncStatus; // PENDIENTE | SINCRONIZADO
  final bool isSynced;
  final String? liquidacionId;
  final bool anulado;
  final String? motivoAnulacion;
  final DateTime createdAt;
  final String? auditLogId;
  final DateTime? updatedAt;
  final String? updatedByUid;

  bool get isLiquidada =>
      liquidacionId != null && liquidacionId!.trim().isNotEmpty;

  bool get canBeModified => !isLiquidada && !anulado;

  String get duplicateKey =>
      '${productorId.trim()}_${fechaEntrega.trim()}_${jornada.trim().toUpperCase()}';

  factory MilkReceptionModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final String? liqRaw = map['liquidacionId']?.toString().trim();
    final String? motivoRaw = map['motivoAnulacion']?.toString().trim();
    final String rawStatus = (map['syncStatus'] ?? '').toString().toUpperCase();
    final bool parsedSynced = map['isSynced'] is bool
        ? map['isSynced'] as bool
        : rawStatus == AppConstants.syncSynced;
    final String resolvedStatus = rawStatus.isNotEmpty
        ? rawStatus
        : (parsedSynced ? AppConstants.syncSynced : AppConstants.syncPending);

    return MilkReceptionModel(
      recepcionId: (map['recepcionId'] ?? documentId ?? '').toString(),
      productorId: (map['productorId'] ?? '').toString(),
      codigoAsociadoSnap: (map['codigoAsociadoSnap'] ?? '').toString(),
      nombreProductorSnap: (map['nombreProductorSnap'] ?? '').toString(),
      litros: parseSafeDouble(map['litros']),
      fechaEntrega: (map['fechaEntrega'] ?? '').toString(),
      horaEntrega: (map['horaEntrega'] ?? '').toString(),
      jornada: (map['jornada'] ?? AppConstants.shiftMorning)
          .toString()
          .toUpperCase(),
      operarioUid: (map['operarioUid'] ?? '').toString(),
      syncStatus: resolvedStatus,
      isSynced: parsedSynced,
      liquidacionId: (liqRaw == null || liqRaw.isEmpty) ? null : liqRaw,
      anulado: map['anulado'] == true,
      motivoAnulacion:
          (motivoRaw == null || motivoRaw.isEmpty) ? null : motivoRaw,
      createdAt: parseUtcDate(map['createdAt']),
      auditLogId: map['auditLogId'] as String?,
      updatedAt: parseNullableUtcDate(map['updatedAt']),
      updatedByUid: map['updatedByUid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'recepcionId': recepcionId,
      'productorId': productorId,
      'codigoAsociadoSnap': codigoAsociadoSnap,
      'nombreProductorSnap': nombreProductorSnap,
      'litros': litros,
      'fechaEntrega': fechaEntrega,
      'horaEntrega': horaEntrega,
      'jornada': jornada.toUpperCase(),
      'operarioUid': operarioUid,
      'syncStatus': syncStatus,
      'isSynced': isSynced,
      'liquidacionId': liquidacionId,
      'anulado': anulado,
      'motivoAnulacion': motivoAnulacion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (auditLogId != null) 'auditLogId': auditLogId,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (updatedByUid != null) 'updatedByUid': updatedByUid,
    };
  }

  MilkReceptionModel copyWith({
    String? recepcionId,
    String? productorId,
    String? codigoAsociadoSnap,
    String? nombreProductorSnap,
    double? litros,
    String? fechaEntrega,
    String? horaEntrega,
    String? jornada,
    String? operarioUid,
    String? syncStatus,
    bool? isSynced,
    String? liquidacionId,
    bool clearLiquidacionId = false,
    bool? anulado,
    String? motivoAnulacion,
    DateTime? createdAt,
    String? auditLogId,
  }) {
    return MilkReceptionModel(
      recepcionId: recepcionId ?? this.recepcionId,
      productorId: productorId ?? this.productorId,
      codigoAsociadoSnap: codigoAsociadoSnap ?? this.codigoAsociadoSnap,
      nombreProductorSnap: nombreProductorSnap ?? this.nombreProductorSnap,
      litros: litros ?? this.litros,
      fechaEntrega: fechaEntrega ?? this.fechaEntrega,
      horaEntrega: horaEntrega ?? this.horaEntrega,
      jornada: jornada ?? this.jornada,
      operarioUid: operarioUid ?? this.operarioUid,
      syncStatus: syncStatus ?? this.syncStatus,
      isSynced: isSynced ?? this.isSynced,
      liquidacionId:
          clearLiquidacionId ? null : (liquidacionId ?? this.liquidacionId),
      anulado: anulado ?? this.anulado,
      motivoAnulacion: motivoAnulacion ?? this.motivoAnulacion,
      createdAt: createdAt ?? this.createdAt,
      auditLogId: auditLogId ?? this.auditLogId,
      updatedAt: updatedAt,
      updatedByUid: updatedByUid,
    );
  }
}
