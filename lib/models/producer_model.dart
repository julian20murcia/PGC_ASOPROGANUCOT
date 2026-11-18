import 'model_parse_helpers.dart';

/// Entidad de productor ganadero asociado en Susa (`productores`).
class ProducerModel {
  const ProducerModel({
    required this.productorId,
    this.uidUsuario,
    required this.codigoAsociado,
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    required this.telefono,
    required this.nombreFinca,
    required this.vereda,
    required this.estado,
    required this.aceptoHabeasData,
    this.fechaAutorizacionDatos,
    this.autorizadoPorUid,
    this.avisoPrivacidad,
    this.soporteAutorizacion,
    this.auditLogId,
    required this.fechaCreacion,
    this.isSynced = true,
  });

  final String productorId;
  final String? uidUsuario;
  final String codigoAsociado;
  final String cedula;
  final String nombres;
  final String apellidos;
  final String telefono;
  final String nombreFinca;
  final String vereda;
  final String estado; // ACTIVO | INACTIVO
  final bool aceptoHabeasData;
  final DateTime? fechaAutorizacionDatos;
  final String? autorizadoPorUid;
  final Map<String, dynamic>? avisoPrivacidad;
  final String? soporteAutorizacion;
  final String? auditLogId;
  final DateTime fechaCreacion;
  final bool isSynced;

  String get nombreCompleto =>
      '${nombres.trim()} ${apellidos.trim()}'.trim();

  bool get isActivo => estado.toUpperCase() == 'ACTIVO';

  bool get hasValidHabeasData =>
      aceptoHabeasData && fechaAutorizacionDatos != null;

  factory ProducerModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final String? uidUsuarioRaw = map['uidUsuario']?.toString().trim();
    final String? authUidRaw = map['autorizadoPorUid']?.toString().trim();
    return ProducerModel(
      productorId: (map['productorId'] ?? documentId ?? '').toString(),
      uidUsuario:
          (uidUsuarioRaw == null || uidUsuarioRaw.isEmpty) ? null : uidUsuarioRaw,
      codigoAsociado: (map['codigoAsociado'] ?? '').toString().trim(),
      cedula: (map['cedula'] ?? '').toString().trim(),
      nombres: (map['nombres'] ?? '').toString().trim(),
      apellidos: (map['apellidos'] ?? '').toString().trim(),
      telefono: (map['telefono'] ?? '').toString().trim(),
      nombreFinca: (map['nombreFinca'] ?? '').toString().trim(),
      vereda: (map['vereda'] ?? '').toString().trim(),
      estado: (map['estado'] ?? 'ACTIVO').toString().trim().toUpperCase(),
      aceptoHabeasData: map['aceptoHabeasData'] == true,
      fechaAutorizacionDatos:
          parseNullableUtcDate(map['fechaAutorizacionDatos']),
      autorizadoPorUid:
          (authUidRaw == null || authUidRaw.isEmpty) ? null : authUidRaw,
      avisoPrivacidad: map['avisoPrivacidad'] is Map
          ? Map<String, dynamic>.from(map['avisoPrivacidad'] as Map)
          : null,
      soporteAutorizacion: map['soporteAutorizacion'] as String?,
      auditLogId: map['auditLogId'] as String?,
      fechaCreacion: parseUtcDate(map['fechaCreacion']),
      isSynced: map['isSynced'] is bool ? map['isSynced'] as bool : true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productorId': productorId,
      'uidUsuario': uidUsuario,
      'codigoAsociado': codigoAsociado.trim().toUpperCase(),
      'cedula': cedula.trim(),
      'nombres': nombres.trim(),
      'apellidos': apellidos.trim(),
      'telefono': telefono.trim(),
      'nombreFinca': nombreFinca.trim(),
      'vereda': vereda.trim(),
      'estado': estado.trim().toUpperCase(),
      'aceptoHabeasData': aceptoHabeasData,
      'fechaAutorizacionDatos':
          fechaAutorizacionDatos?.toUtc().toIso8601String(),
      'autorizadoPorUid': autorizadoPorUid,
      if (avisoPrivacidad != null) 'avisoPrivacidad': avisoPrivacidad,
      if (soporteAutorizacion != null) 'soporteAutorizacion': soporteAutorizacion,
      if (auditLogId != null) 'auditLogId': auditLogId,
      'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
      'isSynced': isSynced,
    };
  }

  ProducerModel copyWith({
    String? productorId,
    String? uidUsuario,
    bool clearUidUsuario = false,
    String? codigoAsociado,
    String? cedula,
    String? nombres,
    String? apellidos,
    String? telefono,
    String? nombreFinca,
    String? vereda,
    String? estado,
    bool? aceptoHabeasData,
    DateTime? fechaAutorizacionDatos,
    String? autorizadoPorUid,
    DateTime? fechaCreacion,
    bool? isSynced,
    String? auditLogId,
  }) {
    return ProducerModel(
      productorId: productorId ?? this.productorId,
      uidUsuario: clearUidUsuario ? null : (uidUsuario ?? this.uidUsuario),
      codigoAsociado: codigoAsociado ?? this.codigoAsociado,
      cedula: cedula ?? this.cedula,
      nombres: nombres ?? this.nombres,
      apellidos: apellidos ?? this.apellidos,
      telefono: telefono ?? this.telefono,
      nombreFinca: nombreFinca ?? this.nombreFinca,
      vereda: vereda ?? this.vereda,
      estado: estado ?? this.estado,
      aceptoHabeasData: aceptoHabeasData ?? this.aceptoHabeasData,
      fechaAutorizacionDatos:
          fechaAutorizacionDatos ?? this.fechaAutorizacionDatos,
      autorizadoPorUid: autorizadoPorUid ?? this.autorizadoPorUid,
      avisoPrivacidad: avisoPrivacidad,
      soporteAutorizacion: soporteAutorizacion,
      auditLogId: auditLogId ?? this.auditLogId,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
