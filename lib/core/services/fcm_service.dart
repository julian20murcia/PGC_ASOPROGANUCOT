import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../models/app_notification_model.dart';

/// Servicio encapsulado de Firebase Cloud Messaging (FCM).
/// Cumple la regla de validación estricta por plataforma para evitar fallos en Windows Desktop.
class FcmService {
  FcmService();

  static const String broadcastTopic = 'asoproganucott_comunicados';

  final StreamController<AppNotificationModel> _foregroundController =
      StreamController<AppNotificationModel>.broadcast();

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedAppSub;

  Stream<AppNotificationModel> get foregroundNotifications =>
      _foregroundController.stream;

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<String?> fetchDeviceTokenIfSupported() async {
    if (!isSupportedPlatform) {
      return null;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = messaging.onRegistered.first.timeout(const Duration(seconds: 4));
      await messaging.register();
      return await token;
    } catch (_) {
      return null;
    }
  }

  /// Los avisos dirigidos se consultan mediante una sesión autenticada.
  Future<void> initializeForProducer({
    void Function(AppNotificationModel notification)? onNotification,
    Future<void> Function()? onRefreshRequested,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      await messaging.subscribeToTopic(broadcastTopic);
      await _onMessageSub?.cancel();
      void handle(RemoteMessage msg) {
        if (msg.data['refrescarAvisos'] == 'true') {
          unawaited(onRefreshRequested?.call());
          return;
        }
        final AppNotificationModel? parsed = parseRemoteMessageData(
          msg.data,
          title: msg.notification?.title,
          body: msg.notification?.body,
        );
        if (parsed != null) {
          _foregroundController.add(parsed);
          onNotification?.call(parsed);
        }
      }
      _onMessageSub = FirebaseMessaging.onMessage.listen(handle);
      await _onOpenedAppSub?.cancel();
      _onOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(handle);
    } catch (_) {
      // Fallo silencioso en emuladores o dispositivos sin Google Play Services.
    }
  }

  /// Convierte un payload de `RemoteMessage` en un [AppNotificationModel] local.
  static AppNotificationModel? parseRemoteMessageData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final String resolvedTitle =
        (title ?? data['titulo'] ?? '').toString().trim();
    final String resolvedBody =
        (body ?? data['mensaje'] ?? '').toString().trim();
    if (resolvedTitle.isEmpty && resolvedBody.isEmpty) {
      return null;
    }

    final String idRaw = (data['notificacionId'] ?? '').toString().trim();
    final String tipoRaw =
        (data['tipo'] ?? 'COMUNICADO').toString().trim().toUpperCase();
    final String destRaw =
        (data['destinoProductorId'] ?? '').toString().trim();
    final DateTime? parsedDate = DateTime.tryParse(
      (data['fechaEnvio'] ?? '').toString().trim(),
    );

    return AppNotificationModel(
      notificacionId: idRaw.isNotEmpty
          ? idRaw
          : 'fcm_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      titulo: resolvedTitle.isNotEmpty ? resolvedTitle : 'Aviso ASOPROGANUCOTT',
      mensaje: resolvedBody,
      tipo: tipoRaw.isEmpty ? 'COMUNICADO' : tipoRaw,
      destinoProductorId: destRaw.isEmpty ? null : destRaw,
      fechaEnvio: (parsedDate ?? DateTime.now()).toUtc(),
      leida: false,
    );
  }

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onOpenedAppSub?.cancel();
    await _foregroundController.close();
  }
}
