import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/services/assistant_service.dart';
import '../../../core/theme/app_theme.dart';

enum VoiceState { idle, recording, transcribing }

/// Botón de dictado: graba con el micrófono, envía el audio a la Cloud
/// Function `transcribeAudio` (OpenAI) y entrega el texto transcrito.
///
/// Un toque inicia la grabación; otro toque la detiene y transcribe.
/// La grabación se corta sola a los [maxDuration].
class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({
    super.key,
    required this.service,
    required this.onText,
    required this.onError,
    this.enabled = true,
    this.onStateChanged,
    this.recorderFactory,
  });

  final AssistantService service;
  final ValueChanged<String> onText;
  final ValueChanged<String> onError;
  final bool enabled;
  final ValueChanged<VoiceState>? onStateChanged;

  /// Inyectable para pruebas. Por defecto [AudioRecorder.new].
  final AudioRecorder Function()? recorderFactory;

  static const Duration maxDuration = Duration(minutes: 3);

  @override
  State<VoiceInputButton> createState() => VoiceInputButtonState();
}

class VoiceInputButtonState extends State<VoiceInputButton> {
  AudioRecorder? _recorder;
  VoiceState _state = VoiceState.idle;
  String _mime = 'audio/mp4';
  String? _path;
  DateTime? _startedAt;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  double _level = 0;

  VoiceState get state => _state;

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    final AudioRecorder? r = _recorder;
    if (r != null) {
      unawaited(() async {
        try {
          if (await r.isRecording()) await r.cancel();
        } catch (_) {}
        try {
          await r.dispose();
        } catch (_) {}
      }());
    }
    _deleteFile(_path);
    super.dispose();
  }

  void _set(VoiceState s) {
    if (!mounted) return;
    setState(() => _state = s);
    widget.onStateChanged?.call(s);
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final File f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> _toggle() async {
    switch (_state) {
      case VoiceState.idle:
        await _start();
      case VoiceState.recording:
        await _stop();
      case VoiceState.transcribing:
        break;
    }
  }

  Future<void> _start() async {
    if (kIsWeb) {
      widget.onError('El dictado por voz está disponible en la aplicación de escritorio y móvil.');
      return;
    }
    try {
      final AudioRecorder rec = _recorder ??= (widget.recorderFactory ?? AudioRecorder.new)();
      if (!await rec.hasPermission()) {
        widget.onError('No hay permiso para usar el micrófono. Habilítalo en la configuración del sistema.');
        return;
      }
      AudioEncoder encoder = AudioEncoder.aacLc;
      String ext = 'm4a';
      _mime = 'audio/mp4';
      if (!await rec.isEncoderSupported(AudioEncoder.aacLc)) {
        encoder = AudioEncoder.wav;
        ext = 'wav';
        _mime = 'audio/wav';
      }
      final Directory tmp = await getTemporaryDirectory();
      _path = '${tmp.path}${Platform.pathSeparator}dictado_${DateTime.now().millisecondsSinceEpoch}.$ext';
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
        path: _path!,
      );
      _startedAt = DateTime.now();
      _ampSub?.cancel();
      _ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((Amplitude a) {
        // dBFS (-60..0) → 0..1
        final double v = ((a.current + 50) / 50).clamp(0.0, 1.0);
        if (mounted) setState(() => _level = v);
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        if (_elapsed >= VoiceInputButton.maxDuration) {
          unawaited(_stop());
        } else {
          setState(() {});
        }
      });
      _set(VoiceState.recording);
    } catch (_) {
      _cleanupTimers();
      _set(VoiceState.idle);
      widget.onError('No se pudo acceder al micrófono. Verifica que esté conectado y disponible.');
    }
  }

  Duration get _elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  void _cleanupTimers() {
    _ticker?.cancel();
    _ticker = null;
    _ampSub?.cancel();
    _ampSub = null;
    _level = 0;
  }

  /// Descarta la grabación en curso sin transcribir.
  Future<void> cancel() async {
    if (_state != VoiceState.recording) return;
    _cleanupTimers();
    try {
      await _recorder?.cancel();
    } catch (_) {}
    _deleteFile(_path);
    _path = null;
    _set(VoiceState.idle);
  }

  Future<void> _stop() async {
    if (_state != VoiceState.recording) return;
    _cleanupTimers();
    final Duration took = _elapsed;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {
      path = null;
    }
    path ??= _path;
    if (took < const Duration(milliseconds: 700)) {
      _deleteFile(path);
      _set(VoiceState.idle);
      widget.onError('Grabación muy corta. Toca el micrófono, habla y vuelve a tocarlo para terminar.');
      return;
    }
    _set(VoiceState.transcribing);
    try {
      final File f = File(path!);
      final Uint8List bytes = await f.readAsBytes();
      final String text = await widget.service.transcribe(bytes, mimeType: _mime);
      if (mounted) widget.onText(text);
    } on AssistantException catch (e) {
      widget.onError(e.message);
    } catch (_) {
      widget.onError('No se pudo transcribir el audio. Intenta de nuevo.');
    } finally {
      _deleteFile(path);
      _path = null;
      _set(VoiceState.idle);
    }
  }

  String _clock(Duration d) =>
      '${d.inMinutes.toString().padLeft(1, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bool recording = _state == VoiceState.recording;
    final bool busy = _state == VoiceState.transcribing;
    final String tip = recording
        ? 'Detener y transcribir'
        : busy
            ? 'Transcribiendo…'
            : 'Dictar por voz';

    final Widget button = Tooltip(
      message: tip,
      child: SizedBox(
        width: 36,
        height: 36,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: recording
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.danger.withValues(alpha: 0.18 + 0.35 * _level),
                      blurRadius: 4 + 10 * _level,
                      spreadRadius: 1 + 4 * _level,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            key: const Key('assistant-mic'),
            padding: EdgeInsets.zero,
            onPressed: (widget.enabled || recording) && !busy ? _toggle : null,
            style: IconButton.styleFrom(
              backgroundColor: recording ? AppTheme.danger : AppTheme.surfaceMuted,
              foregroundColor: recording ? Colors.white : AppTheme.brand,
              disabledBackgroundColor: AppTheme.surfaceMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brand),
                  )
                : Icon(recording ? Icons.stop_rounded : Icons.mic_none_rounded, size: 19),
          ),
        ),
      ),
    );

    if (!recording && !busy) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (recording) ...<Widget>[
          Container(
            key: const Key('assistant-mic-status'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.dangerBg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  _clock(_elapsed),
                  style: AppTheme.monoStyle(fontSize: 11.5, color: AppTheme.dangerText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Descartar grabación',
            child: IconButton(
              key: const Key('assistant-mic-cancel'),
              visualDensity: VisualDensity.compact,
              onPressed: cancel,
              icon: const Icon(Icons.close_rounded, size: 17, color: AppTheme.textMuted),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('Transcribiendo…', style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
          ),
        button,
      ],
    );
  }
}
