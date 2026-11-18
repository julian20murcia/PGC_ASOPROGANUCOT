import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AsoproganucotApp());
}

class AsoproganucotApp extends StatelessWidget {
  const AsoproganucotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ASOPROGANUCOT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
      ),
      home: const FirebaseStatusScreen(),
    );
  }
}

class FirebaseStatusScreen extends StatelessWidget {
  const FirebaseStatusScreen({super.key});

  bool get _isMessagingSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final FirebaseApp app = Firebase.app();
    final FirebaseAuth auth = FirebaseAuth.instance;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final String messagingStatus = _isMessagingSupported
        ? 'Conectado (${FirebaseMessaging.instance.app.name})'
        : 'Configurado (disponible en Android, iOS, macOS y Web)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ASOPROGANUCOT'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.cloud_done_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Conexión Firebase activa',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(label: 'Project ID', value: app.options.projectId),
                    _InfoRow(label: 'App ID', value: app.options.appId),
                    const Divider(height: 24),
                    _InfoRow(
                      label: 'Firebase Core',
                      value: 'Inicializado (${app.name})',
                    ),
                    _InfoRow(
                      label: 'Firebase Auth',
                      value: 'Listo (${auth.app.name})',
                    ),
                    _InfoRow(
                      label: 'Cloud Firestore',
                      value: 'Listo (${firestore.app.name})',
                    ),
                    _InfoRow(
                      label: 'Cloud Messaging',
                      value: messagingStatus,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
}
