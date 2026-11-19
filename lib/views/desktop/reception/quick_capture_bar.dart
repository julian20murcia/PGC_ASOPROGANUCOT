import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/reception_controller.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/voice_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/pro_ui.dart';
import '../../shared/widgets/ui_kit.dart';
import 'reception_grid_logic.dart';

/// Barra compacta de captura rápida (productor → jornada → litros → Enter).
///
/// Todo por teclado en menos de 10 s: escribir código o nombre, Enter elige
/// la primera coincidencia y salta a litros, Enter guarda y vuelve al
/// productor. Los duplicados se avisan en línea (Enter de nuevo confirma).
class QuickCaptureBar extends StatefulWidget {
  const QuickCaptureBar({super.key, required this.canCreate, this.onSaved});

  final bool canCreate;
  final VoidCallback? onSaved;

  @override
  State<QuickCaptureBar> createState() => _QuickCaptureBarState();
}

class _QuickCaptureBarState extends State<QuickCaptureBar> {
  final TextEditingController _producerCtrl = TextEditingController();
  final TextEditingController _litersCtrl = TextEditingController();
  final FocusNode _producerFocus = FocusNode(debugLabel: 'captura-productor');
  late final FocusNode _litersFocus = FocusNode(
    debugLabel: 'captura-litros',
    onKeyEvent: _onLitersKey,
  );

  MilkReceptionModel? _duplicate;
  String? _error;

  @override
  void dispose() {
    _producerCtrl.dispose();
    _litersCtrl.dispose();
    _producerFocus.dispose();
    _litersFocus.dispose();
    super.dispose();
  }

  static String _display(ProducerModel p) =>
      '${p.codigoAsociado} · ${p.nombreCompleto}';

  void _pick(ProducerModel p) {
    context.read<ReceptionController>().selectProducer(p);
    _producerCtrl.value = TextEditingValue(
      text: _display(p),
      selection: TextSelection.collapsed(offset: _display(p).length),
    );
    setState(() {
      _duplicate = null;
      _error = null;
    });
    _litersFocus.requestFocus();
    VoiceService.instance.speak(p.nombreCompleto);
  }

  KeyEventResult _onLitersKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        (_duplicate != null || _error != null)) {
      setState(() {
        _duplicate = null;
        _error = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    final ReceptionController ctrl = context.read<ReceptionController>();
    if (!widget.canCreate) {
      setState(() => _error = 'No tienes permiso para registrar entregas.');
      return;
    }
    if (ctrl.selectedProducer == null && _producerCtrl.text.trim().isNotEmpty) {
      final ProducerModel? match =
          ctrl.findExactProducer(_producerCtrl.text) ??
          ctrl.matchProducersByCodeOrQuery(_producerCtrl.text).firstOrNull;
      if (match != null) ctrl.selectProducer(match);
    }
    if (ctrl.selectedProducer == null) {
      setState(() => _error = 'Selecciona un productor activo.');
      _producerFocus.requestFocus();
      return;
    }
    final LitersParseResult parsed = parseLitersInput(_litersCtrl.text);
    if (!parsed.isValid) {
      setState(
        () => _error = parsed.isEmpty
            ? 'Ingresa los litros recibidos.'
            : parsed.error,
      );
      _litersFocus.requestFocus();
      return;
    }
    final double liters = parsed.value!;
    final bool allowDuplicate = _duplicate != null;
    final String operarioUid =
        context.read<AuthController>().currentUser?.uid ?? 'operario';
    final String spokenName = ctrl.selectedProducer!.nombreCompleto;
    final bool morning = ctrl.selectedShift == AppConstants.shiftMorning;

    final result = await ctrl.registerDelivery(
      litros: liters,
      operarioUid: operarioUid,
      allowDuplicate: allowDuplicate,
    );
    if (!mounted) return;

    if (result.duplicateFound != null) {
      VoiceService.instance.speak(
        'Atención: posible entrega duplicada de ${result.duplicateFound!.nombreProductorSnap}',
      );
      setState(() {
        _duplicate = result.duplicateFound;
        _error = null;
      });
      _litersFocus.requestFocus();
      return;
    }
    if (result.saved) {
      VoiceService.instance.speak(
        'Registrado: ${VoiceService.spokenLiters(liters)} litros, $spokenName, '
        'jornada ${morning ? 'mañana' : 'tarde'}',
      );
      _producerCtrl.clear();
      _litersCtrl.clear();
      setState(() {
        _duplicate = null;
        _error = null;
      });
      showAppToast(
        context,
        ctrl.feedbackMessage ?? 'Entrega registrada.',
        tone: Tone.success,
      );
      widget.onSaved?.call();
      _producerFocus.requestFocus();
    } else {
      setState(
        () => _error =
            ctrl.errorMessage ?? 'No fue posible registrar la entrega.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReceptionController ctrl = context.watch<ReceptionController>();
    final ProducerModel? selected = ctrl.selectedProducer;
    final bool narrow = MediaQuery.sizeOf(context).width < 1100;

    final Widget producerField = RawAutocomplete<ProducerModel>(
      textEditingController: _producerCtrl,
      focusNode: _producerFocus,
      displayStringForOption: _display,
      optionsBuilder: (TextEditingValue v) {
        if (selected != null && v.text == _display(selected)) {
          return const Iterable<ProducerModel>.empty();
        }
        if (v.text.trim().isEmpty) return const Iterable<ProducerModel>.empty();
        return ctrl.matchProducersByCodeOrQuery(v.text);
      },
      onSelected: _pick,
      fieldViewBuilder:
          (
            BuildContext context,
            TextEditingController controller,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextField(
              key: const ValueKey<String>('captura-productor'),
              controller: controller,
              focusNode: focusNode,
              enabled: widget.canCreate,
              inputFormatters: AppInputs.text(),
              style: AppTheme.bodyStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
              onChanged: (String v) {
                if (ctrl.selectedProducer != null &&
                    v != _display(ctrl.selectedProducer!)) {
                  ctrl.selectProducer(null);
                }
                if (_error != null || _duplicate != null) {
                  setState(() {
                    _error = null;
                    _duplicate = null;
                  });
                }
              },
              onSubmitted: (String v) {
                final ProducerModel? exact = ctrl.findExactProducer(v);
                if (exact != null) {
                  _pick(exact);
                } else {
                  onFieldSubmitted();
                  if (ctrl.selectedProducer == null) {
                    final ProducerModel? first = ctrl
                        .matchProducersByCodeOrQuery(v)
                        .firstOrNull;
                    if (first != null && v.trim().isNotEmpty) _pick(first);
                  }
                }
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: ctrl.activeProducers.isEmpty
                    ? 'Sin productores activos'
                    : 'Productor: código, cédula o nombre',
                prefixIcon: Icon(
                  selected != null
                      ? Icons.check_circle_rounded
                      : Icons.person_search_rounded,
                  size: 17,
                  color: selected != null ? AppTheme.brand : AppTheme.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            );
          },
      optionsViewBuilder:
          (
            BuildContext context,
            AutocompleteOnSelected<ProducerModel> onSelected,
            Iterable<ProducerModel> options,
          ) {
            final int highlighted = AutocompleteHighlightedOption.of(context);
            final List<ProducerModel> list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6,
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 420,
                    maxHeight: 260,
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) {
                      final ProducerModel p = list[i];
                      return InkWell(
                        onTap: () => onSelected(p),
                        child: Container(
                          height: 36,
                          color: i == highlighted ? AppTheme.brandSoft : null,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 74,
                                child: Text(
                                  p.codigoAsociado,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.monoStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.brand,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  p.nombreCompleto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodyStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  p.nombreFinca,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodyStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ),
                              if (i == highlighted) ...<Widget>[
                                const SizedBox(width: 6),
                                const KeyCap('Enter'),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
    );

    final Widget shift = AppSegmentedControl<String>(
      selected: ctrl.selectedShift,
      onChanged: ctrl.setSelectedShift,
      segments: const <AppSegment<String>>[
        AppSegment<String>(
          value: AppConstants.shiftMorning,
          label: 'Mañana',
          icon: Icons.wb_sunny_outlined,
        ),
        AppSegment<String>(
          value: AppConstants.shiftAfternoon,
          label: 'Tarde',
          icon: Icons.wb_twilight_rounded,
        ),
      ],
    );

    final Widget liters = SizedBox(
      width: 130,
      child: TextField(
        key: const ValueKey<String>('captura-litros'),
        controller: _litersCtrl,
        focusNode: _litersFocus,
        enabled: widget.canCreate,
        inputFormatters: AppInputs.liters(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        style: AppTheme.monoStyle(fontSize: 14, fontWeight: FontWeight.w700),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          isDense: true,
          hintText: '0',
          suffixText: 'L',
          suffixStyle: AppTheme.monoStyle(
            fontSize: 13,
            color: AppTheme.textMuted,
          ),
          prefixIcon: const Icon(Icons.water_drop_outlined, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
        ),
      ),
    );

    final Widget submit = FilledButton.icon(
      onPressed: (ctrl.isSaving || !widget.canCreate) ? null : _submit,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
      icon: ctrl.isSaving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check_rounded, size: 17),
      label: Text(_duplicate != null ? 'Registrar igual' : 'Registrar entrega'),
    );

    final Widget title = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.brandSoft,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            size: 16,
            color: AppTheme.brand,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Captura rápida en planta',
              style: AppTheme.subtitleStyle().copyWith(fontSize: 13),
            ),
            Text(
              'Hoy · Enter para avanzar',
              style: AppTheme.bodyStyle(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );

    final Widget fields = narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: title),
                  const _VoiceToggle(),
                ],
              ),
              const SizedBox(height: 10),
              producerField,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[shift, liters, submit],
              ),
            ],
          )
        : Row(
            children: <Widget>[
              title,
              const SizedBox(width: 16),
              Expanded(child: producerField),
              const SizedBox(width: 10),
              shift,
              const SizedBox(width: 10),
              liters,
              const SizedBox(width: 10),
              submit,
              const SizedBox(width: 8),
              const _VoiceToggle(),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: _duplicate != null ? AppTheme.warning : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: fields,
          ),
          if (_duplicate != null)
            _notice(
              _duplicateText(_duplicate!),
              Tone.warning,
              Icons.warning_amber_rounded,
            ),
          if (_error != null)
            _notice(_error!, Tone.danger, Icons.error_outline_rounded),
        ],
      ),
    );
  }

  String _duplicateText(MilkReceptionModel d) {
    final String hora = d.horaEntrega.length >= 5
        ? d.horaEntrega.substring(0, 5)
        : d.horaEntrega;
    final String shift = d.jornada == AppConstants.shiftAfternoon
        ? 'tarde'
        : 'mañana';
    return 'Posible duplicado: ${d.nombreProductorSnap} ya entregó ${formatLitersCo(d.litros)} L '
        'hoy en la jornada de la $shift ($hora). Enter de nuevo para registrar igual · Esc cancela.';
  }

  Widget _notice(String text, Tone tone, IconData icon) {
    return Container(
      color: tone.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: tone.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodyStyle(
                fontSize: 12.5,
                color: tone.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interruptor de lectura en voz alta del productor seleccionado.
class _VoiceToggle extends StatelessWidget {
  const _VoiceToggle();

  @override
  Widget build(BuildContext context) {
    final VoiceService voice = VoiceService.instance;
    return ListenableBuilder(
      listenable: voice,
      builder: (BuildContext context, _) {
        final bool on = voice.enabled;
        return IconButton(
          tooltip: on
              ? 'Lectura en voz alta activada: dice el nombre del productor. Clic para silenciar.'
              : 'Lectura en voz alta silenciada. Clic para activar.',
          onPressed: () {
            voice.toggle();
            if (voice.enabled) voice.speak('Lectura en voz alta activada');
          },
          style: IconButton.styleFrom(
            backgroundColor: on ? AppTheme.brandSoft : AppTheme.surfaceMuted,
            fixedSize: const Size(36, 36),
            minimumSize: const Size(36, 36),
          ),
          icon: Icon(
            on ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded,
            size: 17,
            color: on ? AppTheme.brand : AppTheme.textMuted,
          ),
        );
      },
    );
  }
}
