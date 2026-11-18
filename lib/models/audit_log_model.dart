import 'model_parse_helpers.dart';

/// Bitácora inmutable de auditoría (`auditoria_logs`).
class AuditLogModel {
  const AuditLogModel({
    required this.logId,
    required this.entidadAfectada,
    required this.registroId,
    required this.accion,
    this.valorAnterior,
    this.valorNuevo,
    this.motivo,
    required this.usuarioUid,
    required this.timestamp,
  });

  final String logId;
  final String entidadAfectada;
  final String registroId;
  final String accion; // CREAR | EDITAR | LIQUIDAR | ANULAR
  final Map<String, dynamic>? valorAnterior;
  final Map<String, dynamic>? valorNuevo;
  final String? motivo;
  final String usuarioUid;
  final DateTime timestamp;

  factory AuditLogModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    Map<String, dynamic>? parseOptionalMap(dynamic raw) {
      if (raw is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(raw);
      }
      return null;
    }

    final String? motivoRaw = map['motivo']?.toString().trim();
    return AuditLogModel(
      logId: (map['logId'] ?? documentId ?? '').toString(),
      entidadAfectada: (map['entidadAfectada'] ?? '').toString(),
      registroId: (map['registroId'] ?? '').toString(),
      accion: (map['accion'] ?? '').toString().trim().toUpperCase(),
      valorAnterior: parseOptionalMap(map['valorAnterior']),
      valorNuevo: parseOptionalMap(map['valorNuevo']),
      motivo: (motivoRaw == null || motivoRaw.isEmpty) ? null : motivoRaw,
      usuarioUid: (map['usuarioUid'] ?? '').toString(),
      timestamp: parseUtcDate(map['timestamp']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'logId': logId,
      'entidadAfectada': entidadAfectada,
      'registroId': registroId,
      'accion': accion.trim().toUpperCase(),
      'valorAnterior': valorAnterior,
      'valorNuevo': valorNuevo,
      'motivo': motivo,
      'usuarioUid': usuarioUid,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}
