import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../controllers/producer_controller.dart';
import '../../../core/services/producer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/privacy_notice.dart';
import '../../../models/producer_model.dart';
import '../../shared/widgets/privacy_notice_view.dart';
import '../../shared/widgets/pro_ui.dart';

/// Resultado del asistente: productor guardado y si se pidió crear acceso móvil.
typedef ProducerWizardResult = ({ProducerModel producer, bool wantsAppAccess});

/// Abre el asistente de registro (o edición si [existing] no es null).
Future<ProducerWizardResult?> showProducerWizard(
  BuildContext context, {
  required String actorUid,
  ProducerModel? existing,
  bool canCreateAppAccess = false,
}) {
  context.read<ProducerController>().clearFeedback();
  return showDialog<ProducerWizardResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProducerFormWizard(
      actorUid: actorUid,
      existing: existing,
      canCreateAppAccess: canCreateAppAccess,
    ),
  );
}

/// Claves estables para pruebas de widget.
class ProducerWizardKeys {
  ProducerWizardKeys._();
  static const Key next = Key('producer-wizard-next');
  static const Key back = Key('producer-wizard-back');
  static const Key nombres = Key('producer-field-nombres');
  static const Key apellidos = Key('producer-field-apellidos');
  static const Key cedula = Key('producer-field-cedula');
  static const Key telefono = Key('producer-field-telefono');
  static const Key codigo = Key('producer-field-codigo');
  static const Key finca = Key('producer-field-finca');
  static const Key vereda = Key('producer-field-vereda');
  static const Key soporte = Key('producer-field-soporte');
  static const Key consent = Key('producer-consent-checkbox');
  static const Key activo = Key('producer-active-switch');
  static const Key appAccess = Key('producer-wizard-app-access');
  static const Key done = Key('producer-wizard-done');
}

class ProducerFormWizard extends StatefulWidget {
  const ProducerFormWizard({
    super.key,
    required this.actorUid,
    this.existing,
    this.canCreateAppAccess = false,
  });

  final String actorUid;
  final ProducerModel? existing;
  final bool canCreateAppAccess;

  @override
  State<ProducerFormWizard> createState() => _ProducerFormWizardState();
}

class _StepInfo {
  const _StepInfo(this.title, this.short, this.hint, this.icon);
  final String title;
  final String short;
  final String hint;
  final IconData icon;
}

class _ProducerFormWizardState extends State<ProducerFormWizard> {
  static const List<_StepInfo> _steps = <_StepInfo>[
    _StepInfo(
      'Datos personales',
      'Datos personales',
      'Nombre, cédula y celular del productor',
      Icons.person_outline_rounded,
    ),
    _StepInfo(
      'Finca',
      'Finca',
      'Código de asociado, finca y vereda',
      Icons.cottage_outlined,
    ),
    _StepInfo(
      'Autorización de datos',
      'Autorización',
      'Ley 1581 de 2012 · Habeas Data',
      Icons.privacy_tip_outlined,
    ),
    _StepInfo(
      'Revisar y guardar',
      'Revisar',
      'Confirma la información antes de guardar',
      Icons.fact_check_outlined,
    ),
  ];

  final List<GlobalKey<FormState>> _formKeys =
      List<GlobalKey<FormState>>.generate(3, (_) => GlobalKey<FormState>());

  late final TextEditingController _nombres;
  late final TextEditingController _apellidos;
  late final TextEditingController _cedula;
  late final TextEditingController _telefono;
  late final TextEditingController _codigo;
  late final TextEditingController _finca;
  late final TextEditingController _vereda;
  late final TextEditingController _soporte;
  final FocusNode _veredaFocus = FocusNode();

  int _step = 0;
  int _maxReached = 0;
  bool _active = true;
  bool _consent = false;
  bool _consentError = false;
  ProducerModel? _saved;

  Future<PrivacyNotice>? _noticeFuture;
  PrivacyNotice? _notice;

  bool get _isEditing => widget.existing != null;
  bool get _isLast => _step == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    final ProducerModel? p = widget.existing;
    final ProducerController ctrl = context.read<ProducerController>();
    _nombres = TextEditingController(text: p?.nombres ?? '');
    _apellidos = TextEditingController(text: p?.apellidos ?? '');
    _cedula = TextEditingController(text: p?.cedula ?? '');
    _telefono = TextEditingController(text: p?.telefono ?? '');
    _codigo = TextEditingController(
      text: p?.codigoAsociado ?? ctrl.suggestedNextCode(),
    );
    _finca = TextEditingController(text: p?.nombreFinca ?? '');
    _vereda = TextEditingController(text: p?.vereda ?? '');
    _soporte = TextEditingController(text: p?.soporteAutorizacion ?? '');
    _active = p?.isActivo ?? true;
    _consent = p?.aceptoHabeasData ?? false;
    if (_isEditing) _maxReached = _steps.length - 1;
    if (!_isEditing) _noticeFuture = _startNoticeLoad();
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _nombres,
      _apellidos,
      _cedula,
      _telefono,
      _codigo,
      _finca,
      _vereda,
      _soporte,
    ]) {
      c.dispose();
    }
    _veredaFocus.dispose();
    super.dispose();
  }

  // ── Aviso de privacidad ────────────────────────────────────────────────
  /// Inicia la carga del aviso; el error se muestra cuando el usuario llega al
  /// paso 3, así que se marca como manejado para no romper la app antes.
  Future<PrivacyNotice> _startNoticeLoad() {
    final Future<PrivacyNotice> future = _loadNotice();
    future.ignore();
    return future;
  }

  Future<PrivacyNotice> _loadNotice() async {
    final PrivacyNotice notice = await context
        .read<ProducerController>()
        .loadPrivacyNotice();
    if (mounted) setState(() => _notice = notice);
    return notice;
  }

  void _retryNotice() {
    setState(() {
      _notice = null;
      _consent = false;
      _noticeFuture = _startNoticeLoad();
    });
  }

  String _noticeError(Object? error) {
    if (error is FormatException) return error.message;
    if (error is FirebaseException &&
        (error.code == 'permission-denied' ||
            error.code == 'unauthenticated')) {
      return 'No tienes acceso al aviso institucional. Verifica la sesión y los permisos.';
    }
    return 'No se pudo consultar el aviso institucional. Verifica la conexión y reintenta.';
  }

  // ── Navegación ─────────────────────────────────────────────────────────
  bool _validateStep(int step) {
    if (step < 2) return _formKeys[step].currentState?.validate() ?? false;
    if (step == 2) {
      if (_isEditing) return true;
      final bool formOk = _formKeys[2].currentState?.validate() ?? false;
      final bool consentOk = _notice != null && _consent;
      setState(() => _consentError = !consentOk);
      return formOk && consentOk;
    }
    return true;
  }

  void _next() {
    final ProducerController ctrl = context.read<ProducerController>();
    if (ctrl.isSaving || _saved != null) return;
    if (_isLast) {
      _save();
      return;
    }
    if (!_validateStep(_step)) return;
    setState(() {
      _step++;
      if (_step > _maxReached) _maxReached = _step;
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step--);
  }

  void _goTo(int step) {
    if (step == _step || step > _maxReached) return;
    if (step > _step && !_validateStep(_step)) return;
    setState(() => _step = step);
  }

  Future<void> _save() async {
    final ProducerController ctrl = context.read<ProducerController>();
    final String estado = _active ? 'ACTIVO' : 'INACTIVO';
    final bool ok;
    if (_isEditing) {
      ok = await ctrl.updateProducer(
        previous: widget.existing!,
        codigoAsociado: _codigo.text,
        cedula: _cedula.text,
        nombres: _nombres.text,
        apellidos: _apellidos.text,
        telefono: _telefono.text,
        nombreFinca: _finca.text,
        vereda: _vereda.text,
        estado: estado,
        aceptoHabeasData: true,
        actorUid: widget.actorUid,
      );
    } else {
      ok = await ctrl.createProducer(
        codigoAsociado: _codigo.text,
        cedula: _cedula.text,
        nombres: _nombres.text,
        apellidos: _apellidos.text,
        telefono: _telefono.text,
        nombreFinca: _finca.text,
        vereda: _vereda.text,
        estado: estado,
        aceptoHabeasData: _consent,
        actorUid: widget.actorUid,
        privacyNotice: _notice,
        authorizationReference: _soporte.text,
      );
    }
    if (!mounted || !ok) return;
    final ProducerModel? saved = ctrl.lastSavedProducer;
    if (saved == null) return;
    if (_isEditing) {
      Navigator.of(context).pop((producer: saved, wantsAppAccess: false));
      return;
    }
    setState(() => _saved = saved);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ProducerController ctrl = context.watch<ProducerController>();
    if (_saved != null) return _buildSuccess(_saved!);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _next,
      },
      child: AppDialog(
        width: 640,
        icon: _isEditing ? Icons.edit_outlined : Icons.person_add_alt_1_rounded,
        title: _isEditing ? 'Editar productor' : 'Registrar productor',
        subtitle: _isEditing
            ? widget.existing!.nombreCompleto
            : 'Completa 4 pasos cortos. Puedes volver atrás sin perder lo escrito.',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StepperHeader(
              steps: _steps,
              current: _step,
              maxReached: _maxReached,
              onTap: ctrl.isSaving ? null : _goTo,
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Icon(_steps[_step].icon, size: 18, color: AppTheme.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: _steps[_step].title,
                      style: AppTheme.subtitleStyle(),
                      children: <InlineSpan>[
                        TextSpan(
                          text: '  ·  ${_steps[_step].hint}',
                          style: AppTheme.bodyStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey<int>(_step),
                child: switch (_step) {
                  0 => _buildPersonal(ctrl),
                  1 => _buildFarm(ctrl),
                  2 => _buildConsent(ctrl),
                  _ => _buildReview(ctrl),
                },
              ),
            ),
          ],
        ),
        footerLeading: Text(
          'Paso ${_step + 1} de ${_steps.length}',
          style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        actions: <Widget>[
          OutlinedButton.icon(
            key: ProducerWizardKeys.back,
            onPressed: ctrl.isSaving ? null : _back,
            icon: Icon(
              _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded,
              size: 16,
            ),
            label: Text(_step == 0 ? 'Cancelar' : 'Atrás'),
          ),
          FilledButton.icon(
            key: ProducerWizardKeys.next,
            onPressed: ctrl.isSaving ? null : _next,
            icon: ctrl.isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 16,
                  ),
            label: Text(
              _isLast
                  ? (_isEditing ? 'Guardar cambios' : 'Guardar productor')
                  : 'Siguiente',
            ),
          ),
        ],
      ),
    );
  }

  Widget _pair(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (c.maxWidth < 440) {
          return Column(children: <Widget>[a, const SizedBox(height: 14), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _stepIntro(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(text, style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.4)),
  );

  Widget _buildPersonal(ProducerController ctrl) {
    final bool enabled = !ctrl.isSaving;
    return Form(
      key: _formKeys[0],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            'Escribe los datos tal como aparecen en la cédula del productor.',
          ),
          _pair(
            AppTextField(
              key: ProducerWizardKeys.nombres,
              label: 'Nombres',
              required: true,
              autofocus: true,
              enabled: enabled,
              controller: _nombres,
              hint: 'Ej. José Luis',
              inputFormatters: AppInputs.personName(),
              textInputAction: TextInputAction.next,
              validator: ProducerRules.names,
            ),
            AppTextField(
              key: ProducerWizardKeys.apellidos,
              label: 'Apellidos',
              required: true,
              enabled: enabled,
              controller: _apellidos,
              hint: 'Ej. Rodríguez López',
              inputFormatters: AppInputs.personName(),
              textInputAction: TextInputAction.next,
              validator: ProducerRules.surnames,
            ),
          ),
          const SizedBox(height: 14),
          _pair(
            AppTextField(
              key: ProducerWizardKeys.cedula,
              label: 'Cédula',
              required: true,
              enabled: enabled,
              controller: _cedula,
              hint: 'Solo números',
              helper:
                  'Entre ${FieldLimits.documentMin} y ${FieldLimits.document} dígitos',
              monospace: true,
              prefixIcon: Icons.badge_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: AppInputs.document(),
              textInputAction: TextInputAction.next,
              validator: (String? v) {
                final String? base = ProducerRules.document(v);
                if (base != null) return base;
                final ProducerModel? dup = ctrl.findByCedula(
                  v ?? '',
                  excludeId: widget.existing?.productorId,
                );
                return dup == null
                    ? null
                    : 'Ya registrada para ${dup.nombreCompleto}';
              },
            ),
            AppTextField(
              key: ProducerWizardKeys.telefono,
              label: 'Celular',
              required: true,
              enabled: enabled,
              controller: _telefono,
              hint: '3101234567',
              helper: '10 dígitos',
              monospace: true,
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: AppInputs.phone(),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _next(),
              validator: ProducerRules.phone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFarm(ProducerController ctrl) {
    final bool enabled = !ctrl.isSaving;
    final String suggested = _isEditing
        ? widget.existing!.codigoAsociado
        : ctrl.suggestedNextCode();
    return Form(
      key: _formKeys[1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _stepIntro(
            'El código identifica al asociado en la planta y en los desprendibles de pago.',
          ),
          _pair(
            AppTextField(
              key: ProducerWizardKeys.codigo,
              label: 'Código de asociado',
              required: true,
              enabled: enabled,
              controller: _codigo,
              monospace: true,
              prefixIcon: Icons.tag_rounded,
              helper: _isEditing ? null : 'Sugerido: $suggested',
              inputFormatters: AppInputs.code(),
              textInputAction: TextInputAction.next,
              suffix: _isEditing
                  ? null
                  : IconButton(
                      tooltip: 'Usar código sugerido',
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      onPressed: enabled
                          ? () => setState(() => _codigo.text = suggested)
                          : null,
                    ),
              validator: (String? v) {
                final String? base = ProducerRules.code(v);
                if (base != null) return base;
                final ProducerModel? dup = ctrl.findByCode(
                  v ?? '',
                  excludeId: widget.existing?.productorId,
                );
                return dup == null
                    ? null
                    : 'Ya asignado a ${dup.nombreCompleto}';
              },
            ),
            AppTextField(
              key: ProducerWizardKeys.finca,
              label: 'Nombre de la finca',
              required: true,
              enabled: enabled,
              controller: _finca,
              hint: 'Ej. El Porvenir',
              prefixIcon: Icons.cottage_outlined,
              inputFormatters: AppInputs.text(max: FieldLimits.farmName),
              textInputAction: TextInputAction.next,
              validator: ProducerRules.farm,
            ),
          ),
          const SizedBox(height: 14),
          RawAutocomplete<String>(
            textEditingController: _vereda,
            focusNode: _veredaFocus,
            optionsBuilder: (TextEditingValue v) {
              final List<String> list = ctrl.veredaSuggestions(v.text);
              if (list.length == 1 &&
                  list.first.toLowerCase() == v.text.trim().toLowerCase()) {
                return const <String>[];
              }
              return list.take(8);
            },
            fieldViewBuilder:
                (
                  BuildContext context,
                  TextEditingController controller,
                  FocusNode focusNode,
                  VoidCallback onFieldSubmitted,
                ) {
                  return AppTextField(
                    key: ProducerWizardKeys.vereda,
                    label: 'Vereda',
                    required: true,
                    enabled: enabled,
                    controller: controller,
                    focusNode: focusNode,
                    hint: 'Escribe o elige una vereda existente',
                    helper: ctrl.availableVeredas.isEmpty
                        ? null
                        : '${ctrl.availableVeredas.length} veredas registradas: elige una para evitar duplicados',
                    prefixIcon: Icons.place_outlined,
                    inputFormatters: AppInputs.text(max: FieldLimits.vereda),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _next(),
                    validator: ProducerRules.vereda,
                  );
                },
            optionsViewBuilder:
                (
                  BuildContext context,
                  AutocompleteOnSelected<String> onSelected,
                  Iterable<String> options,
                ) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 0,
                      color: AppTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 220,
                          maxWidth: 360,
                        ),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          children: <Widget>[
                            for (final String o in options)
                              InkWell(
                                onTap: () => onSelected(o),
                                hoverColor: AppTheme.surfaceMuted,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      const Icon(
                                        Icons.place_outlined,
                                        size: 15,
                                        color: AppTheme.textMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          o,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTheme.bodyStyle(
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
          ),
        ],
      ),
    );
  }

  Widget _bullet(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 15, color: AppTheme.brand),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _buildConsent(ProducerController ctrl) {
    final Widget explanation = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('¿Por qué se pide esto?', style: AppTheme.subtitleStyle()),
        const SizedBox(height: 8),
        _bullet(
          Icons.gavel_rounded,
          'La Ley 1581 de 2012 (Habeas Data) exige que el productor autorice el uso de sus datos personales antes de registrarlos.',
        ),
        _bullet(
          Icons.water_drop_outlined,
          'La asociación los usa solo para registrar entregas de leche, liquidar pagos y que él consulte su historial.',
        ),
        _bullet(
          Icons.verified_user_outlined,
          'El productor puede consultar, corregir o pedir la eliminación de sus datos cuando quiera.',
        ),
      ],
    );

    if (_isEditing) {
      final ProducerModel p = widget.existing!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          explanation,
          const SizedBox(height: 12),
          _InfoBox(
            tone: p.hasValidHabeasData ? Tone.success : Tone.warning,
            icon: p.hasValidHabeasData
                ? Icons.check_circle_rounded
                : Icons.history_rounded,
            text: p.hasValidHabeasData
                ? 'Autorización registrada el ${AppFormatters.formatDate(p.fechaAutorizacionDatos!)}'
                      '${p.soporteAutorizacion == null ? '' : ' · Soporte: ${p.soporteAutorizacion}'}.'
                : 'Autorización histórica sin fecha. Verifica el soporte en el archivo de la asociación.',
          ),
        ],
      );
    }

    return Form(
      key: _formKeys[2],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          explanation,
          const SizedBox(height: 12),
          FutureBuilder<PrivacyNotice>(
            future: _noticeFuture,
            builder: (BuildContext context, AsyncSnapshot<PrivacyNotice> snap) {
              final bool loading = snap.connectionState != ConnectionState.done;
              if (loading) {
                return const _InfoBox(
                  tone: Tone.neutral,
                  icon: Icons.hourglass_top_rounded,
                  text: 'Cargando el aviso institucional…',
                  progress: true,
                );
              }
              if (snap.hasError || snap.data == null) {
                return _InfoBox(
                  tone: Tone.danger,
                  icon: Icons.cloud_off_rounded,
                  text: _noticeError(snap.error),
                  action: TextButton.icon(
                    onPressed: _retryNotice,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reintentar'),
                  ),
                );
              }
              return Container(
                constraints: const BoxConstraints(maxHeight: 170),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: DefaultTextStyle.merge(
                    style: AppTheme.bodyStyle(fontSize: 12, height: 1.4),
                    child: PrivacyNoticeView(notice: snap.data!),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Material(
            color: _consent ? AppTheme.brandSoft : AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              side: BorderSide(
                color: _consentError && !_consent
                    ? AppTheme.danger
                    : (_consent ? AppTheme.brandMuted : AppTheme.inputBorder),
              ),
            ),
            child: CheckboxListTile(
              key: ProducerWizardKeys.consent,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (_notice == null || ctrl.isSaving)
                  ? null
                  : (bool? v) => setState(() {
                      _consent = v == true;
                      if (_consent) _consentError = false;
                    }),
              title: Text(
                'Entregué el aviso y el productor autorizó el tratamiento de sus datos.',
                style: AppTheme.bodyStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          if (_consentError && !_consent)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _notice == null
                    ? 'Espera a que cargue el aviso de privacidad para continuar.'
                    : 'Marca la casilla para confirmar la autorización.',
                style: AppTheme.bodyStyle(
                  fontSize: 12,
                  color: AppTheme.dangerText,
                ),
              ),
            ),
          const SizedBox(height: 14),
          AppTextField(
            key: ProducerWizardKeys.soporte,
            label: 'Soporte de autorización (opcional)',
            enabled: !ctrl.isSaving,
            controller: _soporte,
            prefixIcon: Icons.description_outlined,
            hint: 'Ej. Formato firmado N.º 045 · Carpeta 2026',
            helper:
                'Si lo dejas vacío se genera una constancia digital automática (AUT-PLANTA-…). Máx. ${FieldLimits.shortText} caracteres.',
            inputFormatters: AppInputs.text(max: FieldLimits.shortText),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _next(),
            validator: ProducerRules.authorizationReference,
          ),
        ],
      ),
    );
  }

  Widget _buildReview(ProducerController ctrl) {
    Widget section(String title, int step, List<(String, String)> rows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AppTheme.overlineStyle(),
                ),
              ),
              TextButton(
                onPressed: ctrl.isSaving
                    ? null
                    : () => setState(() => _step = step),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Editar'),
              ),
            ],
          ),
          for (final (String k, String v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 150,
                    child: Text(
                      k,
                      style: AppTheme.bodyStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      v.isEmpty ? '—' : v,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final String fullName =
        '${ProducerRules.titleCase(_nombres.text)} ${ProducerRules.titleCase(_apellidos.text)}'
            .trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (ctrl.errorMessage != null) ...<Widget>[
          _InfoBox(
            tone: Tone.danger,
            icon: Icons.error_outline_rounded,
            text: ctrl.errorMessage!,
          ),
          const SizedBox(height: 12),
        ],
        section('Datos personales', 0, <(String, String)>[
          ('Nombre completo', fullName),
          ('Cédula', _cedula.text),
          ('Celular', _telefono.text),
        ]),
        const Divider(height: 20),
        section('Finca', 1, <(String, String)>[
          (
            'Código de asociado',
            ProducerRules.collapse(_codigo.text).toUpperCase(),
          ),
          ('Finca', ProducerRules.collapse(_finca.text)),
          ('Vereda', ProducerRules.collapse(_vereda.text)),
        ]),
        const Divider(height: 20),
        section('Autorización de datos', 2, <(String, String)>[
          (
            'Habeas Data',
            _isEditing
                ? (widget.existing!.hasValidHabeasData
                      ? 'Autorizado'
                      : 'Autorización histórica')
                : (_consent ? 'Autorizado' : 'Pendiente'),
          ),
          if (!_isEditing)
            ('Soporte', ProducerRules.collapse(_soporte.text).isEmpty
                ? 'Constancia digital automática'
                : ProducerRules.collapse(_soporte.text)),
          if (!_isEditing && _notice != null)
            ('Aviso', 'Versión ${_notice!.data['version']}'),
        ]),
        const Divider(height: 20),
        Material(
          color: AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: SwitchListTile(
            key: ProducerWizardKeys.activo,
            dense: true,
            value: _active,
            onChanged: ctrl.isSaving
                ? null
                : (bool v) => setState(() => _active = v),
            title: Text(
              _active ? 'Productor activo' : 'Productor inactivo',
              style: AppTheme.subtitleStyle().copyWith(fontSize: 13),
            ),
            subtitle: Text(
              _active
                  ? 'Puede entregar leche en la planta desde hoy.'
                  : 'No aparecerá en la recepción de leche hasta activarlo.',
              style: AppTheme.bodyStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Los cambios quedan registrados en la bitácora de auditoría.',
          style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildSuccess(ProducerModel p) {
    final bool linked = ProducerController.hasAppAccess(p);
    return AppDialog(
      width: 480,
      icon: Icons.check_circle_outline_rounded,
      title: 'Productor registrado',
      subtitle: 'Ya puede entregar leche en la planta.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              InitialsAvatar(p.nombreCompleto, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.subtitleStyle(),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.codigoAsociado} · ${p.nombreFinca} · ${p.vereda}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.canCreateAppAccess && !linked) ...<Widget>[
            const SizedBox(height: 16),
            const _InfoBox(
              tone: Tone.brand,
              icon: Icons.smartphone_rounded,
              text:
                  'Opcional: crea su acceso a la app móvil para que consulte entregas y pagos desde el celular.',
            ),
          ],
        ],
      ),
      actions: <Widget>[
        if (widget.canCreateAppAccess && !linked)
          OutlinedButton.icon(
            key: ProducerWizardKeys.appAccess,
            onPressed: () =>
                Navigator.of(context).pop((producer: p, wantsAppAccess: true)),
            icon: const Icon(Icons.smartphone_rounded, size: 16),
            label: const Text('Crear acceso a la app móvil'),
          ),
        FilledButton(
          key: ProducerWizardKeys.done,
          onPressed: () =>
              Navigator.of(context).pop((producer: p, wantsAppAccess: false)),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

/// Encabezado del asistente: pasos numerados + barra de progreso.
class _StepperHeader extends StatelessWidget {
  const _StepperHeader({
    required this.steps,
    required this.current,
    required this.maxReached,
    required this.onTap,
  });

  final List<_StepInfo> steps;
  final int current;
  final int maxReached;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final bool compact = c.maxWidth < 520;
            return Row(
              children: <Widget>[
                for (int i = 0; i < steps.length; i++) ...<Widget>[
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 1.5,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: i <= current ? AppTheme.brand : AppTheme.border,
                      ),
                    ),
                  _StepDot(
                    index: i,
                    info: steps[i],
                    state: i < current
                        ? _DotState.done
                        : (i == current
                              ? _DotState.current
                              : _DotState.pending),
                    showLabel: !compact || i == current,
                    onTap: (onTap != null && i <= maxReached)
                        ? () => onTap!(i)
                        : null,
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (current + 1) / steps.length,
            minHeight: 4,
            backgroundColor: AppTheme.surfaceSunken,
            color: AppTheme.brand,
          ),
        ),
      ],
    );
  }
}

enum _DotState { done, current, pending }

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.info,
    required this.state,
    required this.showLabel,
    this.onTap,
  });

  final int index;
  final _StepInfo info;
  final _DotState state;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = state != _DotState.pending;
    final Widget dot = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == _DotState.pending ? AppTheme.surface : AppTheme.brand,
        border: Border.all(
          color: active ? AppTheme.brand : AppTheme.borderStrong,
          width: 1.5,
        ),
      ),
      child: state == _DotState.done
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : Text(
              '${index + 1}',
              style: AppTheme.monoStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: state == _DotState.current
                    ? Colors.white
                    : AppTheme.textMuted,
              ),
            ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            dot,
            if (showLabel) ...<Widget>[
              const SizedBox(width: 7),
              Text(
                info.short,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyStyle(
                  fontSize: 12.5,
                  fontWeight: state == _DotState.current
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: active ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso en línea plano (sin tarjetas anidadas).
class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.tone,
    required this.icon,
    required this.text,
    this.action,
    this.progress = false,
  });

  final Tone tone;
  final IconData icon;
  final String text;
  final Widget? action;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: tone.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppTheme.bodyStyle(
                    fontSize: 12.5,
                    color: tone.fg,
                    height: 1.4,
                  ),
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(width: 6),
                action!,
              ],
            ],
          ),
          if (progress) ...<Widget>[
            const SizedBox(height: 8),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }
}
