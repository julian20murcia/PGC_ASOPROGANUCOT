import '../core/constants/app_constants.dart';

/// Entidad pura de usuario del sistema ASOPROGANUCOT (Sección 3.3).
///
/// Soporta serialización hacia Cloud Firestore y almacenamiento local en Hive.
class UserModel {
  const UserModel({
    required this.uid,
    required this.nombreCompleto,
    required this.documento,
    required this.correo,
    required this.telefono,
    required this.rol,
    required this.activo,
    required this.fcmTokens,
    required this.fechaCreacion,
    this.ultimoAcceso,
    this.isBootstrapSession = false,
  });

  final String uid;
  final String nombreCompleto;
  final String documento;
  final String correo;
  final String telefono;
  final String rol;
  final bool activo;
  final List<String> fcmTokens;
  final DateTime fechaCreacion;
  final DateTime? ultimoAcceso;
  final bool isBootstrapSession;

  bool get isAdmin => rol == AppConstants.roleAdmin;
  bool get isOperario => rol == AppConstants.roleOperario;
  bool get isProductor => rol == AppConstants.roleProductor;
  bool get canAccessDesktopAdmin => isAdmin || isOperario;
  bool get canManageUsers => isAdmin;
  bool get canConfigureRatesOrSettle => isAdmin;
  bool get canRecordReceptions => isAdmin || isOperario;

  String get initials {
    final List<String> parts = nombreCompleto
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'AS';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Sesión temporal para configuración inicial sin credenciales.
  factory UserModel.bootstrapAdmin() {
    final DateTime now = DateTime.now().toUtc();
    return UserModel(
      uid: 'bootstrap-admin',
      nombreCompleto: 'Configuración Inicial',
      documento: '0000000000',
      correo: 'configuracion@asoproganucot.local',
      telefono: '',
      rol: AppConstants.roleAdmin,
      activo: true,
      fcmTokens: const <String>[],
      fechaCreacion: now,
      ultimoAcceso: now,
      isBootstrapSession: true,
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map, {String? documentId}) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) {
        return value.toUtc();
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      // Soporte para Timestamp de Firestore sin acoplar el modelo al SDK.
      if (value != null) {
        try {
          final dynamic converted = (value as dynamic).toDate();
          if (converted is DateTime) {
            return converted.toUtc();
          }
        } catch (_) {}
      }
      return DateTime.now().toUtc();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value == null) {
        return null;
      }
      return parseDate(value);
    }

    final List<String> tokens = (map['fcmTokens'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic e) => e.toString())
        .where((String e) => e.isNotEmpty)
        .toList();

    return UserModel(
      uid: (map['uid'] ?? documentId ?? '').toString(),
      nombreCompleto: (map['nombreCompleto'] ?? '').toString(),
      documento: (map['documento'] ?? '').toString(),
      correo: (map['correo'] ?? '').toString(),
      telefono: (map['telefono'] ?? '').toString(),
      rol: (map['rol'] ?? AppConstants.roleProductor).toString().toUpperCase(),
      activo: map['activo'] is bool ? map['activo'] as bool : true,
      fcmTokens: tokens,
      fechaCreacion: parseDate(map['fechaCreacion']),
      ultimoAcceso: parseNullableDate(map['ultimoAcceso']),
      isBootstrapSession: map['isBootstrapSession'] == true,
    );
  }

  Map<String, dynamic> toMap({bool includeBootstrapFlag = false}) {
    final Map<String, dynamic> data = <String, dynamic>{
      'uid': uid,
      'nombreCompleto': nombreCompleto.trim(),
      'documento': documento.trim(),
      'correo': correo.trim().toLowerCase(),
      'telefono': telefono.trim(),
      'rol': rol,
      'activo': activo,
      'fcmTokens': fcmTokens,
      'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
      'ultimoAcceso': ultimoAcceso?.toUtc().toIso8601String(),
    };
    if (includeBootstrapFlag) {
      data['isBootstrapSession'] = isBootstrapSession;
    }
    return data;
  }

  UserModel copyWith({
    String? uid,
    String? nombreCompleto,
    String? documento,
    String? correo,
    String? telefono,
    String? rol,
    bool? activo,
    List<String>? fcmTokens,
    DateTime? fechaCreacion,
    DateTime? ultimoAcceso,
    bool? isBootstrapSession,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      documento: documento ?? this.documento,
      correo: correo ?? this.correo,
      telefono: telefono ?? this.telefono,
      rol: rol ?? this.rol,
      activo: activo ?? this.activo,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      ultimoAcceso: ultimoAcceso ?? this.ultimoAcceso,
      isBootstrapSession: isBootstrapSession ?? this.isBootstrapSession,
    );
  }
}
