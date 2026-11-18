import 'model_parse_helpers.dart';

/// Notificación individual o comunicado institucional (`notificaciones`).
class AppNotificationModel {
  const AppNotificationModel({
    required this.notificacionId,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    this.destinoProductorId,
    required this.fechaEnvio,
    this.leida = false,
  });

  final String notificacionId;
  final String titulo;
  final String mensaje;
  final String tipo; // ENTREGA | CIERRE_QUINCENA | PAGO | COMUNICADO
  final String? destinoProductorId; // null => comunicado general
  final DateTime fechaEnvio;
  final bool leida;

  factory AppNotificationModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final String? destRaw = map['destinoProductorId']?.toString().trim();
    return AppNotificationModel(
      notificacionId:
          (map['notificacionId'] ?? documentId ?? '').toString(),
      titulo: (map['titulo'] ?? '').toString().trim(),
      mensaje: (map['mensaje'] ?? '').toString().trim(),
      tipo: (map['tipo'] ?? 'COMUNICADO').toString().trim().toUpperCase(),
      destinoProductorId:
          (destRaw == null || destRaw.isEmpty) ? null : destRaw,
      fechaEnvio: parseUtcDate(map['fechaEnvio']),
      leida: map['leida'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'notificacionId': notificacionId,
      'titulo': titulo.trim(),
      'mensaje': mensaje.trim(),
      'tipo': tipo.trim().toUpperCase(),
      'destinoProductorId': destinoProductorId,
      'fechaEnvio': fechaEnvio.toUtc().toIso8601String(),
      'leida': leida,
    };
  }

  AppNotificationModel copyWith({
    String? notificacionId,
    String? titulo,
    String? mensaje,
    String? tipo,
    String? destinoProductorId,
    DateTime? fechaEnvio,
    bool? leida,
  }) {
    return AppNotificationModel(
      notificacionId: notificacionId ?? this.notificacionId,
      titulo: titulo ?? this.titulo,
      mensaje: mensaje ?? this.mensaje,
      tipo: tipo ?? this.tipo,
      destinoProductorId: destinoProductorId ?? this.destinoProductorId,
      fechaEnvio: fechaEnvio ?? this.fechaEnvio,
      leida: leida ?? this.leida,
    );
  }
}
