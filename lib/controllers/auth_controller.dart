import 'package:flutter/foundation.dart';

import '../core/services/fcm_service.dart';
import '../core/services/firebase_user_service.dart';
import '../core/services/hive_service.dart';
import '../models/user_model.dart';

/// Controlador MVC de autenticación, control de roles (RBAC) y sesión persistente.
class AuthController extends ChangeNotifier {
  AuthController({
    FirebaseUserService? userService,
    HiveService? hiveService,
    FcmService? fcmService,
  })  : _userService = userService ?? FirebaseUserService(),
        _hiveService = hiveService ?? HiveService(),
        _fcmService = fcmService ?? FcmService();

  final FirebaseUserService _userService;
  final HiveService _hiveService;
  final FcmService _fcmService;

  UserModel? _currentUser;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  String _savedIdentifier = '';
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  bool get rememberMe => _rememberMe;
  String get savedIdentifier => _savedIdentifier;
  String? get errorMessage => _errorMessage;
  bool get isBootstrapSession => _currentUser?.isBootstrapSession == true;

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
      await _hiveService.init();
      _rememberMe = await _hiveService.getRememberMe();
      _savedIdentifier = await _hiveService.getLastIdentifier();

      final firebaseUser = _userService.currentFirebaseUser;
      if (firebaseUser != null) {
        final UserModel? profile = await _userService.getUserProfileByUid(
          firebaseUser.uid,
          fallbackEmail: firebaseUser.email,
        );
        if (profile != null && profile.activo) {
          _currentUser = profile;
        } else {
          await _userService.signOut();
          _currentUser = null;
        }
      } else if (_rememberMe && await _hiveService.isBootstrapSessionSaved()) {
        _currentUser = UserModel.bootstrapAdmin();
      }
    } catch (_) {
      _currentUser = null;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Permite el ingreso directo sin escribir nada (Modo Configuración Inicial)
  /// o valida credenciales reales contra Firebase Auth + Firestore (`usuarios`).
  Future<bool> signIn({
    required String identifier,
    required String password,
    required bool rememberMe,
  }) async {
    _errorMessage = null;
    _rememberMe = rememberMe;

    final String cleanIdentifier = identifier.trim();
    final String cleanPassword = password.trim();

    // Acceso directo sin escribir credenciales para configurar usuarios iniciales.
    if (cleanIdentifier.isEmpty && cleanPassword.isEmpty) {
      final UserModel bootstrap = UserModel.bootstrapAdmin();
      _currentUser = bootstrap;
      await _hiveService.saveSessionState(
        rememberMe: rememberMe,
        lastIdentifier: _savedIdentifier,
        bootstrapMode: true,
        cachedUser: bootstrap,
      );
      notifyListeners();
      return true;
    }

    if (cleanIdentifier.isEmpty || cleanPassword.isEmpty) {
      _errorMessage =
          'Ingresa tu correo o documento y contraseña, o deja ambos campos vacíos para entrar al modo de configuración inicial.';
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
      _currentUser = signedUser;
      _savedIdentifier = cleanIdentifier;

      final String? token = await _fcmService.fetchDeviceTokenIfSupported();
      if (token != null && token.isNotEmpty) {
        await _userService.appendFcmToken(uid: signedUser.uid, token: token);
      }

      await _hiveService.saveSessionState(
        rememberMe: rememberMe,
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

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _userService.signOut();
      await _hiveService.clearActiveSession(keepIdentifier: _rememberMe);
      _currentUser = null;
      _errorMessage = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
