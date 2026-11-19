import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/rate_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/milk_rate_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';

/// Módulo administrativo para configurar y consultar la tarifa histórica por litro (`RF-12`).
class RatesModuleView extends StatefulWidget {
  const RatesModuleView({super.key});

  @override
  State<RatesModuleView> createState() => _RatesModuleViewState();
}

class _RatesModuleViewState extends State<RatesModuleView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RateController>().loadRates();
    });
  }

  Future<void> _openCreateRateDialog() async {
    final AuthController auth = context.read<AuthController>();
    final RateController ctrl = context.read<RateController>();
    final UserModel actor = auth.currentUser ?? UserModel.bootstrapAdmin();
    ctrl.clearFeedback();

    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRateDialog(
        actor: actor,
        currentPrice: ctrl.activeRate?.precioPorLitro,
      ),
    );
    if (saved == true && mounted) {
      _showToast(
        ctrl.feedbackMessage ?? 'Nueva tarifa registrada correctamente.',
      );
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.inkBlack,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RateController ctrl = context.watch<RateController>();
    final AuthController auth = context.watch<AuthController>();
    final bool isAdmin = auth.currentUser?.isAdmin == true;
    final bool isNarrow = MediaQuery.of(context).size.width < 920;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 24,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(ctrl, isAdmin: isAdmin, isNarrow: isNarrow),
            const SizedBox(height: 16),
            _buildKpiStrip(ctrl, isNarrow),
            const SizedBox(height: 14),
            const AppInlineNotice(
              icon: Icons.verified_outlined,
              background: AppTheme.primaryGreenLight,
              foreground: AppTheme.successText,
              message:
                  'Cada ajuste crea una nueva vigencia sin modificar los precios anteriores. Las liquidaciones ya cerradas conservan intacta la tarifa aplicada al momento de su emisión.',
            ),
            const SizedBox(height: 18),
            if (ctrl.isLoading && ctrl.rates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: DairyLoader(
                    size: DairyLoaderSize.lg,
                    label: 'Cargando tarifas por litro…',
                    hint: 'Consultando historial de vigencias.',
                  ),
                ),
              )
            else if (ctrl.rates.isEmpty)
              _buildEmptyState(isAdmin: isAdmin)
            else ...<Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Historial de vigencias',
                    style: AppTheme.subtitleStyle(),
                  ),
                  const SizedBox(width: 10),
                  AppCountPill(text: '${ctrl.rates.length}'),
                  if (ctrl.fromCache) ...<Widget>[
                    const SizedBox(width: 8),
                    const SyncStatusBadge(
                      isSynced: false,
                      pendingLabel: 'Respaldo local',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              _buildHistoryTable(ctrl),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    RateController ctrl, {
    required bool isAdmin,
    required bool isNarrow,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Tarifas por Litro',
          style: AppTheme.titleStyle(isMobile: isNarrow),
        ),
        const SizedBox(height: 4),
        const Text(
          'Valor oficial de compra por litro de leche cruda e historial de vigencias por período.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    );

    final Widget actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: ctrl.isLoading ? null : ctrl.loadRates,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Actualizar'),
        ),
        if (isAdmin)
          PrimaryActionButton(
            label: 'Nueva tarifa vigente',
            icon: Icons.add_rounded,
            fullWidth: false,
            onPressed: _openCreateRateDialog,
          ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[titleBlock, const SizedBox(height: 12), actions],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        actions,
      ],
    );
  }

  Widget _buildKpiStrip(RateController ctrl, bool isNarrow) {
    final MilkRateModel? active = ctrl.activeRate;

    final Widget hero = _ActiveRateHero(
      rate: active,
      variation: ctrl.variationAmount,
      variationPercent: ctrl.variationPercent,
    );

    final List<Widget> side = <Widget>[
      AppMetricTile(
        title: 'Referencia 1.000 L',
        value: active != null
            ? AppFormatters.formatCurrency(active.precioPorLitro * 1000)
            : '—',
        subtitle: 'Estimado bruto por cada mil litros',
        icon: Icons.calculate_outlined,
        accentColor: AppTheme.indigoAccent,
      ),
      AppMetricTile(
        title: 'Vigencias registradas',
        value: '${ctrl.rates.length}',
        subtitle: ctrl.fromCache
            ? 'Mostrando respaldo local'
            : 'Historial íntegro conservado',
        icon: Icons.history_rounded,
        accentColor: AppTheme.warmGold,
      ),
    ];

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          hero,
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: side[0]),
              const SizedBox(width: 10),
              Expanded(child: side[1]),
            ],
          ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(flex: 2, child: hero),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: <Widget>[side[0], const SizedBox(height: 12), side[1]],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required bool isAdmin}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: <Widget>[
          const AppIconBadge(
            icon: Icons.payments_outlined,
            color: AppTheme.primaryGreen,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            'Aún no hay una tarifa por litro registrada',
            style: AppTheme.subtitleStyle(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Configura el valor oficial vigente por litro para habilitar los cierres quincenales y estimados de producción.',
            style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (isAdmin) ...<Widget>[
            const SizedBox(height: 18),
            PrimaryActionButton(
              label: 'Configurar tarifa inicial',
              icon: Icons.add_rounded,
              fullWidth: false,
              onPressed: _openCreateRateDialog,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryTable(RateController ctrl) {
    // Tarifa inmediatamente anterior (por fecha de inicio) de cada vigencia.
    final List<MilkRateModel> byDate = List<MilkRateModel>.from(ctrl.rates)
      ..sort(
        (MilkRateModel a, MilkRateModel b) =>
            a.fechaInicioVigencia.compareTo(b.fechaInicioVigencia),
      );
    final Map<String, MilkRateModel> previousOf = <String, MilkRateModel>{
      for (int i = 1; i < byDate.length; i++) byDate[i].tarifaId: byDate[i - 1],
    };

    return CleanDataTable(
      columns: const <CleanTableColumn>[
        CleanTableColumn(label: 'Estado'),
        CleanTableColumn(label: 'Precio por litro', numeric: true),
        CleanTableColumn(label: 'Variación'),
        CleanTableColumn(label: 'Vigencia'),
        CleanTableColumn(label: 'Referencia 500 L', numeric: true),
        CleanTableColumn(label: 'Observación / Motivo'),
      ],
      rows: ctrl.rates.map((MilkRateModel rate) {
        final bool isActive = rate.activa;
        final MilkRateModel? prev = previousOf[rate.tarifaId];
        return <Widget>[
          _RateStateBadge(active: isActive),
          Text(
            AppFormatters.formatCurrency(rate.precioPorLitro),
            style: AppTheme.monoStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: isActive ? AppTheme.primaryGreen : AppTheme.textPrimary,
            ),
          ),
          prev == null
              ? const Text(
                  'Tarifa base',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                )
              : _VariationChip(
                  amount: rate.precioPorLitro - prev.precioPorLitro,
                  percent: prev.precioPorLitro > 0
                      ? (rate.precioPorLitro - prev.precioPorLitro) /
                            prev.precioPorLitro *
                            100
                      : null,
                ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                AppFormatters.formatDate(rate.fechaInicioVigencia),
                style: AppTheme.monoStyle(fontSize: 12.5),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: AppTheme.textMuted,
                ),
              ),
              Text(
                rate.fechaFinVigencia != null
                    ? AppFormatters.formatDate(rate.fechaFinVigencia!)
                    : 'Actualidad',
                style: rate.fechaFinVigencia != null
                    ? AppTheme.monoStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      )
                    : const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryGreen,
                      ),
              ),
            ],
          ),
          Text(
            AppFormatters.formatCurrency(rate.precioPorLitro * 500),
            style: AppTheme.monoStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              rate.observacion.isEmpty ? '—' : rate.observacion,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ];
      }).toList(),
    );
  }
}

/// Tarjeta destacada con la tarifa vigente y su variación.
class _ActiveRateHero extends StatelessWidget {
  const _ActiveRateHero({
    required this.rate,
    required this.variation,
    required this.variationPercent,
  });

  final MilkRateModel? rate;
  final double? variation;
  final double? variationPercent;

  @override
  Widget build(BuildContext context) {
    final MilkRateModel? r = rate;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 4),
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.inkBlack, Color(0xFF14663A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F0C3B24),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -6,
            bottom: -18,
            child: Icon(
              Icons.water_drop_rounded,
              size: 120,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tarifa vigente actual',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCFE9D8),
                      ),
                    ),
                  ),
                  if (r != null) const _LivePill(),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      r != null
                          ? AppFormatters.formatCurrency(r.precioPorLitro)
                          : 'Sin definir',
                      style: AppTheme.monoStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (r != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '/ litro',
                        style: AppTheme.monoStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFCFE9D8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _HeroChip(
                    icon: Icons.event_available_outlined,
                    label: r != null
                        ? 'Desde el ${AppFormatters.formatDate(r.fechaInicioVigencia)}'
                        : 'Registra la tarifa base inicial',
                  ),
                  if (variation != null)
                    _HeroChip(
                      icon: variation! > 0
                          ? Icons.trending_up_rounded
                          : variation! < 0
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                      label:
                          '${variation! >= 0 ? '+' : ''}${AppFormatters.formatCurrency(variation!)}'
                          '${variationPercent != null ? ' (${variationPercent! >= 0 ? '+' : ''}${variationPercent!.toStringAsFixed(1)}%)' : ''}'
                          ' vs. anterior',
                    )
                  else if (r != null)
                    const _HeroChip(
                      icon: Icons.flag_outlined,
                      label: 'Sin historial previo',
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: const Color(0xFF4ADE80).withValues(alpha: 0.4),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.circle, size: 7, color: Color(0xFF4ADE80)),
          SizedBox(width: 5),
          Text(
            'En vigor',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateStateBadge extends StatelessWidget {
  const _RateStateBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppTheme.successBg : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: active
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            active ? Icons.bolt_rounded : Icons.history_rounded,
            size: 13,
            color: active ? AppTheme.success : AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            active ? 'Vigente' : 'Histórica',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? AppTheme.successText : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de subida / bajada de precio respecto a la vigencia anterior.
class _VariationChip extends StatelessWidget {
  const _VariationChip({required this.amount, this.percent});

  final double amount;
  final double? percent;

  @override
  Widget build(BuildContext context) {
    final bool up = amount > 0;
    final bool flat = amount == 0;
    final Color fg = flat
        ? AppTheme.textSecondary
        : (up ? AppTheme.successText : AppTheme.dangerText);
    final Color bg = flat
        ? AppTheme.surfaceMuted
        : (up ? AppTheme.successBg : AppTheme.dangerBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            flat
                ? Icons.remove_rounded
                : (up
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded),
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 3),
          Text(
            '${up ? '+' : ''}${AppFormatters.formatCurrency(amount)}'
            '${percent != null ? ' · ${percent!.abs().toStringAsFixed(1)}%' : ''}',
            style: AppTheme.monoStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateRateDialog extends StatefulWidget {
  const _CreateRateDialog({required this.actor, this.currentPrice});

  final UserModel actor;
  final double? currentPrice;

  @override
  State<_CreateRateDialog> createState() => _CreateRateDialogState();
}

class _CreateRateDialogState extends State<_CreateRateDialog> {
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _obsCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();
  String? _priceError;

  @override
  void initState() {
    super.initState();
    if (widget.currentPrice != null && widget.currentPrice! > 0) {
      _priceCtrl.text = widget.currentPrice!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _submit() async {
    final double? price = AppFormatters.parseCurrencyInput(_priceCtrl.text);
    if (price == null || price <= 0) {
      context.read<RateController>().clearFeedback();
      setState(
        () => _priceError = 'Ingresa un precio por litro válido mayor a cero.',
      );
      return;
    }

    final DateTime startDay = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      0,
      0,
      0,
    );

    final bool ok = await context.read<RateController>().createRate(
      actor: widget.actor,
      precioPorLitro: price,
      fechaInicioVigencia: startDay,
      observacion: _obsCtrl.text,
    );
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final RateController ctrl = context.watch<RateController>();
    final String? error = ctrl.errorMessage;
    final double? current = widget.currentPrice;
    final double? typed = AppFormatters.parseCurrencyInput(_priceCtrl.text);
    final double? diff = (current != null && typed != null && typed > 0)
        ? typed - current
        : null;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDialogHeader(
                icon: Icons.price_change_outlined,
                title: 'Actualizar tarifa por litro',
                subtitle:
                    'Se cerrará la vigencia actual sin alterar liquidaciones ya emitidas.',
                onClose: ctrl.isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 18),
              _label('Precio por litro (COP)'),
              TextField(
                controller: _priceCtrl,
                autofocus: true,
                enabled: !ctrl.isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: AppTheme.monoStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (_) => setState(() => _priceError = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Ej: 1850',
                  prefixText: r'$ ',
                  prefixStyle: AppTheme.monoStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                  suffixText: '/ litro',
                  suffixStyle: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                  errorText: _priceError,
                ),
              ),
              const SizedBox(height: 10),
              AppInfoPanel(
                children: <Widget>[
                  AppInfoRow(
                    label: 'Tarifa actual',
                    value: current != null
                        ? AppFormatters.formatCurrency(current)
                        : 'Sin tarifa previa',
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Variación',
                    value: diff == null
                        ? '—'
                        : '${diff >= 0 ? '+' : ''}${AppFormatters.formatCurrency(diff)}'
                              '${current != null && current > 0 ? ' (${diff >= 0 ? '+' : ''}${(diff / current * 100).toStringAsFixed(1)}%)' : ''}',
                    mono: true,
                  ),
                  AppInfoRow(
                    label: 'Referencia 1.000 L',
                    value: typed != null && typed > 0
                        ? AppFormatters.formatCurrency(typed * 1000)
                        : '—',
                    mono: true,
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _label('Fecha de inicio de vigencia'),
              InkWell(
                onTap: ctrl.isSaving ? null : _pickDate,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today_outlined, size: 17),
                    suffixIcon: Icon(Icons.edit_calendar_outlined, size: 17),
                  ),
                  child: Text(
                    AppFormatters.formatDate(_startDate, useLocal: false),
                    style: AppTheme.monoStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _label('Observación o motivo del ajuste'),
              TextField(
                controller: _obsCtrl,
                enabled: !ctrl.isSaving,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Ej: Ajuste quincenal aprobado por junta directiva',
                ),
              ),
              if (error != null && error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                AppInlineNotice.danger(message: error),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    onPressed: ctrl.isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  PrimaryActionButton(
                    label: 'Guardar tarifa',
                    icon: Icons.check_rounded,
                    isLoading: ctrl.isSaving,
                    fullWidth: false,
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
