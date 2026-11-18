/// Utilidades puras de conversión segura entre mapas Firestore/Hive y modelos de dominio.
DateTime parseUtcDate(dynamic value, {DateTime? fallback}) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toUtc() ??
        (fallback ?? DateTime.now().toUtc());
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
  return fallback ?? DateTime.now().toUtc();
}

DateTime? parseNullableUtcDate(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String && value.trim().isEmpty) {
    return null;
  }
  return parseUtcDate(value);
}

double parseSafeDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? defaultValue;
  }
  return defaultValue;
}

int parseSafeInt(dynamic value, {int defaultValue = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? defaultValue;
  }
  return defaultValue;
}
