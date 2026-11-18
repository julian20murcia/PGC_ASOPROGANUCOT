import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Servicio encapsulado de Firebase Cloud Messaging (FCM).
/// Cumple la regla de validación estricta por plataforma para evitar fallos en Windows Desktop.
class FcmService {
  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<String?> fetchDeviceTokenIfSupported() async {
    if (!isSupportedPlatform) {
      return null;
    }
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }
}
