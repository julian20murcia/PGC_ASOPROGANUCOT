import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
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
  });

  final AdminSection section;
  final String label;
  final IconData icon;
  final String group;
  final bool adminOnly;
  final String description;
  final List<String> rfTags;
}

/// Shell administrativo de escritorio/planta con identidad propia Agro-Holstein
/// inspirada en el marco Houston (barra lateral colapsable sobre gutter + pantalla flotante).
class AdminShellView extends StatefulWidget {
  const AdminShellView({super.key});

  @override
  State<AdminShellView> createState() => _AdminShellViewState();
}

class _AdminShellViewState extends State<AdminShellView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AdminSection _activeSection;
  final List<AdminSection> _recentSections = <AdminSection>[];
  bool _sidebarPinned = true;
  bool _sidebarHovered = false;
  bool _logoutHovered = false;

  static const List<_NavItemMeta> _allNavItems = <_NavItemMeta>[
    _NavItemMeta(
      section: AdminSection.dashboard,
      label: 'Inicio',
      icon: Icons.home_outlined,
      group: 'Principal',
      adminOnly: false,
      description:
          'Indicadores en tiempo real de litros acopiados por jornada (mañana/tarde), acumulado quincenal y estado de sincronización.',
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
          'Cálculo quincenal exacto, emisión de comprobantes PDF (Ley 527/1999), registro de pagos y alertas push.',
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

  void _selectSection(AdminSection section) {
    if (_activeSection == section) return;
    setState(() {
      if (_activeSection != AdminSection.dashboard) {
        _recentSections.remove(_activeSection);
        _recentSections.insert(0, _activeSection);
        if (_recentSections.length > 3) {
          _recentSections.removeLast();
        }
      }
      _activeSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserController userCtrl = context.watch<UserController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();
    final List<_NavItemMeta> items = _visibleItemsFor(user);
    final bool isDesktop = MediaQuery.of(context).size.width >= 960;
    final bool isExpanded = _sidebarPinned || _sidebarHovered;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.canvas,
      drawer: isDesktop
          ? null
          : Drawer(
              backgroundColor: AppTheme.canvas,
              child: SafeArea(
                child: _buildHolsteinSidebar(
                  user: user,
                  items: items,
                  expanded: true,
                  isOnline: userCtrl.isOnline,
                  isDrawer: true,
                  onSelectSection: (AdminSection section) {
                    _selectSection(section);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: <Widget>[
            if (isDesktop)
              MouseRegion(
                onEnter: (_) => setState(() => _sidebarHovered = true),
                onExit: (_) => setState(() => _sidebarHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOutCubic,
                  width: isExpanded ? 258 : 70,
                  child: _buildHolsteinSidebar(
                    user: user,
                    items: items,
                    expanded: isExpanded,
                    isOnline: userCtrl.isOnline,
                    isDrawer: false,
                    onSelectSection: _selectSection,
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isDesktop ? 0 : 8, 6, 8, 8),
                child: Column(
                  children: <Widget>[
                    _buildHoustonTopBar(
                      user: user,
                      isDesktop: isDesktop,
                      isOnline: userCtrl.isOnline,
                      isExpanded: isExpanded,
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppTheme.cowBlack.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder:
                              (Widget child, Animation<double> anim) {
                            return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.012),
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
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHolsteinSidebar({
    required UserModel user,
    required List<_NavItemMeta> items,
    required bool expanded,
    required bool isOnline,
    required bool isDrawer,
    required ValueChanged<AdminSection> onSelectSection,
  }) {
    final _NavItemMeta? homeItem = items.cast<_NavItemMeta?>().firstWhere(
          (_NavItemMeta? i) => i?.section == AdminSection.dashboard,
          orElse: () => null,
        );
    final List<String> groups = <String>[
      'Operación en planta',
      'Finanzas y control',
      'Administración',
    ];

    return Column(
      children: <Widget>[
        // Cabecera propia ASOPROGANUCOT con detalle sutil Holstein
        Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 0,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: expanded ? AppTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: expanded ? Border.all(color: AppTheme.border) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: expanded
                ? const CowSpotPatternPainter(spotColor: Color(0x0B14161D))
                : null,
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppTheme.cowBlack, width: 1.3),
                  ),
                  child: const AsoproganucotLogo(size: 30, compact: true),
                ),
                if (expanded) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          AppConstants.appName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.cowBlack,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Row(
                          children: <Widget>[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? AppTheme.success
                                    : AppTheme.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Flexible(
                              child: Text(
                                'Planta Susa · v1.0',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!isDrawer)
                    IconButton(
                      tooltip: _sidebarPinned
                          ? 'Colapsar barra fija'
                          : 'Fijar barra lateral',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _sidebarPinned = !_sidebarPinned),
                      icon: Icon(
                        _sidebarPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 15,
                        color: _sidebarPinned
                            ? AppTheme.cowBlack
                            : AppTheme.textMuted,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        // Navegación principal
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: <Widget>[
              if (homeItem != null) ...<Widget>[
                _SidebarItemTile(
                  item: homeItem,
                  selected: _activeSection == homeItem.section,
                  expanded: expanded,
                  onTap: () => onSelectSection(homeItem.section),
                ),
                const SizedBox(height: 8),
              ],

              // Recientes (inspirado en AdminSidebar.jsx)
              if (expanded && _recentSections.isNotEmpty) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 6, 10, 4),
                  child: Text(
                    'Recientes',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                for (final AdminSection recentSec in _recentSections)
                  if (items.any((_NavItemMeta i) => i.section == recentSec))
                    _SidebarItemTile(
                      item: _metaFor(recentSec),
                      selected: _activeSection == recentSec,
                      expanded: expanded,
                      isSubtleRecent: true,
                      onTap: () => onSelectSection(recentSec),
                    ),
                const SizedBox(height: 6),
              ],

              // Grupos de módulos
              for (final String group in groups) ...<Widget>[
                if (items.any((_NavItemMeta i) => i.group == group)) ...<Widget>[
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                      child: Text(
                        group,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Divider(height: 1),
                    ),
                  for (final _NavItemMeta item
                      in items.where((_NavItemMeta i) => i.group == group))
                    _SidebarItemTile(
                      item: item,
                      selected: _activeSection == item.section,
                      expanded: expanded,
                      onTap: () => onSelectSection(item.section),
                    ),
                ],
              ],
            ],
          ),
        ),

        // Pie de barra con identidad del usuario activo y botón Cerrar sesión
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Column(
            children: <Widget>[
              if (expanded)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppTheme.cowBlack,
                        child: Text(
                          user.initials,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user.nombreCompleto,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              AppConstants.roleShortLabel(user.rol),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              MouseRegion(
                onEnter: (_) => setState(() => _logoutHovered = true),
                onExit: (_) => setState(() => _logoutHovered = false),
                child: InkWell(
                  onTap: () => context.read<AuthController>().signOut(),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: expanded ? 10 : 0),
                    decoration: BoxDecoration(
                      color: _logoutHovered
                          ? AppTheme.dangerBg
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: expanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: _logoutHovered
                              ? AppTheme.dangerText
                              : AppTheme.textSecondary,
                        ),
                        if (expanded) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cerrar sesión',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: _logoutHovered
                                    ? AppTheme.dangerText
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHoustonTopBar({
    required UserModel user,
    required bool isDesktop,
    required bool isOnline,
    required bool isExpanded,
  }) {
    final _NavItemMeta current = _metaFor(_activeSection);

    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: isDesktop
                  ? (_sidebarPinned ? 'Contraer menú' : 'Fijar menú')
                  : 'Abrir menú',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (isDesktop) {
                  setState(() => _sidebarPinned = !_sidebarPinned);
                } else {
                  _scaffoldKey.currentState?.openDrawer();
                }
              },
              icon: Icon(
                isDesktop
                    ? (isExpanded
                        ? Icons.view_sidebar_outlined
                        : Icons.menu_rounded)
                    : Icons.menu_rounded,
                size: 20,
                color: AppTheme.cowBlack,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                children: <Widget>[
                  if (isDesktop) ...<Widget>[
                    const Flexible(
                      child: Text(
                        AppConstants.appName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
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
                  Expanded(
                    child: Text(
                      current.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SyncStatusBadge(
              isSynced: isOnline,
              syncedLabel: 'En línea · Cloud',
              pendingLabel: 'Offline · Hive',
            ),
            if (isDesktop) ...<Widget>[
              const SizedBox(width: 10),
              Tooltip(
                message: '${user.nombreCompleto} (${user.correo})',
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: AppTheme.cowBlack,
                  child: Text(
                    user.initials,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSectionBody(UserModel user) {
    if (_activeSection == AdminSection.usuarios && user.isAdmin) {
      return const UsersModuleView();
    }

    final _NavItemMeta meta = _metaFor(_activeSection);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.canvasAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.cowBlack,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(meta.icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(meta.label, style: AppTheme.subtitleStyle()),
                          const SizedBox(height: 2),
                          const Text(
                            'Siguiente módulo en la hoja de ruta',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                        (String tag) => HeaderPropertyChip(
                          label: tag,
                          value: '',
                        ),
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
      ),
    );
  }
}

class _SidebarItemTile extends StatefulWidget {
  const _SidebarItemTile({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
    this.isSubtleRecent = false,
  });

  final _NavItemMeta item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final bool isSubtleRecent;

  @override
  State<_SidebarItemTile> createState() => _SidebarItemTileState();
}

class _SidebarItemTileState extends State<_SidebarItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool selected = widget.selected;
    final Color bg = selected
        ? AppTheme.cowBlack
        : _hovered
            ? AppTheme.cowBlack.withValues(alpha: 0.06)
            : Colors.transparent;
    final Color fg = selected
        ? Colors.white
        : _hovered
            ? AppTheme.cowBlack
            : (widget.isSubtleRecent
                ? AppTheme.textSecondary
                : AppTheme.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Tooltip(
        message: widget.expanded ? '' : widget.item.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 36,
              padding: EdgeInsets.symmetric(
                horizontal: widget.expanded ? 10 : 0,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    widget.item.icon,
                    size: 18,
                    color: selected ? Colors.white : fg.withValues(alpha: 0.85),
                  ),
                  if (widget.expanded) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
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
  }
}
