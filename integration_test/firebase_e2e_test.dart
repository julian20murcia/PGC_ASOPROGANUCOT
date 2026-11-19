// Pruebas de integración de punta a punta con el CÓDIGO REAL de la app contra
// el proyecto de PRUEBAS de Firebase (asoproganucott-d2a07).
//
// Ejecutar:  flutter test integration_test/firebase_e2e_test.dart -d windows
//
// Requiere la cuenta de administrador de pruebas e2e.admin@asoproganucott.test
// y los datos sembrados (seed: true). Crea cuentas e2e.int.* que deben
// limpiarse después.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pgc_asoproganucot/core/security/permissions.dart';
import 'package:pgc_asoproganucot/core/services/firebase_user_service.dart';
import 'package:pgc_asoproganucot/core/services/hive_service.dart';
import 'package:pgc_asoproganucot/core/services/producer_service.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';
import 'package:pgc_asoproganucot/core/services/settlement_calculator.dart';
import 'package:pgc_asoproganucot/core/services/settlement_service.dart';
import 'package:pgc_asoproganucot/firebase_options.dart';
import 'package:pgc_asoproganucot/models/milk_reception_model.dart';
import 'package:pgc_asoproganucot/models/privacy_notice.dart';
import 'package:pgc_asoproganucot/models/producer_model.dart';
import 'package:pgc_asoproganucot/models/settlement_model.dart';
import 'package:pgc_asoproganucot/models/user_model.dart';

const String adminEmail = 'e2e.admin@asoproganucott.test';
const String adminPw = 'Prueba2026x';
const String opPw = 'Operario2026';

late FirebaseFirestore db;
late HiveService hive;
final String stamp = DateTime.now().millisecondsSinceEpoch.toString();

Future<UserModel> signInAs(String email, String pw) async {
  await FirebaseAuth.instance.signOut();
  final UserCredential c =
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pw);
  final DocumentSnapshot<Map<String, dynamic>> d =
      await db.collection('usuarios').doc(c.user!.uid).get();
  return UserModel.fromMap(d.data()!, documentId: d.id);
}

Future<Map<String, dynamic>> waitDoc(String path, bool Function(Map<String, dynamic>) ok) async {
  for (int i = 0; i < 30; i++) {
    final DocumentSnapshot<Map<String, dynamic>> s = await db.doc(path).get();
    if (s.exists && ok(s.data()!)) return s.data()!;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw TestFailure('Timeout esperando $path');
}

Future<List<Map<String, dynamic>>> auditFor(String registroId) async {
  final QuerySnapshot<Map<String, dynamic>> q = await db
      .collection('auditoria_logs')
      .where('registroId', isEqualTo: registroId)
      .get();
  return q.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data()).toList();
}

Future<ProducerModel> seedProducer(bool Function(ProducerModel) where) async {
  final QuerySnapshot<Map<String, dynamic>> q =
      await db.collection('productores').where('seed', isEqualTo: true).get();
  return q.docs
      .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => ProducerModel.fromMap(d.data(), documentId: d.id))
      .firstWhere(where);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String opEditorEmail;
  late String opBasicEmail;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    db = FirebaseFirestore.instance;
    db.settings = const Settings(persistenceEnabled: false);
    hive = HiveService(enablePersistence: false);
    await hive.init();
  });

  tearDownAll(() async => FirebaseAuth.instance.signOut());

  test('Admin crea operarios con FirebaseUserService (Cloud Function) y permisos', () async {
    await signInAs(adminEmail, adminPw);
    final FirebaseUserService users = FirebaseUserService(hiveService: hive);
    opEditorEmail = 'e2e.int.editor.$stamp@asoproganucott.test';
    opBasicEmail = 'e2e.int.basico.$stamp@asoproganucott.test';
    final UserModel editor = await users.createUser(
      nombreCompleto: 'Operario Editor Pruebas',
      documento: '71${stamp.substring(stamp.length - 8)}',
      correo: opEditorEmail,
      telefono: '3001112233',
      rol: 'OPERARIO',
      password: opPw,
      activo: true,
      actorUid: 'x',
      permisos: <String, List<String>>{
        Permissions.recepcion: <String>[PermAction.ver, PermAction.crear, PermAction.editar, PermAction.eliminar],
      },
    );
    expect(editor.permisos?[Permissions.recepcion], contains(PermAction.editar));
    final UserModel basic = await users.createUser(
      nombreCompleto: 'Operario Basico Pruebas',
      documento: '72${stamp.substring(stamp.length - 8)}',
      correo: opBasicEmail,
      telefono: '3001112244',
      rol: 'OPERARIO',
      password: opPw,
      activo: true,
      actorUid: 'x',
    );
    expect(basic.permisos, isNull);
    expect(basic.can(Permissions.recepcion, PermAction.editar), isFalse);

    // Error del servidor llega como mensaje legible.
    await expectLater(
      users.createUser(
        nombreCompleto: 'Operario Editor Pruebas', documento: editor.documento, correo: 'otro.$stamp@asoproganucott.test',
        telefono: '3001112233', rol: 'OPERARIO', password: opPw, activo: true, actorUid: 'x',
      ),
      throwsA(isA<UserServiceException>().having((UserServiceException e) => e.message, 'msg', contains('documento'))),
    );
  });

  test('Admin registra, edita e inactiva un productor (reglas + Habeas Data + auditoría)', () async {
    final UserModel admin = await signInAs(adminEmail, adminPw);
    final ProducerService service = ProducerService(hiveService: hive);
    final PrivacyNotice notice = await PrivacyNotice.load();
    final String cedula = '10${stamp.substring(stamp.length - 8)}';
    final ProducerModel created = await service.createProducer(
      codigoAsociado: 'E2E-${stamp.substring(stamp.length - 5)}',
      cedula: cedula,
      nombres: 'Lucía',
      apellidos: 'Pineda Pruebas',
      telefono: '3112223344',
      nombreFinca: 'Finca Integración',
      vereda: 'Aposentos',
      estado: 'ACTIVO',
      aceptoHabeasData: true,
      actorUid: admin.uid,
      privacyNotice: notice,
      authorizationReference: 'Formato firmado E2E',
    );
    final Map<String, dynamic> doc = await waitDoc('productores/${created.productorId}', (_) => true);
    expect(doc['aceptoHabeasData'], isTrue);
    expect(doc['cedula'], cedula);
    expect((await auditFor(created.productorId)).any((Map<String, dynamic> l) => l['accion'] == 'CREAR'), isTrue);

    final ProducerModel edited = await service.updateProducer(
      previous: created,
      codigoAsociado: created.codigoAsociado,
      cedula: created.cedula,
      nombres: created.nombres,
      apellidos: created.apellidos,
      telefono: '3119998877',
      nombreFinca: 'Finca Integración Dos',
      vereda: created.vereda,
      estado: 'ACTIVO',
      aceptoHabeasData: true,
      actorUid: admin.uid,
    );
    await waitDoc('productores/${edited.productorId}', (Map<String, dynamic> d) => d['telefono'] == '3119998877');

    await service.toggleProducerStatus(producer: edited, actorUid: admin.uid);
    await waitDoc('productores/${edited.productorId}', (Map<String, dynamic> d) => d['estado'] == 'INACTIVO');

    // Validación robusta: nombre absurdo rechazado antes de llegar a Firestore.
    await expectLater(
      service.createProducer(
        codigoAsociado: 'E2E-X1', cedula: '1012345678', nombres: 'juliaaaaaaaannnnnnn', apellidos: 'Perez',
        telefono: '3112223344', nombreFinca: 'X Finca', vereda: 'Aposentos', estado: 'ACTIVO',
        aceptoHabeasData: true, actorUid: admin.uid, privacyNotice: notice, authorizationReference: 'Formato',
      ),
      throwsA(anything),
    );
  });

  late MilkReceptionModel reception;

  test('Operario con permiso registra, corrige y anula una entrega (reglas + auditoría)', () async {
    final UserModel op = await signInAs(opEditorEmail, opPw);
    expect(op.can(Permissions.recepcion, PermAction.editar), isTrue);
    final ReceptionService service = ReceptionService(hiveService: hive);
    final ProducerModel producer = await seedProducer((ProducerModel p) => p.isActivo && p.uidUsuario == null);

    reception = await service.registerReception(
      producer: producer,
      litros: 12.5,
      jornada: 'TARDE',
      operarioUid: op.uid,
      timestamp: DateTime(2026, 11, 19, 16, 5),
      allowDuplicate: true,
    );
    final Map<String, dynamic> created =
        await waitDoc('recepciones_leche/${reception.recepcionId}', (Map<String, dynamic> d) => d['isSynced'] == true);
    expect(created['litros'], 12.5);
    reception = MilkReceptionModel.fromMap(created, documentId: reception.recepcionId);

    final MilkReceptionModel corrected = await service.editReceptionLitros(
      existing: reception,
      nuevosLitros: 14,
      motivo: 'Corrección en planilla: 12,5 L → 14 L',
      actor: op,
    );
    await waitDoc('recepciones_leche/${reception.recepcionId}', (Map<String, dynamic> d) => d['litros'] == 14);
    // El operario no puede leer la bitácora (sin reportes/usuarios.ver).
    await expectLater(auditFor(reception.recepcionId), throwsA(isA<FirebaseException>()));

    await service.annulReception(
      existing: corrected,
      motivo: 'Anulación en planilla: prueba E2E',
      actor: op,
    );
    await waitDoc('recepciones_leche/${reception.recepcionId}', (Map<String, dynamic> d) => d['anulado'] == true);

    // El administrador sí ve la auditoría completa de la entrega.
    await signInAs(adminEmail, adminPw);
    final List<Map<String, dynamic>> logs = await auditFor(reception.recepcionId);
    expect(logs.any((Map<String, dynamic> l) => l['accion'] == 'CREAR'), isTrue);
    expect(logs.any((Map<String, dynamic> l) => l['accion'] == 'EDITAR' && '${l['motivo']}'.contains('12,5 L')), isTrue);
    expect(logs.any((Map<String, dynamic> l) => l['accion'] == 'ANULAR'), isTrue);
  });

  test('Operario sin permiso NO puede corregir: lo bloquea la app y también Firestore', () async {
    final UserModel op = await signInAs(opBasicEmail, opPw);
    final ReceptionService service = ReceptionService(hiveService: hive);
    final ProducerModel producer = await seedProducer((ProducerModel p) => p.isActivo && p.uidUsuario == null);
    final MilkReceptionModel r = await service.registerReception(
      producer: producer, litros: 20, jornada: 'MANANA', operarioUid: op.uid,
      timestamp: DateTime(2026, 11, 19, 6, 30), allowDuplicate: true,
    );
    final MilkReceptionModel synced = MilkReceptionModel.fromMap(
      await waitDoc('recepciones_leche/${r.recepcionId}', (Map<String, dynamic> d) => d['isSynced'] == true),
      documentId: r.recepcionId,
    );

    // 1) La app lo bloquea con su propio usuario.
    await expectLater(
      service.editReceptionLitros(existing: synced, nuevosLitros: 21, motivo: 'Intento sin permiso', actor: op),
      throwsA(isA<ReceptionServiceException>()),
    );
    // 2) Aunque alguien manipule la app (actor falso con permiso), Firestore lo rechaza.
    final UserModel forged = op.copyWith(permisos: <String, List<String>>{
      Permissions.recepcion: <String>[PermAction.ver, PermAction.editar, PermAction.eliminar],
    });
    await expectLater(
      service.editReceptionLitros(existing: synced, nuevosLitros: 21, motivo: 'Intento con app manipulada', actor: forged),
      throwsA(anything),
    );
    final Map<String, dynamic> after = (await db.doc('recepciones_leche/${r.recepcionId}').get()).data()!;
    expect(after['litros'], 20);
  });

  test('Admin cierra una quincena real (Cloud Function), registra el pago y la entrega queda bloqueada', () async {
    final UserModel admin = await signInAs(adminEmail, adminPw);
    const String ini = '2026-11-01';
    const String fin = '2026-11-15';
    final QuerySnapshot<Map<String, dynamic>> q = await db
        .collection('recepciones_leche')
        .where('fechaEntrega', isGreaterThanOrEqualTo: ini)
        .where('fechaEntrega', isLessThanOrEqualTo: fin)
        .get();
    final List<MilkReceptionModel> all = q.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => MilkReceptionModel.fromMap(d.data(), documentId: d.id))
        .toList();
    // Productor sembrado (preferiblemente con app) que aún tenga la quincena abierta.
    final Set<String> open = all
        .where((MilkReceptionModel r) => !r.anulado && !r.isLiquidada)
        .map((MilkReceptionModel r) => r.productorId)
        .toSet();
    final QuerySnapshot<Map<String, dynamic>> ps =
        await db.collection('productores').where('seed', isEqualTo: true).get();
    final List<ProducerModel> candidates = ps.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => ProducerModel.fromMap(d.data(), documentId: d.id))
        .where((ProducerModel p) => open.contains(p.productorId))
        .toList()
      ..sort((ProducerModel a, ProducerModel b) => (b.uidUsuario != null ? 1 : 0) - (a.uidUsuario != null ? 1 : 0));
    expect(candidates, isNotEmpty, reason: 'No quedan productores con la quincena 1–15 nov abierta');
    final ProducerModel producer = candidates.first;
    final List<MilkReceptionModel> receptions =
        all.where((MilkReceptionModel r) => r.productorId == producer.productorId).toList();
    final List<MilkReceptionModel> eligible =
        receptions.where((MilkReceptionModel r) => !r.anulado && !r.isLiquidada).toList();
    expect(eligible, isNotEmpty, reason: 'La quincena 1–15 nov ya estaba cerrada para este productor');
    final double expectedLiters = eligible.fold<double>(0, (double s, MilkReceptionModel r) => s + r.litros);

    final SettlementService service = SettlementService(hiveService: hive);
    final List<SettlementModel> closed = await service.closeQuincena(
      actor: admin,
      period: const QuincenaPeriod(startDate: ini, endDate: fin, label: '1–15 de noviembre 2026'),
      pricePerLiter: 2080,
      receptions: receptions,
      producers: <ProducerModel>[producer],
    );
    expect(closed, hasLength(1));
    final Map<String, dynamic> liq = await waitDoc('liquidaciones/${closed.first.liquidacionId}', (_) => true);
    expect((liq['totalLitros'] as num).toDouble(), closeTo(expectedLiters, 0.001));
    expect((liq['valorTotalPagar'] as num).toDouble(), closeTo(expectedLiters * 2080, 1));
    expect(liq['estadoPago'], 'PENDIENTE');
    final Map<String, dynamic> locked = await waitDoc(
      'recepciones_leche/${eligible.first.recepcionId}',
      (Map<String, dynamic> d) => d['liquidacionId'] == closed.first.liquidacionId,
    );

    // No se puede cerrar dos veces el mismo período.
    await expectLater(
      service.closeQuincena(
        actor: admin,
        period: const QuincenaPeriod(startDate: ini, endDate: fin, label: '1–15 de noviembre 2026'),
        pricePerLiter: 2080, receptions: receptions, producers: <ProducerModel>[producer],
      ),
      throwsA(anything),
    );

    // Una entrega liquidada no se puede corregir.
    await expectLater(
      ReceptionService(hiveService: hive).editReceptionLitros(
        existing: MilkReceptionModel.fromMap(locked, documentId: eligible.first.recepcionId),
        nuevosLitros: 1, motivo: 'Intento sobre liquidada', actor: admin,
      ),
      throwsA(isA<ReceptionServiceException>()),
    );

    final SettlementModel paid = await service.markAsPaid(
      actor: admin,
      settlement: SettlementModel.fromMap(liq, documentId: closed.first.liquidacionId),
      observacionPago: 'Transferencia E2E',
    );
    expect(paid.isPagada, isTrue);
    await waitDoc('liquidaciones/${closed.first.liquidacionId}', (Map<String, dynamic> d) => d['estadoPago'] == 'PAGADA');
  });
}
