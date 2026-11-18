import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/design_system_widgets.dart';

/// Portal móvil exclusivo de solo lectura para Productores / Ganaderos (adaptive-ux).
class ProducerShellView extends StatefulWidget {
  const ProducerShellView({super.key});

  @override
  State<ProducerShellView> createState() => _ProducerShellViewState();
}

class _ProducerShellViewState extends State<ProducerShellView> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final UserModel user = auth.currentUser ?? UserModel.bootstrapAdmin();

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: AppTheme.border)),
        title: Row(
          children: <Widget>[
            const AsoproganucotLogo(size: 32, compact: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    user.nombreCompleto,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: auth.signOut,
            icon: const Icon(
              Icons.logout_rounded,
              color: AppTheme.dangerText,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: <Widget>[
            _ProducerTabCard(
              title: 'Resumen de Producción',
              subtitle:
                  'Consulta en tiempo real de tus litros acumulados en la quincena y estimado proyectado.',
              icon: Icons.bar_chart_rounded,
              user: user,
              rfLabel: 'RF-19 · RF-20',
            ),
            _ProducerTabCard(
              title: 'Mis Entregas Diarias',
              subtitle:
                  'Historial cronológico de entregas de mañana y tarde registradas en la planta de Susa.',
              icon: Icons.water_drop_outlined,
              user: user,
              rfLabel: 'RF-21 · Solo lectura',
            ),
            _ProducerTabCard(
              title: 'Liquidaciones y Avisos',
              subtitle:
                  'Comprobantes de liquidación quincenal, estado de pago y bandeja de notificaciones push.',
              icon: Icons.receipt_long_outlined,
              user: user,
              rfLabel: 'RF-22 · RF-23 · RF-24',
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        indicatorColor: AppTheme.cowBlack,
        selectedIndex: _tabIndex,
        onDestinationSelected: (int index) =>
            setState(() => _tabIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: Colors.white),
            label: 'Resumen',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop_rounded, color: Colors.white),
            label: 'Mis Entregas',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded, color: Colors.white),
            label: 'Liquidaciones',
          ),
        ],
      ),
    );
  }
}

class _ProducerTabCard extends StatelessWidget {
  const _ProducerTabCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.user,
    required this.rfLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final UserModel user;
  final String rfLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.cowBlack,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: AppTheme.subtitleStyle()),
                        Text(
                          rfLabel,
                          style: AppTheme.monoStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Sesión verificada: ${user.correo}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Documento: ${user.documento} · Rol: ${AppConstants.roleLabel(user.rol)}',
                style: AppTheme.monoStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
