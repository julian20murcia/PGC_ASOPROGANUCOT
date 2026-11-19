import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Credenciales temporales para una sesión de dictado en vivo (las emite la
/// Cloud Function `createVoiceSession`; la clave real de OpenAI nunca llega a la app).
class VoiceSessionTicket {
  const VoiceSessionTicket({required this.secret, required this.url, this.sampleRate = 24000});
  final String secret;
  final String url;
  final int sampleRate;
}

/// Arma el texto dictado a partir de los eventos de transcripción.
///
/// Cada tramo (`item_id`) recibe fragmentos `delta` mientras se habla y luego
/// un `transcript` definitivo. Los tramos se muestran en el orden en que
/// empezaron. Clase pura: se prueba sin red.
class LiveTranscriptAssembler {
  final List<String> _order = <String>[];
  final Map<String, StringBuffer> _partial = <String, StringBuffer>{};
  final Map<String, String> _final = <String, String>{};

  void _ensure(String id) {
    if (!_partial.containsKey(id) && !_final.containsKey(id)) {
      _order.add(id);
      _partial[id] = StringBuffer();
    }
  }

  void addDelta(String itemId, String delta) {
    if (_final.containsKey(itemId)) return;
    _ensure(itemId);
    _partial[itemId]!.write(delta);
  }

  void complete(String itemId, String transcript) {
    _ensure(itemId);
    _final[itemId] = transcript;
    _partial.remove(itemId);
  }

  /// ¿Hay tramos que aún no reciben su transcripción definitiva?
  bool get hasPending => _partial.isNotEmpty;

  bool get isEmpty => text.isEmpty;

  String get text {
    final List<String> parts = <String>[];
    for (final String id in _order) {
      final String t = (_final[id] ?? _partial[id]?.toString() ?? '').trim();
      if (t.isNotEmpty) parts.add(t);
    }
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// Sesión de transcripción en vivo con la Realtime API de OpenAI
/// (`gpt-live-transcribe`) sobre WebSocket.
///
/// Se le entrega audio PCM16 mono a 24 kHz con [addAudio]; el texto va
/// llegando por [onText] mientras la persona habla.
class LiveTranscriber {
  LiveTranscriber._(this._ws, {required this.onText, required this.onError}) {
    _sub = _ws.listen(
      _onMessage,
      onError: (Object e) => _fail('Se perdió la conexión del dictado. Intenta de nuevo.'),
      onDone: () {
        _closed = true;
        _completeDrain();
      },
      cancelOnError: false,
    );
  }

  /// Abre la conexión (subprotocolo con la clave temporal, como indica OpenAI).
  static Future<LiveTranscriber> connect(
    VoiceSessionTicket ticket, {
    required void Function(String text) onText,
    required void Function(String message) onError,
  }) async {
    final WebSocket ws = await WebSocket.connect(
      ticket.url,
      protocols: <String>['realtime', 'openai-insecure-api-key.${ticket.secret}'],
    ).timeout(const Duration(seconds: 12));
    ws.pingInterval = const Duration(seconds: 20);
    return LiveTranscriber._(ws, onText: onText, onError: onError);
  }

  final WebSocket _ws;
  final void Function(String text) onText;
  final void Function(String message) onError;
  final LiveTranscriptAssembler _assembler = LiveTranscriptAssembler();
  late final StreamSubscription<dynamic> _sub;

  /// Audio acumulado para enviarlo en bloques de ~100 ms (menos mensajes).
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  static const int _chunkBytes = 24000 * 2 ~/ 10;

  bool _closed = false;
  bool _uncommitted = false;
  Completer<void>? _drain;

  String get text => _assembler.text;

  void _send(Map<String, Object?> event) {
    if (_closed) return;
    try {
      _ws.add(jsonEncode(event));
    } catch (_) {}
  }

  void _flush() {
    if (_buffer.isEmpty) return;
    final Uint8List bytes = _buffer.takeBytes();
    _send(<String, Object?>{'type': 'input_audio_buffer.append', 'audio': base64Encode(bytes)});
    _uncommitted = true;
  }

  /// Agrega audio PCM16 (mono, 24 kHz, little-endian).
  void addAudio(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return;
    _buffer.add(pcm);
    if (_buffer.length >= _chunkBytes) _flush();
  }

  /// Cierra el tramo actual (p. ej. al silenciar): su texto queda definitivo.
  void commit() {
    _flush();
    if (!_uncommitted) return;
    _uncommitted = false;
    _send(<String, Object?>{'type': 'input_audio_buffer.commit'});
  }

  /// Termina: confirma el último tramo, espera la transcripción definitiva
  /// (máx. [wait]) y cierra la conexión. Devuelve el texto completo.
  Future<String> finish({Duration wait = const Duration(seconds: 5)}) async {
    commit();
    if (_assembler.hasPending && !_closed) {
      _drain = Completer<void>();
      await _drain!.future.timeout(wait, onTimeout: () {});
    }
    await close();
    return _assembler.text;
  }

  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      try {
        await _ws.close(WebSocketStatus.normalClosure);
      } catch (_) {}
    }
    await _sub.cancel();
  }

  void _completeDrain() {
    final Completer<void>? d = _drain;
    if (d != null && !d.isCompleted) d.complete();
  }

  void _fail(String message) {
    if (_closed) return;
    onError(message);
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final String type = (m['type'] ?? '').toString();
    final String id = (m['item_id'] ?? '').toString();
    switch (type) {
      case 'conversation.item.input_audio_transcription.delta':
        _assembler.addDelta(id, (m['delta'] ?? '').toString());
        onText(_assembler.text);
      case 'conversation.item.input_audio_transcription.completed':
        _assembler.complete(id, (m['transcript'] ?? '').toString());
        onText(_assembler.text);
        if (!_assembler.hasPending) _completeDrain();
      case 'conversation.item.input_audio_transcription.failed':
        _assembler.complete(id, '');
        if (!_assembler.hasPending) _completeDrain();
      case 'error':
        final Object? err = m['error'];
        final String code = err is Map ? (err['code'] ?? '').toString() : '';
        // Confirmar un búfer vacío no es un problema para la persona.
        if (code == 'input_audio_buffer_commit_empty') return;
        _fail('El servicio de dictado reportó un error. Intenta de nuevo.');
    }
  }
}
