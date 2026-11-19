import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import '../../models/assistant_report.dart';
import 'firebase_callable.dart';
import 'live_transcription.dart';

/// Mensaje de la conversación con el asistente IA.
class AssistantMessage {
  const AssistantMessage({required this.fromUser, required this.text, required this.at});
  final bool fromUser;
  final String text;
  final DateTime at;

  Map<String, String> toWire() => <String, String>{
        'role': fromUser ? 'user' : 'assistant',
        'text': text.length > 1500 ? text.substring(0, 1500) : text,
      };
}

/// Respuesta del asistente: texto (markdown) y, si se pidió, un informe descargable.
class AssistantAnswer {
  const AssistantAnswer(this.text, {this.report});
  final String text;
  final AssistantReport? report;
}

class AssistantException implements Exception {
  AssistantException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cliente del asistente IA (OpenAI). La clave vive SOLO en las Cloud
/// Functions `askAssistant` y `transcribeAudio` (Secret Manager); la app
/// nunca la conoce.
class AssistantService {
  AssistantService({FirebaseAuth? auth}) : _auth = auth; // ignore: prefer_initializing_formals
  final FirebaseAuth? _auth;

  static const int maxQuestionLength = 1500;
  static const int maxHistory = 8;

  /// Tamaño máximo del audio dictado (coincide con el límite del servidor).
  static const int maxAudioBytes = 6 * 1024 * 1024;

  Future<String> _token() async {
    final User? me = (_auth ?? FirebaseAuth.instance).currentUser;
    if (me == null) throw AssistantException('Tu sesión expiró. Vuelve a iniciar sesión.');
    final String? token = await me.getIdToken();
    if (token == null) throw AssistantException('Tu sesión expiró. Vuelve a iniciar sesión.');
    return token;
  }

  Future<AssistantAnswer> ask(String question, {List<AssistantMessage> history = const <AssistantMessage>[]}) async {
    final String q = question.trim();
    if (q.isEmpty) throw AssistantException('Escribe una pregunta.');
    if (q.length > maxQuestionLength) {
      throw AssistantException('La pregunta es muy larga (máx. $maxQuestionLength caracteres).');
    }
    final List<AssistantMessage> recent =
        history.length > maxHistory ? history.sublist(history.length - maxHistory) : history;
    try {
      final String token = await _token();
      final Map<String, dynamic> result = await callFirebaseFunction(
        'askAssistant',
        <String, dynamic>{
          'question': q,
          'history': recent.map((AssistantMessage m) => m.toWire()).toList(),
        },
        idToken: token,
        // Los informes con varias consultas pueden tardar más que una respuesta simple.
        timeout: const Duration(seconds: 240),
      );
      final String answer = (result['answer'] ?? '').toString().trim();
      final Object? rawReport = result['report'];
      final AssistantReport? report =
          rawReport is Map ? AssistantReport.tryParse(Map<String, dynamic>.from(rawReport)) : null;
      if (answer.isEmpty && report == null) throw AssistantException('El asistente no devolvió respuesta.');
      return AssistantAnswer(answer, report: report);
    } on StateError catch (e) {
      throw AssistantException(e.message);
    } on AssistantException {
      rethrow;
    } catch (_) {
      throw AssistantException('No hay conexión con el asistente. Verifica tu internet.');
    }
  }

  /// Credenciales temporales para el dictado en vivo (Realtime API).
  Future<VoiceSessionTicket> createVoiceSession() async {
    try {
      final String token = await _token();
      final Map<String, dynamic> result = await callFirebaseFunction(
        'createVoiceSession',
        const <String, dynamic>{},
        idToken: token,
        timeout: const Duration(seconds: 25),
      );
      final String secret = (result['secret'] ?? '').toString();
      final String url = (result['url'] ?? '').toString();
      if (secret.isEmpty || !url.startsWith('wss://')) {
        throw AssistantException('No se pudo iniciar el dictado. Intenta de nuevo.');
      }
      final Object? rate = result['sampleRate'];
      return VoiceSessionTicket(secret: secret, url: url, sampleRate: rate is num ? rate.toInt() : 24000);
    } on StateError catch (e) {
      throw AssistantException(e.message);
    } on AssistantException {
      rethrow;
    } catch (_) {
      throw AssistantException('No se pudo iniciar el dictado. Verifica tu internet.');
    }
  }

  /// Convierte un audio dictado en texto (OpenAI `gpt-transcribe`).
  Future<String> transcribe(Uint8List audio, {required String mimeType}) async {
    if (audio.length < 800) throw AssistantException('No se escuchó nada. Mantén pulsado el micrófono y habla.');
    if (audio.length > maxAudioBytes) {
      throw AssistantException('La grabación es demasiado larga (máx. 3 minutos).');
    }
    try {
      final String token = await _token();
      final Map<String, dynamic> result = await callFirebaseFunction(
        'transcribeAudio',
        <String, dynamic>{'audio': base64Encode(audio), 'mimeType': mimeType},
        idToken: token,
        timeout: const Duration(seconds: 90),
      );
      final String text = (result['text'] ?? '').toString().trim();
      if (text.isEmpty) throw AssistantException('No se entendió el audio. Intenta hablar más cerca del micrófono.');
      return text;
    } on StateError catch (e) {
      throw AssistantException(e.message);
    } on AssistantException {
      rethrow;
    } catch (_) {
      throw AssistantException('No se pudo transcribir el audio. Verifica tu internet.');
    }
  }
}
