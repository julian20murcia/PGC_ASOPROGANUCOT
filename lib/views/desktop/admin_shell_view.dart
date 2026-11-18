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

/// Shell administrativo de escritorio/planta con menú lateral estilo Holstein.
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
      label: 'Inicio / Panel',
      icon: Icons.dashboard_outlined,
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
      group: 'Operación diaria',
      adminOnly: false,
      description:
          'Captura rápida 100% teclado en planta (Mañana / Tarde) con persistencia offline-first en Hive y alerta de duplicados.',
      rfTags: <String>['RF-08', 'RF-09', 'RF-10', 'RF-11'],
    ),
    _NavItemMeta(
      section: AdminSection.productores,
      label: 'Productores',
      icon: Icons.agriculture_outlined,
      group: 'Operación diaria',
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
    // Al entrar sin credenciales en Modo Configuración Inicial, abrir directo Usuarios.
    if (auth.isBootstrapSession) {
      _activeSection = AdminSection.usuarios;
    } else if (auth.currentUser?.isAdmin == true) {
      _activeSection = AdminSection.usuarios;
    } else {
      _activeSection = AdminSection.recepcion;
    }

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

  _NavItemMeta get _currentMeta {
    return _allNavItems.firstWhere(
      (_NavItemMeta m) => m.section == _activeSection,
      orElse: () => _allNavItems.last,
    );
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
              backgroundColor: AppTheme.canvas,
              child: SafeArea(
                child: _buildSidebarContent(
                  user: user,
                  items: items,
                  expanded: true,
                  onSelectSection: (AdminSection section) {
                    setState(() => _activeSection = section);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: <Widget>[
            if (isDesktop)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _sidebarExpanded ? 248 : 76,
                child: _buildSidebarContent(
                  user: user,
                  items: items,
                  expanded: _sidebarExpanded,
                  onSelectSection: (AdminSection section) {
                    setState(() => _activeSection = section);
                  },
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isDesktop ? 0 : 8,
                  8,
                  8,
                  8,
                ),
                child: Column(
                  children: <Widget>[
                    _buildTopBar(
                      user: user,
                      isDesktop: isDesktop,
                      isOnline: userCtrl.isOnline,
                      isBootstrap: auth.isBootstrapSession,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusCard),
                          border: Border.all(color: AppTheme.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildActiveSectionBody(user),
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

  Widget _buildSidebarContent({
    required UserModel user,
    required List<_NavItemMeta> items,
    required bool expanded,
    required ValueChanged<AdminSection> onSelectSection,
  }) {
    final List<String> groupOrder = <String>[
      'Principal',
      'Operación diaria',
      'Finanzas y control',
      'Administración',
    ];

    return CustomPaint(
      painter: const CowSpotPatternPainter(spotColor: Color(0x0714161D)),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: <Widget>[
                const AsoproganucotLogo(size: 36, compact: true),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.cowBlack,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Text(
                          'Planta Susa · Admin',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: <Widget>[
                for (final String groupName in groupOrder) ...<Widget>[
                  if (items.any((_NavItemMeta i) => i.group == groupName)) ...<Widget>[
                    if (expanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                        child: Text(
                          groupName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1),
                      ),
                    for (final _NavItemMeta item
                        in items.where((_NavItemMeta i) => i.group == groupName))
                      _SidebarNavButton(
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
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: <Widget>[
                const Divider(),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => context.read<AuthController>().signOut(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 42,
                    padding: EdgeInsets.symmetric(
                      horizontal: expanded ? 12 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: expanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: AppTheme.dangerText,
                        ),
                        if (expanded) ...<Widget>[
                          const SizedBox(width: 10),
                          const Text(
                            'Cerrar sesión',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.dangerText,
                            ),
                          ),
                        ],
                      ],
                    ),
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
    required UserModel user,
    required bool isDesktop,
    required bool isOnline,
    required bool isBootstrap,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: isDesktop ? 'Contraer / expandir menú' : 'Abrir menú',
            onPressed: () {
              if (isDesktop) {
                setState(() => _sidebarExpanded = !_sidebarExpanded);
              } else {
                _scaffoldKey.currentState?.openDrawer();
              }
            },
            icon: Icon(
              isDesktop
                  ? (_sidebarExpanded
                      ? Icons.menu_open_rounded
                      : Icons.menu_rounded)
                  : Icons.menu_rounded,
              color: AppTheme.cowBlack,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: <Widget>[
                if (isDesktop) ...<Widget>[
                  const Text(
                    'Planta Susa',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
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
                Flexible(
                  child: Text(
                    _currentMeta.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isBootstrap && isDesktop) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.warningBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.35),
                ),
              ),
              child: const Text(
                'Configuración inicial (sin login)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warningText,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          SyncStatusBadge(
            isSynced: isOnline,
            syncedLabel: 'En línea',
            pendingLabel: 'Sin red (Hive)',
          ),
          if (isDesktop) ...<Widget>[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.canvasAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.cowBlack,
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user.nombreCompleto,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        AppConstants.roleShortLabel(user.rol),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textSecondary,
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
    );
  }

  Widget _buildActiveSectionBody(UserModel user) {
    if (_activeSection == AdminSection.usuarios && user.isAdmin) {
      return const UsersModuleView();
    }

    final _NavItemMeta meta = _currentMeta;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.canvasAlt,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
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
                            'Módulo preparado en el menú administrativo',
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
                        (String tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Text(
                            tag,
                            style: AppTheme.monoStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (user.isAdmin) ...<Widget>[
                  const SizedBox(height: 22),
                  PrimaryActionButton(
                    label: 'Ir al módulo Usuarios',
                    icon: Icons.manage_accounts_outlined,
                    fullWidth: false,
                    onPressed: () {
                      setState(() => _activeSection = AdminSection.usuarios);
                    },
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

class _SidebarNavButton extends StatelessWidget {
  const _SidebarNavButton({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final _NavItemMeta item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: expanded ? '' : item.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
            decoration: BoxDecoration(
              // Botón activo en negro vaca Holstein sobre diseño claro
              color: selected ? AppTheme.cowBlack : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  item.icon,
                  size: 19,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                ),
                if (expanded) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? Colors.white : AppTheme.textPrimary,
                      ),
                    ),
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
