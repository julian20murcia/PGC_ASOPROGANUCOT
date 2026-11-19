import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_portal_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import 'producer/deliveries_tab.dart';
import 'producer/home_tab.dart';
import 'producer/mobile_kit.dart';
import 'producer/notices_tab.dart';
import 'producer/producer_tour.dart';
import 'producer/profile_tab.dart';
import 'producer/settlements_tab.dart';

/// Portal móvil de solo lectura para Productores / Ganaderos en campo
/// (`RF-19` a `RF-24`, `RNF-02`, `RNF-05`, `HU-10` a `HU-14`).
///
/// Pestañas: Inicio, Mis entregas, (Perfil al centro), Liquidaciones, Avisos.
class ProducerShellView extends StatefulWidget {
  const ProducerShellView({super.key});

  /// Índices de pestaña.
  static const int tabHome = 0;
  static const int tabDeliveries = 1;
  static const int tabSettlements = 2;
  static const int tabNotices = 3;
  static const int tabProfile = 4;

  @override
  State<ProducerShellView> createState() => _ProducerShellViewState();
}

class _ProducerShellViewState extends State<ProducerShellView> {
  int _tab = ProducerShellView.tabHome;
  final ProducerTourKeys _tourKeys = ProducerTourKeys();
  ProducerPortalController? _fallbackCtrl;
  String? _loadedForUid;
  String? _tourCheckedForUid;
  TutorialCoachMark? _tour;

  ProducerPortalController _resolvePortalController(BuildContext context) {
    try {
      return context.watch<ProducerPortalController>();
    } on ProviderNotFoundException {
      return _fallbackCtrl ??= ProducerPortalController.createDefault(enablePersistence: false);
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

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  Future<void> _refresh(ProducerPortalController portal) async {
    final UserModel? user = context.read<AuthController>().currentUser;
    if (user != null) await portal.loadPortalForUser(user);
  }

  /// Lanza el recorrido de bienvenida solo la primera vez por usuario.
  void _maybeStartTour(ProducerPortalController portal, UserModel user) {
    if (_tourCheckedForUid == user.uid) return;
    if (!portal.hasLoaded || portal.isLoading || !portal.isPortalLoadedForCurrentUser) return;
    _tourCheckedForUid = user.uid;
    portal.preferences.isTourDone(user.uid).then((bool done) {
      if (!mounted || done) return;
      _startTour(portal, user.uid);
    });
  }

  void _startTour(ProducerPortalController portal, String uid) {
    if (_tour?.isShowing ?? false) return;
    setState(() => _tab = ProducerShellView.tabHome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Se marca como visto al mostrarse: nunca vuelve a aparecer solo.
      portal.preferences.setTourDone(uid, true);
      final TutorialCoachMark tour = buildProducerTour(keys: _tourKeys, onDone: () {});
      _tour = tour;
      if (tour.targets.isNotEmpty) tour.show(context: context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();
    final ProducerPortalController portal = _resolvePortalController(context);
    _maybeStartTour(portal, user);

    final String name = portal.activeProducer?.nombreCompleto ?? user.nombreCompleto;
    Future<void> refresh() => _refresh(portal);
    void openSettlement(SettlementModel s) => openSettlementDetail(context, portal, s);

    final List<Widget> pages = <Widget>[
      HomeTab(
        portal: portal,
        user: user,
        tourKeys: _tourKeys,
        onOpenTab: _setTab,
        onOpenProfile: () => _setTab(ProducerShellView.tabProfile),
        onOpenSettlement: openSettlement,
        onRefresh: refresh,
      ),
      DeliveriesTab(portal: portal, onRefresh: refresh),
      SettlementsTab(portal: portal, onRefresh: refresh),
      NoticesTab(portal: portal, onRefresh: refresh),
      ProfileTab(
        portal: portal,
        user: user,
        onReplayTour: () => _startTour(portal, user.uid),
        onSignOut: () => context.read<AuthController>().signOut(),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _tab == ProducerShellView.tabHome,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _setTab(ProducerShellView.tabHome);
        },
        child: Scaffold(
          backgroundColor: AppTheme.canvas,
          body: IndexedStack(
            index: _tab,
            children: <Widget>[
              for (int i = 0; i < pages.length; i++)
                TickerMode(enabled: i == _tab, child: pages[i]),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: _ProfileFab(
            key: _tourKeys.profile,
            initials: initialsOf(name),
            active: _tab == ProducerShellView.tabProfile,
            onTap: () => _setTab(ProducerShellView.tabProfile),
          ),
          bottomNavigationBar: AnimatedBottomNavigationBar.builder(
            itemCount: 4,
            activeIndex: _tab < 4 ? _tab : -1,
            gapLocation: GapLocation.center,
            notchSmoothness: NotchSmoothness.softEdge,
            notchMargin: 6,
            leftCornerRadius: 26,
            rightCornerRadius: 26,
            height: 66,
            backgroundColor: AppTheme.surface,
            splashColor: AppTheme.brandSoft,
            splashSpeedInMilliseconds: 280,
            elevation: 0,
            scaleFactor: 0.12,
            shadow: const Shadow(color: Color(0x1F0B3B37), blurRadius: 20),
            onTap: _setTab,
            tabBuilder: (int i, bool active) => KeyedSubtree(
              key: _tourKeys.navKeys[i],
              child: _NavItem(
                spec: _navSpecs[i],
                active: active,
                badge: i == ProducerShellView.tabNotices ? portal.unreadNotificationsCount : 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSpec {
  const _NavSpec(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const List<_NavSpec> _navSpecs = <_NavSpec>[
  _NavSpec('Inicio', Icons.home_outlined, Icons.home_rounded),
  _NavSpec('Mis entregas', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _NavSpec('Liquidaciones', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _NavSpec('Avisos', Icons.notifications_none_rounded, Icons.notifications_rounded),
];

class _NavItem extends StatelessWidget {
  const _NavItem({required this.spec, required this.active, required this.badge});

  final _NavSpec spec;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppTheme.brand : AppTheme.textMuted;
    return Semantics(
      selected: active,
      button: true,
      label: spec.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: active ? 48 : 34,
                  height: 28,
                  decoration: BoxDecoration(
                    color: active ? AppTheme.brandSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Icon(active ? spec.activeIcon : spec.icon, size: 22, color: color),
                ),
                if (badge > 0)
                  Positioned(
                    top: -5,
                    right: -6,
                    child: CountBadge(key: const ValueKey<String>('nav-notices-badge'), count: badge),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 16,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  spec.label,
                  maxLines: 1,
                  style: MobileTokens.body(size: 12, color: color, weight: active ? FontWeight.w700 : FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileFab extends StatelessWidget {
  const _ProfileFab({super.key, required this.initials, required this.active, required this.onTap});

  final String initials;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mi perfil',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[AppTheme.accent, AppTheme.accentDeep],
                  )
                : MobileTokens.headerGradient,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: (active ? AppTheme.accent : AppTheme.brand).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: active ? 1.08 : 1,
            duration: const Duration(milliseconds: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  initials,
                  style: MobileTokens.body(size: 17, color: Colors.white, weight: FontWeight.w800),
                ),
                Text(
                  'Perfil',
                  style: MobileTokens.body(size: 10.5, color: Colors.white.withValues(alpha: 0.85), weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
