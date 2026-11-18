import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/user_controller.dart';
import 'core/services/hive_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'models/user_model.dart';
import 'views/desktop/admin_shell_view.dart';
import 'views/mobile/producer_shell_view.dart';
import 'views/shared/login_view.dart';
import 'views/shared/widgets/dairy_loader.dart';
import 'views/shared/widgets/design_system_widgets.dart';

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

/// Enrutador principal con transición animada por estado de autenticación y rol RBAC (RF-02).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    late final Widget target;
    if (auth.isInitializing) {
      target = const Scaffold(
        key: ValueKey<String>('splash'),
        backgroundColor: AppTheme.canvas,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AsoproganucotLogo(size: 112),
              SizedBox(height: 22),
              DairyLoader(
                size: DairyLoaderSize.lg,
                label: 'Iniciando ASOPROGANUCOTT…',
                hint: 'Cargando configuración local y sesión segura.',
              ),
            ],
          ),
        ),
      );
    } else {
      final UserModel? user = auth.currentUser;
      if (user == null) {
        target = const LoginView(key: ValueKey<String>('login'));
      } else if (user.canAccessDesktopAdmin) {
        target = const AdminShellView(key: ValueKey<String>('admin_shell'));
      } else {
        target = const ProducerShellView(key: ValueKey<String>('producer_shell'));
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: target,
    );
  }
}
