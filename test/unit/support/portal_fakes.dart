import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pgc_asoproganucot/controllers/auth_controller.dart';
import 'package:pgc_asoproganucot/controllers/producer_portal_controller.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/fcm_service.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/notification_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/rate_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/core/theme/app_theme.dart';
import 'package:pgc_asoproganucot/models/app_notification_model.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/models/milk_rate_model.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';
import 'package:pgc_asoproganucot/views/mobile/producer_shell_view.dart';
import 'package:provider/provider.dart';

/// Fakes y datos compartidos por las pruebas del portal móvil del productor.

class MockUserService extends Mock implements FirebaseUserService {}

class MockFcmService extends Mock implements FcmService {}

class InMemoryProducerRemote implements RemoteProducerDataSource {
  InMemoryProducerRemote(this.items);
  final List<ProducerModel> items;

  @override
  Future<List<ProducerModel>> fetchProducers() async => items;

  @override
  Future<void> upsertProducer(ProducerModel producer) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class InMemoryReceptionRemote implements RemoteReceptionDataSource {
  InMemoryReceptionRemote(this.items);
  final List<MilkReceptionModel> items;

  @override
  Future<List<MilkReceptionModel>> fetchReceptions() async => items;

  @override
  Future<void> upsertReception(MilkReceptionModel reception) async {
    items.removeWhere((MilkReceptionModel r) => r.recepcionId == reception.recepcionId);
    items.add(reception);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class InMemoryRateRemote implements RemoteRateDataSource {
  InMemoryRateRemote(this.rates);
  final List<MilkRateModel> rates;

  @override
  Future<List<MilkRateModel>> fetchRates() async => rates;

  @override
  Future<void> saveRatesBatch(List<MilkRateModel> rates) async {}

  @override
  Future<void> appendAuditLog(AuditLogModel log) async {}
}

class InMemorySettlementRemote implements RemoteSettlementDataSource {
  InMemorySettlementRemote(this.items);
  final List<SettlementModel> items;

  @override
  Future<List<SettlementModel>> fetchSettlements() async => items;

  @override
  Future<void> commitQuincenaClose({
    required List<SettlementModel> settlements,
    required Map<String, List<String>> receptionIdsBySettlement,
    required List<AppNotificationModel> notifications,
    required AuditLogModel auditLog,
  }) async {}

  @override
  Future<void> markSettlementAsPaid({
    required SettlementModel updatedSettlement,
    required AppNotificationModel notification,
    required AuditLogModel auditLog,
  }) async {}
}

class InMemoryNotificationRemote implements RemoteNotificationDataSource, DeletableNotificationDataSource {
  final List<AppNotificationModel> items = <AppNotificationModel>[];
  final List<AuditLogModel> logs = <AuditLogModel>[];
  final List<String> deletedIds = <String>[];
  bool failDeletes = false;

  @override
  Future<List<AppNotificationModel>> fetchNotifications({String? productorId, String? userUid}) async {
    if (productorId == null && userUid == null) {
      return List<AppNotificationModel>.from(items);
    }
    return items.where((AppNotificationModel n) {
      final String? d = n.destinoProductorId;
      return d == null || d == productorId || d == userUid;
    }).toList();
  }

  @override
  Future<void> upsertNotification(AppNotificationModel notification) async {
    items.removeWhere((AppNotificationModel n) => n.notificacionId == notification.notificacionId);
    items.add(notification);
  }

  @override
  Future<void> markNotificationRead(String notificacionId) async {
    final int idx = items.indexWhere((AppNotificationModel n) => n.notificacionId == notificacionId);
    if (idx >= 0) items[idx] = items[idx].copyWith(leida: true);
  }

  @override
  Future<void> appendAuditLog(AuditLogModel log) async => logs.add(log);

  @override
  Future<void> deleteNotification(String notificacionId) async {
    if (failDeletes) throw Exception('offline');
    deletedIds.add(notificacionId);
    items.removeWhere((AppNotificationModel n) => n.notificacionId == notificacionId);
  }
}

/// Preferencias en memoria (equivalente a SharedPreferences para pruebas).
class MemoryPortalPreferences implements PortalPreferences {
  final Map<String, bool> tour = <String, bool>{};
  final Map<String, Set<String>> hidden = <String, Set<String>>{};

  @override
  Future<bool> isTourDone(String uid) async => tour[uid] ?? false;

  @override
  Future<void> setTourDone(String uid, bool done) async => tour[uid] = done;

  @override
  Future<Set<String>> hiddenNotificationIds(String uid) async => Set<String>.from(hidden[uid] ?? <String>{});

  @override
  Future<void> saveHiddenNotificationIds(String uid, Set<String> ids) async => hidden[uid] = Set<String>.from(ids);
}

final UserModel adminUser = UserModel(
  uid: 'uid-admin-1',
  nombreCompleto: 'Admin Susa',
  documento: '1000001',
  correo: 'admin@asoproganucott.com',
  telefono: '3100000001',
  rol: AppConstants.roleAdmin,
  activo: true,
  fcmTokens: const <String>[],
  fechaCreacion: DateTime.utc(2026, 1, 1),
);

final UserModel producerUserA = UserModel(
  uid: 'uid-prod-a',
  nombreCompleto: 'Carlos Mendoza',
  documento: '1073500111',
  correo: 'carlos@finca.com',
  telefono: '3112223344',
  rol: AppConstants.roleProductor,
  activo: true,
  fcmTokens: const <String>[],
  fechaCreacion: DateTime.utc(2026, 1, 5),
);

final ProducerModel producerA = ProducerModel(
  productorId: 'prod-a',
  uidUsuario: 'uid-prod-a',
  codigoAsociado: 'ASO-001',
  cedula: '1073500111',
  nombres: 'Carlos',
  apellidos: 'Mendoza',
  telefono: '3112223344',
  nombreFinca: 'La Pradera',
  vereda: 'El Tablón',
  estado: 'ACTIVO',
  aceptoHabeasData: true,
  fechaAutorizacionDatos: DateTime.utc(2026, 1, 5),
  autorizadoPorUid: 'uid-admin-1',
  fechaCreacion: DateTime.utc(2026, 1, 5),
);

final ProducerModel producerB = ProducerModel(
  productorId: 'prod-b',
  uidUsuario: 'uid-prod-b',
  codigoAsociado: 'ASO-002',
  cedula: '1073500222',
  nombres: 'Lucía',
  apellidos: 'Rojas',
  telefono: '3129998877',
  nombreFinca: 'San Isidro',
  vereda: 'Guatanfur',
  estado: 'ACTIVO',
  aceptoHabeasData: true,
  fechaAutorizacionDatos: DateTime.utc(2026, 1, 6),
  autorizadoPorUid: 'uid-admin-1',
  fechaCreacion: DateTime.utc(2026, 1, 6),
);

MilkReceptionModel reception(
  String id,
  String fecha,
  double litros, {
  String jornada = AppConstants.shiftMorning,
  String hora = '07:15:00',
  String productorId = 'prod-a',
  String? liquidacionId,
  bool anulado = false,
}) {
  return MilkReceptionModel(
    recepcionId: id,
    productorId: productorId,
    codigoAsociadoSnap: productorId == 'prod-a' ? 'ASO-001' : 'ASO-002',
    nombreProductorSnap: productorId == 'prod-a' ? 'Carlos Mendoza' : 'Lucía Rojas',
    litros: litros,
    fechaEntrega: fecha,
    horaEntrega: hora,
    jornada: jornada,
    operarioUid: 'op-1',
    syncStatus: AppConstants.syncSynced,
    isSynced: true,
    liquidacionId: liquidacionId,
    anulado: anulado,
    motivoAnulacion: anulado ? 'Registro duplicado' : null,
    createdAt: DateTime.utc(2026, 11, 1),
  );
}

SettlementModel settlement({
  String id = 'liq-a-1',
  String productorId = 'prod-a',
  String inicio = '2026-11-01',
  String fin = '2026-11-15',
  double litros = 100,
  double valor = 195000,
  bool pagada = true,
  String comprobante = 'LIQ-2026-0001',
}) {
  return SettlementModel(
    liquidacionId: id,
    productorId: productorId,
    nombreProductorSnap: 'Carlos Mendoza',
    cedulaProductorSnap: '1073500111',
    periodoInicio: inicio,
    periodoFin: fin,
    quincenaLabel: '1ª quincena · 11/2026',
    totalLitros: litros,
    cantidadEntregas: 1,
    precioLitroAplicado: 1950,
    valorTotalPagar: valor,
    estadoPago: pagada ? 'PAGADA' : 'PENDIENTE',
    fechaLiquidacion: DateTime.utc(2026, 11, 15, 18),
    fechaPago: pagada ? DateTime.utc(2026, 11, 16, 10) : null,
    observacionPago: pagada ? 'Nequi #4502' : null,
    numeroComprobante: comprobante,
    hashIntegridad: 'abc123def456ghi789',
    creadoPorUid: 'uid-admin-1',
  );
}

AppNotificationModel notice(
  String id, {
  String? dest,
  String tipo = 'COMUNICADO',
  DateTime? at,
  bool leida = false,
  String titulo = 'Aviso',
}) {
  return AppNotificationModel(
    notificacionId: id,
    titulo: titulo,
    mensaje: 'Mensaje de $id',
    tipo: tipo,
    destinoProductorId: dest,
    fechaEnvio: at ?? DateTime.now().toUtc(),
    leida: leida,
  );
}

ProducerPortalController buildPortalController({
  required HiveService hive,
  required List<MilkReceptionModel> receptions,
  required List<SettlementModel> settlements,
  required InMemoryNotificationRemote notifRemote,
  PortalPreferences? preferences,
}) {
  return ProducerPortalController(
    hiveService: hive,
    producerService: ProducerService(
      hiveService: hive,
      remoteDataSource: InMemoryProducerRemote(<ProducerModel>[producerA, producerB]),
    ),
    receptionService: ReceptionService(hiveService: hive, remoteDataSource: InMemoryReceptionRemote(receptions)),
    rateService: RateService(
      hiveService: hive,
      remoteDataSource: InMemoryRateRemote(<MilkRateModel>[
        MilkRateModel(
          tarifaId: 'rate-1',
          precioPorLitro: 1950,
          fechaInicioVigencia: DateTime.utc(2026, 1, 1),
          observacion: 'Tarifa oficial Susa',
          registradoPorUid: 'uid-admin-1',
          activa: true,
        ),
      ]),
    ),
    settlementService: SettlementService(hiveService: hive, remoteDataSource: InMemorySettlementRemote(settlements)),
    notificationService: NotificationService(hiveService: hive, remoteDataSource: notifRemote),
    fcmService: FcmService(),
    preferences: preferences ?? MemoryPortalPreferences(),
  );
}

/// AuthController de prueba con usuario fijo (sin Firebase).
class FakeAuthController extends AuthController {
  FakeAuthController(this.user, {required HiveService hive})
      : super(userService: MockUserService(), hiveService: hive, fcmService: MockFcmService());

  UserModel? user;

  @override
  UserModel? get currentUser => user;
}

Widget wrapShell({required AuthController auth, required ProducerPortalController portal}) {
  return MultiProvider(
    providers: <ChangeNotifierProvider<dynamic>>[
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<ProducerPortalController>.value(value: portal),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: const ProducerShellView(),
    ),
  );
}
