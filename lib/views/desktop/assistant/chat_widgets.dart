import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'markdown_lite.dart';

/// Tipo de entrada en la conversación.
enum ChatEntryKind { user, assistant, error, rateLimit }

class ChatEntry {
  ChatEntry(this.kind, this.text, {DateTime? at, this.retryQuestion}) : at = at ?? DateTime.now();
  final ChatEntryKind kind;
  final String text;
  final DateTime at;

  /// Pregunta a reintentar (solo errores).
  final String? retryQuestion;
}

/// Avatar circular del asistente con la marca.
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.brand, AppTheme.brandDeep],
        ),
      ),
      child: Icon(Icons.auto_awesome_rounded, size: size * 0.52, color: AppTheme.accentSoft),
    );
  }
}

String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Mensaje del usuario: burbuja alineada a la derecha.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.entry});
  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppTheme.brand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: SelectableText(
                entry.text,
                style: AppTheme.bodyStyle(fontSize: 14, color: Colors.white, height: 1.45),
              ),
            ),
            const SizedBox(height: 3),
            Text(_time(entry.at), style: AppTheme.bodyStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Respuesta del asistente: avatar + markdown, sin burbuja (estilo chat moderno).
class AssistantReply extends StatelessWidget {
  const AssistantReply({super.key, required this.entry, required this.onCopy});
  final ChatEntry entry;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AssistantAvatar(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: SelectionArea(child: MarkdownLite(entry.text)),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Tooltip(
                    message: 'Copiar respuesta',
                    child: InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.content_copy_rounded, size: 13, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text('Copiar', style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_time(entry.at), style: AppTheme.bodyStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aviso de error o de límite de uso dentro de la conversación.
class ChatNotice extends StatelessWidget {
  const ChatNotice({super.key, required this.entry, this.onRetry});
  final ChatEntry entry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool limit = entry.kind == ChatEntryKind.rateLimit;
    final Color bg = limit ? AppTheme.warningBg : AppTheme.dangerBg;
    final Color fg = limit ? AppTheme.warningText : AppTheme.dangerText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AssistantAvatar(),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(limit ? Icons.hourglass_top_rounded : Icons.error_outline_rounded, size: 16, color: fg),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        limit ? 'Pausa breve: se alcanzó el límite de uso' : 'No pude responder',
                        style: AppTheme.bodyStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(entry.text, style: AppTheme.bodyStyle(fontSize: 12.5, color: fg, height: 1.4)),
                    ],
                  ),
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Indicador animado "Pensando…".
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const AssistantAvatar(),
        const SizedBox(width: 12),
        AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < 3; i++)
                Builder(builder: (BuildContext context) {
                  final double phase = (_c.value - i * 0.18) % 1.0;
                  final double v = math.sin(phase * math.pi).clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    transform: Matrix4.translationValues(0, -3 * v, 0),
                    decoration: BoxDecoration(
                      color: Color.lerp(AppTheme.brandMuted, AppTheme.brand, v),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text('Pensando…', style: AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textMuted)),
      ],
    );
  }
}

/// Pantalla de bienvenida con sugerencias en chips.
class AssistantWelcome extends StatelessWidget {
  const AssistantWelcome({super.key, required this.suggestions, required this.onPick, this.userName});
  final List<String> suggestions;
  final ValueChanged<String> onPick;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AssistantAvatar(size: 48),
        const SizedBox(height: 14),
        Text(
          userName == null ? '¿En qué te ayudo hoy?' : 'Hola, $userName. ¿En qué te ayudo hoy?',
          textAlign: TextAlign.center,
          style: AppTheme.titleStyle(),
        ),
        const SizedBox(height: 6),
        Text(
          'Pregunta sobre entregas, productores, liquidaciones o tarifas. Respondo con los datos de la plataforma.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyStyle(fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String s in suggestions)
              ActionChip(
                avatar: const Icon(Icons.north_east_rounded, size: 14, color: AppTheme.brand),
                label: Text(s),
                labelStyle: AppTheme.bodyStyle(fontSize: 12.8, color: AppTheme.textPrimary),
                backgroundColor: AppTheme.surface,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                onPressed: () => onPick(s),
              ),
          ],
        ),
      ],
    );
  }
}
