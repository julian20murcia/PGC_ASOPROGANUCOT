import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_portal_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/settlement_pdf_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_notification_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/privacy_notice.dart';
import '../../models/producer_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/privacy_notice_view.dart';
import '../shared/widgets/ui_kit.dart';

/// Portal móvil exclusivo de solo lectura para Productores / Ganaderos en campo
/// (`RF-19` a `RF-24`, `RNF-02`, `RNF-05`, `HU-10` a `HU-14`).
class ProducerShellView extends StatefulWidget {
  const ProducerShellView({super.key});

  @override
  State<ProducerShellView> createState() => _ProducerShellViewState();
}

class _ProducerShellViewState extends State<ProducerShellView> {
  int _tabIndex = 0;
  int _settlementsSubTab = 0; // 0: Comprobantes PDF, 1: Avisos y Comunicados
  ProducerPortalController? _fallbackCtrl;
  bool _usesFallbackCtrl = false;
  String? _loadedForUid;

  ProducerPortalController _resolvePortalController(BuildContext context) {
    try {
      _usesFallbackCtrl = false;
      return context.watch<ProducerPortalController>();
    } on ProviderNotFoundException {
      _usesFallbackCtrl = true;
      return _fallbackCtrl ??= ProducerPortalController.createDefault(
        enablePersistence: false,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final UserModel? user = context.read<AuthController>().currentUser;
    final ProducerPortalController portal = _resolvePortalController(context);
    if (user != null && _loadedForUid != user.uid) {
      _loadedForUid = user.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        portal.loadPortalForUser(user);
      });
    }
  }

  @override
  void dispose() {
    _fallbackCtrl?.dispose();
    super.dispose();
  }

  static String _greeting() {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  void _goToNoticesTab() {
    setState(() {
      _tabIndex = 2;
      _settlementsSubTab = 1;
    });
  }

  void _openProfileSheet(
    BuildContext context,
    ProducerPortalController portal,
    UserModel user,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ProducerProfileSheet(portal: portal, user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();
    final ProducerPortalController portal = _resolvePortalController(context);

    Widget buildScaffold(BuildContext ctx) {
      final ProducerModel? producer = portal.activeProducer;
      final double topInset = MediaQuery.of(ctx).padding.top;
      final int unreadCount = portal.unreadNotificationsCount;

      return Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Column(
          children: <Widget>[
            ModernWaveHeader(
              height: 176 + topInset,
              bottomSurfaceColor: AppTheme.canvas,
              padding: EdgeInsets.fromLTRB(18, topInset + 10, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const AsoproganucotLogo(
                        size: 34,
                        compact: true,
                        onDark: true,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          AppConstants.appName,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _HeaderAction(
                        tooltip: 'Actualizar datos',
                        icon: Icons.refresh_rounded,
                        onPressed: portal.isLoading
                            ? null
                            : () => portal.loadPortalForUser(user),
                      ),
                      const SizedBox(width: 5),
                      _HeaderAction(
                        tooltip: 'Avisos y comunicados',
                        icon: Icons.notifications_none_rounded,
                        badgeCount: unreadCount,
                        onPressed: _goToNoticesTab,
                      ),
                      const SizedBox(width: 5),
                      _HeaderAction(
                        tooltip: 'Mi perfil y Habeas Data',
                        icon: Icons.account_circle_outlined,
                        iconColor: const Color(0xFF86EFAC),
                        onPressed: () => _openProfileSheet(ctx, portal, user),
                      ),
                      const SizedBox(width: 5),
                      _HeaderAction(
                        tooltip: 'Cerrar sesión',
                        icon: Icons.logout_rounded,
                        onPressed: auth.signOut,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _greeting(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA7F3D0),
                        ),
                      ),
                      Text(
                        'Hola, ${producer?.nombreCompleto ?? user.nombreCompleto}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          if (producer != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                producer.codigoAsociado,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          Text(
                            producer != null
                                ? 'C.C. ${user.documento} · ${producer.vereda}'
                                : 'C.C. ${user.documento} · ${AppConstants.roleShortLabel(user.rol)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFD1FAE5),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  portal.isLoading &&
                      producer == null &&
                      portal.allReceptions.isEmpty
                  ? const Center(
                      child: DairyLoader(
                        size: DairyLoaderSize.lg,
                        label: 'Cargando tu información…',
                        hint: 'Consultando entregas y liquidaciones.',
                      ),
                    )
                  : IndexedStack(
                      index: _tabIndex,
                      children: <Widget>[
                        _ProducerSummaryTab(
                          portal: portal,
                          onOpenDeliveries: () => setState(() => _tabIndex = 1),
                          onOpenSettlements: () => setState(() {
                            _tabIndex = 2;
                            _settlementsSubTab = 0;
                          }),
                          onOpenNotices: _goToNoticesTab,
                          onOpenProfile: () =>
                              _openProfileSheet(ctx, portal, user),
                        ),
                        _ProducerDeliveriesTab(portal: portal),
                        _ProducerSettlementsAndNoticesTab(
                          portal: portal,
                          activeSubTab: _settlementsSubTab,
                          onChangeSubTab: (int next) =>
                              setState(() => _settlementsSubTab = next),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: NavigationBar(
            backgroundColor: AppTheme.surface,
            indicatorColor: AppTheme.primaryGreenLight,
            height: 68,
            selectedIndex: _tabIndex,
            onDestinationSelected: (int index) =>
                setState(() => _tabIndex = index),
            destinations: <NavigationDestination>[
              const NavigationDestination(
                icon: Icon(Icons.home_outlined, color: AppTheme.primaryGreen),
                selectedIcon: Icon(
                  Icons.home_rounded,
                  color: AppTheme.primaryGreen,
                ),
                label: 'Resumen',
              ),
              const NavigationDestination(
                icon: Icon(Icons.water_drop_outlined, color: AppTheme.skyBlue),
                selectedIcon: Icon(
                  Icons.water_drop_rounded,
                  color: AppTheme.skyBlue,
                ),
                label: 'Mis Entregas',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  backgroundColor: AppTheme.warmGold,
                  label: Text('$unreadCount'),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.warmGold,
                  ),
                ),
                selectedIcon: const Icon(
                  Icons.notifications_rounded,
                  color: AppTheme.warmGold,
                ),
                label: 'Liquidaciones',
              ),
            ],
          ),
        ),
      );
    }

    if (_usesFallbackCtrl) {
      return AnimatedBuilder(
        animation: portal,
        builder: (BuildContext context, _) => buildScaffold(context),
      );
    }
    return buildScaffold(context);
  }
}

/// Pestaña 1: Resumen (`RF-20`, `RNF-02`: alto contraste y texto >= 15px para campo).
class _ProducerSummaryTab extends StatelessWidget {
  const _ProducerSummaryTab({
    required this.portal,
    required this.onOpenDeliveries,
    required this.onOpenSettlements,
    required this.onOpenNotices,
    required this.onOpenProfile,
  });

  final ProducerPortalController portal;
  final VoidCallback onOpenDeliveries;
  final VoidCallback onOpenSettlements;
  final VoidCallback onOpenNotices;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final ProducerModel? producer = portal.activeProducer;
    final SettlementModel? latest = portal.latestSettlement;
    final double pricePerLiter = portal.activePricePerLiter;

    return RefreshIndicator(
      color: AppTheme.primaryGreen,
      onRefresh: () async {
        final UserModel? u = portal.activeUser;
        if (u != null) await portal.loadPortalForUser(u);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          if (portal.fromCache) ...<Widget>[
            _InfoBanner(
              icon: Icons.cloud_off_rounded,
              color: AppTheme.skyBlue,
              bgColor: AppTheme.skyBlueLight,
              text:
                  'Mostrando respaldo local en tu teléfono. Los datos se actualizarán al recuperar señal.',
            ),
            const SizedBox(height: 12),
          ],
          if (producer == null) ...<Widget>[
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              color: AppTheme.warmGold,
              bgColor: AppTheme.warmGoldLight,
              text:
                  'Tu usuario aún no tiene una ficha de productor vinculada. Solicita la vinculación en planta Susa para ver tus entregas y pagos.',
            ),
            const SizedBox(height: 12),
          ],
          // Tarjeta principal: Acumulado Quincenal y Proyectado
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF0369A1), AppTheme.skyBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x290284C7),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  right: -14,
                  top: -10,
                  child: Icon(
                    Icons.water_drop_rounded,
                    size: 110,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.water_drop_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Acopio Quincenal',
                                style: AppTheme.subtitleStyle(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                portal.currentQuincena.label,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE0F2FE),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${portal.quincenaDeliveriesCount} ent.',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppFormatters.formatLiters(portal.quincenaLiters),
                      style: AppTheme.monoStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: <Widget>[
                          const AppIconBadge(
                            icon: Icons.payments_outlined,
                            color: AppTheme.primaryGreen,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'Estimado proyectado quincena',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    pricePerLiter > 0
                                        ? AppFormatters.formatCurrency(
                                            portal.quincenaEstimatedAmount,
                                          )
                                        : 'Sin tarifa configurada',
                                    style: AppTheme.monoStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primaryGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (pricePerLiter > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.canvasAlt,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Text(
                                '${AppFormatters.formatCurrency(pricePerLiter)}/L',
                                style: AppTheme.monoStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.inkBlack,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Dos tarjetas rápidas: Mes actual + Última liquidación
          Row(
            children: <Widget>[
              Expanded(
                child: _MobileCompactMetricCard(
                  title: 'Total del mes',
                  value: AppFormatters.formatLiters(portal.monthLiters),
                  subtitle:
                      'Prom. ${AppFormatters.formatLiters(portal.averageDailyLiters)}/día',
                  icon: Icons.calendar_month_rounded,
                  accentColor: AppTheme.primaryGreen,
                  bgColor: AppTheme.primaryGreenLight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MobileCompactMetricCard(
                  title: 'Último pago',
                  value: latest != null
                      ? AppFormatters.formatCurrency(latest.valorTotalPagar)
                      : 'Sin cierres',
                  subtitle: latest != null
                      ? '${latest.numeroComprobante} · ${latest.estadoPago}'
                      : 'En proceso',
                  icon: Icons.receipt_long_rounded,
                  accentColor: AppTheme.warmGold,
                  bgColor: AppTheme.warmGoldLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Gráfico simple de barras últimos 7 días
          _MobileRecentChartCard(series: portal.last7DaysSeries),
          const SizedBox(height: 12),
          // Accesos de máximo 2 toques
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text('Accesos rápidos', style: AppTheme.subtitleStyle()),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: _QuickTile(
                  icon: Icons.water_drop_outlined,
                  color: AppTheme.skyBlue,
                  label: 'Mis entregas',
                  onTap: onOpenDeliveries,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickTile(
                  icon: Icons.picture_as_pdf_outlined,
                  color: AppTheme.primaryGreen,
                  label: 'Comprobantes',
                  onTap: onOpenSettlements,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _QuickTile(
                  icon: Icons.campaign_outlined,
                  color: AppTheme.warmGold,
                  label: 'Avisos (${portal.unreadNotificationsCount})',
                  onTap: onOpenNotices,
                  badge: portal.unreadNotificationsCount > 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickTile(
                  icon: Icons.verified_user_outlined,
                  color: AppTheme.tealAccent,
                  label: 'Perfil y rectificación',
                  onTap: onOpenProfile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileCompactMetricCard extends StatelessWidget {
  const _MobileCompactMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080C3B24),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(height: 3, color: accentColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppIconBadge(icon: icon, color: accentColor, size: 30),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: AppTheme.monoStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileRecentChartCard extends StatelessWidget {
  const _MobileRecentChartCard({required this.series});

  final List<ProducerDailySeriesPoint> series;

  @override
  Widget build(BuildContext context) {
    double maxTotal = 0;
    for (final ProducerDailySeriesPoint p in series) {
      if (p.totalLiters > maxTotal) maxTotal = p.totalLiters;
    }
    if (maxTotal <= 0) maxTotal = 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIconBadge(
                icon: Icons.bar_chart_rounded,
                color: AppTheme.primaryGreen,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Entregas últimos 7 días',
                  style: AppTheme.subtitleStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: <Widget>[
              _MiniDot(color: AppTheme.skyBlue, label: 'Mañana'),
              SizedBox(width: 12),
              _MiniDot(color: AppTheme.primaryGreen, label: 'Tarde'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 156,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  top: 18,
                  bottom: 24,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List<Widget>.generate(
                      3,
                      (_) => Container(height: 1, color: AppTheme.dividerLight),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: series.map((ProducerDailySeriesPoint d) {
                    final double total = d.totalLiters;
                    final double factor = (total / maxTotal).clamp(0.04, 1.0);
                    final bool isToday = identical(d, series.last);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Text(
                              total > 0 ? total.toStringAsFixed(0) : '0',
                              style: AppTheme.monoStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: total <= 0 ? 0.04 : factor,
                                  child: Container(
                                    width: 24,
                                    decoration: BoxDecoration(
                                      color: total <= 0
                                          ? AppTheme.border
                                          : Colors.transparent,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                        bottom: Radius.circular(2),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: total <= 0
                                        ? null
                                        : Column(
                                            children: <Widget>[
                                              if (d.afternoonLiters > 0)
                                                Expanded(
                                                  flex:
                                                      (d.afternoonLiters * 100)
                                                          .round()
                                                          .clamp(1, 100000),
                                                  child: Container(
                                                    color:
                                                        AppTheme.primaryGreen,
                                                  ),
                                                ),
                                              if (d.morningLiters > 0)
                                                Expanded(
                                                  flex: (d.morningLiters * 100)
                                                      .round()
                                                      .clamp(1, 100000),
                                                  child: Container(
                                                    color: AppTheme.skyBlue,
                                                  ),
                                                ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? AppTheme.inkBlack
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                d.label,
                                maxLines: 1,
                                softWrap: false,
                                style: AppTheme.monoStyle(
                                  fontSize: 10.5,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isToday
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDot extends StatelessWidget {
  const _MiniDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Pestaña 2: Mis Entregas Diarias (`RF-21`, `HU-11`, solo lectura).
class _ProducerDeliveriesTab extends StatelessWidget {
  const _ProducerDeliveriesTab({required this.portal});

  final ProducerPortalController portal;

  Future<void> _pickDate(BuildContext context) async {
    final DateTime initial = portal.selectedDateFilter ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      portal.setSelectedDateFilter(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<MilkReceptionModel> list = portal.filteredReceptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _FilterPill(
                      label: 'Quincena actual',
                      selected: portal.periodFilter == 'QUINCENA',
                      color: AppTheme.primaryGreen,
                      onTap: () => portal.setPeriodFilter('QUINCENA'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'Mes actual',
                      selected: portal.periodFilter == 'MES',
                      color: AppTheme.primaryGreen,
                      onTap: () => portal.setPeriodFilter('MES'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: portal.selectedDateFilter != null
                          ? AppFormatters.formatDate(portal.selectedDateFilter!)
                          : 'Elegir fecha',
                      selected: portal.periodFilter == 'FECHA',
                      color: AppTheme.skyBlue,
                      onTap: () => _pickDate(context),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'Todas',
                      selected: portal.periodFilter == 'TODAS',
                      color: AppTheme.primaryGreen,
                      onTap: () => portal.setPeriodFilter('TODAS'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _FilterPill(
                      label: 'Todas las jornadas',
                      selected: portal.shiftFilter == 'ALL',
                      color: AppTheme.inkBlack,
                      onTap: () => portal.setShiftFilter('ALL'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'Mañana',
                      selected: portal.shiftFilter == AppConstants.shiftMorning,
                      color: AppTheme.skyBlue,
                      onTap: () =>
                          portal.setShiftFilter(AppConstants.shiftMorning),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'Tarde',
                      selected:
                          portal.shiftFilter == AppConstants.shiftAfternoon,
                      color: AppTheme.warmGold,
                      onTap: () =>
                          portal.setShiftFilter(AppConstants.shiftAfternoon),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: <Color>[AppTheme.inkBlack, Color(0xFF14663A)],
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.fact_check_outlined,
                      size: 19,
                      color: Color(0xFFA7F3D0),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${list.length} entrega(s) en filtro',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      AppFormatters.formatLiters(portal.filteredTotalLiters),
                      style: AppTheme.monoStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.water_drop_outlined,
                          size: 36,
                          color: AppTheme.skyBlue,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Sin entregas en este filtro',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Prueba seleccionando otra quincena, fecha o jornada.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final MilkReceptionModel r = list[index];
                    final bool isMorning =
                        r.jornada == AppConstants.shiftMorning;
                    final Color shiftColor = isMorning
                        ? AppTheme.skyBlue
                        : AppTheme.warmGold;
                    final Color shiftBg = isMorning
                        ? AppTheme.skyBlueLight
                        : AppTheme.warmGoldLight;

                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x080C3B24),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Container(width: 4, color: shiftColor),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: shiftBg,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                isMorning
                                                    ? Icons.wb_sunny_outlined
                                                    : Icons.wb_twilight_rounded,
                                                size: 14,
                                                color: shiftColor,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                isMorning ? 'MAÑANA' : 'TARDE',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: shiftColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Spacer(),
                                        SyncStatusBadge(isSynced: r.isSynced),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                AppFormatters.formatIsoDate(
                                                  r.fechaEntrega,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: <Widget>[
                                                  const Icon(
                                                    Icons.schedule_rounded,
                                                    size: 15,
                                                    color: AppTheme.textMuted,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Flexible(
                                                    child: Text(
                                                      'Hora de acopio: ${r.horaEntrega}',
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        color: AppTheme
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: <Widget>[
                                            Text(
                                              AppFormatters.formatLiters(
                                                r.litros,
                                              ),
                                              style: AppTheme.monoStyle(
                                                fontSize: 21,
                                                fontWeight: FontWeight.w800,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: r.isLiquidada
                                                    ? AppTheme.primaryGreenLight
                                                    : AppTheme.surfaceMuted,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                r.isLiquidada
                                                    ? 'Liquidada'
                                                    : 'En quincena',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: r.isLiquidada
                                                      ? AppTheme.primaryGreen
                                                      : AppTheme.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Pestaña 3: Liquidaciones quincenales con descarga PDF + Bandeja de Avisos (`RF-22`, `RF-24`).
class _ProducerSettlementsAndNoticesTab extends StatelessWidget {
  const _ProducerSettlementsAndNoticesTab({
    required this.portal,
    required this.activeSubTab,
    required this.onChangeSubTab,
  });

  final ProducerPortalController portal;
  final int activeSubTab;
  final ValueChanged<int> onChangeSubTab;

  @override
  Widget build(BuildContext context) {
    final List<SettlementModel> settlements = portal.settlements;
    final List<AppNotificationModel> notifications =
        portal.visibleNotifications;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _SubTabButton(
                  label: 'Comprobantes (${settlements.length})',
                  icon: Icons.receipt_long_rounded,
                  selected: activeSubTab == 0,
                  accentColor: AppTheme.primaryGreen,
                  onTap: () => onChangeSubTab(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SubTabButton(
                  label: 'Avisos (${portal.unreadNotificationsCount})',
                  icon: Icons.campaign_rounded,
                  selected: activeSubTab == 1,
                  accentColor: AppTheme.warmGold,
                  onTap: () => onChangeSubTab(1),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: activeSubTab == 0
              ? _buildSettlementsList(context, settlements)
              : _buildNotificationsList(context, notifications),
        ),
      ],
    );
  }

  Widget _buildSettlementsList(
    BuildContext context,
    List<SettlementModel> settlements,
  ) {
    if (settlements.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.receipt_long_outlined,
                size: 38,
                color: AppTheme.primaryGreen,
              ),
              SizedBox(height: 10),
              Text(
                'Aún no tienes liquidaciones cerradas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                'Cuando la planta cierre la quincena podrás ver y descargar aquí tu comprobante en PDF.',
                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: settlements.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final SettlementModel s = settlements[index];
        final bool isPaid = s.isPagada;
        final Color statusColor = isPaid
            ? AppTheme.primaryGreen
            : AppTheme.warmGold;
        final Color statusBg = isPaid
            ? AppTheme.primaryGreenLight
            : AppTheme.warmGoldLight;

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0A0C3B24),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(height: 4, color: statusColor),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        AppIconBadge(
                          icon: Icons.receipt_long_rounded,
                          color: statusColor,
                          size: 38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                s.quincenaLabel,
                                style: AppTheme.subtitleStyle(),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Comprobante ${s.numeroComprobante}',
                                style: AppTheme.monoStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                isPaid
                                    ? Icons.task_alt_rounded
                                    : Icons.schedule_rounded,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                s.estadoPago,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.date_range_outlined,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Del ${AppFormatters.formatIsoDate(s.periodoInicio)} al ${AppFormatters.formatIsoDate(s.periodoFin)}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.canvasAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: <Widget>[
                          _SettlementRow(
                            label: 'Total litros (${s.cantidadEntregas} ent.)',
                            value: AppFormatters.formatLiters(s.totalLitros),
                          ),
                          const SizedBox(height: 6),
                          _SettlementRow(
                            label: 'Tarifa aplicada',
                            value:
                                '${AppFormatters.formatCurrency(s.precioLitroAplicado)}/L',
                          ),
                          const Divider(height: 16),
                          _SettlementRow(
                            label: 'Valor total a pagar',
                            value: AppFormatters.formatCurrency(
                              s.valorTotalPagar,
                            ),
                            highlightColor: AppTheme.primaryGreen,
                            large: true,
                          ),
                        ],
                      ),
                    ),
                    if (isPaid && s.fechaPago != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: AppTheme.primaryGreen,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Pagado el ${AppFormatters.formatDate(s.fechaPago!)}${s.observacionPago != null ? ' · ${s.observacionPago}' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _openPdfVoucher(context, s, share: false),
                            icon: const Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Ver PDF',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openPdfVoucher(context, s, share: true),
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: const Text(
                              'Descargar',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPdfVoucher(
    BuildContext context,
    SettlementModel settlement, {
    required bool share,
  }) async {
    try {
      final List<MilkReceptionModel> recs = portal.receptionsForSettlement(
        settlement,
      );
      if (share) {
        await SettlementPdfService.shareOrDownloadVoucher(
          settlement: settlement,
          receptions: recs,
          producer: portal.activeProducer,
        );
      } else {
        await SettlementPdfService.printOrPreviewVoucher(
          settlement: settlement,
          receptions: recs,
          producer: portal.activeProducer,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible abrir el comprobante PDF: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Widget _buildNotificationsList(
    BuildContext context,
    List<AppNotificationModel> notifications,
  ) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _FilterPill(
                      label: 'Todas (${portal.allNotifications.length})',
                      selected: !portal.onlyUnreadNotifications,
                      color: AppTheme.primaryGreen,
                      onTap: () => portal.setOnlyUnreadNotifications(false),
                    ),
                    _FilterPill(
                      label: 'No leídas (${portal.unreadNotificationsCount})',
                      selected: portal.onlyUnreadNotifications,
                      color: AppTheme.warmGold,
                      onTap: () => portal.setOnlyUnreadNotifications(true),
                    ),
                  ],
                ),
                if (portal.unreadNotificationsCount > 0)
                  TextButton(
                    onPressed: portal.markAllRead,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Marcar leídas'),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: notifications.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 38,
                          color: AppTheme.warmGold,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Sin avisos o comunicados por mostrar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Recibirás alertas automáticas por cada entrega, cierre de quincena, pago y comunicado oficial.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final AppNotificationModel n = notifications[index];
                    final ({Color color, Color bg, IconData icon, String label})
                    meta = _notificationMeta(n.tipo);

                    return InkWell(
                      onTap: () =>
                          portal.markNotificationRead(n.notificacionId),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: n.leida
                              ? AppTheme.surface
                              : meta.bg.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: n.leida
                                ? AppTheme.border
                                : meta.color.withValues(alpha: 0.40),
                            width: n.leida ? 1 : 1.3,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: meta.bg,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                meta.icon,
                                size: 19,
                                color: meta.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: meta.bg,
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                        child: Text(
                                          n.destinoProductorId == null
                                              ? '${meta.label} · General'
                                              : meta.label,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: meta.color,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      if (!n.leida)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: meta.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    n.titulo,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.mensaje,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      height: 1.4,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppFormatters.formatDateTime(n.fechaEnvio),
                                    style: AppTheme.monoStyle(
                                      fontSize: 12.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static ({Color color, Color bg, IconData icon, String label})
  _notificationMeta(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'ENTREGA':
        return (
          color: AppTheme.skyBlue,
          bg: AppTheme.skyBlueLight,
          icon: Icons.water_drop_rounded,
          label: 'Entrega diaria',
        );
      case 'CIERRE_QUINCENA':
      case 'LIQUIDACION':
        return (
          color: AppTheme.indigoAccent,
          bg: AppTheme.indigoLight,
          icon: Icons.receipt_long_rounded,
          label: 'Liquidación',
        );
      case 'PAGO':
        return (
          color: AppTheme.primaryGreen,
          bg: AppTheme.primaryGreenLight,
          icon: Icons.payments_rounded,
          label: 'Pago confirmado',
        );
      case 'RECTIFICACION':
        return (
          color: AppTheme.tealAccent,
          bg: AppTheme.tealLight,
          icon: Icons.verified_user_rounded,
          label: 'Habeas Data',
        );
      default:
        return (
          color: AppTheme.warmGold,
          bg: AppTheme.warmGoldLight,
          icon: Icons.campaign_rounded,
          label: 'Comunicado',
        );
    }
  }
}

/// Hoja modal de Perfil del Productor y Solicitud de Rectificación Ley 1581 de 2012 (`RF-19`).
class _ProducerProfileSheet extends StatefulWidget {
  const _ProducerProfileSheet({required this.portal, required this.user});

  final ProducerPortalController portal;
  final UserModel user;

  @override
  State<_ProducerProfileSheet> createState() => _ProducerProfileSheetState();
}

class _ProducerProfileSheetState extends State<_ProducerProfileSheet> {
  static const List<String> _fields = <String>[
    'Teléfono de contacto',
    'Nombre de finca / predio',
    'Vereda',
    'Nombres o apellidos',
    'Otro dato personal',
  ];

  bool _showRectificationForm = false;
  String _selectedField = _fields.first;
  final TextEditingController _detailCtrl = TextEditingController();
  String? _localMessage;
  bool _localSuccess = false;

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final bool ok = await widget.portal.submitRectificationRequest(
      actor: widget.user,
      campo: _selectedField,
      detalle: _detailCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _localSuccess = ok;
      _localMessage = ok
          ? (widget.portal.feedbackMessage ??
                'Solicitud enviada al Administrador.')
          : (widget.portal.errorMessage ?? 'No se pudo enviar la solicitud.');
      if (ok) {
        _detailCtrl.clear();
        _showRectificationForm = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ProducerModel? producer = widget.portal.activeProducer;
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: AppTheme.primaryGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Mi Perfil de Asociado',
                          style: AppTheme.serifStyle(fontSize: 19),
                        ),
                        const Text(
                          'Consulta personal y Habeas Data (Ley 1581 de 2012)',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.canvasAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: <Widget>[
                    _ProfileLine(
                      label: 'Nombre completo',
                      value:
                          producer?.nombreCompleto ??
                          widget.user.nombreCompleto,
                    ),
                    _ProfileLine(
                      label: 'Cédula / Documento',
                      value: producer?.cedula ?? widget.user.documento,
                    ),
                    if (widget.user.correo.isNotEmpty)
                      _ProfileLine(
                        label: 'Correo de acceso',
                        value: widget.user.correo,
                      ),
                    _ProfileLine(
                      label: 'Teléfono',
                      value: producer?.telefono ?? widget.user.telefono,
                    ),
                    if (producer != null) ...<Widget>[
                      _ProfileLine(
                        label: 'Código de asociado',
                        value: producer.codigoAsociado,
                      ),
                      _ProfileLine(
                        label: 'Finca / Predio',
                        value: producer.nombreFinca,
                      ),
                      _ProfileLine(
                        label: 'Vereda',
                        value: '${producer.vereda}, Susa',
                      ),
                      _ProfileLine(
                        label: 'Estado asociación',
                        value: producer.estado,
                      ),
                      _ProfileLine(
                        label: 'Habeas Data',
                        value:
                            producer.soporteAutorizacion != null &&
                                producer.hasValidHabeasData
                            ? 'Autorizado (${AppFormatters.formatDate(producer.fechaAutorizacionDatos!)})'
                            : 'Consulta el soporte con la asociación',
                      ),
                    ],
                  ],
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text('Aviso de privacidad y canales de atención'),
                onPressed: () {
                  final notice = PrivacyNotice.load();
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Tratamiento de datos personales'),
                      content: SingleChildScrollView(
                        child: FutureBuilder<PrivacyNotice>(
                          future: notice,
                          builder: (context, snapshot) {
                            final data = snapshot.data;
                            if (data != null) {
                              return PrivacyNoticeView(notice: data);
                            }
                            if (snapshot.hasError) {
                              final savedNotice = producer?.avisoPrivacidad;
                              if (savedNotice != null) {
                                return PrivacyNoticeView(
                                  notice: PrivacyNotice.fromMap(savedNotice),
                                );
                              }
                              return const Text(
                                'No se pudo cargar el aviso. Puedes solicitar una copia en la sede de la asociación.',
                              );
                            }
                            return const LinearProgressIndicator();
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (_localMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _InfoBanner(
                  icon: _localSuccess
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: _localSuccess
                      ? AppTheme.primaryGreen
                      : AppTheme.danger,
                  bgColor: _localSuccess
                      ? AppTheme.primaryGreenLight
                      : AppTheme.dangerBg,
                  text: _localMessage!,
                ),
              ],
              const SizedBox(height: 14),
              if (producer != null && !_showRectificationForm)
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showRectificationForm = true),
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: AppTheme.tealAccent,
                  ),
                  label: const Text(
                    'Solicitar rectificación de datos (Ley 1581)',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              if (_showRectificationForm) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.tealLight.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.tealAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Solicitud de rectificación de datos personales',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppSelect<String>(
                        value: _selectedField,
                        labelText: 'Dato a corregir',
                        prefixIcon: Icons.edit_note_rounded,
                        options: _fields
                            .map(
                              (String f) =>
                                  AppSelectOption<String>(value: f, label: f),
                            )
                            .toList(),
                        onChanged: (String value) {
                          setState(() => _selectedField = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _detailCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'Indica el dato actualizado que deseas corregir en tu ficha…',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.portal.isSubmitting
                                  ? null
                                  : () => setState(
                                      () => _showRectificationForm = false,
                                    ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: widget.portal.isSubmitting
                                  ? null
                                  : _sendRequest,
                              child: widget.portal.isSubmitting
                                  ? const DairyLoader(
                                      size: DairyLoaderSize.xs,
                                      label: '',
                                      color: Colors.white,
                                    )
                                  : const Text('Enviar solicitud'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.label,
    required this.value,
    this.highlightColor,
    this.large = false,
  });

  final String label;
  final String value;
  final Color? highlightColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: large ? 15.5 : 14.5,
              fontWeight: large ? FontWeight.w700 : FontWeight.w500,
              color: large ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppTheme.monoStyle(
            fontSize: large ? 18 : 15,
            fontWeight: FontWeight.w800,
            color: highlightColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? color : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  const _SubTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.14)
              : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? accentColor : AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected ? accentColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? accentColor : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón circular translúcido para la cabecera verde del portal.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.badgeCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color iconColor;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(icon, size: 19, color: iconColor),
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.warmGold,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppTheme.inkBlack, width: 1.5),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Acceso rápido grande (objetivo táctil amplio para uso en campo).
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      AppIconBadge(icon: icon, color: color, size: 40),
                      if (badge)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: AppTheme.warmGold,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
