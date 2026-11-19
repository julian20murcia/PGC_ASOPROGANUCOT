import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../core/services/assistant_report_export.dart';
import '../../core/services/assistant_service.dart';
import '../../core/services/file_export_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_rules.dart';
import '../../models/assistant_report.dart';
import '../shared/widgets/pro_ui.dart';
import 'assistant/chat_widgets.dart';
import 'assistant/report_card.dart';
import 'assistant/voice_input.dart';

/// Asistente IA (OpenAI vía Cloud Functions `askAssistant` y
/// `transcribeAudio`): chat con los datos de la plataforma, dictado por voz e
/// informes descargables en PDF/Excel con gráficas. La clave del modelo nunca
/// vive en la app.
class AssistantModuleView extends StatefulWidget {
  const AssistantModuleView({super.key, this.service});

  /// Servicio inyectable (pruebas). Por defecto [AssistantService].
  final AssistantService? service;

  static const List<String> suggestions = <String>[
    '¿Quién entregó más leche este mes?',
    '¿Cuánto debemos pagar esta quincena?',
    '¿Qué productores no han entregado hoy?',
    'Compara la producción de mañana vs tarde',
    'Informe PDF del top 10 de productores de este mes con gráficas',
    'Excel con la producción diaria del mes y una gráfica de líneas',
  ];

  static const String disclaimer =
      'Las respuestas se generan con IA a partir de los datos de la plataforma; verifica cifras críticas.';

  /// ¿El mensaje del servidor corresponde a un límite de uso/frecuencia?
  static bool isRateLimitMessage(String message) {
    final String m = message.toLowerCase();
    return m.contains('límite') ||
        m.contains('limite') ||
        m.contains('cupo') ||
        m.contains('ocupado') ||
        m.contains('resource-exhausted') ||
        m.contains('demasiadas');
  }

  @override
  State<AssistantModuleView> createState() => _AssistantModuleViewState();
}

class _AssistantModuleViewState extends State<AssistantModuleView> {
  static const Duration _cooldown = Duration(seconds: 20);

  late final AssistantService _service = widget.service ?? AssistantService();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ScrollController _inputScroll = ScrollController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final List<ChatEntry> _entries = <ChatEntry>[];
  bool _sending = false;
  bool _dictating = false;
  final Map<ChatEntry, ExportFormat> _exporting = <ChatEntry, ExportFormat>{};
  int _conversation = 0;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _inputScroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _coolingDown => _cooldownLeft > 0;

  bool get _canSend => !_sending && !_coolingDown && !_dictating && _input.text.trim().isNotEmpty;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bool enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  /// Historial válido (sin errores) para dar contexto al modelo.
  List<AssistantMessage> get _history => <AssistantMessage>[
        for (final ChatEntry e in _entries)
          if (e.kind == ChatEntryKind.user || e.kind == ChatEntryKind.assistant)
            AssistantMessage(fromUser: e.kind == ChatEntryKind.user, text: e.text, at: e.at),
      ];

  Future<void> _send([String? preset]) async {
    final String q = (preset ?? _input.text).trim();
    if (q.isEmpty || _sending || _coolingDown || _dictating) return;
    final String question = q.length > AssistantService.maxQuestionLength
        ? q.substring(0, AssistantService.maxQuestionLength)
        : q;
    final List<AssistantMessage> history = _history;
    final int conv = _conversation;
    setState(() {
      _entries.add(ChatEntry(ChatEntryKind.user, question));
      _sending = true;
      if (preset == null) _input.clear();
    });
    _scrollToEnd();
    ChatEntry reply;
    try {
      final AssistantAnswer answer = await _service.ask(question, history: history);
      reply = ChatEntry(
        ChatEntryKind.assistant,
        answer.text.isEmpty ? 'Listo, aquí tienes el informe solicitado.' : answer.text,
        report: answer.report,
      );
    } on AssistantException catch (e) {
      reply = _errorEntry(e.message, question);
    } catch (_) {
      reply = _errorEntry('Ocurrió un error inesperado. Intenta de nuevo.', question);
    }
    if (!mounted || conv != _conversation) return;
    setState(() {
      _entries.add(reply);
      _sending = false;
    });
    if (reply.kind == ChatEntryKind.rateLimit) _startCooldown();
    _scrollToEnd();
    _focus.requestFocus();
  }

  ChatEntry _errorEntry(String message, String question) {
    if (AssistantModuleView.isRateLimitMessage(message)) {
      return ChatEntry(
        ChatEntryKind.rateLimit,
        '$message Mientras tanto puedes revisar los módulos de Reportes o Liquidaciones.',
        retryQuestion: question,
      );
    }
    return ChatEntry(ChatEntryKind.error, message, retryQuestion: question);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownLeft = _cooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldownLeft = _cooldownLeft > 0 ? _cooldownLeft - 1 : 0);
      if (_cooldownLeft == 0) t.cancel();
    });
  }

  void _retry(ChatEntry e) {
    final String? q = e.retryQuestion;
    if (q == null) return;
    setState(() {
      // Quita la pregunta fallida y su error para no duplicarlos.
      final int idx = _entries.indexOf(e);
      if (idx > 0 && _entries[idx - 1].kind == ChatEntryKind.user) _entries.removeAt(idx - 1);
      _entries.remove(e);
    });
    _send(q);
  }

  Future<void> _newConversation() async {
    if (_entries.isEmpty) return;
    setState(() {
      _entries.clear();
      _exporting.clear();
      _sending = false;
      _conversation++;
      _input.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(context, 'Respuesta copiada al portapapeles.', tone: Tone.success);
  }

  /// Texto que había en el cuadro al empezar a dictar (se conserva delante).
  String _dictationPrefix = '';

  void _onDictationStart() => _dictationPrefix = _input.text.trimRight();

  /// Dictado en vivo: el cuadro muestra lo escrito antes + lo que se va diciendo.
  void _onDictated(String text) {
    final String spoken = text.trim();
    String next = _dictationPrefix.isEmpty
        ? spoken
        : (spoken.isEmpty ? _dictationPrefix : '$_dictationPrefix $spoken');
    if (next.length > AssistantService.maxQuestionLength) {
      next = next.substring(0, AssistantService.maxQuestionLength);
    }
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _scrollInputToEnd();
  }

  void _onDictationDone(String text) {
    _onDictated(text);
    _focus.requestFocus();
  }

  void _onDictationCancel() {
    _input.value = TextEditingValue(
      text: _dictationPrefix,
      selection: TextSelection.collapsed(offset: _dictationPrefix.length),
    );
    _focus.requestFocus();
  }

  void _scrollInputToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputScroll.hasClients) _inputScroll.jumpTo(_inputScroll.position.maxScrollExtent);
    });
  }

  void _onVoiceError(String message) {
    if (!mounted) return;
    showAppToast(context, message, tone: Tone.danger);
  }

  Future<void> _downloadReport(ChatEntry entry, ExportFormat format) async {
    final AssistantReport? report = entry.report;
    if (report == null || _exporting.containsKey(entry)) return;
    setState(() => _exporting[entry] = format);
    try {
      String? who;
      try {
        who = context.read<AuthController>().currentUser?.nombreCompleto;
      } catch (_) {
        who = null;
      }
      final Uint8List bytes = await AssistantReportExport.build(report, format, generatedBy: who);
      final String name = '${AssistantReportExport.fileBaseName(report)}.${format.extension}';
      if (FileExportService.isDesktop) {
        final SavedFile saved = await FileExportService.save(bytes, name);
        if (!mounted) return;
        showAppToast(
          context,
          'Informe ${format.label} guardado en Descargas/ASOPROGANUCOTT',
          tone: Tone.success,
          action: SnackBarAction(
            label: 'Abrir carpeta',
            textColor: AppTheme.brandMuted,
            onPressed: () => FileExportService.reveal(saved),
          ),
        );
      } else {
        await FileExportService.share(bytes, name, mimeType: format.mimeType, subject: report.title);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'No se pudo generar el informe: $e', tone: Tone.danger);
    } finally {
      if (mounted) setState(() => _exporting.remove(entry));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.sizeOf(context).width < 900;
    final double pad = narrow ? 16 : 24;
    final String? firstName = _firstName(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            title: 'Asistente IA',
            subtitle: 'Consulta los datos de la asociación en lenguaje natural',
            leading: const AssistantAvatar(size: 34),
            actions: <Widget>[
              SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: _entries.isEmpty ? null : _newConversation,
                  icon: const Icon(Icons.add_comment_outlined, size: 16),
                  label: const Text('Nueva conversación'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  Expanded(child: _buildMessages(firstName)),
                  _buildComposer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _firstName(BuildContext context) {
    try {
      final String? name = context.read<AuthController>().currentUser?.nombreCompleto;
      if (name == null || name.trim().isEmpty) return null;
      return name.trim().split(RegExp(r'\s+')).first;
    } catch (_) {
      return null;
    }
  }

  Widget _centered(Widget child) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child),
      );

  Widget _buildMessages(String? firstName) {
    if (_entries.isEmpty) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 48),
            child: Center(
              child: _centered(
                AssistantWelcome(
                  suggestions: AssistantModuleView.suggestions,
                  onPick: _send,
                  userName: firstName,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final int count = _entries.length + (_sending ? 1 : 0);
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (BuildContext context, int i) {
        if (i >= _entries.length) return _centered(const ThinkingIndicator());
        final ChatEntry e = _entries[i];
        return _centered(switch (e.kind) {
          ChatEntryKind.user => UserBubble(entry: e),
          ChatEntryKind.assistant => AssistantReply(
              entry: e,
              onCopy: () => _copy(e.text),
              attachment: e.report == null
                  ? null
                  : AssistantReportCard(
                      report: e.report!,
                      busyFormat: _exporting[e],
                      onDownload: (ExportFormat f) => _downloadReport(e, f),
                    ),
            ),
          ChatEntryKind.error || ChatEntryKind.rateLimit => ChatNotice(
              entry: e,
              onRetry: e.retryQuestion != null && !_sending && !_coolingDown && i == _entries.length - 1
                  ? () => _retry(e)
                  : null,
            ),
        });
      },
    );
  }

  Widget _buildComposer() {
    final int len = _input.text.characters.length;
    const int max = AssistantService.maxQuestionLength;
    final bool nearLimit = len > max * 0.9;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceMuted,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: _centered(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _focus.hasFocus ? AppTheme.brand : AppTheme.inputBorder),
                boxShadow: AppTheme.shadowSm,
              ),
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('assistant-input'),
                      controller: _input,
                      focusNode: _focus,
                      scrollController: _inputScroll,
                      // Mientras se dicta, el texto lo escribe la voz.
                      readOnly: _dictating,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      inputFormatters: AppInputs.multiline(max: max),
                      style: AppTheme.bodyStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.45),
                      decoration: InputDecoration(
                        hintText: _coolingDown
                            ? 'Espera $_cooldownLeft s para volver a preguntar…'
                            : _dictating
                                ? 'Habla con normalidad… el texto aparece aquí'
                                : 'Escribe o dicta tu pregunta, o pide un informe en PDF/Excel…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: VoiceInputButton(
                      service: _service,
                      enabled: !_sending,
                      onStart: _onDictationStart,
                      onText: _onDictated,
                      onDone: _onDictationDone,
                      onCancel: _onDictationCancel,
                      onError: _onVoiceError,
                      onStateChanged: (VoiceState s) {
                        if (mounted) setState(() => _dictating = s != VoiceState.idle);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Tooltip(
                      message: 'Enviar (Enter) · Nueva línea (Shift + Enter)',
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: FilledButton(
                          key: const Key('assistant-send'),
                          onPressed: _canSend ? () => _send() : null,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_upward_rounded, size: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.info_outline_rounded, size: 12, color: AppTheme.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    AssistantModuleView.disclaimer,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$len/$max',
                  key: const Key('assistant-counter'),
                  style: AppTheme.monoStyle(
                    fontSize: 11,
                    color: nearLimit ? AppTheme.warningText : AppTheme.textMuted,
                    fontWeight: nearLimit ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
