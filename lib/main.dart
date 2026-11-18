import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/producer_controller.dart';
import 'controllers/sync_controller.dart';
import 'controllers/user_controller.dart';
import 'core/services/hive_service.dart';
import 'core/services/producer_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'models/user_model.dart';
import 'views/desktop/admin_shell_view.dart';
import 'views/mobile/producer_shell_view.dart';
import 'views/shared/login_view.dart';
import 'views/shared/widgets/dairy_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final HiveService hiveService = HiveService();
  await hiveService.init();

  runApp(AsoproganucotApp(hiveService: hiveService));
}

class AsoproganucotApp extends StatelessWidget {
  const AsoproganucotApp({
    super.key,
    required this.hiveService,
  });

  final HiveService hiveService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<dynamic>>[
        ChangeNotifierProvider<AuthController>(
          create: (_) => AuthController(hiveService: hiveService)..initialize(),
        ),
        ChangeNotifierProvider<UserController>(
          create: (_) => UserController(),
        ),
        ChangeNotifierProvider<SyncController>(
          create: (_) => SyncController(hiveService: hiveService)..initialize(),
        ),
        ChangeNotifierProvider<ProducerController>(
          create: (_) => ProducerController(
            producerService: ProducerService(hiveService: hiveService),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'ASOPROGANUCOTT',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

/// Enrutador principal con telón institucional y disolución radial al autenticar.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  bool _showingReveal = false;
  bool _wasInitializing = false;
  String? _lastUserUid;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showingReveal = false);
        }
      });

    final AuthController initialAuth = context.read<AuthController>();
    _wasInitializing = initialAuth.isInitializing;
    _lastUserUid = initialAuth.currentUser?.uid;
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _triggerCurtainReveal() {
    _showingReveal = true;
    _revealController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final String? nextUid = auth.currentUser?.uid;

    // Disolver telón al terminar carga inicial o al iniciar sesión correctamente.
    if ((_wasInitializing && !auth.isInitializing) ||
        (_lastUserUid == null && nextUid != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showingReveal) {
          setState(_triggerCurtainReveal);
        }
      });
    }
    _wasInitializing = auth.isInitializing;
    _lastUserUid = nextUid;

    if (auth.isInitializing) {
      return const Scaffold(
        key: ValueKey<String>('splash'),
        backgroundColor: AppTheme.inkBlack,
        body: AsoproganucotCurtain(
          eyebrow: 'INICIALIZANDO · SUSA, CUNDINAMARCA',
          statusText: 'Cargando configuración local y sesión segura…',
        ),
      );
    }

    final UserModel? user = auth.currentUser;
    final Widget destination = user == null
        ? const LoginView(key: ValueKey<String>('login'))
        : user.canAccessDesktopAdmin
            ? const AdminShellView(key: ValueKey<String>('admin_shell'))
            : const ProducerShellView(key: ValueKey<String>('producer_shell'));

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: destination,
        ),
        if (_showingReveal)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _revealController,
                builder: (BuildContext context, _) {
                  return AsoproganucotCurtain(
                    eyebrow: 'ACCESO AUTORIZADO · ASOPROGANUCOTT',
                    statusText: user == null
                        ? 'Cerrando sesión…'
                        : 'Abriendo entorno operativo…',
                    revealProgress: _revealController.value,
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
