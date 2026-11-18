import 'model_parse_helpers.dart';

/// Entidad histórica de tarifa por litro de leche cruda (`tarifas_leche`).
class MilkRateModel {
  const MilkRateModel({
    required this.tarifaId,
    required this.precioPorLitro,
    required this.fechaInicioVigencia,
    this.fechaFinVigencia,
    required this.observacion,
    required this.registradoPorUid,
    this.activa = true,
  });

  final String tarifaId;
  final double precioPorLitro;
  final DateTime fechaInicioVigencia;
  final DateTime? fechaFinVigencia;
  final String observacion;
  final String registradoPorUid;
  final bool activa;

  bool isVigenteEn(DateTime fecha) {
    final DateTime target = fecha.toUtc();
    final bool afterStart = !target.isBefore(fechaInicioVigencia.toUtc());
    final bool beforeEnd =
        fechaFinVigencia == null || !target.isAfter(fechaFinVigencia!.toUtc());
    return activa && afterStart && beforeEnd;
  }

  factory MilkRateModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    return MilkRateModel(
      tarifaId: (map['tarifaId'] ?? documentId ?? '').toString(),
      precioPorLitro: parseSafeDouble(map['precioPorLitro']),
      fechaInicioVigencia: parseUtcDate(map['fechaInicioVigencia']),
      fechaFinVigencia: parseNullableUtcDate(map['fechaFinVigencia']),
      observacion: (map['observacion'] ?? '').toString().trim(),
      registradoPorUid: (map['registradoPorUid'] ?? '').toString(),
      activa: map['activa'] is bool ? map['activa'] as bool : true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tarifaId': tarifaId,
      'precioPorLitro': precioPorLitro,
      'fechaInicioVigencia': fechaInicioVigencia.toUtc().toIso8601String(),
      'fechaFinVigencia': fechaFinVigencia?.toUtc().toIso8601String(),
      'observacion': observacion.trim(),
      'registradoPorUid': registradoPorUid,
      'activa': activa,
    };
  }

  MilkRateModel copyWith({
    String? tarifaId,
    double? precioPorLitro,
    DateTime? fechaInicioVigencia,
    DateTime? fechaFinVigencia,
    bool clearFechaFinVigencia = false,
    String? observacion,
    String? registradoPorUid,
    bool? activa,
  }) {
    return MilkRateModel(
      tarifaId: tarifaId ?? this.tarifaId,
      precioPorLitro: precioPorLitro ?? this.precioPorLitro,
      fechaInicioVigencia: fechaInicioVigencia ?? this.fechaInicioVigencia,
      fechaFinVigencia: clearFechaFinVigencia
          ? null
          : (fechaFinVigencia ?? this.fechaFinVigencia),
      observacion: observacion ?? this.observacion,
      registradoPorUid: registradoPorUid ?? this.registradoPorUid,
      activa: activa ?? this.activa,
    );
  }
}
