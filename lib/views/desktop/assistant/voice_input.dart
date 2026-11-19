import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/services/assistant_service.dart';
import '../../../core/services/live_transcription.dart';
import '../../../core/theme/app_theme.dart';

/// Estados del dictado.
/// * `connecting`: pidiendo credenciales y abriendo la conexión.
/// * `live`: escuchando; el texto aparece mientras se habla.
/// * `muted`: micrófono silenciado (la sesión sigue abierta para continuar).
/// * `finishing`: cerrando el último tramo.
enum VoiceState { idle, connecting, live, muted, finishing }

/// Dictado en vivo para el asistente (OpenAI Realtime, `gpt-live-transcribe`).
///
/// * Toque en el micrófono: empieza a escuchar y el texto va apareciendo.
/// * Botón silenciar: pausa el envío de audio para pensar, sin perder lo dictado.
/// * ✓ Listo: termina y deja el texto en el cuadro para revisarlo.
/// * ✕: descarta lo dictado en esta sesión.
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.service,
    required this.onText,
    required this.onError,
    this.onStart,
    this.onDone,
    this.onCancel,
    this.enabled = true,
    this.onStateChanged,
    this.recorderFactory,
  });

  final AssistantService service;

  /// Texto dictado hasta el momento (se llama mientras se habla).
  final ValueChanged<String> onText;
  final ValueChanged<String> onError;
  final VoidCallback? onStart;

  /// Texto final al terminar con ✓.
  final ValueChanged<String>? onDone;

  /// Se descartó el dictado con ✕.
  final VoidCallback? onCancel;
  final bool enabled;
  final ValueChanged<VoiceState>? onStateChanged;

  /// Inyectable para pruebas. Por defecto [AudioRecorder.new].
  final AudioRecorder Function()? recorderFactory;

  /// Límite de una sesión de dictado (se termina sola).
  static const Duration maxDuration = Duration(minutes: 5);

  @override
  State<VoiceInputButton> createState() => VoiceInputButtonState();
}

class VoiceInputButtonState extends State<VoiceInputButton> with SingleTickerProviderStateMixin {
  AudioRecorder? _recorder;
  LiveTranscriber? _live;
  StreamSubscription<Uint8List>? _audioSub;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _ticker;
  VoiceState _state = VoiceState.idle;
  DateTime? _startedAt;
  double _level = 0;
  int _session = 0;

  /// Modo respaldo: si el dictado en vivo no está disponible (sin conexión con
  /// el servicio en vivo, función no desplegada…), se graba a un archivo y se
  /// transcribe al terminar con `transcribeAudio`. Así el micrófono nunca queda
  /// inservible.
  String? _filePath;
  String _fileMime = 'audio/mp4';
  bool get _fileMode => _filePath != null;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  }

  VoiceState get state => _state;
  bool get _active => _state != VoiceState.idle;

  @override
  void dispose() {
    _session++;
    _pulse.dispose();
    unawaited(_teardown().whenComplete(() => _deleteFile(_filePath)));
    final AudioRecorder? r = _recorder;
    if (r != null) unawaited(r.dispose().catchError((Object _) {}));
    super.dispose();
  }

  void _set(VoiceState s) {
    _state = s;
    if (s == VoiceState.live) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
    if (mounted) setState(() {});
    widget.onStateChanged?.call(s);
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _ampSub?.cancel();
    _ampSub = null;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder?.isRecording() ?? false) await _recorder?.stop();
    } catch (_) {}
    _level = 0;
  }

  void _error(String message) {
    if (mounted) widget.onError(message);
  }

  Future<void> start() async {
    if (_active) return;
    if (kIsWeb) {
      _error('El dictado por voz está disponible en la aplicación de escritorio y móvil.');
      return;
    }
    final int session = ++_session;
    _set(VoiceState.connecting);
    try {
      final AudioRecorder rec = _recorder ??= (widget.recorderFactory ?? AudioRecorder.new)();
      if (!await rec.hasPermission()) {
        throw AssistantException('No hay permiso para usar el micrófono. Habilítalo en la configuración del sistema.');
      }
      bool liveOk = false;
      try {
        liveOk = await _startLive(rec, session);
      } on AssistantException catch (e) {
        if (_isHardStop(e.message)) rethrow;
      } catch (_) {
        liveOk = false;
      }
      if (session != _session) return;
      if (!liveOk) {
        await _live?.close();
        _live = null;
        await _startFile(rec);
      }
      _ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((Amplitude a) {
        final double v = _state == VoiceState.live ? ((a.current + 50) / 50).clamp(0.0, 1.0) : 0;
        if (mounted && (v - _level).abs() > 0.04) setState(() => _level = v);
      });
      _startedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (_elapsed >= VoiceInputButton.maxDuration) {
          unawaited(finish());
        } else {
          setState(() {});
        }
      });
      widget.onStart?.call();
      _set(VoiceState.live);
    } on AssistantException catch (e) {
      await _abort(session, e.message);
    } catch (_) {
      await _abort(session, 'No se pudo iniciar el dictado. Verifica el micrófono y tu conexión.');
    }
  }

  /// Errores en los que no tiene sentido grabar en modo respaldo.
  static bool _isHardStop(String m) {
    final String x = m.toLowerCase();
    return x.contains('permiso') ||
        x.contains('límite') ||
        x.contains('limite') ||
        x.contains('cupo') ||
        x.contains('sesión expiró') ||
        x.contains('no tienes acceso') ||
        x.contains('saldo');
  }

  /// Dictado en vivo: credenciales temporales + WebSocket + audio en streaming.
  Future<bool> _startLive(AudioRecorder rec, int session) async {
    final VoiceSessionTicket ticket = await widget.service.createVoiceSession();
    if (session != _session) return false;
    final LiveTranscriber live = await LiveTranscriber.connect(
      ticket,
      onText: (String t) {
        if (session == _session && mounted) widget.onText(t);
      },
      onError: (String m) {
        if (session != _session) return;
        _error(m);
        unawaited(cancel(silent: true));
      },
    );
    if (session != _session) {
      await live.close();
      return false;
    }
    _live = live;
    final Stream<Uint8List> audio = await rec.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: ticket.sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _audioSub = audio.listen((Uint8List chunk) {
      // Silenciado: el audio no sale del equipo.
      if (_state == VoiceState.live) _live?.addAudio(chunk);
    });
    return true;
  }

  /// Respaldo: graba a un archivo (se transcribe completo al terminar).
  Future<void> _startFile(AudioRecorder rec) async {
    AudioEncoder encoder = AudioEncoder.aacLc;
    String ext = 'm4a';
    _fileMime = 'audio/mp4';
    if (!await rec.isEncoderSupported(AudioEncoder.aacLc)) {
      encoder = AudioEncoder.wav;
      ext = 'wav';
      _fileMime = 'audio/wav';
    }
    final Directory tmp = await getTemporaryDirectory();
    final String path = '${tmp.path}${Platform.pathSeparator}dictado_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await rec.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _filePath = path;
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final File f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _abort(int session, String message) async {
    if (session != _session) return;
    await _teardown();
    await _live?.close();
    _live = null;
    _set(VoiceState.idle);
    _error(message);
  }

  /// Silencia o reactiva el micrófono sin terminar el dictado.
  void toggleMute() {
    if (_state == VoiceState.live) {
      _live?.commit(); // lo dicho hasta aquí queda definitivo
      if (_fileMode) unawaited(_recorder?.pause().catchError((Object _) {}));
      _level = 0;
      _set(VoiceState.muted);
    } else if (_state == VoiceState.muted) {
      if (_fileMode) unawaited(_recorder?.resume().catchError((Object _) {}));
      _set(VoiceState.live);
    }
  }

  /// Termina el dictado y entrega el texto final.
  Future<void> finish() async {
    if (_state != VoiceState.live && _state != VoiceState.muted) return;
    final int session = _session;
    _set(VoiceState.finishing);
    String text;
    if (_fileMode) {
      text = await _finishFile();
    } else {
      await _teardown();
      text = await (_live?.finish() ?? Future<String>.value(''));
      _live = null;
    }
    if (session != _session) return;
    _set(VoiceState.idle);
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _error('No se escuchó nada. Toca el micrófono y vuelve a intentarlo.');
    }
    widget.onDone?.call(text);
  }

  Future<String> _finishFile() async {
    _ticker?.cancel();
    _ticker = null;
    await _ampSub?.cancel();
    _ampSub = null;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {
      path = null;
    }
    path ??= _filePath;
    try {
      final Uint8List bytes = await File(path!).readAsBytes();
      final String text = await widget.service.transcribe(bytes, mimeType: _fileMime);
      if (mounted) widget.onText(text);
      return text;
    } on AssistantException catch (e) {
      _error(e.message);
      return '';
    } catch (_) {
      _error('No se pudo transcribir el audio. Intenta de nuevo.');
      return '';
    } finally {
      _deleteFile(path);
      _filePath = null;
    }
  }

  /// Descarta lo dictado en esta sesión.
  Future<void> cancel({bool silent = false}) async {
    if (!_active) return;
    _session++;
    await _teardown();
    await _live?.close();
    _live = null;
    _deleteFile(_filePath);
    _filePath = null;
    _set(VoiceState.idle);
    if (!silent) widget.onCancel?.call();
  }

  Duration get _elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _square({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color bg = AppTheme.surfaceMuted,
    Color fg = AppTheme.brand,
    Widget? child,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          key: key,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: AppTheme.surfaceMuted,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: child ?? Icon(icon, size: 19),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return _square(
        key: const Key('assistant-mic'),
        tooltip: 'Dictar por voz (el texto aparece mientras hablas)',
        icon: Icons.mic_none_rounded,
        onPressed: widget.enabled ? start : null,
      );
    }

    final bool live = _state == VoiceState.live;
    final bool muted = _state == VoiceState.muted;
    final bool busy = _state == VoiceState.connecting || _state == VoiceState.finishing;

    final Widget status = Container(
      key: const Key('assistant-mic-status'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: muted ? AppTheme.surfaceSunken : AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (busy)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppTheme.danger),
            )
          else if (muted)
            const Icon(Icons.mic_off_rounded, size: 12, color: AppTheme.textMuted)
          else
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            switch (_state) {
              VoiceState.connecting => 'Conectando…',
              VoiceState.finishing when _fileMode => 'Transcribiendo…',
              VoiceState.finishing => 'Terminando…',
              VoiceState.muted => 'Silenciado · ${_clock(_elapsed)}',
              _ when _fileMode => 'Grabando · ${_clock(_elapsed)}',
              _ => 'Escuchando · ${_clock(_elapsed)}',
            },
            style: AppTheme.monoStyle(
              fontSize: 11.5,
              color: muted ? AppTheme.textSecondary : AppTheme.dangerText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        status,
        const SizedBox(width: 4),
        Tooltip(
          message: 'Descartar dictado',
          child: IconButton(
            key: const Key('assistant-mic-cancel'),
            visualDensity: VisualDensity.compact,
            onPressed: _state == VoiceState.finishing ? null : () => cancel(),
            icon: const Icon(Icons.close_rounded, size: 17, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(width: 2),
        // Silenciar / reactivar: el halo crece con la voz mientras escucha.
        AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: live
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.danger.withValues(alpha: 0.15 + 0.35 * _level),
                      blurRadius: 3 + 9 * _level,
                      spreadRadius: 0.5 + 3 * _level,
                    ),
                  ]
                : null,
          ),
          child: _square(
            key: const Key('assistant-mic-mute'),
            tooltip: muted ? 'Reactivar micrófono' : 'Silenciar mientras piensas',
            icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            onPressed: live || muted ? toggleMute : null,
            bg: muted ? AppTheme.surfaceSunken : AppTheme.danger,
            fg: muted ? AppTheme.textSecondary : Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        _square(
          key: const Key('assistant-mic-done'),
          tooltip: 'Listo: terminar dictado',
          icon: Icons.check_rounded,
          onPressed: live || muted ? finish : null,
          bg: AppTheme.brand,
          fg: Colors.white,
          child: _state == VoiceState.finishing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : null,
        ),
      ],
    );
  }
}
