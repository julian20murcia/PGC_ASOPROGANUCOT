import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../firebase_options.dart';

/// Protocolo HTTPS callable para las plataformas sin SDK de Functions.
Future<Map<String, dynamic>> callFirebaseFunction(
  String name,
  Map<String, dynamic> data, {
  String? idToken,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final project = DefaultFirebaseOptions.currentPlatform.projectId;
  final response = await http
      .post(
        Uri.https('us-central1-$project.cloudfunctions.net', '/$name'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(<String, dynamic>{'data': data}),
      )
      .timeout(timeout);
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200 ||
      decoded['result'] is! Map<String, dynamic>) {
    final error = decoded['error'];
    throw StateError(
      error is Map
          ? '${error['message']}'
          : 'Servicio de Firebase no disponible.',
    );
  }
  return decoded['result'] as Map<String, dynamic>;
}
