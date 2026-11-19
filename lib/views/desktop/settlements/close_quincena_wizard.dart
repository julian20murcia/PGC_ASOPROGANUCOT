import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/settlement_controller.dart';
import '../../../core/services/settlement_calculator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_rate_model.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';
import 'settlement_widgets.dart';

/// Abre el asistente de cierre. Devuelve la clave del período cerrado
/// (`inicio_fin`) si el cierre fue exitoso y el usuario quiere verlo.
Future<String?> showCloseQuincenaWizard(
  BuildContext context, {
  QuincenaPeriod? initial,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CloseQuincenaWizard(initial: initial),
  );
}

enum _PeriodChoice { current, previous, custom }

enum _Phase { editing, running, success, error }

/// Asistente de 3 pasos para cerrar una quincena.
class CloseQuincenaWizard extends StatefulWidget {
  const CloseQuincenaWizard({super.key, this.initial});
  final QuincenaPeriod? initial;

  @override
  State<CloseQuincenaWizard> createState() => _CloseQuincenaWizardState();
}

class _CloseQuincenaWizardState extends State<CloseQuincenaWizard> {
  static const List<String> _stepTitles = <String>[
    'Elegir quincena',
    'Revisar productores',
    'Confirmar cierre',
  ];

  int _step = 0;
  _Phase _phase = _Phase.editing;
  late _PeriodChoice _choice;
  late QuincenaPeriod _period;
  final Set<String> _excluded = <String>{};
  String? _resultMessage;
  int _closedCount = 0;

  QuincenaPeriod get _current => QuincenaPeriod.currentForDate(DateTime.now());
  QuincenaPeriod get _previous =>
      QuincenaPeriod.previousForDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    final QuincenaPeriod p = widget.initial ?? _previous;
    _period = p;
    _choice = p.startDate == _current.startDate && p.endDate == _current.endDate
        ? _PeriodChoice.current
        : (p.startDate == _previous.startDate && p.endDate == _previous.endDate
              ? _PeriodChoice.previous
              : _PeriodChoice.custom);
  }

  void _setPeriod(QuincenaPeriod p, _PeriodChoice choice) {
    setState(() {
      _period = p;
      _choice = choice;
      _excluded.clear();
    });
  }

  Future<void> _run() async {
    final UserModel? actor = context.read<AuthController>().currentUser;
    if (actor == null) return;
    setState(() => _phase = _Phase.running);
    final SettlementController ctrl = context.read<SettlementController>();
    final bool ok = await ctrl.executeQuincenaClose(
      actor: actor,
      period: _period,
      excludedProducerIds: Set<String>.from(_excluded),
    );
    if (!mounted) return;
    setState(() {
      _phase = ok ? _Phase.success : _Phase.error;
      _closedCount = ctrl.lastClosedCount;
      _resultMessage = ok
          ? ctrl.feedbackMessage
          : (ctrl.errorMessage ?? 'No se pudo completar el cierre.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettlementController ctrl = context.watch<SettlementController>();
    final SettlementPreviewResult preview = ctrl.previewForPeriod(_period);
    final List<SettlementCandidate> included = preview.candidates
        .where((SettlementCandidate c) => !_excluded.contains(c.productorId))
        .toList();
    final bool hasRate = (ctrl.activeRate?.precioPorLitro ?? 0) > 0;

    final bool canNext = switch (_step) {
      0 => hasRate && preview.hasEligibleCandidates && !preview.hasPendingSync,
      1 => included.isNotEmpty,
      _ => true,
    };

    Widget body;
    List<Widget> actions;
    switch (_phase) {
      case _Phase.running:
        body = _ProgressView(count: included.length, period: _period);
        actions = const <Widget>[];
      case _Phase.success:
        body = _ResultView(
          success: true,
          message: _resultMessage ?? '',
          count: _closedCount,
          period: _period,
        );
        actions = <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pop('${_period.startDate}_${_period.endDate}'),
            icon: const Icon(Icons.open_in_new_rounded, size: 17),
            label: const Text('Ver quincena cerrada'),
          ),
        ];
      case _Phase.error:
        body = _ResultView(
          success: false,
          message: _resultMessage ?? '',
          count: 0,
          period: _period,
        );
        actions = <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () => setState(() {
              _phase = _Phase.editing;
              _step = 0;
            }),
            child: const Text('Revisar y reintentar'),
          ),
        ];
      case _Phase.editing:
        body = switch (_step) {
          0 => _stepPeriod(ctrl, preview, hasRate),
          1 => _stepProducers(preview, included),
          _ => _stepConfirm(ctrl, preview, included),
        };
        actions = <Widget>[
          if (_step > 0)
            OutlinedButton(
              onPressed: () => setState(() => _step--),
              child: const Text('Atrás'),
            )
          else
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          if (_step < 2)
            FilledButton(
              onPressed: canNext ? () => setState(() => _step++) : null,
              child: const Text('Continuar'),
            )
          else
            FilledButton.icon(
              onPressed: included.isEmpty ? null : _run,
              icon: const Icon(Icons.lock_rounded, size: 17),
              label: Text('Cerrar quincena (${included.length})'),
            ),
        ];
    }

    return AppDialog(
      title: 'Ejecutar cierre quincenal',
      subtitle: _phase == _Phase.editing
          ? 'Paso ${_step + 1} de 3 · ${_stepTitles[_step]}'
          : _period.label,
      icon: Icons.lock_clock_rounded,
      width: 900,
      footerLeading: _phase == _Phase.editing
          ? _Stepper(step: _step, titles: _stepTitles)
          : null,
      body: body,
      actions: actions,
    );
  }

  // ── Paso 1 ────────────────────────────────────────────────────────────

  Widget _stepPeriod(
    SettlementController ctrl,
    SettlementPreviewResult preview,
    bool hasRate,
  ) {
    final DateTime today = DateTime.now();
    final String todayIso = AppFormatters.toIsoDate(today);
    final List<MilkReceptionModel> inRange = ctrl.receptionsInPeriod(_period);
    final DailyDeliveryMatrix matrix = DailyDeliveryMatrix.build(
      startIso: _period.startDate,
      endIso: _period.endDate,
      receptions: inRange,
    );
    final List<String> elapsedEmpty = matrix.emptyDays
        .where((String d) => d.compareTo(todayIso) <= 0)
        .toList();
    final bool notFinished = _period.endDate.compareTo(todayIso) >= 0;
    final MilkRateModel? rate = ctrl.activeRate;
    final List<MilkRateModel> others = ctrl.otherRatesDuring(_period);
    final List<SettlementModel> already = ctrl.settlementsOverlapping(_period);

    Widget choice(
      _PeriodChoice c,
      String title,
      String sub,
      VoidCallback onTap,
    ) {
      final bool sel = _choice == c;
      return Expanded(
        child: Material(
          color: sel ? AppTheme.brandSoft : AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            side: BorderSide(
              color: sel ? AppTheme.brand : AppTheme.border,
              width: sel ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    sel
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 18,
                    color: sel ? AppTheme.brand : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.subtitleStyle(),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Cerrar una quincena significa calcular cuánto se le debe a cada productor por la leche entregada en ese período. '
          'Elige el período; te mostraremos si hay algo que revisar antes de continuar.',
          style: AppTheme.bodyStyle(fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            choice(
              _PeriodChoice.previous,
              'Quincena anterior',
              _previous.label,
              () => _setPeriod(_previous, _PeriodChoice.previous),
            ),
            const SizedBox(width: 8),
            choice(
              _PeriodChoice.current,
              'Quincena actual',
              _current.label,
              () => _setPeriod(_current, _PeriodChoice.current),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppDateRangeField(
                value: DateRangeValue(
                  DateTime.parse(_period.startDate),
                  DateTime.parse(_period.endDate),
                ),
                lastDate: DateTime(today.year + 1, 12, 31),
                onChanged: (DateRangeValue v) => _setPeriod(
                  QuincenaPeriod.custom(v.start, v.end),
                  _PeriodChoice.custom,
                ),
                expand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.date_range_rounded,
                size: 18,
                color: AppTheme.brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Cubre del '),
                      TextSpan(
                        text: AppFormatters.formatIsoDate(_period.startDate),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' al '),
                      TextSpan(
                        text: AppFormatters.formatIsoDate(_period.endDate),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ' · ${matrix.days.length} días · ${inRange.length} entregas registradas · '
                            '${preview.candidates.length} productor(es) por liquidar',
                      ),
                    ],
                  ),
                  style: AppTheme.bodyStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('VERIFICACIONES', style: AppTheme.overlineStyle()),
        const SizedBox(height: 2),
        if (preview.hasPendingSync)
          CheckLine(
            tone: Tone.danger,
            title:
                '${preview.pendingSyncReceptions.length} entrega(s) pendientes de sincronizar',
            detail:
                'Sincroniza los equipos de recepción antes de cerrar; de lo contrario esas entregas quedarían por fuera.',
          )
        else
          const CheckLine(
            tone: Tone.success,
            title: 'Todas las entregas del período están sincronizadas',
          ),
        if (!hasRate)
          const CheckLine(
            tone: Tone.danger,
            title: 'No hay tarifa vigente',
            detail:
                'Registra una tarifa por litro en el módulo Tarifas antes de cerrar.',
          )
        else
          CheckLine(
            tone: others.isEmpty ? Tone.success : Tone.warning,
            title:
                'Tarifa que se aplicará: ${AppFormatters.formatCurrency(rate!.precioPorLitro)} por litro',
            detail: others.isEmpty
                ? 'Vigente desde el ${AppFormatters.formatDate(rate.fechaInicioVigencia)}.'
                : 'Durante el período también rigió ${others.map((MilkRateModel r) => AppFormatters.formatCurrency(r.precioPorLitro)).join(', ')}; el cierre usa la tarifa vigente hoy.',
          ),
        if (elapsedEmpty.isEmpty)
          const CheckLine(
            tone: Tone.success,
            title: 'Hay registros en todos los días transcurridos',
          )
        else
          CheckLine(
            tone: Tone.warning,
            title: '${elapsedEmpty.length} día(s) sin ningún registro',
            detail:
                '${elapsedEmpty.take(8).map(AppFormatters.formatIsoDate).join(', ')}'
                '${elapsedEmpty.length > 8 ? '…' : ''}. Verifica que no falten entregas por digitar.',
          ),
        if (notFinished)
          const CheckLine(
            tone: Tone.warning,
            title: 'El período todavía no termina',
            detail:
                'Si cierras ahora, las entregas que lleguen después para estos productores no podrán liquidarse en este mismo período.',
          ),
        if (already.isNotEmpty)
          CheckLine(
            tone: Tone.info,
            title:
                '${already.length} comprobante(s) ya emitidos en este período',
            detail:
                'Esos productores no se vuelven a liquidar; solo se incluyen los que faltan.',
          ),
        if (!preview.hasEligibleCandidates && !preview.hasPendingSync)
          const CheckLine(
            tone: Tone.danger,
            title: 'No hay entregas pendientes por liquidar en este período',
            detail:
                'Puede que la quincena ya esté cerrada o que no existan registros.',
          ),
      ],
    );
  }

  // ── Paso 2 ────────────────────────────────────────────────────────────

  Widget _stepProducers(
    SettlementPreviewResult preview,
    List<SettlementCandidate> included,
  ) {
    final double liters =
        included.fold<int>(
          0,
          (int s, SettlementCandidate c) => s + (c.totalLiters * 1000).round(),
        ) /
        1000.0;
    final double amount =
        included.fold<int>(
          0,
          (int s, SettlementCandidate c) =>
              s + (c.valorTotalPagar * 100).round(),
        ) /
        100.0;
    final int deliveries = included.fold<int>(
      0,
      (int s, SettlementCandidate c) => s + c.deliveryCount,
    );
    final bool allOn = _excluded.isEmpty;

    Widget head(String t, double? w, {TextAlign align = TextAlign.start}) {
      final Widget cell = HeaderCell(t, right: align == TextAlign.right);
      return w == null
          ? Expanded(child: cell)
          : SizedBox(width: w, child: cell);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Revisa lo que se le pagará a cada productor. Si alguno no debe liquidarse ahora, quítale la marca: '
          'sus entregas quedan abiertas para un cierre posterior.',
          style: AppTheme.bodyStyle(fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              Container(
                color: AppTheme.surfaceMuted,
                height: 38,
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 44,
                      child: Checkbox(
                        value: allOn ? true : (included.isEmpty ? false : null),
                        tristate: true,
                        onChanged: (_) => setState(() {
                          if (allOn) {
                            _excluded.addAll(
                              preview.candidates.map(
                                (SettlementCandidate c) => c.productorId,
                              ),
                            );
                          } else {
                            _excluded.clear();
                          }
                        }),
                      ),
                    ),
                    head('Código', 72),
                    head('Productor', null),
                    head('Entregas', 70, align: TextAlign.right),
                    head('Mañana', 84, align: TextAlign.right),
                    head('Tarde', 84, align: TextAlign.right),
                    head('Total L', 92, align: TextAlign.right),
                    head('Precio', 84, align: TextAlign.right),
                    head('Valor', 116, align: TextAlign.right),
                  ],
                ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: preview.candidates.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppTheme.dividerLight),
                  itemBuilder: (BuildContext context, int i) {
                    final SettlementCandidate c = preview.candidates[i];
                    final bool on = !_excluded.contains(c.productorId);
                    final Color fg = on
                        ? AppTheme.textPrimary
                        : AppTheme.textMuted;
                    return InkWell(
                      onTap: () => setState(
                        () => on
                            ? _excluded.add(c.productorId)
                            : _excluded.remove(c.productorId),
                      ),
                      child: SizedBox(
                        height: 40,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: 44,
                                child: Checkbox(
                                  value: on,
                                  onChanged: (bool? v) => setState(
                                    () => v == true
                                        ? _excluded.remove(c.productorId)
                                        : _excluded.add(c.productorId),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: CellText(
                                  c.codigoAsociado,
                                  mono: true,
                                  size: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Expanded(
                                child: CellText(
                                  c.nombreProductor,
                                  strong: true,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: CellText(
                                  '${c.deliveryCount}',
                                  mono: true,
                                  align: TextAlign.right,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 84,
                                child: CellText(
                                  AppFormatters.formatLiters(
                                    c.morningLiters,
                                    withUnit: false,
                                  ),
                                  mono: true,
                                  align: TextAlign.right,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 84,
                                child: CellText(
                                  AppFormatters.formatLiters(
                                    c.afternoonLiters,
                                    withUnit: false,
                                  ),
                                  mono: true,
                                  align: TextAlign.right,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 92,
                                child: CellText(
                                  AppFormatters.formatLiters(c.totalLiters),
                                  mono: true,
                                  strong: true,
                                  align: TextAlign.right,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 84,
                                child: CellText(
                                  AppFormatters.formatCurrency(
                                    c.precioPorLitro,
                                  ),
                                  mono: true,
                                  align: TextAlign.right,
                                  color: fg,
                                ),
                              ),
                              SizedBox(
                                width: 116,
                                child: CellText(
                                  AppFormatters.formatCurrency(
                                    c.valorTotalPagar,
                                  ),
                                  mono: true,
                                  strong: true,
                                  align: TextAlign.right,
                                  color: on
                                      ? AppTheme.brandDeep
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                color: AppTheme.brandSoft,
                height: 42,
                padding: const EdgeInsets.only(left: 56, right: 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CellText(
                        '${included.length} de ${preview.candidates.length} productores incluidos',
                        strong: true,
                        color: AppTheme.brandDeep,
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: CellText(
                        '$deliveries',
                        mono: true,
                        strong: true,
                        align: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 168),
                    SizedBox(
                      width: 92,
                      child: CellText(
                        AppFormatters.formatLiters(liters),
                        mono: true,
                        strong: true,
                        align: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 84),
                    SizedBox(
                      width: 116,
                      child: CellText(
                        AppFormatters.formatCurrency(amount),
                        mono: true,
                        strong: true,
                        align: TextAlign.right,
                        color: AppTheme.brandDeep,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Paso 3 ────────────────────────────────────────────────────────────

  Widget _stepConfirm(
    SettlementController ctrl,
    SettlementPreviewResult preview,
    List<SettlementCandidate> included,
  ) {
    final double liters =
        included.fold<int>(
          0,
          (int s, SettlementCandidate c) => s + (c.totalLiters * 1000).round(),
        ) /
        1000.0;
    final double amount =
        included.fold<int>(
          0,
          (int s, SettlementCandidate c) =>
              s + (c.valorTotalPagar * 100).round(),
        ) /
        100.0;
    final int deliveries = included.fold<int>(
      0,
      (int s, SettlementCandidate c) => s + c.deliveryCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppTheme.border),
          ),
          child: InlineMetricRow(
            items: <InlineMetric>[
              InlineMetric(
                'Período',
                _period.label,
                hint:
                    '${AppFormatters.formatIsoDate(_period.startDate)} – ${AppFormatters.formatIsoDate(_period.endDate)}',
              ),
              InlineMetric(
                'Productores',
                '${included.length}',
                hint: _excluded.isEmpty
                    ? 'Todos incluidos'
                    : '${_excluded.length} excluido(s)',
              ),
              InlineMetric(
                'Litros',
                AppFormatters.formatLiters(liters),
                hint: '$deliveries entregas',
              ),
              InlineMetric(
                'Total a pagar',
                AppFormatters.formatCurrency(amount),
                hint:
                    'Tarifa ${AppFormatters.formatCurrency(preview.precioPorLitro)}/L',
                valueColor: AppTheme.brandDeep,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('QUÉ PASARÁ AL CONFIRMAR', style: AppTheme.overlineStyle()),
        const SizedBox(height: 4),
        CheckLine(
          tone: Tone.brand,
          icon: Icons.lock_rounded,
          title: 'Se bloquean las $deliveries entregas del período',
          detail:
              'Ya no podrán corregirse ni anularse desde Recepción; quedan amarradas a su comprobante.',
        ),
        CheckLine(
          tone: Tone.brand,
          icon: Icons.receipt_long_rounded,
          title: 'Se generan ${included.length} comprobantes de pago',
          detail:
              'Cada uno con su número consecutivo (COMP-AAAA-####) y huella de integridad SHA-256.',
        ),
        const CheckLine(
          tone: Tone.brand,
          icon: Icons.notifications_active_rounded,
          title: 'Se notifica a cada productor',
          detail:
              'Verán su desprendible en la app móvil. Luego registras aquí el pago de cada uno.',
        ),
        if (_excluded.isNotEmpty)
          CheckLine(
            tone: Tone.warning,
            title: '${_excluded.length} productor(es) quedan por fuera',
            detail:
                'Sus entregas siguen abiertas y podrás liquidarlas en otro cierre.',
          ),
        const SizedBox(height: 6),
        Text(
          'Esta acción no se puede deshacer.',
          style: AppTheme.bodyStyle(
            fontSize: 12.5,
            color: AppTheme.dangerText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step, required this.titles});
  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < titles.length; i++) ...<Widget>[
          if (i > 0)
            Container(
              width: 18,
              height: 1.5,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: i <= step ? AppTheme.brand : AppTheme.border,
            ),
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i < step
                  ? AppTheme.brand
                  : (i == step ? AppTheme.brandSoft : AppTheme.surfaceSunken),
              shape: BoxShape.circle,
              border: Border.all(
                color: i <= step ? AppTheme.brand : AppTheme.border,
              ),
            ),
            child: i < step
                ? const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: AppTheme.surface,
                  )
                : Text(
                    '${i + 1}',
                    style: AppTheme.monoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: i == step ? AppTheme.brand : AppTheme.textMuted,
                    ),
                  ),
          ),
          if (i == step) ...<Widget>[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                titles[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyStyle(
                  fontSize: 12.5,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.count, required this.period});
  final int count;
  final QuincenaPeriod period;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.hourglass_top_rounded,
            size: 34,
            color: AppTheme.brand,
          ),
          const SizedBox(height: 12),
          Text(
            'Cerrando ${period.label}…',
            style: AppTheme.subtitleStyle().copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Generando $count comprobante(s), bloqueando entregas y notificando a los productores. No cierres esta ventana.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyStyle(fontSize: 13),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(99)),
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: AppTheme.surfaceSunken,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.success,
    required this.message,
    required this.count,
    required this.period,
  });
  final bool success;
  final String message;
  final int count;
  final QuincenaPeriod period;

  @override
  Widget build(BuildContext context) {
    final Tone tone = success ? Tone.success : Tone.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
            child: Icon(
              success ? Icons.check_rounded : Icons.error_outline_rounded,
              size: 28,
              color: tone.fg,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            success ? 'Quincena cerrada' : 'El cierre no se completó',
            style: AppTheme.subtitleStyle().copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            success
                ? '$count comprobante(s) emitidos para ${period.label}. Los productores ya fueron notificados.'
                : message,
            textAlign: TextAlign.center,
            style: AppTheme.bodyStyle(fontSize: 13, height: 1.45),
          ),
          if (!success) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Actualiza la lista antes de reintentar: si parte del cierre se confirmó, esos productores ya no aparecerán.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
