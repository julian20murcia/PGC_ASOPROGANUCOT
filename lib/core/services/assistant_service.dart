import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_callable.dart';

/// Mensaje de la conversación con el asistente IA.
class AssistantMessage {
  const AssistantMessage({required this.fromUser, required this.text, required this.at});
  final bool fromUser;
  final String text;
  final DateTime at;

  Map<String, String> toWire() => <String, String>{
        'role': fromUser ? 'user' : 'model',
        'text': text.length > 1500 ? text.substring(0, 1500) : text,
      };
}

class AssistantException implements Exception {
  AssistantException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cliente del asistente IA. La clave de Gemini vive SOLO en la Cloud
/// Function `askAssistant` (Secret Manager); la app nunca la conoce.
class AssistantService {
  AssistantService({FirebaseAuth? auth}) : _auth = auth; // ignore: prefer_initializing_formals
  final FirebaseAuth? _auth;

  static const int maxQuestionLength = 600;
  static const int maxHistory = 8;

  Future<String> ask(String question, {List<AssistantMessage> history = const <AssistantMessage>[]}) async {
    final String q = question.trim();
    if (q.isEmpty) throw AssistantException('Escribe una pregunta.');
    if (q.length > maxQuestionLength) {
      throw AssistantException('La pregunta es muy larga (máx. $maxQuestionLength caracteres).');
    }
    final User? me = (_auth ?? FirebaseAuth.instance).currentUser;
    if (me == null) throw AssistantException('Tu sesión expiró. Vuelve a iniciar sesión.');
    final List<AssistantMessage> recent =
        history.length > maxHistory ? history.sublist(history.length - maxHistory) : history;
    try {
      final String? token = await me.getIdToken();
      final Map<String, dynamic> result = await callFirebaseFunction(
        'askAssistant',
        <String, dynamic>{
          'question': q,
          'history': recent.map((AssistantMessage m) => m.toWire()).toList(),
        },
        idToken: token,
        timeout: const Duration(seconds: 60),
      );
      final String answer = (result['answer'] ?? '').toString().trim();
      if (answer.isEmpty) throw AssistantException('El asistente no devolvió respuesta.');
      return answer;
    } on StateError catch (e) {
      throw AssistantException(e.message);
    } on AssistantException {
      rethrow;
    } catch (_) {
      throw AssistantException('No hay conexión con el asistente. Verifica tu internet.');
    }
  }
}
