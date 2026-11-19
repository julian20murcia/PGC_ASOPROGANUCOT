import '../../../core/constants/app_constants.dart';
import '../../../core/security/permissions.dart';
import '../../../core/utils/input_rules.dart';

/// Fortaleza de una contraseña (medidor del formulario de usuario).
enum PasswordStrength {
  empty,
  weak,
  fair,
  good,
  strong;

  String get label => switch (this) {
        PasswordStrength.empty => '',
        PasswordStrength.weak => 'Débil',
        PasswordStrength.fair => 'Aceptable',
        PasswordStrength.good => 'Buena',
        PasswordStrength.strong => 'Muy segura',
      };

  /// Fracción de la barra (0–1).
  double get fraction => switch (this) {
        PasswordStrength.empty => 0,
        PasswordStrength.weak => 0.25,
        PasswordStrength.fair => 0.5,
        PasswordStrength.good => 0.75,
        PasswordStrength.strong => 1,
      };
}

/// Reglas del formulario de usuario. Coinciden con las validaciones del
/// servidor (`functions/admin.js`) para que los errores se vean antes de
/// enviar y no después.
class UserFormRules {
  UserFormRules._();

  static String? fullName(String? v) => AppValidators.fullName(v);

  static String? document(String? v) => AppValidators.document(v);

  static String? email(String? v) => AppValidators.email(v);

  static String? phone(String? v) => AppValidators.phone(v, required: false);

  /// En creación es obligatoria; en edición es opcional (solo si se cambia).
  static String? password(String? v, {required bool isRequired}) {
    final String s = v ?? '';
    if (s.isEmpty) return isRequired ? 'La contraseña es obligatoria' : null;
    if (RegExp(r'\s').hasMatch(s)) return 'Sin espacios';
    if (s.length > FieldLimits.password) return 'Máximo ${FieldLimits.password} caracteres';
    return AppValidators.password(s, required: isRequired);
  }

  static String? confirmPassword(String? password, String? confirm) {
    final String p = password ?? '';
    final String c = confirm ?? '';
    if (p.isEmpty && c.isEmpty) return null;
    if (c.isEmpty) return 'Confirma la contraseña';
    if (p != c) return 'Las contraseñas no coinciden';
    return null;
  }

  /// Una cuenta de productor nueva debe quedar vinculada a un productor.
  static String? producerLink({required String role, required String? productorId, required bool isCreate}) {
    if (!isCreate || role != AppConstants.roleProductor) return null;
    if (productorId == null || productorId.isEmpty) {
      return 'Selecciona el productor al que pertenece esta cuenta';
    }
    return null;
  }

  static PasswordStrength strength(String password) {
    if (password.isEmpty) return PasswordStrength.empty;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[a-z]').hasMatch(password) && RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    final bool valid = AppValidators.password(password) == null;
    if (!valid || score <= 1) return PasswordStrength.weak;
    if (score == 2) return PasswordStrength.fair;
    if (score <= 4) return PasswordStrength.good;
    return PasswordStrength.strong;
  }

  /// Permisos a enviar al servidor: solo los operarios tienen permisos
  /// personalizados; si coinciden con los del rol se envía null (usa los del rol).
  static Map<String, List<String>>? permissionsToSend(String role, Map<String, List<String>> perms) {
    if (role != AppConstants.roleOperario) return null;
    final Map<String, List<String>> defaults = Permissions.defaultsFor(role);
    if (PermissionTree.equals(perms, defaults)) return null;
    return PermissionTree.normalize(perms);
  }
}

/// Estado de un módulo del árbol de permisos.
enum ModuleGrant { none, partial, all }

/// Lógica pura del árbol de permisos: "ver" es requisito de las demás
/// acciones; quitar "ver" quita todo el módulo.
class PermissionTree {
  PermissionTree._();

  static Map<String, List<String>> copy(Map<String, List<String>> p) => <String, List<String>>{
        for (final MapEntry<String, List<String>> e in p.entries) e.key: List<String>.from(e.value),
      };

  /// Ordena acciones según la definición y descarta módulos vacíos o desconocidos.
  static Map<String, List<String>> normalize(Map<String, List<String>> p) {
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final PermModule m in Permissions.modules) {
      final Set<String> granted = (p[m.key] ?? const <String>[]).toSet();
      final List<String> acts = m.actions.where(granted.contains).toList();
      if (acts.isNotEmpty && !acts.contains(PermAction.ver)) acts.insert(0, PermAction.ver);
      if (acts.isNotEmpty) out[m.key] = acts;
    }
    return out;
  }

  static bool equals(Map<String, List<String>> a, Map<String, List<String>> b) {
    final Map<String, List<String>> na = normalize(a);
    final Map<String, List<String>> nb = normalize(b);
    if (na.length != nb.length) return false;
    for (final String k in na.keys) {
      final List<String>? other = nb[k];
      if (other == null || other.length != na[k]!.length) return false;
      for (int i = 0; i < other.length; i++) {
        if (other[i] != na[k]![i]) return false;
      }
    }
    return true;
  }

  static bool has(Map<String, List<String>> p, String module, String action) =>
      p[module]?.contains(action) ?? false;

  /// Marca o desmarca una acción respetando la dependencia con "ver".
  static Map<String, List<String>> toggleAction(
    Map<String, List<String>> p,
    String module,
    String action,
    bool value,
  ) {
    final PermModule? def = Permissions.module(module);
    if (def == null || !def.actions.contains(action)) return normalize(p);
    final Map<String, List<String>> next = copy(p);
    final Set<String> acts = (next[module] ?? <String>[]).toSet();
    if (value) {
      acts.add(action);
      acts.add(PermAction.ver);
    } else if (action == PermAction.ver) {
      acts.clear();
    } else {
      acts.remove(action);
    }
    if (acts.isEmpty) {
      next.remove(module);
    } else {
      next[module] = acts.toList();
    }
    return normalize(next);
  }

  /// Interruptor maestro del módulo: todo o nada.
  static Map<String, List<String>> setModule(Map<String, List<String>> p, String module, bool value) {
    final PermModule? def = Permissions.module(module);
    if (def == null) return normalize(p);
    final Map<String, List<String>> next = copy(p);
    if (value) {
      next[module] = List<String>.from(def.actions);
    } else {
      next.remove(module);
    }
    return normalize(next);
  }

  static ModuleGrant moduleGrant(Map<String, List<String>> p, String module) {
    final PermModule? def = Permissions.module(module);
    final int n = p[module]?.length ?? 0;
    if (def == null || n == 0) return ModuleGrant.none;
    return n >= def.actions.length ? ModuleGrant.all : ModuleGrant.partial;
  }

  /// Comportamiento del interruptor maestro al pulsarlo: si todo está
  /// concedido lo quita; en cualquier otro caso concede todo.
  static Map<String, List<String>> tapModule(Map<String, List<String>> p, String module) =>
      setModule(p, module, moduleGrant(p, module) != ModuleGrant.all);

  static Map<String, List<String>> all() => Permissions.full();

  static Map<String, List<String>> none() => <String, List<String>>{};
}
