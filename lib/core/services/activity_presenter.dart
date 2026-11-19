import 'package:flutter/material.dart';

import '../../models/audit_log_model.dart';
import '../../models/milk_reception_model.dart';
import '../../models/model_parse_helpers.dart';
import '../constants/app_constants.dart';
import '../security/permissions.dart';
import '../utils/formatters.dart';

/// Tipo de actividad (define icono, color y filtro "Tipo de acción").
enum ActivityKind {
  login,
  create,
  update,
  correction,
  annul,
  settle,
  payment,
  rate,
  broadcast,
  permissions,
  account,
  rectification,
  delete,
  other;

  String get label => switch (this) {
        ActivityKind.login => 'Inicios de sesión',
        ActivityKind.create => 'Registros y creaciones',
        ActivityKind.update => 'Actualizaciones',
        ActivityKind.correction => 'Correcciones',
        ActivityKind.annul => 'Anulaciones',
        ActivityKind.settle => 'Cierres de quincena',
        ActivityKind.payment => 'Pagos',
        ActivityKind.rate => 'Tarifas',
        ActivityKind.broadcast => 'Comunicados',
        ActivityKind.permissions => 'Permisos y roles',
        ActivityKind.account => 'Estado de cuentas',
        ActivityKind.rectification => 'Solicitudes de rectificación',
        ActivityKind.delete => 'Eliminaciones',
        ActivityKind.other => 'Otras acciones',
      };

  IconData get icon => switch (this) {
        ActivityKind.login => Icons.login_rounded,
        ActivityKind.create => Icons.add_circle_outline_rounded,
        ActivityKind.update => Icons.edit_outlined,
        ActivityKind.correction => Icons.edit_note_rounded,
        ActivityKind.annul => Icons.block_rounded,
        ActivityKind.settle => Icons.lock_clock_outlined,
        ActivityKind.payment => Icons.payments_outlined,
        ActivityKind.rate => Icons.price_change_outlined,
        ActivityKind.broadcast => Icons.campaign_outlined,
        ActivityKind.permissions => Icons.admin_panel_settings_outlined,
        ActivityKind.account => Icons.manage_accounts_outlined,
        ActivityKind.rectification => Icons.gavel_outlined,
        ActivityKind.delete => Icons.delete_outline_rounded,
        ActivityKind.other => Icons.history_rounded,
      };
}

/// Módulo de la plataforma al que pertenece la actividad.
enum ActivityModule {
  sesion,
  recepcion,
  productores,
  liquidaciones,
  tarifas,
  usuarios,
  comunicados,
  otro;

  String get label => switch (this) {
        ActivityModule.sesion => 'Sesiones',
        ActivityModule.recepcion => 'Recepción de leche',
        ActivityModule.productores => 'Productores',
        ActivityModule.liquidaciones => 'Liquidaciones',
        ActivityModule.tarifas => 'Tarifas',
        ActivityModule.usuarios => 'Usuarios',
        ActivityModule.comunicados => 'Comunicados',
        ActivityModule.otro => 'Otros',
      };

  static ActivityModule fromEntity(String entity, String action) {
    if (action == 'INICIAR_SESION') return ActivityModule.sesion;
    return switch (entity) {
      AppConstants.receptionsCollection => ActivityModule.recepcion,
      AppConstants.producersCollection => ActivityModule.productores,
      AppConstants.settlementsCollection => ActivityModule.liquidaciones,
      AppConstants.ratesCollection => ActivityModule.tarifas,
      AppConstants.usersCollection => ActivityModule.usuarios,
      AppConstants.notificationsCollection => ActivityModule.comunicados,
      _ => ActivityModule.otro,
    };
  }
}

/// Un campo que cambió: "Litros: 12,5 L → 14,0 L".
class ActivityChange {
  const ActivityChange({
    required this.field,
    required this.label,
    required this.before,
    required this.after,
  });

  final String field;
  final String label;

  /// Null cuando el campo no existía (creación).
  final String? before;
  final String? after;

  @override
  String toString() => '$label: ${before ?? '—'} → ${after ?? '—'}';
}

/// Fuente de nombres para traducir identificadores a personas reales.
class ActivityDirectory {
  ActivityDirectory({
    Map<String, String>? userNames,
    Map<String, String>? producerNames,
    Map<String, MilkReceptionModel>? receptions,
  })  : userNames = userNames ?? <String, String>{},
        producerNames = producerNames ?? <String, String>{},
        receptions = receptions ?? <String, MilkReceptionModel>{};

  /// uid → nombre completo.
  final Map<String, String> userNames;

  /// productorId → nombre completo.
  final Map<String, String> producerNames;

  /// recepcionId → entrega (para resolver productor, jornada y fecha).
  final Map<String, MilkReceptionModel> receptions;

  static final ActivityDirectory empty = ActivityDirectory();
}

/// Actividad legible derivada de un registro de `auditoria_logs`.
class ActivityEntry {
  ActivityEntry({
    required this.log,
    required this.actorName,
    required this.description,
    required this.title,
    required this.kind,
    required this.module,
    required this.changes,
    required this.groupKey,
    this.subjectName,
    this.motivo,
    this.related = const <ActivityEntry>[],
  });

  final AuditLogModel log;
  final String actorName;

  /// Frase sin el nombre del actor, ej. "corrigió los litros de Pedro Ruiz…".
  final String description;

  /// Título corto del tipo de evento, ej. "Corrección de litros".
  final String title;
  final ActivityKind kind;
  final ActivityModule module;
  final List<ActivityChange> changes;
  final String? subjectName;
  final String? motivo;

  /// Eventos del mismo grupo (p. ej. las entregas incluidas en un cierre).
  final List<ActivityEntry> related;

  /// Llave para agrupar eventos generados por una misma operación.
  final String groupKey;

  DateTime get timestamp => log.timestamp;

  /// Frase completa: "Ana Gómez corrigió los litros de …".
  String get sentence {
    final String base = '$actorName $description';
    if (motivo == null || motivo!.isEmpty) return base;
    return '$base — motivo: $motivo';
  }

  ActivityEntry withRelated(List<ActivityEntry> items) => ActivityEntry(
        log: log,
        actorName: actorName,
        description: description,
        title: title,
        kind: kind,
        module: module,
        changes: changes,
        groupKey: groupKey,
        subjectName: subjectName,
        motivo: motivo,
        related: items,
      );
}

/// Traduce registros técnicos de auditoría a frases en español.
///
/// Nunca lanza excepciones: si un registro está malformado devuelve una
/// frase genérica en lugar de romper la línea de tiempo.
class ActivityPresenter {
  ActivityPresenter([ActivityDirectory? directory])
      : directory = directory ?? ActivityDirectory.empty;

  final ActivityDirectory directory;

  /// Campos técnicos que nunca se muestran como cambio.
  static const Set<String> hiddenFields = <String>{
    'auditLogId',
    'updatedAt',
    'updatedByUid',
    'isSynced',
    'syncStatus',
    'actorNombre',
    'logId',
    'fcmTokens',
    'ultimoAccesoLogId',
    'sesionMovilId',
    'sesionMovilAt',
    'hashIntegridad',
    'recepcionIds',
    'avisoPrivacidad',
    'uid',
    'recepcionId',
    'productorId',
    'liquidacionId',
    'tarifaId',
    'notificacionId',
    'operarioUid',
    'creadoPorUid',
    'registradoPorUid',
    'autorizadoPorUid',
  };

  static const Map<String, String> fieldLabels = <String, String>{
    'litros': 'Litros',
    'jornada': 'Jornada',
    'fechaEntrega': 'Fecha de entrega',
    'horaEntrega': 'Hora de entrega',
    'anulado': 'Anulada',
    'motivoAnulacion': 'Motivo de anulación',
    'codigoAsociado': 'Código de asociado',
    'codigoAsociadoSnap': 'Código de asociado',
    'nombreProductorSnap': 'Productor',
    'cedula': 'Cédula',
    'nombres': 'Nombres',
    'apellidos': 'Apellidos',
    'telefono': 'Teléfono',
    'nombreFinca': 'Finca',
    'vereda': 'Vereda',
    'estado': 'Estado',
    'aceptoHabeasData': 'Autorización de datos',
    'fechaAutorizacionDatos': 'Fecha de autorización',
    'soporteAutorizacion': 'Soporte de autorización',
    'uidUsuario': 'Cuenta de la app',
    'nombreCompleto': 'Nombre',
    'documento': 'Documento',
    'correo': 'Correo',
    'rol': 'Rol',
    'activo': 'Estado de la cuenta',
    'permisos': 'Permisos',
    'fechaCreacion': 'Fecha de creación',
    'ultimoAcceso': 'Último acceso',
    'precioPorLitro': 'Precio por litro',
    'fechaInicioVigencia': 'Vigente desde',
    'fechaFinVigencia': 'Vigente hasta',
    'observacion': 'Observación',
    'activa': 'Activa',
    'estadoPago': 'Estado de pago',
    'fechaPago': 'Fecha de pago',
    'observacionPago': 'Observación del pago',
    'numeroComprobante': 'Comprobante',
    'quincenaLabel': 'Quincena',
    'periodoInicio': 'Desde',
    'periodoFin': 'Hasta',
    'totalLitros': 'Total litros',
    'cantidadEntregas': 'Entregas',
    'cantidadComprobantes': 'Comprobantes',
    'precioLitroAplicado': 'Precio aplicado',
    'tarifaAplicada': 'Tarifa aplicada',
    'valorTotalPagar': 'Valor a pagar',
    'valorTotal': 'Valor total',
    'fechaLiquidacion': 'Fecha de liquidación',
    'cedulaProductorSnap': 'Cédula',
    'titulo': 'Título',
    'mensaje': 'Mensaje',
    'tipo': 'Tipo',
    'destinoProductorId': 'Destinatario',
    'leida': 'Leída',
    'campo': 'Campo',
    'detalle': 'Detalle',
    'solicitanteUid': 'Solicitante',
    'createdAt': 'Registrada el',
  };

  // ───────────────────────── API pública ─────────────────────────

  ActivityEntry present(AuditLogModel log) {
    try {
      return _present(log);
    } catch (_) {
      return _fallback(log);
    }
  }

  List<ActivityEntry> presentAll(Iterable<AuditLogModel> logs) =>
      logs.map(present).toList();

  /// Agrupa eventos de una misma operación (p. ej. un cierre de quincena
  /// genera un comprobante + una marca por cada entrega incluida). El evento
  /// principal conserva los demás en [ActivityEntry.related].
  static List<ActivityEntry> group(List<ActivityEntry> entries) {
    final Map<String, List<ActivityEntry>> byKey = <String, List<ActivityEntry>>{};
    final List<String> order = <String>[];
    for (final ActivityEntry e in entries) {
      final List<ActivityEntry>? existing = byKey[e.groupKey];
      if (existing == null) {
        byKey[e.groupKey] = <ActivityEntry>[e];
        order.add(e.groupKey);
      } else {
        existing.add(e);
      }
    }
    return order.map((String k) {
      final List<ActivityEntry> items = byKey[k]!;
      if (items.length == 1) return items.first;
      // El principal es el que no proviene de una entrega individual.
      int primaryIdx = items.indexWhere(
        (ActivityEntry e) => e.log.entidadAfectada != AppConstants.receptionsCollection,
      );
      if (primaryIdx < 0) primaryIdx = 0;
      final ActivityEntry primary = items[primaryIdx];
      final List<ActivityEntry> rest = <ActivityEntry>[
        for (int i = 0; i < items.length; i++)
          if (i != primaryIdx) items[i],
      ];
      return primary.withRelated(rest);
    }).toList();
  }

  /// Cambios campo por campo entre dos instantáneas (solo lo que cambió).
  List<ActivityChange> diff(Map<String, dynamic>? before, Map<String, dynamic>? after) {
    if (before == null && after == null) return const <ActivityChange>[];
    final Map<String, dynamic> b = before ?? const <String, dynamic>{};
    final Map<String, dynamic> a = after ?? const <String, dynamic>{};
    final List<String> keys = <String>{...b.keys, ...a.keys}
        .where((String k) => !hiddenFields.contains(k))
        .toList();
    keys.sort((String x, String y) => _fieldRank(x).compareTo(_fieldRank(y)));
    final List<ActivityChange> out = <ActivityChange>[];
    for (final String k in keys) {
      final dynamic vb = b[k];
      final dynamic va = a[k];
      if (before != null && _deepEquals(vb, va)) continue;
      if (before == null && va == null) continue;
      if (k == 'permisos') {
        out.add(ActivityChange(
          field: k,
          label: labelFor(k),
          before: before == null ? null : describePermissions(vb),
          after: describePermissions(va),
        ));
        continue;
      }
      out.add(ActivityChange(
        field: k,
        label: labelFor(k),
        before: before == null || !b.containsKey(k) ? null : formatValue(k, vb),
        after: a.containsKey(k) ? formatValue(k, va) : null,
      ));
    }
    return out;
  }

  static String labelFor(String field) => fieldLabels[field] ?? _humanize(field);

  /// Formatea un valor según el campo (litros, pesos, fechas, roles…).
  String formatValue(String field, dynamic v) {
    if (v == null) return '—';
    if (v is String && v.trim().isEmpty) return '—';
    switch (field) {
      case 'litros':
      case 'totalLitros':
        final double? n = _num(v);
        return n == null ? v.toString() : AppFormatters.formatLiters(n);
      case 'precioPorLitro':
      case 'precioLitroAplicado':
      case 'tarifaAplicada':
      case 'valorTotalPagar':
      case 'valorTotal':
        final double? n = _num(v);
        return n == null ? v.toString() : AppFormatters.formatCurrency(n);
      case 'jornada':
        return _shift(v.toString());
      case 'rol':
        return AppConstants.roleShortLabel(v.toString().toUpperCase());
      case 'activo':
        return v == true ? 'Activa' : 'Suspendida';
      case 'estado':
        return v.toString().toUpperCase() == 'ACTIVO' ? 'Activo' : 'Inactivo';
      case 'estadoPago':
        return v.toString().toUpperCase() == 'PAGADA' ? 'Pagada' : 'Pendiente';
      case 'destinoProductorId':
        final String s = v.toString();
        if (s.isEmpty || s == 'GENERAL') return 'Todos los productores';
        return directory.producerNames[s] ?? 'Un productor';
      case 'uidUsuario':
      case 'solicitanteUid':
        return directory.userNames[v.toString()] ?? 'Cuenta vinculada';
      case 'permisos':
        return describePermissions(v);
    }
    if (v is bool) return v ? 'Sí' : 'No';
    if (v is num) {
      return v == v.roundToDouble()
          ? AppFormatters.formatCurrency(v.toDouble(), symbol: '')
          : v.toString().replaceAll('.', ',');
    }
    if (v is List) return v.isEmpty ? '—' : '${v.length} elementos';
    if (v is Map) return '${v.length} datos';
    final DateTime? date = _maybeDate(v);
    if (date != null) {
      final String s = v is String ? v : '';
      final bool dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
      return dateOnly ? AppFormatters.formatIsoDate(s) : AppFormatters.formatDateTime(date);
    }
    final String s = v.toString();
    return s.length > 140 ? '${s.substring(0, 137)}…' : s;
  }

  /// Resume un mapa de permisos: "12 de 31 permisos".
  static String describePermissions(dynamic raw) {
    if (raw == null) return 'Permisos del rol';
    final Map<String, List<String>>? perms = Permissions.parse(raw);
    if (perms == null) return 'Permisos del rol';
    return '${Permissions.countGranted(perms)} de ${Permissions.totalActions} permisos';
  }

  /// Diferencia de permisos legible: "+ Recepción: Editar · − Usuarios: Ver".
  static List<String> permissionDelta(dynamic beforeRaw, dynamic afterRaw) {
    final Map<String, List<String>> b = Permissions.parse(beforeRaw) ?? <String, List<String>>{};
    final Map<String, List<String>> a = Permissions.parse(afterRaw) ?? <String, List<String>>{};
    final List<String> out = <String>[];
    for (final PermModule m in Permissions.modules) {
      final Set<String> sb = (b[m.key] ?? const <String>[]).toSet();
      final Set<String> sa = (a[m.key] ?? const <String>[]).toSet();
      for (final String act in m.actions) {
        if (sa.contains(act) && !sb.contains(act)) {
          out.add('+ ${m.label}: ${PermAction.label(act)}');
        } else if (sb.contains(act) && !sa.contains(act)) {
          out.add('− ${m.label}: ${PermAction.label(act)}');
        }
      }
    }
    return out;
  }

  // ───────────────────────── Implementación ─────────────────────────

  ActivityEntry _present(AuditLogModel log) {
    final String action = log.accion.toUpperCase();
    final String entity = log.entidadAfectada;
    final ActivityModule module = ActivityModule.fromEntity(entity, action);
    final String actor = actorNameFor(log);

    if (action == 'INICIAR_SESION') {
      return _entry(log, actor, module,
          kind: ActivityKind.login, title: 'Inicio de sesión', description: 'inició sesión en la plataforma');
    }

    switch (entity) {
      case AppConstants.receptionsCollection:
        return _reception(log, actor, module, action);
      case AppConstants.producersCollection:
        return _producer(log, actor, module, action);
      case AppConstants.settlementsCollection:
        return _settlement(log, actor, module, action);
      case AppConstants.ratesCollection:
        return _rate(log, actor, module, action);
      case AppConstants.notificationsCollection:
        return _broadcast(log, actor, module, action);
      case AppConstants.usersCollection:
        return _user(log, actor, module, action);
    }
    return _fallback(log);
  }

  String actorNameFor(AuditLogModel log) {
    final String? known = directory.userNames[log.usuarioUid];
    if (known != null && known.trim().isNotEmpty) return known.trim();
    final String? snap = _str(log.valorNuevo?['actorNombre']) ?? _str(log.valorAnterior?['actorNombre']);
    if (snap != null) return snap;
    if (log.usuarioUid.isEmpty) return 'Usuario desconocido';
    final String short = log.usuarioUid.length > 6 ? log.usuarioUid.substring(0, 6) : log.usuarioUid;
    return 'Usuario $short…';
  }

  ActivityEntry _reception(AuditLogModel log, String actor, ActivityModule module, String action) {
    final Map<String, dynamic> snap = _snapshot(log);
    final MilkReceptionModel? known = directory.receptions[log.registroId];
    final String producer = _producerName(
          id: _str(snap['productorId']) ?? known?.productorId,
          snapshotName: _str(snap['nombreProductorSnap']) ?? known?.nombreProductorSnap,
        ) ??
        'un productor';
    final String? shiftRaw = _str(snap['jornada']) ?? known?.jornada;
    final String? dateRaw = _str(snap['fechaEntrega']) ?? known?.fechaEntrega;
    final List<String> ctx = <String>[
      if (shiftRaw != null) _shift(shiftRaw).toLowerCase(),
      if (dateRaw != null) AppFormatters.formatIsoDate(dateRaw),
    ];
    final String where = ctx.isEmpty ? '' : ' (${ctx.join(', ')})';
    final double? litersBefore = _num(log.valorAnterior?['litros']);
    final double? litersAfter = _num(log.valorNuevo?['litros']) ?? known?.litros;

    switch (action) {
      case 'CREAR':
        final String liters = litersAfter == null ? '' : ': ${AppFormatters.formatLiters(litersAfter)}';
        return _entry(log, actor, module,
            kind: ActivityKind.create,
            title: 'Entrega registrada',
            subject: producer,
            description: 'registró la entrega de $producer$where$liters',
            changes: const <ActivityChange>[]);
      case 'EDITAR':
        final String from = litersBefore == null ? '' : ' de ${AppFormatters.formatLiters(litersBefore)}';
        final String to = litersAfter == null ? '' : ' a ${AppFormatters.formatLiters(litersAfter)}';
        return _entry(log, actor, module,
            kind: ActivityKind.correction,
            title: 'Corrección de litros',
            subject: producer,
            description: 'corrigió los litros de $producer$where$from$to');
      case 'ANULAR':
        final double? l = litersBefore ?? litersAfter;
        final String liters = l == null ? '' : ' de ${AppFormatters.formatLiters(l)}';
        return _entry(log, actor, module,
            kind: ActivityKind.annul,
            title: 'Entrega anulada',
            subject: producer,
            description: 'anuló la entrega$liters de $producer$where');
      case 'LIQUIDAR':
        final String comp = log.motivo ?? '';
        final String? liqId = _str(log.valorNuevo?['liquidacionId']);
        return _entry(log, actor, module,
            kind: ActivityKind.settle,
            title: 'Entrega liquidada',
            subject: producer,
            description: 'incluyó la entrega de $producer$where en el comprobante ${comp.isEmpty ? 'de la quincena' : comp}',
            motivoOverride: '',
            groupKey: liqId != null ? 'liq:$liqId' : null);
    }
    return _generic(log, actor, module, action, 'una entrega de $producer$where');
  }

  ActivityEntry _producer(AuditLogModel log, String actor, ActivityModule module, String action) {
    final Map<String, dynamic> snap = _snapshot(log);
    final String name = _producerName(
          id: log.registroId,
          snapshotName: _joinName(snap['nombres'], snap['apellidos']),
        ) ??
        'un productor';
    final String? code = _str(snap['codigoAsociado']);
    final String label = code == null ? name : '$name ($code)';

    if (action == 'SOLICITAR_RECTIFICACION') {
      final String campo = _str(log.valorNuevo?['campo']) ?? 'sus datos';
      return _entry(log, actor, module,
          kind: ActivityKind.rectification,
          title: 'Solicitud de rectificación',
          subject: name,
          description: 'solicitó rectificar "$campo" en los datos de $name',
          motivoOverride: _str(log.valorNuevo?['detalle']) ?? log.motivo);
    }
    if (action == 'CREAR') {
      return _entry(log, actor, module,
          kind: ActivityKind.create, title: 'Productor creado', subject: name, description: 'creó el productor $label');
    }
    if (action == 'EDITAR') {
      final List<ActivityChange> changes = diff(log.valorAnterior, log.valorNuevo);
      final Set<String> fields = changes.map((ActivityChange c) => c.field).toSet();
      if (fields.length == 1 && fields.contains('estado')) {
        final bool active = _str(log.valorNuevo?['estado'])?.toUpperCase() == 'ACTIVO';
        return _entry(log, actor, module,
            kind: ActivityKind.account,
            title: active ? 'Productor reactivado' : 'Productor inactivado',
            subject: name,
            description: active ? 'reactivó al productor $label' : 'inactivó al productor $label',
            changes: changes);
      }
      if (fields.contains('uidUsuario') && fields.length == 1) {
        return _entry(log, actor, module,
            kind: ActivityKind.permissions,
            title: 'Cuenta vinculada',
            subject: name,
            description: 'vinculó la cuenta de la app móvil al productor $label',
            changes: changes);
      }
      final String what = changes.isEmpty
          ? ''
          : ': ${changes.take(3).map((ActivityChange c) => c.label.toLowerCase()).join(', ')}${changes.length > 3 ? '…' : ''}';
      return _entry(log, actor, module,
          kind: ActivityKind.update,
          title: 'Productor actualizado',
          subject: name,
          description: 'actualizó los datos del productor $label$what',
          changes: changes);
    }
    return _generic(log, actor, module, action, 'el productor $label');
  }

  ActivityEntry _settlement(AuditLogModel log, String actor, ActivityModule module, String action) {
    final Map<String, dynamic> snap = _snapshot(log);
    final String? producer = _producerName(
      id: _str(snap['productorId']),
      snapshotName: _str(snap['nombreProductorSnap']),
    );
    final String? comp = _str(snap['numeroComprobante']);
    final String? label = _str(snap['quincenaLabel']);
    if (action == 'LIQUIDAR') {
      final String period = _periodLabel(snap) ?? label ?? 'la quincena';
      if (producer == null) {
        // Cierre global (versión anterior: un solo registro por quincena).
        final int? count = _num(snap['cantidadComprobantes'])?.toInt();
        final double? total = _num(snap['valorTotal']);
        final List<String> extra = <String>[
          if (count != null) '$count comprobantes',
          if (total != null) AppFormatters.formatCurrency(total),
        ];
        return _entry(log, actor, module,
            kind: ActivityKind.settle,
            title: 'Cierre de quincena',
            description: 'cerró la quincena $period${extra.isEmpty ? '' : ' (${extra.join(', ')})'}',
            motivoOverride: '');
      }
      final String liqId = _str(snap['liquidacionId']) ?? log.registroId;
      return _entry(log, actor, module,
          kind: ActivityKind.settle,
          title: 'Cierre de quincena',
          subject: producer,
          description: 'cerró la quincena $period de $producer${comp == null ? '' : ' (comprobante $comp)'}',
          motivoOverride: '',
          groupKey: 'liq:$liqId');
    }
    if (action == 'EDITAR' &&
        (_str(log.valorNuevo?['estadoPago'])?.toUpperCase() == 'PAGADA')) {
      final String who = producer ?? 'un productor';
      return _entry(log, actor, module,
          kind: ActivityKind.payment,
          title: 'Pago registrado',
          subject: producer,
          description: 'registró el pago de $who${comp == null ? '' : ' (comprobante $comp)'}',
          changes: diff(log.valorAnterior, log.valorNuevo)
              .where((ActivityChange c) => c.field != 'numeroComprobante')
              .toList());
    }
    return _generic(log, actor, module, action, 'la liquidación${comp == null ? '' : ' $comp'}');
  }

  ActivityEntry _rate(AuditLogModel log, String actor, ActivityModule module, String action) {
    final double? price = _num(log.valorNuevo?['precioPorLitro']);
    final double? prev = _num(log.valorAnterior?['precioPorLitro']);
    final String? since = _str(log.valorNuevo?['fechaInicioVigencia']);
    if (action == 'CREAR' && price != null) {
      return _entry(log, actor, module,
          kind: ActivityKind.rate,
          title: 'Tarifa publicada',
          description: 'publicó la tarifa ${AppFormatters.formatCurrency(price)}/L'
              '${since == null ? '' : ' vigente desde ${_dateText(since)}'}'
              '${prev == null ? '' : ' (antes ${AppFormatters.formatCurrency(prev)}/L)'}',
          changes: <ActivityChange>[
            ActivityChange(
              field: 'precioPorLitro',
              label: 'Precio por litro',
              before: prev == null ? null : AppFormatters.formatCurrency(prev),
              after: AppFormatters.formatCurrency(price),
            ),
          ]);
    }
    return _generic(log, actor, module, action, 'una tarifa');
  }

  ActivityEntry _broadcast(AuditLogModel log, String actor, ActivityModule module, String action) {
    final Map<String, dynamic> snap = _snapshot(log);
    final String title = _str(snap['titulo']) ?? 'sin título';
    final String? target = _str(snap['destinoProductorId']);
    final String to = (target == null || target == 'GENERAL')
        ? 'a todos los productores'
        : 'a ${directory.producerNames[target] ?? 'un productor'}';
    if (action == 'CREAR') {
      return _entry(log, actor, module,
          kind: ActivityKind.broadcast,
          title: 'Comunicado enviado',
          description: 'envió el comunicado "$title" $to',
          motivoOverride: '',
          changes: const <ActivityChange>[]);
    }
    if (action == 'ELIMINAR' || action == 'ANULAR') {
      return _entry(log, actor, module,
          kind: ActivityKind.delete,
          title: 'Comunicado eliminado',
          description: 'eliminó el comunicado "$title" (enviado $to)',
          changes: const <ActivityChange>[]);
    }
    return _generic(log, actor, module, action, 'el comunicado "$title"');
  }

  ActivityEntry _user(AuditLogModel log, String actor, ActivityModule module, String action) {
    final Map<String, dynamic> snap = _snapshot(log);
    final String name = directory.userNames[log.registroId] ??
        _str(log.valorNuevo?['nombreCompleto']) ??
        _str(log.valorAnterior?['nombreCompleto']) ??
        'un usuario';
    final String? rolRaw = _str(snap['rol']);
    final String role = rolRaw == null ? '' : ' (${AppConstants.roleShortLabel(rolRaw.toUpperCase())})';
    final String motivo = (log.motivo ?? '').toLowerCase();

    if (action == 'CREAR') {
      return _entry(log, actor, module,
          kind: ActivityKind.create,
          title: 'Usuario creado',
          subject: name,
          description: 'creó el usuario $name$role',
          changes: const <ActivityChange>[]);
    }
    if (action == 'ELIMINAR') {
      return _entry(log, actor, module,
          kind: ActivityKind.delete, title: 'Usuario eliminado', subject: name, description: 'eliminó el usuario $name');
    }
    if (action == 'EDITAR' || action == 'ACTUALIZAR' || action == 'CAMBIAR_PERMISOS' ||
        action == 'SUSPENDER' || action == 'ACTIVAR') {
      final List<ActivityChange> changes = diff(log.valorAnterior, log.valorNuevo);
      final Set<String> fields = changes.map((ActivityChange c) => c.field).toSet();
      final List<String> verbs = <String>[];
      ActivityKind kind = ActivityKind.update;
      String title = 'Usuario actualizado';
      if (fields.contains('activo') || action == 'SUSPENDER' || action == 'ACTIVAR') {
        final bool nowActive = action == 'ACTIVAR' || log.valorNuevo?['activo'] == true;
        verbs.add(nowActive ? 'reactivó la cuenta de $name' : 'suspendió la cuenta de $name');
        kind = ActivityKind.account;
        title = nowActive ? 'Cuenta reactivada' : 'Cuenta suspendida';
      }
      if (fields.contains('rol')) {
        final String from = formatValue('rol', log.valorAnterior?['rol']);
        final String to = formatValue('rol', log.valorNuevo?['rol']);
        verbs.add('cambió el rol de $name de $from a $to');
        kind = ActivityKind.permissions;
        title = 'Cambio de rol';
      }
      if (fields.contains('permisos') || action == 'CAMBIAR_PERMISOS' || motivo.contains('permisos')) {
        verbs.add('cambió los permisos de $name');
        if (kind == ActivityKind.update) {
          kind = ActivityKind.permissions;
          title = 'Cambio de permisos';
        }
      }
      if (motivo.contains('contraseña')) {
        verbs.add('cambió la contraseña de $name');
        if (kind == ActivityKind.update) title = 'Cambio de contraseña';
      }
      final List<ActivityChange> dataChanges = changes
          .where((ActivityChange c) => c.field != 'activo' && c.field != 'rol' && c.field != 'permisos')
          .toList();
      if (dataChanges.isNotEmpty) {
        verbs.add(verbs.isEmpty
            ? 'actualizó los datos de $name: ${dataChanges.map((ActivityChange c) => c.label.toLowerCase()).join(', ')}'
            : 'actualizó ${dataChanges.map((ActivityChange c) => c.label.toLowerCase()).join(', ')}');
      }
      if (verbs.isEmpty) verbs.add('actualizó el usuario $name');
      return _entry(log, actor, module,
          kind: kind,
          title: title,
          subject: name,
          description: _joinVerbs(verbs),
          changes: changes,
          // El motivo del servidor solo repite lo que ya dice la frase.
          motivoOverride: '');
    }
    return _generic(log, actor, module, action, 'el usuario $name');
  }

  ActivityEntry _generic(AuditLogModel log, String actor, ActivityModule module, String action, String what) {
    final (ActivityKind kind, String verb, String title) = switch (action) {
      'CREAR' => (ActivityKind.create, 'creó', 'Registro creado'),
      'EDITAR' || 'ACTUALIZAR' => (ActivityKind.update, 'modificó', 'Registro modificado'),
      'ANULAR' => (ActivityKind.annul, 'anuló', 'Registro anulado'),
      'ELIMINAR' => (ActivityKind.delete, 'eliminó', 'Registro eliminado'),
      'LIQUIDAR' => (ActivityKind.settle, 'liquidó', 'Liquidación'),
      _ => (ActivityKind.other, 'realizó "${_humanize(action.toLowerCase())}" sobre', 'Otra acción'),
    };
    return _entry(log, actor, module, kind: kind, title: title, description: '$verb $what');
  }

  ActivityEntry _fallback(AuditLogModel log) {
    String actor;
    try {
      actor = actorNameFor(log);
    } catch (_) {
      actor = 'Usuario desconocido';
    }
    final ActivityModule module = ActivityModule.fromEntity(log.entidadAfectada, log.accion);
    final String action = log.accion.isEmpty ? 'una acción' : '"${_humanize(log.accion.toLowerCase())}"';
    return ActivityEntry(
      log: log,
      actorName: actor,
      description: 'realizó $action en ${module.label.toLowerCase()}',
      title: 'Otra acción',
      kind: ActivityKind.other,
      module: module,
      changes: const <ActivityChange>[],
      groupKey: 'log:${log.logId}',
      motivo: log.motivo,
    );
  }

  ActivityEntry _entry(
    AuditLogModel log,
    String actor,
    ActivityModule module, {
    required ActivityKind kind,
    required String title,
    required String description,
    String? subject,
    List<ActivityChange>? changes,
    String? motivoOverride,
    String? groupKey,
  }) {
    final String? motivo = motivoOverride == null
        ? log.motivo
        : (motivoOverride.isEmpty ? null : motivoOverride);
    return ActivityEntry(
      log: log,
      actorName: actor,
      description: description,
      title: title,
      kind: kind,
      module: module,
      subjectName: subject,
      changes: changes ?? diff(log.valorAnterior, log.valorNuevo),
      motivo: motivo,
      groupKey: groupKey ?? 'log:${log.logId.isEmpty ? identityHashCode(log) : log.logId}',
    );
  }

  // ───────────────────────── Utilidades ─────────────────────────

  Map<String, dynamic> _snapshot(AuditLogModel log) => <String, dynamic>{
        ...?log.valorAnterior,
        ...?log.valorNuevo,
      };

  String? _producerName({String? id, String? snapshotName}) {
    if (id != null && directory.producerNames[id]?.trim().isNotEmpty == true) {
      return directory.producerNames[id]!.trim();
    }
    if (snapshotName != null && snapshotName.trim().isNotEmpty) return snapshotName.trim();
    return null;
  }

  String? _periodLabel(Map<String, dynamic> snap) {
    final String? from = _str(snap['periodoInicio']);
    final String? to = _str(snap['periodoFin']);
    if (from == null || to == null) return null;
    final DateTime? a = DateTime.tryParse(from);
    final DateTime? b = DateTime.tryParse(to);
    if (a == null || b == null) return null;
    const List<String> m = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    if (a.year == b.year && a.month == b.month) return '${a.day}–${b.day} ${m[b.month - 1]} ${b.year}';
    return '${a.day} ${m[a.month - 1]} – ${b.day} ${m[b.month - 1]} ${b.year}';
  }

  static String _joinVerbs(List<String> verbs) {
    if (verbs.length == 1) return verbs.first;
    return '${verbs.sublist(0, verbs.length - 1).join(', ')} y ${verbs.last}';
  }

  static String? _joinName(dynamic a, dynamic b) {
    final String s = '${a ?? ''} ${b ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.').trim());
    return null;
  }

  static String _shift(String raw) {
    final String s = raw.toUpperCase();
    if (s == AppConstants.shiftMorning || s == 'MAÑANA') return 'Mañana';
    if (s == AppConstants.shiftAfternoon) return 'Tarde';
    return raw;
  }

  static String _dateText(String raw) {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return AppFormatters.formatIsoDate(raw);
    return raw;
  }

  static DateTime? _maybeDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) return null;
      return DateTime.tryParse(v);
    }
    // Timestamp de Firestore u otro objeto con toDate().
    if (v is! num && v is! bool) {
      final DateTime parsed = parseUtcDate(v, fallback: DateTime.utc(1));
      return parsed.year == 1 ? null : parsed;
    }
    return null;
  }

  static bool _deepEquals(dynamic a, dynamic b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final dynamic k in a.keys) {
        if (!b.containsKey(k) || !_deepEquals(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is String && b is String) return a.trim() == b.trim();
    if ((a == null && b is String && b.trim().isEmpty) || (b == null && a is String && a.trim().isEmpty)) {
      return true;
    }
    return a == b || a.toString() == b.toString();
  }

  static int _fieldRank(String field) {
    const List<String> order = <String>[
      'nombreCompleto', 'nombres', 'apellidos', 'rol', 'activo', 'permisos', 'litros', 'jornada',
      'fechaEntrega', 'anulado', 'motivoAnulacion', 'estado', 'precioPorLitro', 'estadoPago',
      'fechaPago', 'observacionPago', 'titulo', 'mensaje', 'destinoProductorId',
    ];
    final int i = order.indexOf(field);
    return i < 0 ? 100 : i;
  }

  static String _humanize(String key) {
    if (key.isEmpty) return key;
    final String spaced = key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (Match m) => '${m[1]} ${m[2]}')
        .toLowerCase()
        .trim();
    return spaced.isEmpty ? key : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
