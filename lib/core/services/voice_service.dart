import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lectura en voz alta (texto a voz) para confirmar operaciones en planta sin
/// mirar la pantalla, p. ej. el nombre del productor seleccionado en Recepción.
///
/// Es tolerante a fallos: si el dispositivo no tiene motor de voz o el plugin
/// no está disponible (pruebas automatizadas), simplemente no habla.
class VoiceService extends ChangeNotifier {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  FlutterTts? _tts;
  Future<bool>? _init;
  bool _enabled = true;

  /// Si la lectura en voz alta está activa (el operario puede silenciarla).
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) stop();
    notifyListeners();
  }

  void toggle() => enabled = !_enabled;

  bool get _isSupportedEnvironment {
    if (kIsWeb) return true;
    // `flutter test` no tiene plugins nativos: evitamos llamadas al canal.
    return !Platform.environment.containsKey('FLUTTER_TEST');
  }

  Future<bool> _ensureReady() {
    return _init ??= _configure();
  }

  Future<bool> _configure() async {
    if (!_isSupportedEnvironment) return false;
    try {
      final FlutterTts tts = FlutterTts();
      _tts = tts;

      // Preferimos una voz instalada en español (Colombia, México o España).
      await _selectSpanishVoice(tts);
      try {
        await tts.setLanguage('es-CO');
      } catch (_) {
        try {
          await tts.setLanguage('es-ES');
        } catch (_) {}
      }
      try {
        await tts.setVolume(1.0);
        await tts.setPitch(1.0);
        if (!kIsWeb && Platform.isAndroid) {
          await tts.setSpeechRate(0.48);
        }
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('[VoiceService] Motor de voz no disponible: $e');
      _tts = null;
      return false;
    }
  }

  Future<void> _selectSpanishVoice(FlutterTts tts) async {
    try {
      final dynamic voices = await tts.getVoices;
      if (voices is! List) return;
      Map<String, String>? best;
      int bestScore = -1;
      for (final dynamic v in voices) {
        if (v is! Map) continue;
        final String name = '${v['name'] ?? ''}';
        final String locale = '${v['locale'] ?? ''}'.toLowerCase();
        if (!locale.startsWith('es')) continue;
        int score = 1;
        if (locale.contains('co')) score = 4;
        if (locale.contains('mx') || locale.contains('419')) score = 3;
        if (locale.contains('es-es') || locale.contains('es_es')) score = 2;
        if (score > bestScore) {
          bestScore = score;
          best = <String, String>{'name': name, 'locale': '${v['locale']}'};
        }
      }
      if (best != null) await tts.setVoice(best);
    } catch (_) {
      // Algunas plataformas no exponen la lista de voces.
    }
  }

  /// Lee [text] en voz alta interrumpiendo cualquier lectura en curso.
  Future<void> speak(String text) async {
    if (!_enabled || text.trim().isEmpty) return;
    final bool ready = await _ensureReady();
    final FlutterTts? tts = _tts;
    if (!ready || tts == null) return;
    try {
      await tts.stop();
      await tts.speak(text);
    } catch (e) {
      debugPrint('[VoiceService] No se pudo leer el texto: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /// Formatea litros para que la voz los lea natural: 32.0 → "32", 32.5 → "32,5".
  static String spokenLiters(double liters) {
    final String fixed = liters.toStringAsFixed(1);
    final String trimmed = fixed.endsWith('.0')
        ? fixed.substring(0, fixed.length - 2)
        : fixed;
    return trimmed.replaceAll('.', ',');
  }
}
