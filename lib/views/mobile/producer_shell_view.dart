import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../shared/widgets/design_system_widgets.dart';

/// Portal móvil exclusivo de solo lectura para Productores / Ganaderos en campo.
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
    final double topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        children: <Widget>[
          ModernWaveHeader(
            height: 196 + topInset,
            padding: EdgeInsets.fromLTRB(20, topInset + 14, 20, 62),
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
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      onPressed: auth.signOut,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Hola, ${user.nombreCompleto}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'C.C. ${user.documento} · ${AppConstants.roleShortLabel(user.rol)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFD1FAE5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: <Widget>[
                _ProducerTabCard(
                  title: 'Resumen de Producción',
                  subtitle:
                      'Consulta en tiempo real de tus litros acumulados en la quincena y estimado proyectado.',
                  icon: Icons.bar_chart_rounded,
                  user: user,
                  tagLabel: 'Quincena actual',
                ),
                _ProducerTabCard(
                  title: 'Mis Entregas Diarias',
                  subtitle:
                      'Historial cronológico de entregas de mañana y tarde registradas en la planta de Susa.',
                  icon: Icons.water_drop_outlined,
                  user: user,
                  tagLabel: 'Historial de acopio',
                ),
                _ProducerTabCard(
                  title: 'Liquidaciones y Avisos',
                  subtitle:
                      'Comprobantes de liquidación quincenal, estado de pago y avisos de la asociación.',
                  icon: Icons.receipt_long_outlined,
                  user: user,
                  tagLabel: 'Pagos y comprobantes',
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
          indicatorColor: AppTheme.inkBlack,
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
              selectedIcon:
                  Icon(Icons.notifications_rounded, color: Colors.white),
              label: 'Liquidaciones',
            ),
          ],
        ),
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
    required this.tagLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final UserModel user;
  final String tagLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
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
                      color: AppTheme.primaryGreenLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: AppTheme.primaryGreen,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: AppTheme.subtitleStyle()),
                        Text(
                          tagLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen,
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
                'Cuenta activa: ${user.correo}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
