import 'package:cloud_firestore/cloud_firestore.dart';

class PrivacyNotice {
  PrivacyNotice._(this.data);

  static const List<String> fields = <String>[
    'version', 'responsable', 'direccion', 'correo', 'telefono',
    'politicaUrl', 'finalidades', 'derechos',
  ];

  final Map<String, String> data;

  factory PrivacyNotice.fromMap(Map<String, dynamic> map) {
    final values = <String, String>{};
    for (final field in fields) {
      final value = map[field];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('El aviso de privacidad está incompleto.');
      }
      values[field] = value;
    }
    final Uri? policy = Uri.tryParse(values['politicaUrl']!);
    if (policy == null || policy.scheme != 'https' || policy.host.isEmpty) {
      throw const FormatException('La política de tratamiento requiere una dirección HTTPS.');
    }
    return PrivacyNotice._(Map<String, String>.unmodifiable(values));
  }

  static Future<PrivacyNotice> load() async {
    final snapshot = await FirebaseFirestore.instance.doc('configuracion/privacidad').get();
    return PrivacyNotice.fromMap(snapshot.data() ?? const <String, dynamic>{});
  }
}
