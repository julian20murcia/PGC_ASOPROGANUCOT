import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/services/device_session_service.dart';
import '../core/services/fcm_service.dart';
import '../core/services/firebase_user_service.dart';
import '../core/services/hive_service.dart';
import '../models/user_model.dart';

/// Motivos por los que la plataforma cerró la sesión automáticamente.
class SessionEndReason {
  SessionEndReason._();
  static const String inactivity =
      'Tu sesión se cerró por inactividad (10 minutos sin uso). Ingresa de nuevo para continuar.';
  static const String otherDevice =
      'Tu cuenta se abrió en otro dispositivo, por eso cerramos la sesión en este.';
  static const String suspended =
      'Tu cuenta fue suspendida o modificada por un administrador.';
}

/// Controlador MVC de autenticación, control de roles (RBAC) y sesión persistente.
class AuthController extends ChangeNotifier {
  AuthController({
    FirebaseUserService? userService,
    HiveService? hiveService,
    FcmService? fcmService,
    DeviceSessionService? deviceSession,
  })  : _userService = userService ?? FirebaseUserService(),
        _hiveService = hiveService ?? HiveService(),
        _fcmService = fcmService ?? FcmService(),
        _deviceSession = deviceSession ?? DeviceSessionService();

  final FirebaseUserService _userService;
  final HiveService _hiveService;
  final FcmService _fcmService;
  final DeviceSessionService _deviceSession;

  StreamSubscription<String>? _tokenRefreshSub;

  UserModel? _currentUser;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  String _savedIdentifier = '';
  String? _errorMessage;
  String? _sessionEndedReason;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  bool get rememberMe => _rememberMe;

  /// Celular (Android/iOS): la sesión SIEMPRE se recuerda y solo se cierra si
  /// la cuenta se abre en otro teléfono (o el administrador la suspende).
  /// En el PC sigue la casilla "Recordar acceso" y el cierre por inactividad.
  static bool get persistentMobileSession =>
      debugPersistentMobileSession ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// Solo pruebas: fuerza el comportamiento de celular (true) o de PC (false).
  @visibleForTesting
  static bool? debugPersistentMobileSession;
  String get savedIdentifier => _savedIdentifier;
  String? get errorMessage => _errorMessage;

  /// Mensaje a mostrar en el login cuando la sesión se cerró automáticamente.
  String? get sessionEndedReason => _sessionEndedReason;

  void clearSessionEndedReason() {
    if (_sessionEndedReason != null) {
      _sessionEndedReason = null;
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
      await _hiveService.init();
      _rememberMe = persistentMobileSession || await _hiveService.getRememberMe();
      _savedIdentifier = await _hiveService.getLastIdentifier();

      final firebaseUser = _userService.currentFirebaseUser;
      if (firebaseUser != null && _rememberMe) {
        final UserModel? profile = await _userService.getUserProfileByUid(
          firebaseUser.uid,
        );
        if (profile != null && profile.activo) {
          if (await _deviceSession.isCurrent(profile.uid)) {
            _currentUser = profile;
            _watchDeviceSession(profile.uid);
            unawaited(_registerDeviceToken(profile.uid));
          } else {
            await _userService.signOut();
            _sessionEndedReason = SessionEndReason.otherDevice;
            _currentUser = null;
          }
        } else {
          await _userService.signOut();
          _currentUser = null;
        }
      } else if (firebaseUser != null && !_rememberMe) {
        await _userService.signOut();
        _currentUser = null;
      }
    } catch (_) {
      _currentUser = null;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Valida credenciales reales contra Firebase Auth + Cloud Firestore (`usuarios`).
  Future<bool> signIn({
    required String identifier,
    required String password,
    required bool rememberMe,
  }) async {
    _errorMessage = null;
    _sessionEndedReason = null;
    _rememberMe = persistentMobileSession || rememberMe;

    final String cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty) {
      _errorMessage = 'Ingresa tu correo electrónico o número de documento.';
      notifyListeners();
      return false;
    }

    if (password.isEmpty) {
      _errorMessage = 'Ingresa tu contraseña para continuar.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final UserModel signedUser = await _userService.signInWithIdentifier(
        identifier: cleanIdentifier,
        password: password,
      );

      // Sesión única en móviles: este dispositivo pasa a ser el vigente.
      try {
        await _deviceSession.claim(signedUser.uid);
      } catch (_) {
        await _userService.signOut();
        throw UserServiceException(
          'No se pudo asegurar la sesión en este dispositivo. Revisa tu conexión e intenta de nuevo.',
        );
      }

      _currentUser = signedUser;
      _savedIdentifier = cleanIdentifier;
      _watchDeviceSession(signedUser.uid);

      await _registerDeviceToken(signedUser.uid);

      await _hiveService.saveSessionState(
        rememberMe: _rememberMe,
        lastIdentifier: cleanIdentifier,
        bootstrapMode: false,
        cachedUser: signedUser,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } on UserServiceException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage =
          'No fue posible completar el inicio de sesión. Intenta nuevamente.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _registerDeviceToken(String uid) async {
    try {
      final String? token = await _fcmService.fetchDeviceTokenIfSupported();
      if (token != null && token.isNotEmpty) {
        if (persistentMobileSession) {
          // Sesión única en celular: solo este teléfono recibe los avisos de la
          // cuenta (el teléfono anterior deja de recibirlos).
          await _userService.replaceFcmTokens(uid: uid, token: token);
        } else {
          await _userService.appendFcmToken(uid: uid, token: token);
        }
      }
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _fcmService.onTokenRefresh.listen((String nextToken) {
        if (nextToken.isNotEmpty && _currentUser?.uid == uid) {
          unawaited(_userService.appendFcmToken(uid: uid, token: nextToken));
        }
      });
    } catch (_) {
      // No bloquear la sesión ni entornos de prueba si no hay canal push.
    }
  }

  void _watchDeviceSession(String uid) {
    _deviceSession.watch(uid, (bool suspended) {
      if (_currentUser?.uid == uid) {
        signOut(reason: suspended ? SessionEndReason.suspended : SessionEndReason.otherDevice);
      }
    });
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Cierra la sesión. [reason] se muestra luego en la pantalla de ingreso
  /// (por ejemplo, cierre por inactividad o por otro dispositivo).
  Future<void> signOut({String? reason}) async {
    if (_currentUser == null && reason != null) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _deviceSession.stop();
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      // Este teléfono deja de recibir avisos de la cuenta al cerrar sesión.
      final String? uid = _currentUser?.uid;
      if (uid != null) {
        try {
          await _fcmService
              .unregisterDevice(
                removeToken: (String token) => _userService.removeFcmToken(uid: uid, token: token),
              )
              .timeout(const Duration(seconds: 5), onTimeout: () {});
        } catch (_) {
          // Nunca impedir el cierre de sesión por el canal push.
        }
      }
      await _userService.signOut();
      await _hiveService.clearActiveSession(keepIdentifier: _rememberMe);
      _currentUser = null;
      _errorMessage = null;
      _sessionEndedReason = reason;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _deviceSession.stop();
    unawaited(_tokenRefreshSub?.cancel());
    super.dispose();
  }
}
