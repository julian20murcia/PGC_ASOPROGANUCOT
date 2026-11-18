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
            const SizedBox(height: 16),
            _buildIntegrityNotice(),
            const SizedBox(height: 16),
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
            else
              _buildHistoryTable(ctrl),
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
        children: <Widget>[
          titleBlock,
          const SizedBox(height: 12),
          actions,
        ],
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
    final double? diff = ctrl.variationAmount;
    final double? pct = ctrl.variationPercent;

    final String variationLabel = diff == null
        ? 'Sin historial previo'
        : '${diff >= 0 ? '+' : ''}${AppFormatters.formatCurrency(diff)}'
            '${pct != null ? ' (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)' : ''}';

    final List<Widget> cards = <Widget>[
      AppKpiCard(
        title: 'Tarifa vigente actual',
        value: active != null
            ? AppFormatters.formatCurrency(active.precioPorLitro)
            : 'Sin definir',
        subtitle: active != null
            ? 'Desde el ${AppFormatters.formatDate(active.fechaInicioVigencia)}'
            : 'Registra la tarifa base inicial',
        icon: Icons.payments_outlined,
        accentColor: AppTheme.primaryGreen,
      ),
      AppKpiCard(
        title: 'Variación respecto anterior',
        value: diff == null
            ? '—'
            : '${diff >= 0 ? '+' : ''}${AppFormatters.formatCurrency(diff)}',
        subtitle: variationLabel,
        icon: Icons.trending_up_rounded,
        accentColor: AppTheme.skyBlue,
      ),
      AppKpiCard(
        title: 'Vigencias registradas',
        value: '${ctrl.rates.length}',
        subtitle: ctrl.fromCache
            ? 'Mostrando respaldo local'
            : 'Historial íntegro conservado',
        icon: Icons.history_rounded,
        accentColor: AppTheme.warmGold,
      ),
      AppKpiCard(
        title: 'Referencia 1.000 L',
        value: active != null
            ? AppFormatters.formatCurrency(active.precioPorLitro * 1000)
            : '—',
        subtitle: 'Estimado bruto por cada mil litros',
        icon: Icons.calculate_outlined,
        accentColor: AppTheme.indigoAccent,
      ),
    ];

    if (isNarrow) {
      return Column(
        children: cards
            .map(
              (Widget card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: card,
              ),
            )
            .toList(),
      );
    }

    return Row(
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          Expanded(child: cards[i]),
          if (i < cards.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  Widget _buildIntegrityNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreenLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppTheme.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.verified_outlined,
            size: 18,
            color: AppTheme.primaryGreen,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cada ajuste crea una nueva vigencia sin modificar los precios anteriores. Las liquidaciones ya cerradas conservan intacta la tarifa aplicada al momento de su emisión.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.successText,
                height: 1.4,
              ),
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
          const Icon(
            Icons.payments_outlined,
            size: 42,
            color: AppTheme.textMuted,
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
    return CleanDataTable(
      columns: const <CleanTableColumn>[
        CleanTableColumn(label: 'Estado'),
        CleanTableColumn(label: 'Precio por litro', numeric: true),
        CleanTableColumn(label: 'Vigencia desde'),
        CleanTableColumn(label: 'Vigencia hasta'),
        CleanTableColumn(label: 'Referencia 500 L', numeric: true),
        CleanTableColumn(label: 'Observación / Motivo'),
      ],
      rows: ctrl.rates.map((MilkRateModel rate) {
        final bool isActive = rate.activa;
        return <Widget>[
          SyncStatusBadge(
            isSynced: isActive,
            syncedLabel: 'Vigente',
            pendingLabel: 'Histórica',
          ),
          Text(
            AppFormatters.formatCurrency(rate.precioPorLitro),
            style: AppTheme.monoStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: isActive ? AppTheme.primaryGreen : AppTheme.textPrimary,
            ),
          ),
          Text(
            AppFormatters.formatDate(rate.fechaInicioVigencia),
            style: AppTheme.monoStyle(
              fontSize: 12.5,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            rate.fechaFinVigencia != null
                ? AppFormatters.formatDate(rate.fechaFinVigencia!)
                : 'Actualidad',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isActive ? AppTheme.primaryGreen : AppTheme.textSecondary,
            ),
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
              rate.observacion,
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

class _CreateRateDialog extends StatefulWidget {
  const _CreateRateDialog({
    required this.actor,
    this.currentPrice,
  });

  final UserModel actor;
  final double? currentPrice;

  @override
  State<_CreateRateDialog> createState() => _CreateRateDialogState();
}

class _CreateRateDialogState extends State<_CreateRateDialog> {
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _obsCtrl = TextEditingController();
  DateTime _startDate = DateTime.now();

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
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un precio por litro válido mayor a cero.'),
          backgroundColor: AppTheme.danger,
        ),
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

  @override
  Widget build(BuildContext context) {
    final RateController ctrl = context.watch<RateController>();
    final String? error = ctrl.errorMessage;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Actualizar tarifa por litro',
                      style: AppTheme.serifStyle(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: ctrl.isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Se cerrará la vigencia actual sin alterar liquidaciones ya emitidas.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              const Text(
                'Precio por litro (COP)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  hintText: 'Ej: 1850',
                  prefixText: r'$ ',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Fecha de inicio de vigencia',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: ctrl.isSaving ? null : _pickDate,
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  AppFormatters.formatDate(_startDate, useLocal: false),
                  style: AppTheme.monoStyle(fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Observación o motivo del ajuste',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Ej: Ajuste quincenal aprobado por junta directiva',
                ),
              ),
              if (error != null && error.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerBg,
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.dangerText,
                    ),
                  ),
                ),
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
