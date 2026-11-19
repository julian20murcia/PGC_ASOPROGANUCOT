import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';

/// Sesión única en dispositivos móviles.
///
/// Al iniciar sesión en un teléfono se genera un identificador de sesión que
/// se guarda localmente y en `usuarios/{uid}.sesionMovilId`. Cada teléfono
/// escucha su perfil: si otro dispositivo inicia sesión con la misma cuenta,
/// el identificador cambia y este dispositivo cierra la sesión.
class DeviceSessionService {
  DeviceSessionService({FirebaseFirestore? firestore}) : _db = firestore;

  final FirebaseFirestore? _db;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  static const Uuid _uuid = Uuid();

  /// Solo aplica en Android/iOS reales con Firebase inicializado.
  static bool get isEnabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      Firebase.apps.isNotEmpty;

  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  static String _key(String uid) => 'mobile_session_id_$uid';

  /// Reclama la sesión para este dispositivo (último en iniciar sesión gana).
  Future<void> claim(String uid) async {
    if (!isEnabled) return;
    final String id = _uuid.v4();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), id);
    await _firestore.collection(AppConstants.usersCollection).doc(uid).update(<String, dynamic>{
      'sesionMovilId': id,
      'sesionMovilAt': FieldValue.serverTimestamp(),
    });
  }

  /// Comprueba al reabrir la app si esta sigue siendo la sesión vigente.
  /// Devuelve false si otro dispositivo tomó la sesión.
  Future<bool> isCurrent(String uid) async {
    if (!isEnabled) return true;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? local = prefs.getString(_key(uid));
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final String? remote = snap.data()?['sesionMovilId'] as String?;
      if (local == null) {
        // Instalación previa a esta función: se reclama la sesión.
        await claim(uid);
        return true;
      }
      return remote == null || remote == local;
    } catch (_) {
      return true; // Sin conexión: se valida cuando vuelva la red.
    }
  }

  /// Escucha cambios del perfil; llama [onTakenOver] si otro dispositivo
  /// reclama la sesión.
  Future<void> watch(String uid, void Function(bool suspended) onTakenOver) async {
    if (!isEnabled) return;
    await stop();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _sub = _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
      final String? remote = snap.data()?['sesionMovilId'] as String?;
      final String? local = prefs.getString(_key(uid));
      if (snap.data()?['activo'] == false) {
        onTakenOver(true);
      } else if (remote != null && local != null && remote != local) {
        onTakenOver(false);
      }
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> forget(String uid) async {
    if (!isEnabled) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}
