import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/dairy_loader.dart';
import '../shared/widgets/design_system_widgets.dart';
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
    required this.rfTags,
    this.isFooterGroup = false,
  });

  final AdminSection section;
  final String label;
  final IconData icon;
  final String group;
  final bool adminOnly;
  final String description;
  final List<String> rfTags;
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
      description:
          'Indicadores operativos de litros acopiados por jornada (mañana y tarde), acumulado quincenal y estado de sincronización.',
      rfTags: <String>['RF-16', 'RNF-03'],
    ),
    _NavItemMeta(
      section: AdminSection.recepcion,
      label: 'Recepción de Leche',
      icon: Icons.water_drop_outlined,
      group: 'Operación en planta',
      adminOnly: false,
      description:
          'Captura rápida 100% teclado en planta (Mañana / Tarde) con persistencia offline-first en Hive y alerta de duplicados.',
      rfTags: <String>['RF-08', 'RF-09', 'RF-10', 'RF-11'],
    ),
    _NavItemMeta(
      section: AdminSection.productores,
      label: 'Productores',
      icon: Icons.agriculture_outlined,
      group: 'Operación en planta',
      adminOnly: false,
      description:
          'Padrón de ganaderos asociados en Susa con validación de cédula única, código interno y consentimiento Ley 1581 de 2012.',
      rfTags: <String>['RF-04', 'RF-05', 'RF-06', 'RF-07'],
    ),
    _NavItemMeta(
      section: AdminSection.liquidaciones,
      label: 'Liquidaciones',
      icon: Icons.receipt_long_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      description:
          'Cálculo quincenal exacto, emisión de comprobantes PDF (Ley 527/1999), registro de pagos y notificaciones push.',
      rfTags: <String>['RF-13', 'RF-14', 'RF-15'],
    ),
    _NavItemMeta(
      section: AdminSection.tarifas,
      label: 'Tarifas por Litro',
      icon: Icons.payments_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      description:
          'Configuración de precio vigente por litro de leche cruda conservando el histórico para auditorías.',
      rfTags: <String>['RF-12'],
    ),
    _NavItemMeta(
      section: AdminSection.reportes,
      label: 'Reportes y Auditoría',
      icon: Icons.assessment_outlined,
      group: 'Finanzas y control',
      adminOnly: true,
      description:
          'Estadísticas individuales y globales exportables en PDF/CSV y bitácora inmutable de auditoría.',
      rfTags: <String>['RF-17', 'RF-18', 'RNF-06'],
    ),
    _NavItemMeta(
      section: AdminSection.usuarios,
      label: 'Usuarios',
      icon: Icons.manage_accounts_outlined,
      group: 'Administración',
      adminOnly: true,
      description:
          'Gestión de cuentas en Firebase Authentication y asignación de roles diferenciados (ADMIN, OPERARIO, PRODUCTOR).',
      rfTags: <String>['RF-01', 'RF-02', 'RF-03'],
      isFooterGroup: true,
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
              width: 244,
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
              width: _sidebarExpanded ? 228 : 62,
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
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 210),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
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
    final List<_NavItemMeta> mainItems =
        items.where((_NavItemMeta i) => !i.isFooterGroup).toList();
    final List<_NavItemMeta> footerItems =
        items.where((_NavItemMeta i) => i.isFooterGroup).toList();

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
                  padding: EdgeInsets.fromLTRB(
                    expanded ? 14 : 8,
                    14,
                    expanded ? 10 : 8,
                    12,
                  ),
                  child: expanded
                      ? Row(
                          children: <Widget>[
                            const AsoproganucotLogo(
                              size: 32,
                              compact: true,
                              onDark: true,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    AppConstants.appName,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Planta Susa',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.52),
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
                      children: grouped.entries.map(
                        (MapEntry<String, List<_NavItemMeta>> entry) {
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
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
                        },
                      ).toList(),
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
                    horizontal: expanded ? 12 : 6,
                    vertical: 12,
                  ),
                  child: expanded
                      ? Row(
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
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.56),
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

  Widget _buildTopBar({
    required bool isDesktop,
    required bool isOnline,
  }) {
    final _NavItemMeta meta = _metaFor(_activeSection);

    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 22 : 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
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
                  Text(
                    meta.group,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '/',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
                Flexible(
                  child: Text(
                    meta.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.25,
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
                SyncStatusBadge(
                  isSynced: isOnline,
                  syncedLabel: 'En línea',
                  pendingLabel: 'Offline · Hive',
                ),
                if (isDesktop) ...<Widget>[
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: AppTheme.border,
                  ),
                  const Text(
                    'Susa, Cundinamarca',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
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
    if (_activeSection == AdminSection.usuarios) {
      return const UsersModuleView();
    }

    final _NavItemMeta meta = _metaFor(_activeSection);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
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
                      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
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
                          'Módulo planificado en la hoja de ruta',
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: meta.rfTags
                    .map(
                      (String tag) => HeaderPropertyChip(label: tag, value: ''),
                    )
                    .toList(),
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
    );
  }
}

class _SidebarGroupHeader extends StatelessWidget {
  const _SidebarGroupHeader({
    required this.title,
    this.rightInset = 12,
  });

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
              style: GoogleFonts.sourceSerif4(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: Colors.white.withValues(alpha: 0.50),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.11),
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
            : Colors.white.withValues(alpha: 0.78);
    final Color iconColor = selected
        ? AppTheme.primaryGreen
        : _hovered
            ? Colors.white
            : Colors.white.withValues(alpha: 0.62);
    final Color bg = selected
        ? AppTheme.surface
        : _hovered
            ? Colors.white.withValues(alpha: 0.08)
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
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
              ),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: <Widget>[
                  Icon(widget.item.icon, size: 17, color: iconColor),
                  if (widget.expanded) ...<Widget>[
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
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
              child: CustomPaint(
                painter: _ConcaveFilletPainter(isTop: true),
              ),
            ),
          ),
          Positioned(
            bottom: -8,
            right: 0,
            width: 8,
            height: 8,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConcaveFilletPainter(isTop: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja las esquinas cóncavas blancas de 8px de la pestaña activa contra la barra negra.
class _ConcaveFilletPainter extends CustomPainter {
  _ConcaveFilletPainter({required this.isTop});

  final bool isTop;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width;
    final Paint paint = Paint()
      ..color = AppTheme.surface
      ..style = PaintingStyle.fill;

    final Path path = Path();
    if (isTop) {
      path
        ..moveTo(r, 0)
        ..lineTo(r, r)
        ..lineTo(0, r)
        ..arcToPoint(
          Offset(r, 0),
          radius: Radius.circular(r),
          clockwise: false,
        )
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(r, 0)
        ..lineTo(r, r)
        ..arcToPoint(
          Offset.zero,
          radius: Radius.circular(r),
          clockwise: false,
        )
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
        color: Colors.white.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.sourceSerif4(
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
                  : Colors.white.withValues(alpha: 0.65),
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
    return Text(
      formatted,
      style: AppTheme.monoStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
