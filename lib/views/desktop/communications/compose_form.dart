import 'package:flutter/material.dart';

import '../../../core/services/broadcast_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/pro_ui.dart';
import '../../shared/widgets/ui_kit.dart';

/// Borrador de un comunicado (lo que se está escribiendo).
class BroadcastDraft {
  const BroadcastDraft({required this.title, required this.message, this.producerId});
  final String title;
  final String message;

  /// null => todos los productores.
  final String? producerId;
}

/// Formulario para redactar un comunicado.
class ComposeForm extends StatefulWidget {
  const ComposeForm({
    super.key,
    required this.producers,
    required this.onDraftChanged,
    required this.onSend,
    required this.sending,
    required this.enabled,
  });

  final List<ProducerModel> producers;
  final ValueChanged<BroadcastDraft> onDraftChanged;

  /// Devuelve true si se envió (para limpiar el formulario).
  final Future<bool> Function(BroadcastDraft draft) onSend;
  final bool sending;
  final bool enabled;

  @override
  State<ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends State<ComposeForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _message = TextEditingController();
  bool _general = true;
  String? _producerId;
  String? _targetError;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  BroadcastDraft get _draft => BroadcastDraft(
        title: _title.text,
        message: _message.text,
        producerId: _general ? null : _producerId,
      );

  void _changed() {
    setState(() {});
    widget.onDraftChanged(_draft);
  }

  void _clear() {
    _title.clear();
    _message.clear();
    setState(() {
      _general = true;
      _producerId = null;
      _targetError = null;
    });
    _form.currentState?.reset();
    widget.onDraftChanged(_draft);
  }

  Future<void> _send() async {
    final bool valid = _form.currentState?.validate() ?? false;
    final String? targetError = !_general && (_producerId == null) ? 'Selecciona el productor' : null;
    setState(() => _targetError = targetError);
    if (!valid || targetError != null) return;
    final bool ok = await widget.onSend(_draft);
    if (ok && mounted) _clear();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.enabled && !widget.sending;
    final List<ProducerModel> active = widget.producers.where((ProducerModel p) => p.isActivo).toList()
      ..sort((ProducerModel a, ProducerModel b) => a.nombreCompleto.compareTo(b.nombreCompleto));
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Destinatarios',
            required: true,
            child: AppSegmentedControl<bool>(
              selected: _general,
              onChanged: (bool v) {
                if (!enabled) return;
                setState(() {
                  _general = v;
                  _targetError = null;
                });
                widget.onDraftChanged(_draft);
              },
              segments: <AppSegment<bool>>[
                AppSegment<bool>(value: true, label: 'Todos los productores (${active.length})', icon: Icons.groups_2_outlined),
                const AppSegment<bool>(value: false, label: 'Un productor', icon: Icons.person_pin_outlined),
              ],
            ),
          ),
          if (!_general) ...<Widget>[
            const SizedBox(height: 10),
            AppSelect<String?>(
              value: _producerId,
              enabled: enabled,
              prefixIcon: Icons.search_rounded,
              hintText: 'Buscar productor por nombre, código o cédula…',
              searchable: true,
              searchHint: 'Nombre, código o cédula…',
              options: <AppSelectOption<String?>>[
                for (final ProducerModel p in active)
                  AppSelectOption<String?>(
                    value: p.productorId,
                    label: p.nombreCompleto,
                    description: '${p.codigoAsociado} · ${p.vereda}',
                    searchText: p.cedula,
                  ),
              ],
              onChanged: (String? v) {
                setState(() {
                  _producerId = v;
                  _targetError = null;
                });
                widget.onDraftChanged(_draft);
              },
            ),
            if (_targetError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_targetError!, style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.dangerText)),
              ),
          ],
          const SizedBox(height: 14),
          AppTextField(
            key: const ValueKey<String>('broadcast-title'),
            label: 'Título',
            required: true,
            enabled: enabled,
            controller: _title,
            hint: 'Ej. Cambio de horario de recepción',
            helper: '${_title.text.length}/${BroadcastRules.titleMax} caracteres',
            inputFormatters: AppInputs.text(max: BroadcastRules.titleMax),
            validator: BroadcastRules.validateTitle,
            onChanged: (_) => _changed(),
          ),
          const SizedBox(height: 12),
          AppTextField(
            key: const ValueKey<String>('broadcast-message'),
            label: 'Mensaje',
            required: true,
            enabled: enabled,
            controller: _message,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            hint: 'Escribe el aviso de forma clara y breve.',
            helper: '${_message.text.length}/${BroadcastRules.messageMax} caracteres',
            inputFormatters: AppInputs.multiline(max: BroadcastRules.messageMax),
            validator: BroadcastRules.validateMessage,
            onChanged: (_) => _changed(),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _general
                      ? 'Llegará como notificación a todos los productores con la app.'
                      : 'Por privacidad, la notificación solo dice que hay un aviso nuevo; el texto se lee dentro de la app.',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: enabled ? _clear : null, child: const Text('Limpiar')),
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const ValueKey<String>('broadcast-send'),
                onPressed: enabled ? _send : null,
                icon: widget.sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Enviar comunicado'),
              ),
            ],
          ),
          if (!widget.enabled) ...<Widget>[
            const SizedBox(height: 10),
            const StatusBadge('Tu cuenta solo puede consultar comunicados', tone: Tone.warning, icon: Icons.lock_outline),
          ],
        ],
      ),
    );
  }
}
