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

  static String topicForProducer(String productorId) {
    final String safe = productorId
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_');
    return 'productor_$safe';
  }

  Future<String?> fetchDeviceTokenIfSupported() async {
    if (!isSupportedPlatform) {
      return null;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final Future<String> tokenFuture = messaging.onRegistered.first;
      await messaging.register();
      return await tokenFuture.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  /// Suscribe al productor a comunicados institucionales y alertas de su código
  /// escuchando mensajes FCM entrantes en primer plano (`RF-23`, `CHK-05`).
  Future<void> initializeForProducer({
    required String userUid,
    String? productorId,
    void Function(AppNotificationModel notification)? onNotification,
  }) async {
    if (!isSupportedPlatform) {
      return;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      await messaging.subscribeToTopic(broadcastTopic);
      if (productorId != null && productorId.trim().isNotEmpty) {
        await messaging.subscribeToTopic(topicForProducer(productorId));
      }
      if (userUid.trim().isNotEmpty) {
        await messaging.subscribeToTopic(topicForProducer(userUid));
      }

      await _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final AppNotificationModel? parsed = parseRemoteMessageData(
          msg.data,
          title: msg.notification?.title,
          body: msg.notification?.body,
        );
        if (parsed != null) {
          _foregroundController.add(parsed);
          onNotification?.call(parsed);
        }
      });

      await _onOpenedAppSub?.cancel();
      _onOpenedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
        final AppNotificationModel? parsed = parseRemoteMessageData(
          msg.data,
          title: msg.notification?.title,
          body: msg.notification?.body,
        );
        if (parsed != null) {
          _foregroundController.add(parsed);
          onNotification?.call(parsed);
        }
      });
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
