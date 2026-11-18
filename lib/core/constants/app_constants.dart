/// Constantes globales del sistema ASOPROGANUCOT.
class AppConstants {
  AppConstants._();

  static const String appName = 'ASOPROGANUCOTT';
  static const String appTagline =
      'Asociación de Productores de Leche · Susa, Cundinamarca';

  // Roles RBAC oficiales (Sección 2 del Documento Maestro)
  static const String roleAdmin = 'ADMIN';
  static const String roleOperario = 'OPERARIO';
  static const String roleProductor = 'PRODUCTOR';

  static const List<String> allRoles = <String>[
    roleAdmin,
    roleOperario,
    roleProductor,
  ];

  static String roleLabel(String role) {
    switch (role) {
      case roleAdmin:
        return 'Administrador Central';
      case roleOperario:
        return 'Operario de Recepción';
      case roleProductor:
        return 'Productor / Ganadero';
      default:
        return role;
    }
  }

  static String roleShortLabel(String role) {
    switch (role) {
      case roleAdmin:
        return 'Administrador';
      case roleOperario:
        return 'Operario';
      case roleProductor:
        return 'Productor';
      default:
        return role;
    }
  }

  // Colecciones de Cloud Firestore (Sección 3.3)
  static const String usersCollection = 'usuarios';
  static const String producersCollection = 'productores';
  static const String ratesCollection = 'tarifas_leche';
  static const String receptionsCollection = 'recepciones_leche';
  static const String settlementsCollection = 'liquidaciones';
  static const String notificationsCollection = 'notificaciones';
  static const String auditLogsCollection = 'auditoria_logs';

  // Cajas locales de Hive (Offline-First)
  static const String usersBox = 'users_box';
  static const String sessionBox = 'session_box';
  static const String deliveriesBox = 'deliveries_box';
  static const String producersBox = 'producers_box';

  // Llaves de sesión en Hive
  static const String sessionRememberMeKey = 'remember_me';
  static const String sessionLastIdentifierKey = 'last_identifier';
  static const String sessionBootstrapModeKey = 'bootstrap_mode';
  static const String sessionCachedUserKey = 'cached_user_map';

  // Assets oficiales
  static const String logoAssetPath = 'assets/images/logo_asoproganucot.png';
  static const String iconAssetPath = 'assets/images/app_icon.png';
  static const String cowModelAssetPath =
      'assets/models/spot_holstein_cow.glb';
}
