import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Acciones posibles dentro de un módulo.
class PermAction {
  PermAction._();
  static const String ver = 'ver';
  static const String crear = 'crear';
  static const String editar = 'editar';
  static const String eliminar = 'eliminar';
  static const String exportar = 'exportar';

  static const List<String> all = <String>[ver, crear, editar, eliminar, exportar];

  static String label(String a) => switch (a) {
        ver => 'Ver',
        crear => 'Crear',
        editar => 'Editar',
        eliminar => 'Eliminar / anular',
        exportar => 'Descargar',
        _ => a,
      };
}

/// Definición de un módulo del árbol de permisos.
class PermModule {
  const PermModule({
    required this.key,
    required this.label,
    required this.icon,
    required this.actions,
    required this.description,
    this.actionHints = const <String, String>{},
  });

  final String key;
  final String label;
  final IconData icon;
  final List<String> actions;
  final String description;

  /// Explicación específica de qué significa cada acción en este módulo.
  final Map<String, String> actionHints;
}

/// Árbol oficial de permisos de la plataforma de escritorio.
class Permissions {
  Permissions._();

  static const String dashboard = 'dashboard';
  static const String recepcion = 'recepcion';
  static const String productores = 'productores';
  static const String liquidaciones = 'liquidaciones';
  static const String tarifas = 'tarifas';
  static const String reportes = 'reportes';
  static const String usuarios = 'usuarios';
  static const String comunicados = 'comunicados';
  static const String asistente = 'asistente';

  static const List<PermModule> modules = <PermModule>[
    PermModule(
      key: dashboard,
      label: 'Inicio y estadísticas',
      icon: Icons.space_dashboard_outlined,
      description: 'Panel general, indicadores y predicciones.',
      actions: <String>[PermAction.ver],
    ),
    PermModule(
      key: recepcion,
      label: 'Recepción de leche',
      icon: Icons.water_drop_outlined,
      description: 'Registro diario de litros por productor y jornada.',
      actions: <String>[PermAction.ver, PermAction.crear, PermAction.editar, PermAction.eliminar, PermAction.exportar],
      actionHints: <String, String>{
        PermAction.crear: 'Registrar nuevas entregas',
        PermAction.editar: 'Corregir litros en la tabla',
        PermAction.eliminar: 'Anular entregas',
      },
    ),
    PermModule(
      key: productores,
      label: 'Productores',
      icon: Icons.groups_outlined,
      description: 'Directorio de asociados y sus datos.',
      actions: <String>[PermAction.ver, PermAction.crear, PermAction.editar, PermAction.eliminar, PermAction.exportar],
      actionHints: <String, String>{PermAction.eliminar: 'Inactivar productores'},
    ),
    PermModule(
      key: liquidaciones,
      label: 'Liquidaciones',
      icon: Icons.receipt_long_outlined,
      description: 'Cierre de quincenas, pagos y desprendibles.',
      actions: <String>[PermAction.ver, PermAction.crear, PermAction.editar, PermAction.exportar],
      actionHints: <String, String>{
        PermAction.crear: 'Cerrar quincenas',
        PermAction.editar: 'Registrar pagos',
      },
    ),
    PermModule(
      key: tarifas,
      label: 'Tarifas por litro',
      icon: Icons.price_change_outlined,
      description: 'Precio de compra y venta por litro.',
      actions: <String>[PermAction.ver, PermAction.crear],
      actionHints: <String, String>{PermAction.crear: 'Publicar nuevas tarifas'},
    ),
    PermModule(
      key: reportes,
      label: 'Reportes y auditoría',
      icon: Icons.insights_outlined,
      description: 'Reportes consolidados y actividad de usuarios.',
      actions: <String>[PermAction.ver, PermAction.exportar],
    ),
    PermModule(
      key: usuarios,
      label: 'Usuarios y permisos',
      icon: Icons.admin_panel_settings_outlined,
      description: 'Cuentas de acceso, roles y permisos.',
      actions: <String>[PermAction.ver, PermAction.crear, PermAction.editar, PermAction.eliminar],
      actionHints: <String, String>{PermAction.eliminar: 'Suspender cuentas'},
    ),
    PermModule(
      key: comunicados,
      label: 'Comunicados',
      icon: Icons.campaign_outlined,
      description: 'Avisos a productores en la app móvil.',
      actions: <String>[PermAction.ver, PermAction.crear, PermAction.eliminar],
    ),
    PermModule(
      key: asistente,
      label: 'Asistente IA',
      icon: Icons.auto_awesome_outlined,
      description: 'Preguntas en lenguaje natural sobre los datos.',
      actions: <String>[PermAction.ver],
    ),
  ];

  static PermModule? module(String key) {
    for (final PermModule m in modules) {
      if (m.key == key) return m;
    }
    return null;
  }

  /// Permisos completos (administrador).
  static Map<String, List<String>> full() => <String, List<String>>{
        for (final PermModule m in modules) m.key: List<String>.from(m.actions),
      };

  /// Permisos por defecto según el rol.
  static Map<String, List<String>> defaultsFor(String role) {
    switch (role) {
      case AppConstants.roleAdmin:
        return full();
      case AppConstants.roleOperario:
        return <String, List<String>>{
          dashboard: <String>[PermAction.ver],
          recepcion: <String>[PermAction.ver, PermAction.crear, PermAction.exportar],
          productores: <String>[PermAction.ver],
          liquidaciones: <String>[PermAction.ver],
          tarifas: <String>[PermAction.ver],
          comunicados: <String>[PermAction.ver],
          asistente: <String>[PermAction.ver],
        };
      default:
        return <String, List<String>>{};
    }
  }

  /// Normaliza un mapa crudo de Firestore descartando módulos/acciones desconocidos.
  static Map<String, List<String>>? parse(dynamic raw) {
    if (raw is! Map) return null;
    final Map<String, List<String>> out = <String, List<String>>{};
    raw.forEach((dynamic k, dynamic v) {
      final PermModule? m = module(k.toString());
      if (m == null || v is! List) return;
      final List<String> acts =
          v.map((dynamic e) => e.toString()).where(m.actions.contains).toSet().toList();
      // "ver" es requisito de cualquier otra acción.
      if (acts.isNotEmpty && !acts.contains(PermAction.ver)) acts.insert(0, PermAction.ver);
      if (acts.isNotEmpty) out[m.key] = acts;
    });
    return out;
  }

  /// Cantidad de acciones concedidas (para resúmenes en la UI).
  static int countGranted(Map<String, List<String>> perms) =>
      perms.values.fold<int>(0, (int s, List<String> l) => s + l.length);

  static int get totalActions =>
      modules.fold<int>(0, (int s, PermModule m) => s + m.actions.length);
}
