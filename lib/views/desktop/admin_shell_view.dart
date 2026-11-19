import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/design_system_widgets.dart';
import '../shared/widgets/pro_ui.dart';
import 'assistant_module_view.dart';
import 'communications_module_view.dart';
import 'dashboard_module_view.dart';
import 'producers_module_view.dart';
import 'rates_module_view.dart';
import 'reception_module_view.dart';
import 'rectifications/rectification_inbox_button.dart';
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
  comunicados,
  usuarios,
  asistente,
}

class _NavItem {
  const _NavItem(this.section, this.label, this.icon, this.activeIcon, this.permission, this.group, {this.shortcut});
  final AdminSection section;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String permission;
  final String group;
  final String? shortcut;
}

const List<_NavItem> _navItems = <_NavItem>[
  _NavItem(AdminSection.dashboard, 'Inicio', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded,
      Permissions.dashboard, 'Operación', shortcut: '1'),
  _NavItem(AdminSection.recepcion, 'Recepción de Leche', Icons.water_drop_outlined, Icons.water_drop_rounded,
      Permissions.recepcion, 'Operación', shortcut: '2'),
  _NavItem(AdminSection.productores, 'Productores', Icons.groups_outlined, Icons.groups_rounded,
      Permissions.productores, 'Operación', shortcut: '3'),
  _NavItem(AdminSection.liquidaciones, 'Liquidaciones', Icons.receipt_long_outlined, Icons.receipt_long_rounded,
      Permissions.liquidaciones, 'Operación', shortcut: '4'),
  _NavItem(AdminSection.tarifas, 'Tarifas por Litro', Icons.price_change_outlined, Icons.price_change_rounded,
      Permissions.tarifas, 'Gestión', shortcut: '5'),
  _NavItem(AdminSection.reportes, 'Reportes y Auditoría', Icons.insights_outlined, Icons.insights_rounded,
      Permissions.reportes, 'Gestión', shortcut: '6'),
  _NavItem(AdminSection.comunicados, 'Comunicados', Icons.campaign_outlined, Icons.campaign_rounded,
      Permissions.comunicados, 'Gestión', shortcut: '7'),
  _NavItem(AdminSection.usuarios, 'Usuarios', Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings_rounded, Permissions.usuarios, 'Gestión', shortcut: '8'),
  _NavItem(AdminSection.asistente, 'Asistente IA', Icons.auto_awesome_outlined, Icons.auto_awesome,
      Permissions.asistente, 'Inteligencia', shortcut: '9'),
];

/// Contenedor principal de la plataforma de escritorio (ADMIN / OPERARIO).
class AdminShellView extends StatefulWidget {
  const AdminShellView({super.key});

  @override
  State<AdminShellView> createState() => _AdminShellViewState();
}

class _AdminShellViewState extends State<AdminShellView> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  AdminSection? _active;

  /// Módulos ya abiertos: se conservan montados (estado, scroll y datos
  /// cargados) para que volver a ellos sea instantáneo y no recargue Firestore.
  final Set<AdminSection> _visited = <AdminSection>{};
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserController>().startConnectivityMonitor();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl + 1…9 cambia de módulo.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isControlPressed) return false;
    final String? ch = event.character;
    if (ch == null) return false;
    final UserModel? user = context.read<AuthController>().currentUser;
    if (user == null) return false;
    for (final _NavItem item in _visibleItems(user)) {
      if (item.shortcut == ch) {
        _select(item.section);
        return true;
      }
    }
    return false;
  }

  List<_NavItem> _visibleItems(UserModel user) =>
      _navItems.where((_NavItem i) => user.can(i.permission, PermAction.ver)).toList();

  void _select(AdminSection section) {
    if (_active == section) return;
    setState(() => _active = section);
  }

  void _navigateByKey(String key) {
    for (final _NavItem i in _navItems) {
      if (i.permission == key || i.section.name == key) {
        _select(i.section);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();
    final List<_NavItem> items = _visibleItems(user);
    final bool wide = MediaQuery.sizeOf(context).width >= 1000;

    if (items.isEmpty) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Tu cuenta no tiene módulos asignados',
          message: 'Pide al administrador que te asigne permisos.',
          action: OutlinedButton(onPressed: () => auth.signOut(), child: const Text('Cerrar sesión')),
        ),
      );
    }
    final AdminSection active = items.any((_NavItem i) => i.section == _active) ? _active! : items.first.section;
    final _NavItem activeItem = items.firstWhere((_NavItem i) => i.section == active);
    final Set<AdminSection> allowed = <AdminSection>{for (final _NavItem i in items) i.section};
    _visited
      ..removeWhere((AdminSection s) => !allowed.contains(s))
      ..add(active);

    final Widget sidebar = _Sidebar(
      items: items,
      active: active,
      expanded: wide ? _expanded : true,
      user: user,
      onSelect: (AdminSection s) {
        _select(s);
        if (!wide) Navigator.of(context).maybePop();
      },
      onToggle: wide ? () => setState(() => _expanded = !_expanded) : null,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.canvas,
      drawer: wide ? null : Drawer(width: 240, backgroundColor: AppTheme.brandInk, child: SafeArea(child: sidebar)),
      body: Row(
        children: <Widget>[
          if (wide)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: _expanded ? 228 : 64,
              child: sidebar,
            ),
          Expanded(
            child: Column(
              children: <Widget>[
                _TopBar(
                  title: activeItem.label,
                  group: activeItem.group,
                  icon: activeItem.activeIcon,
                  user: user,
                  showMenu: !wide,
                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onAssistant: items.any((_NavItem i) => i.section == AdminSection.asistente) &&
                          active != AdminSection.asistente
                      ? () => _select(AdminSection.asistente)
                      : null,
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      for (final AdminSection s in AdminSection.values)
                        if (_visited.contains(s))
                          // Oculto: no pinta, no anima y no recibe foco ni teclado.
                          Visibility(
                            key: ValueKey<AdminSection>(s),
                            visible: s == active,
                            maintainState: true,
                            child: _FadeInOnShow(visible: s == active, child: _body(s)),
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

  Widget _body(AdminSection section) {
    switch (section) {
      case AdminSection.dashboard:
        return DashboardModuleView(onNavigateSection: _navigateByKey);
      case AdminSection.recepcion:
        return const ReceptionModuleView();
      case AdminSection.productores:
        return const ProducersModuleView();
      case AdminSection.liquidaciones:
        return const SettlementsModuleView();
      case AdminSection.tarifas:
        return const RatesModuleView();
      case AdminSection.reportes:
        return const ReportsModuleView();
      case AdminSection.comunicados:
        return const CommunicationsModuleView();
      case AdminSection.usuarios:
        return const UsersModuleView();
      case AdminSection.asistente:
        return const AssistantModuleView();
    }
  }
}

/// Fundido breve cada vez que un módulo vuelve a mostrarse.
class _FadeInOnShow extends StatefulWidget {
  const _FadeInOnShow({required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  State<_FadeInOnShow> createState() => _FadeInOnShowState();
}

class _FadeInOnShowState extends State<_FadeInOnShow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 160), value: 0)..forward();
  late final Animation<double> _opacity = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(covariant _FadeInOnShow old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: widget.child,
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.active,
    required this.expanded,
    required this.user,
    required this.onSelect,
    required this.onToggle,
  });

  final List<_NavItem> items;
  final AdminSection active;
  final bool expanded;
  final UserModel user;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final List<String> groups = <String>[];
    for (final _NavItem i in items) {
      if (!groups.contains(i.group)) groups.add(i.group);
    }
    return Container(
      color: AppTheme.brandInk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 60,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const AsoproganucotLogo(size: 30),
                  ),
                  if (expanded) ...<Widget>[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppConstants.appName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Acopio lechero · Susa',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              children: <Widget>[
                for (final String g in groups) ...<Widget>[
                  if (expanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      child: Text(
                        g.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Colors.white38,
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, color: Color(0x14FFFFFF), indent: 8, endIndent: 8),
                    ),
                  for (final _NavItem i in items.where((_NavItem x) => x.group == g))
                    _NavTile(
                      item: i,
                      selected: i.section == active,
                      expanded: expanded,
                      onTap: () => onSelect(i.section),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          _SidebarUser(user: user, expanded: expanded),
          if (onToggle != null)
            InkWell(
              onTap: onToggle,
              child: SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: <Widget>[
                    if (expanded) const SizedBox(width: 20),
                    Icon(
                      expanded ? Icons.keyboard_double_arrow_left_rounded : Icons.keyboard_double_arrow_right_rounded,
                      size: 18,
                      color: Colors.white54,
                    ),
                    if (expanded) ...<Widget>[
                      const SizedBox(width: 10),
                      Text('Contraer menú', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.item, required this.selected, required this.expanded, required this.onTap});
  final _NavItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool sel = widget.selected;
    final Color fg = sel ? Colors.white : (_hover ? Colors.white : Colors.white70);
    final Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.expanded ? 10 : 0),
          decoration: BoxDecoration(
            color: sel
                ? AppTheme.brand
                : _hover
                    ? const Color(0x14FFFFFF)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: widget.expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: <Widget>[
              Icon(sel ? widget.item.activeIcon : widget.item.icon, size: 18, color: fg),
              if (widget.expanded) ...<Widget>[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (widget.item.section == AdminSection.asistente)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0x33FFFFFF) : AppTheme.accent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'IA',
                      style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.expanded
        ? tile
        : Tooltip(
            message: '${widget.item.label}${widget.item.shortcut != null ? '  (Ctrl+${widget.item.shortcut})' : ''}',
            preferBelow: false,
            child: tile,
          );
  }
}

class _SidebarUser extends StatelessWidget {
  const _SidebarUser({required this.user, required this.expanded});
  final UserModel user;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      offset: const Offset(8, -110),
      onSelected: (String v) async {
        if (v == 'logout') {
          final bool ok = await confirmAction(
            context,
            title: 'Cerrar sesión',
            message: '¿Deseas salir de la plataforma? Los registros pendientes de sincronizar se conservan en este equipo.',
            confirmLabel: 'Cerrar sesión',
          );
          if (ok && context.mounted) await context.read<AuthController>().signOut();
        }
      },
      itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(user.nombreCompleto, style: AppTheme.subtitleStyle()),
              Text(user.correo, style: AppTheme.bodyStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: <Widget>[
              Icon(Icons.logout_rounded, size: 18, color: AppTheme.danger),
              SizedBox(width: 10),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0, vertical: 12),
        child: Row(
          mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                user.initials,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.brandInk),
              ),
            ),
            if (expanded) ...<Widget>[
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      user.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    Text(
                      AppConstants.roleShortLabel(user.rol),
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white38),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.group,
    required this.icon,
    required this.user,
    required this.showMenu,
    required this.onMenu,
    required this.onAssistant,
  });

  final String title;
  final String group;
  final IconData icon;
  final UserModel user;
  final bool showMenu;
  final VoidCallback onMenu;
  final VoidCallback? onAssistant;

  @override
  Widget build(BuildContext context) {
    final UserController users = context.watch<UserController>();
    final SyncController sync = context.watch<SyncController>();
    final bool online = users.isOnline && sync.isOnline;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: <Widget>[
          if (showMenu)
            IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded), tooltip: 'Menú'),
          Text(group, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.textMuted),
          ),
          Icon(icon, size: 16, color: AppTheme.brand),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
          ),
          const Spacer(),
          if (sync.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Entregas guardadas en este equipo que aún no se envían a la nube',
                child: StatusBadge('${sync.pendingCount} por sincronizar', tone: Tone.warning, icon: Icons.cloud_upload_outlined),
              ),
            ),
          StatusBadge(
            online ? 'En línea' : 'Sin conexión',
            tone: online ? Tone.success : Tone.danger,
            dot: true,
          ),
          RectificationInboxButton(user: user),
          const SizedBox(width: 12),
          const _Clock(),
          if (onAssistant != null) ...<Widget>[
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: onAssistant,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandSoft,
                foregroundColor: AppTheme.brand,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Preguntar a la IA'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _t;
  DateTime _now = DateTime.now();

  static const List<String> _days = <String>['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const List<String> _months = <String>[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String hh = _now.hour.toString().padLeft(2, '0');
    final String mm = _now.minute.toString().padLeft(2, '0');
    return Text(
      '${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]} · $hh:$mm',
      style: AppTheme.monoStyle(fontSize: 12.5, color: AppTheme.textSecondary),
    );
  }
}
