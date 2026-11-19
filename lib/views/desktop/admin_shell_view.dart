import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../controllers/producer_portal_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_notification_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/app_select.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/ui_kit.dart';
import 'dashboard_module_view.dart';
import 'producers_module_view.dart';
import 'rates_module_view.dart';
import 'reception_module_view.dart';
import 'reports_module_view.dart';
import 'settlements_module_view.dart';
import 'users_module_view.dart';

enum AdminSection {
  dashboard,
  recepcion,
  productores,
  liquidaciones,
  tarifas,
  reportes,
  usuarios,
}

class _NavItemMeta {
  const _NavItemMeta({
    required this.section,
    required this.label,
    required this.icon,
    required this.group,
    required this.adminOnly,
    required this.description,
    required this.accentColor,
    required this.darkIconColor,
    this.isFooterGroup = false,
  });

  final AdminSection section;
  final String label;
  final IconData icon;
  final String group;
  final bool adminOnly;
  final String description;
  final Color accentColor;
  final Color darkIconColor;
  final bool isFooterGroup;
}

/// Shell administrativo de escritorio/planta de ASOPROGANUCOT:
/// barra lateral en tinta negra `#0E1117` con pestaña cóncava blanca activa,
/// encabezados serif con divisores y hoja principal limpia en blanco puro `#FFFFFF`.
class AdminShellView extends StatefulWidget {
  const AdminShellView({super.key});

  @override
  State<AdminShellView> createState() => _AdminShellViewState();
}

class _AdminShellViewState extends State<AdminShellView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AdminSection _activeSection;
  bool _sidebarExpanded = true;

  static const List<_NavItemMeta> _allNavItems = <_NavItemMeta>[
    _NavItemMeta(
      section: AdminSection.dashboard,
      label: 'Inicio',
      icon: Icons.home_outlined,
      group: 'Principal',
      adminOnly: false,
      accentColor: AppTheme.primaryGreen,
      darkIconColor: Color(0xFF4ADE80),
      description:
          'Resumen diario de litros acopiados por jornada (mañana y tarde) y acumulado de la quincena actual.',
    ),
    _NavItemMeta(
      section: AdminSection.recepcion,
      label: 'Recepción de Leche',
      icon: Icons.water_drop_outlined,
      group: 'Operación en planta',
      adminOnly: false,
      accentColor: AppTheme.skyBlue,
      darkIconColor: Color(0xFF38BDF8),
      description:
          'Registro ágil en planta por productor y jornada (Mañana / Tarde) con guardado seguro y verificación de duplicados.',
    ),
    _NavItemMeta(
      section: AdminSection.productores,
      label: 'Productores',
      icon: Icons.agriculture_outlined,
      group: 'Operación en planta',
      adminOnly: false,
      accentColor: AppTheme.primaryGreen,
      darkIconColor: Color(0xFF34D399),
      description:
          'Padrón general de ganaderos asociados en Susa, código interno, datos de contacto y autorización de datos.',
    ),
    _NavItemMeta(
      section: AdminSection.liquidaciones,
      label: 'Liquidaciones',
      icon: Icons.receipt_long_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      accentColor: AppTheme.warmGold,
      darkIconColor: Color(0xFFFBBF24),
      description:
          'Cálculo quincenal automático, comprobantes descargables en PDF, control de pagos y avisos a productores.',
    ),
    _NavItemMeta(
      section: AdminSection.tarifas,
      label: 'Tarifas por Litro',
      icon: Icons.payments_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      accentColor: AppTheme.tealAccent,
      darkIconColor: Color(0xFF2DD4BF),
      description:
          'Configuración del valor vigente por litro de leche cruda e historial de ajustes por período.',
    ),
    _NavItemMeta(
      section: AdminSection.reportes,
      label: 'Reportes y Auditoría',
      icon: Icons.assessment_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      accentColor: AppTheme.indigoAccent,
      darkIconColor: Color(0xFF818CF8),
      description:
          'Estadísticas consolidadas por productor y por período exportables para archivo contable y control interno.',
    ),
    _NavItemMeta(
      section: AdminSection.usuarios,
      label: 'Usuarios',
      icon: Icons.manage_accounts_outlined,
      group: 'Administración',
      adminOnly: true,
      accentColor: AppTheme.skyBlue,
      darkIconColor: Color(0xFF60A5FA),
      description:
          'Administración de cuentas de acceso y perfiles del personal administrativo, operarios de planta y productores.',
      isFooterGroup: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final AuthController auth = context.read<AuthController>();
    _activeSection = auth.currentUser?.isAdmin == true
        ? AdminSection.usuarios
        : AdminSection.recepcion;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserController>().startConnectivityMonitor();
    });
  }

  List<_NavItemMeta> _visibleItemsFor(UserModel user) {
    return _allNavItems
        .where((_NavItemMeta item) => !item.adminOnly || user.isAdmin)
        .toList();
  }

  _NavItemMeta _metaFor(AdminSection section) {
    return _allNavItems.firstWhere(
      (_NavItemMeta m) => m.section == section,
      orElse: () => _allNavItems.last,
    );
  }

  String _roleDisplayName(String rol) {
    switch (rol) {
      case AppConstants.roleAdmin:
        return 'Administrador';
      case AppConstants.roleOperario:
        return 'Operario de planta';
      case AppConstants.roleProductor:
        return 'Productor';
      default:
        return rol;
    }
  }

  void _selectSection(AdminSection section) {
    if (_activeSection == section) return;
    setState(() => _activeSection = section);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserController userCtrl = context.watch<UserController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();
    final List<_NavItemMeta> items = _visibleItemsFor(user);
    final bool isDesktop = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.canvas,
      drawer: isDesktop
          ? null
          : Drawer(
              width: 248,
              backgroundColor: AppTheme.inkBlack,
              child: SafeArea(
                child: _buildBlackSidebar(
                  user: user,
                  items: items,
                  expanded: true,
                  isDrawer: true,
                  onSelectSection: (AdminSection section) {
                    _selectSection(section);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      body: Row(
        children: <Widget>[
          if (isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              width: _sidebarExpanded ? 244 : 62,
              child: _buildBlackSidebar(
                user: user,
                items: items,
                expanded: _sidebarExpanded,
                isDrawer: false,
                onSelectSection: _selectSection,
              ),
            ),
          Expanded(
            child: Container(
              color: AppTheme.canvas,
              child: Column(
                children: <Widget>[
                  _buildTopBar(
                    isDesktop: isDesktop,
                    isOnline: userCtrl.isOnline,
                    user: user,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 210),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder:
                          (
                            Widget? currentChild,
                            List<Widget> previousChildren,
                          ) {
                            return Stack(
                              alignment: Alignment.topLeft,
                              fit: StackFit.expand,
                              children: <Widget>[
                                ...previousChildren,
                                ?currentChild,
                              ],
                            );
                          },
                      transitionBuilder:
                          (Widget child, Animation<double> anim) {
                            return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.01),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            );
                          },
                      child: KeyedSubtree(
                        key: ValueKey<AdminSection>(_activeSection),
                        child: _buildActiveSectionBody(user),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlackSidebar({
    required UserModel user,
    required List<_NavItemMeta> items,
    required bool expanded,
    required bool isDrawer,
    required ValueChanged<AdminSection> onSelectSection,
  }) {
    final List<_NavItemMeta> mainItems = items
        .where((_NavItemMeta i) => !i.isFooterGroup)
        .toList();
    final List<_NavItemMeta> footerItems = items
        .where((_NavItemMeta i) => i.isFooterGroup)
        .toList();

    final Map<String, List<_NavItemMeta>> grouped =
        <String, List<_NavItemMeta>>{};
    for (final _NavItemMeta item in mainItems) {
      grouped.putIfAbsent(item.group, () => <_NavItemMeta>[]).add(item);
    }

    return Container(
      color: AppTheme.inkBlack,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Estelas sutiles de Susa en el cuarto inferior del menú lateral
          const MilkFlowBackground(bottomMasked: true, opacity: 0.75),
          SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Marca + botón de colapso
                Padding(
                  padding: EdgeInsets.fromLTRB(expanded ? 12 : 8, 14, 8, 12),
                  child: expanded
                      ? Row(
                          children: <Widget>[
                            const AsoproganucotLogo(
                              size: 32,
                              compact: true,
                              onDark: true,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      AppConstants.appName,
                                      maxLines: 1,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.1,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Planta Susa',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white.withValues(
                                        alpha: 0.84,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isDrawer)
                              _SidebarIconButton(
                                tooltip: 'Contraer menú',
                                icon: Icons.chevron_left_rounded,
                                onPressed: () =>
                                    setState(() => _sidebarExpanded = false),
                              ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const AsoproganucotLogo(
                              size: 30,
                              compact: true,
                              onDark: true,
                            ),
                            const SizedBox(height: 8),
                            _SidebarIconButton(
                              tooltip: 'Expandir menú',
                              icon: Icons.chevron_right_rounded,
                              onPressed: () =>
                                  setState(() => _sidebarExpanded = true),
                            ),
                          ],
                        ),
                ),
                // Navegación principal agrupada
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 10 : 6,
                      4,
                      isDrawer ? 10 : 0,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: grouped.entries.map((
                        MapEntry<String, List<_NavItemMeta>> entry,
                      ) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (expanded)
                              _SidebarGroupHeader(
                                title: entry.key,
                                rightInset: isDrawer ? 0 : 12,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Divider(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                            ...entry.value.map(
                              (_NavItemMeta item) => _OtepNavTab(
                                item: item,
                                selected: _activeSection == item.section,
                                expanded: expanded,
                                showConcaveTab: !isDrawer && expanded,
                                onTap: () => onSelectSection(item.section),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // Sección inferior de administración (ej. Usuarios)
                if (footerItems.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 10 : 6,
                      0,
                      isDrawer ? 10 : 0,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (expanded)
                          _SidebarGroupHeader(
                            title: 'Administración',
                            rightInset: isDrawer ? 0 : 12,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                        ...footerItems.map(
                          (_NavItemMeta item) => _OtepNavTab(
                            item: item,
                            selected: _activeSection == item.section,
                            expanded: expanded,
                            showConcaveTab: !isDrawer && expanded,
                            onTap: () => onSelectSection(item.section),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Pie con perfil del usuario activo y cierre de sesión
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: expanded ? 10 : 6,
                    vertical: 10,
                  ),
                  child: expanded
                      ? Container(
                          padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              _UserInitialCircle(initials: user.initials),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      user.nombreCompleto,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      _roleDisplayName(user.rol),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white.withValues(
                                          alpha: 0.84,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _SidebarIconButton(
                                tooltip: 'Cerrar sesión',
                                icon: Icons.logout_rounded,
                                onPressed: () =>
                                    context.read<AuthController>().signOut(),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _UserInitialCircle(initials: user.initials),
                            const SizedBox(height: 8),
                            _SidebarIconButton(
                              tooltip: 'Cerrar sesión',
                              icon: Icons.logout_rounded,
                              onPressed: () =>
                                  context.read<AuthController>().signOut(),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBroadcastDialog(UserModel user) async {
    ProducerPortalController? portalCtrl;
    ProducerController? producerCtrl;
    bool ownsPortalCtrl = false;
    try {
      portalCtrl = context.read<ProducerPortalController>();
    } on ProviderNotFoundException {
      portalCtrl = ProducerPortalController.createDefault(
        enablePersistence: false,
      );
      ownsPortalCtrl = true;
    }
    try {
      producerCtrl = context.read<ProducerController>();
    } on ProviderNotFoundException {
      producerCtrl = null;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _BroadcastDialog(
        actor: user,
        portalController: portalCtrl!,
        producers: producerCtrl?.allProducers ?? const <ProducerModel>[],
      ),
    );
    if (ownsPortalCtrl) {
      portalCtrl.dispose();
    }
  }

  Widget _buildTopBar({
    required bool isDesktop,
    required bool isOnline,
    required UserModel user,
  }) {
    final _NavItemMeta meta = _metaFor(_activeSection);

    return Container(
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 22 : 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x080C3B24),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          if (!isDesktop) ...<Widget>[
            IconButton(
              tooltip: 'Abrir menú',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(
                Icons.menu_rounded,
                size: 20,
                color: AppTheme.inkBlack,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Row(
              children: <Widget>[
                if (isDesktop) ...<Widget>[
                  Flexible(
                    flex: 1,
                    child: Text(
                      meta.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
                AppIconBadge(
                  icon: meta.icon,
                  color: meta.accentColor,
                  size: 30,
                ),
                const SizedBox(width: 9),
                Flexible(
                  flex: 2,
                  child: Text(
                    meta.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (user.isAdmin) ...<Widget>[
                  if (isDesktop)
                    OutlinedButton.icon(
                      onPressed: () => _openBroadcastDialog(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(
                        Icons.campaign_rounded,
                        size: 16,
                        color: AppTheme.warmGold,
                      ),
                      label: const Text(
                        'Comunicados',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Comunicados institucionales',
                      onPressed: () => _openBroadcastDialog(user),
                      icon: const Icon(
                        Icons.campaign_rounded,
                        size: 20,
                        color: AppTheme.warmGold,
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
                _ConnectionPill(isOnline: isOnline),
                if (isDesktop) ...<Widget>[
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: AppTheme.border,
                  ),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.place_outlined,
                        size: 15,
                        color: AppTheme.primaryGreen,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Susa, Cundinamarca',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: AppTheme.border,
                  ),
                  const _LiveHeaderDateTime(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSectionBody(UserModel user) {
    if (_activeSection == AdminSection.dashboard) {
      return DashboardModuleView(
        onNavigateSection: (String key) {
          switch (key) {
            case 'recepcion':
              _selectSection(AdminSection.recepcion);
            case 'productores':
              _selectSection(AdminSection.productores);
            case 'liquidaciones':
              _selectSection(AdminSection.liquidaciones);
            case 'tarifas':
              _selectSection(AdminSection.tarifas);
            case 'reportes':
              _selectSection(AdminSection.reportes);
          }
        },
      );
    }
    if (_activeSection == AdminSection.usuarios) {
      return const UsersModuleView();
    }
    if (_activeSection == AdminSection.productores) {
      return const ProducersModuleView();
    }
    if (_activeSection == AdminSection.recepcion) {
      return const ReceptionModuleView();
    }
    if (_activeSection == AdminSection.tarifas) {
      return const RatesModuleView();
    }
    if (_activeSection == AdminSection.liquidaciones) {
      return const SettlementsModuleView();
    }
    if (_activeSection == AdminSection.reportes) {
      return const ReportsModuleView();
    }

    final _NavItemMeta meta = _metaFor(_activeSection);
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Icon(
                        meta.icon,
                        color: AppTheme.primaryGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            meta.label,
                            style: AppTheme.serifStyle(
                              fontSize: 20,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Text(
                            'Módulo operativo de planta',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  meta.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (user.isAdmin) ...<Widget>[
                  const SizedBox(height: 22),
                  PrimaryActionButton(
                    label: 'Volver a Usuarios',
                    icon: Icons.manage_accounts_outlined,
                    fullWidth: false,
                    onPressed: () => _selectSection(AdminSection.usuarios),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final Color fg = isOnline ? AppTheme.successText : AppTheme.warningText;
    final Color bg = isOnline ? AppTheme.successBg : AppTheme.warningBg;
    final Color dot = isOnline ? AppTheme.success : AppTheme.warning;
    return Tooltip(
      message: isOnline
          ? 'Conectado: los registros se sincronizan con la nube.'
          : 'Sin conexión: los registros se guardan en este equipo.',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: dot.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(color: dot.withValues(alpha: 0.45), blurRadius: 5),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 5),
            Text(
              isOnline ? 'En línea' : 'Sin conexión',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  const _SidebarGroupHeader({required this.title, this.rightInset = 12});

  final String title;
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 12, rightInset, 6),
      child: Row(
        children: <Widget>[
          Flexible(
            flex: 8,
            fit: FlexFit.loose,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtepNavTab extends StatefulWidget {
  const _OtepNavTab({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.showConcaveTab,
    required this.onTap,
  });

  final _NavItemMeta item;
  final bool selected;
  final bool expanded;
  final bool showConcaveTab;
  final VoidCallback onTap;

  @override
  State<_OtepNavTab> createState() => _OtepNavTabState();
}

class _OtepNavTabState extends State<_OtepNavTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final bool showConcave = selected && widget.showConcaveTab;

    final Color fg = selected
        ? AppTheme.inkBlack
        : _hovered
        ? Colors.white
        : const Color(0xFFF8FAFC);
    final Color iconColor = selected
        ? widget.item.accentColor
        : widget.item.darkIconColor;
    final Color bg = selected
        ? AppTheme.canvas
        : _hovered
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.transparent;

    final BorderRadius radius = showConcave
        ? const BorderRadius.only(
            topLeft: Radius.circular(8),
            bottomLeft: Radius.circular(8),
          )
        : BorderRadius.circular(7);

    final Widget tabTile = Tooltip(
      message: widget.expanded ? '' : widget.item.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 36,
              margin: showConcave
                  ? EdgeInsets.zero
                  : EdgeInsets.only(right: widget.expanded ? 10 : 0),
              padding: EdgeInsets.symmetric(
                horizontal: widget.expanded ? 11 : 0,
              ),
              decoration: BoxDecoration(color: bg, borderRadius: radius),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected
                          ? widget.item.accentColor.withValues(alpha: 0.14)
                          : widget.item.darkIconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(widget.item.icon, size: 16, color: iconColor),
                  ),
                  if (widget.expanded) ...<Widget>[
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!showConcave) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: tabTile,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          tabTile,
          Positioned(
            top: -8,
            right: 0,
            width: 8,
            height: 8,
            child: IgnorePointer(
              child: CustomPaint(painter: _ConcaveFilletPainter(isTop: true)),
            ),
          ),
          Positioned(
            bottom: -8,
            right: 0,
            width: 8,
            height: 8,
            child: IgnorePointer(
              child: CustomPaint(painter: _ConcaveFilletPainter(isTop: false)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja las esquinas cóncavas de 8px de la pestaña activa contra la barra lateral.
class _ConcaveFilletPainter extends CustomPainter {
  _ConcaveFilletPainter({required this.isTop});

  final bool isTop;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width;
    final Paint paint = Paint()
      ..color = AppTheme.canvas
      ..style = PaintingStyle.fill;

    final Path path = Path();
    if (isTop) {
      path
        ..moveTo(r, 0)
        ..lineTo(r, r)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r), clockwise: false)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(r, 0)
        ..lineTo(r, r)
        ..arcToPoint(Offset.zero, radius: Radius.circular(r), clockwise: false)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConcaveFilletPainter oldDelegate) =>
      oldDelegate.isTop != isTop;
}

class _UserInitialCircle extends StatelessWidget {
  const _UserInitialCircle({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppTheme.primaryGreen, AppTheme.skyBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatefulWidget {
  const _SidebarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<_SidebarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 17,
              color: _hovered
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.86),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveHeaderDateTime extends StatefulWidget {
  const _LiveHeaderDateTime();

  @override
  State<_LiveHeaderDateTime> createState() => _LiveHeaderDateTimeState();
}

class _LiveHeaderDateTimeState extends State<_LiveHeaderDateTime> {
  static const List<String> _months = <String>[
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final DateTime current = DateTime.now();
      if (current.minute != _now.minute || current.hour != _now.hour) {
        setState(() => _now = current);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _pad2(int n) => n < 10 ? '0$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final String formatted =
        '${_pad2(_now.day)} ${_months[_now.month - 1]} ${_now.year} · '
        '${_pad2(_now.hour)}:${_pad2(_now.minute)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.canvasAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.schedule_rounded,
            size: 13,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            formatted,
            style: AppTheme.monoStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Diálogo administrativo para emitir comunicados institucionales masivos o dirigidos (`RF-24`, `HU-14`).
class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog({
    required this.actor,
    required this.portalController,
    required this.producers,
  });

  final UserModel actor;
  final ProducerPortalController portalController;
  final List<ProducerModel> producers;

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();
  String? _selectedProducerId;
  String? _feedback;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.portalController.loadAdminNotifications();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bool ok = await widget.portalController.sendBroadcast(
      actor: widget.actor,
      titulo: _titleCtrl.text,
      mensaje: _messageCtrl.text,
      destinoProductorId: _selectedProducerId,
    );
    if (!mounted) return;
    setState(() {
      _isSuccess = ok;
      _feedback = ok
          ? (widget.portalController.feedbackMessage ?? 'Comunicado enviado.')
          : (widget.portalController.errorMessage ?? 'No se pudo enviar.');
      if (ok) {
        _titleCtrl.clear();
        _messageCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.portalController,
      builder: (BuildContext context, _) {
        final ProducerPortalController ctrl = widget.portalController;
        final List<AppNotificationModel> history = ctrl.adminNotifications;
        final bool general = _selectedProducerId == null;

        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: (MediaQuery.of(context).size.height * 0.9).clamp(
                420.0,
                720.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[AppTheme.warmGoldLight, AppTheme.surface],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    border: Border(
                      bottom: BorderSide(color: AppTheme.dividerLight),
                    ),
                  ),
                  child: AppDialogHeader(
                    icon: Icons.campaign_rounded,
                    color: AppTheme.warmGold,
                    title: 'Comunicados Institucionales',
                    subtitle:
                        'Envía avisos push a todos los productores o a un asociado puntual.',
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AppSelect<String?>(
                          value: _selectedProducerId,
                          labelText: 'Destinatario',
                          prefixIcon: Icons.campaign_outlined,
                          searchable: true,
                          searchHint: 'Buscar productor…',
                          options: <AppSelectOption<String?>>[
                            const AppSelectOption<String?>(
                              value: null,
                              label:
                                  'Todos los productores (Comunicado general)',
                              icon: Icons.groups_2_outlined,
                            ),
                            ...widget.producers
                                .where((ProducerModel p) => p.isActivo)
                                .map(
                                  (ProducerModel p) => AppSelectOption<String?>(
                                    value: p.productorId,
                                    label: p.nombreCompleto,
                                    description: 'Código ${p.codigoAsociado}',
                                  ),
                                ),
                          ],
                          onChanged: (String? value) {
                            setState(() => _selectedProducerId = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Icon(
                              general
                                  ? Icons.public_rounded
                                  : Icons.person_pin_outlined,
                              size: 14,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                general
                                    ? 'Llegará a todos los productores activos con la app instalada.'
                                    : 'Solo el productor seleccionado recibirá el aviso.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _titleCtrl,
                          maxLength: 80,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Asunto del comunicado',
                            hintText:
                                'Ej. Reunión general de asociados en Susa',
                            prefixIcon: Icon(Icons.title_rounded, size: 17),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _messageCtrl,
                          maxLines: 4,
                          maxLength: 500,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Mensaje',
                            alignLabelWithHint: true,
                            hintText:
                                'Escribe el aviso que llegará a la bandeja y alertas del productor…',
                          ),
                        ),
                        if (_feedback != null) ...<Widget>[
                          const SizedBox(height: 8),
                          _isSuccess
                              ? AppInlineNotice(
                                  icon: Icons.check_circle_outline_rounded,
                                  background: AppTheme.primaryGreenLight,
                                  foreground: AppTheme.successText,
                                  message: _feedback!,
                                )
                              : AppInlineNotice.danger(message: _feedback!),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: PrimaryActionButton(
                            label: 'Enviar comunicado',
                            icon: Icons.send_rounded,
                            fullWidth: false,
                            isLoading: ctrl.isSubmitting,
                            onPressed: _submit,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.history_rounded,
                              size: 17,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'Historial reciente de avisos y solicitudes',
                              style: AppTheme.subtitleStyle(),
                            ),
                            const SizedBox(width: 8),
                            AppCountPill(text: '${history.length}'),
                            const SizedBox(width: 10),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (ctrl.isLoading && history.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: DairyLoader(
                                size: DairyLoaderSize.sm,
                                label: 'Cargando avisos…',
                              ),
                            ),
                          )
                        else if (history.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 22),
                            decoration: BoxDecoration(
                              color: AppTheme.canvasAlt,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusCard,
                              ),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: const Column(
                              children: <Widget>[
                                AppIconBadge(
                                  icon: Icons.notifications_none_rounded,
                                  color: AppTheme.warmGold,
                                  size: 40,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Aún no se han emitido comunicados institucionales.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final AppNotificationModel n in history)
                            _HistoryItem(notification: n),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.notification});

  final AppNotificationModel notification;

  @override
  Widget build(BuildContext context) {
    final AppNotificationModel n = notification;
    final bool rect = n.tipo == 'RECTIFICACION';
    final Color color = rect ? AppTheme.tealAccent : AppTheme.warmGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIconBadge(
            icon: rect ? Icons.rate_review_outlined : Icons.campaign_outlined,
            color: color,
            size: 32,
          ),
          const SizedBox(width: 10),
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
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                      ),
                      child: Text(
                        n.tipo,
                        style: AppTheme.monoStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      AppFormatters.formatDateTime(n.fechaEnvio),
                      style: AppTheme.monoStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  n.titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  n.mensaje,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppTheme.textSecondary,
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
