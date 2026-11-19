import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/app_notification_model.dart';

/// Servicio encapsulado de Firebase Cloud Messaging (FCM).
/// Cumple la regla de validación estricta por plataforma para evitar fallos en Windows Desktop.
class FcmService {
  FcmService();

  static const String broadcastTopic = 'asoproganucott_comunicados';
  static const MethodChannel _localAlertsChannel = MethodChannel(
    'com.example.pgc_asoproganucot/notifications',
  );

  final StreamController<AppNotificationModel> _foregroundController =
      StreamController<AppNotificationModel>.broadcast();

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedAppSub;

  Stream<AppNotificationModel> get foregroundNotifications =>
      _foregroundController.stream;

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Stream<String> get onTokenRefresh {
    if (!isSupportedPlatform) {
      return const Stream<String>.empty();
    }
    try {
      return FirebaseMessaging.instance.onRegistered;
    } catch (_) {
      return const Stream<String>.empty();
    }
  }

  Future<String?> fetchDeviceTokenIfSupported() async {
    if (!isSupportedPlatform) {
      return null;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      try {
        final Future<String> tokenFuture = messaging.onRegistered.first.timeout(
          const Duration(seconds: 6),
        );
        await messaging.register();
        final String registeredToken = (await tokenFuture).trim();
        if (registeredToken.isNotEmpty) {
          return registeredToken;
        }
      } catch (_) {
        // Respaldo con getToken si onRegistered vence antes de emitir.
      }
      // ignore: deprecated_member_use
      final String? fallbackToken = await messaging.getToken();
      final String cleanFallback = (fallbackToken ?? '').trim();
      return cleanFallback.isEmpty ? null : cleanFallback;
    } catch (_) {
      return null;
    }
  }

  Future<void> showLocalAlertIfSupported({
    required String title,
    required String body,
    int? id,
  }) async {
    if (!isSupportedPlatform || kIsWeb || !Platform.isAndroid) {
      return;
    }
    if (title.trim().isEmpty && body.trim().isEmpty) {
      return;
    }
    try {
      await _localAlertsChannel.invokeMethod<void>(
        'showNotification',
        <String, dynamic>{
          'id': id ?? DateTime.now().millisecondsSinceEpoch.remainder(1000000),
          'title': title.trim().isEmpty ? 'ASOPROGANUCOTT' : title.trim(),
          'body': body.trim(),
        },
      );
    } catch (_) {
      // Sin canal nativo disponible (p. ej. entorno de pruebas).
    }
  }

  /// Al cerrar sesión: quita el token de la cuenta, se da de baja de los
  /// comunicados generales e invalida el token (el próximo inicio genera otro).
  Future<void> unregisterDevice({required Future<void> Function(String token) removeToken}) async {
    if (!isSupportedPlatform) return;
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      // ignore: deprecated_member_use
      final String? token = await messaging.getToken();
      if (token != null && token.isNotEmpty) await removeToken(token);
      await messaging.unsubscribeFromTopic(broadcastTopic);
      await messaging.unregister();
    } catch (_) {
      // Sin red o sin Play Services: no impedir el cierre de sesión.
    }
    await _onMessageSub?.cancel();
    _onMessageSub = null;
    await _onOpenedAppSub?.cancel();
    _onOpenedAppSub = null;
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
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (Platform.isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      await messaging.subscribeToTopic(broadcastTopic);
      await _onMessageSub?.cancel();

      void handle(RemoteMessage msg, {required bool isForeground}) {
        final AppNotificationModel? parsed = parseRemoteMessageData(
          msg.data,
          title: msg.notification?.title,
          body: msg.notification?.body,
        );
        if (parsed != null) {
          if (isForeground) {
            unawaited(
              showLocalAlertIfSupported(
                title: parsed.titulo,
                body: parsed.mensaje,
                id: parsed.notificacionId.hashCode & 0x7FFFFFFF,
              ),
            );
          }
          _foregroundController.add(parsed);
          onNotification?.call(parsed);
        }
        final String tipo =
            (parsed?.tipo ?? msg.data['tipo'] ?? '').toString().toUpperCase();
        final bool shouldRefresh =
            msg.data['refrescarAvisos'] == 'true' ||
            tipo == 'ENTREGA' ||
            tipo == 'CIERRE_QUINCENA' ||
            tipo == 'LIQUIDACION' ||
            tipo == 'PAGO';
        if (shouldRefresh) {
          unawaited(onRefreshRequested?.call());
        }
      }

      _onMessageSub = FirebaseMessaging.onMessage.listen(
        (RemoteMessage msg) => handle(msg, isForeground: true),
      );
      await _onOpenedAppSub?.cancel();
      _onOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage msg) => handle(msg, isForeground: false),
      );
      final RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        handle(initialMessage, isForeground: false);
      }
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
