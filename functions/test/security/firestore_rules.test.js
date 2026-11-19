/**
 * PRUEBAS DE SEGURIDAD — Reglas de Firestore (control de acceso).
 *
 * Se ejecutan contra el emulador de Firestore con las reglas reales del
 * proyecto (`firestore.rules`). Cada prueba simula a un actor (anónimo,
 * productor, otro productor, operario, operario con permisos limitados,
 * administrador y administrador suspendido) e intenta operaciones legítimas
 * y ataques: lectura de datos ajenos, escalamiento de privilegios,
 * manipulación de pagos, alteración de tarifas históricas y de la bitácora.
 *
 * Ejecutar:
 *   firebase emulators:exec --only firestore --project demo-asoproganucot \
 *     "node --test functions/test/security/firestore_rules.test.js"
 */
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test, before, after, describe } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, query, where,
} = require('firebase/firestore');

const PROJECT = 'demo-asoproganucot';
let env;

const ADMIN = 'u_admin';
const OPER = 'u_operario';
const OPER_LIM = 'u_operario_lim';
const PROD1 = 'u_prod1';
const PROD2 = 'u_prod2';
const SUSP = 'u_suspendido';

function user(uid, rol, extra = {}) {
  return {
    uid, rol, activo: true, nombreCompleto: `Usuario ${uid}`, documento: '1012345678',
    correo: `${uid}@ejemplo.co`, telefono: '3101234567', fcmTokens: [], ...extra,
  };
}

before(async () => {
  const [host, port] = String(process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      rules: readFileSync(join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8'),
      host,
      port: Number(port),
    },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const put = (path, data) => setDoc(doc(db, path), data);
    await put(`usuarios/${ADMIN}`, user(ADMIN, 'ADMIN'));
    await put(`usuarios/${OPER}`, user(OPER, 'OPERARIO'));
    await put(`usuarios/${OPER_LIM}`, user(OPER_LIM, 'OPERARIO', { permisos: { recepcion: ['ver'] } }));
    await put(`usuarios/${PROD1}`, user(PROD1, 'PRODUCTOR'));
    await put(`usuarios/${PROD2}`, user(PROD2, 'PRODUCTOR'));
    await put(`usuarios/${SUSP}`, user(SUSP, 'ADMIN', { activo: false }));

    await put('productores/prod1', { productorId: 'prod1', uidUsuario: PROD1, nombres: 'Ana', estado: 'ACTIVO' });
    await put('productores/prod2', { productorId: 'prod2', uidUsuario: PROD2, nombres: 'Beto', estado: 'ACTIVO' });

    const rec = (id, productorId, extra = {}) => put(`recepciones_leche/${id}`, {
      recepcionId: id, productorId, litros: 20, fechaEntrega: '2026-11-10', jornada: 'MANANA',
      anulado: false, liquidacionId: null, ...extra,
    });
    await rec('r1', 'prod1');
    await rec('r2', 'prod2');
    await rec('r_liq', 'prod1', { liquidacionId: 'l1' });

    await put('liquidaciones/l1', { liquidacionId: 'l1', productorId: 'prod1', estadoPago: 'PENDIENTE', valorTotalPagar: 37000 });
    await put('liquidaciones/l2', { liquidacionId: 'l2', productorId: 'prod2', estadoPago: 'PENDIENTE', valorTotalPagar: 12000 });

    const notif = (id, extra) => put(`notificaciones/${id}`, {
      notificacionId: id, titulo: 'Aviso', mensaje: 'Texto', leida: false, fechaEnvio: '2026-11-10T00:00:00Z', ...extra,
    });
    await notif('n_prod1', { tipo: 'ENTREGA', destinoProductorId: 'prod1' });
    await notif('n_prod2', { tipo: 'ENTREGA', destinoProductorId: 'prod2' });
    await notif('n_rect', { tipo: 'RECTIFICACION', destinoProductorId: 'prod1' });
    await notif('c_general', { tipo: 'COMUNICADO', destinoProductorId: null });
    await notif('t_general', { tipo: 'TARIFA', destinoProductorId: null });
    await notif('x_general', { tipo: 'ENTREGA', destinoProductorId: null });

    await put('tarifas_leche/t1', { tarifaId: 't1', precioPorLitro: 1850, activa: true, observacion: 'Inicial' });
    await put('configuracion/finanzas', { precioVentaLitro: 2300, costoOperativoMensual: 1500000 });
    await put('auditoria_logs/log1', { logId: 'log1', accion: 'CREAR', entidadAfectada: 'tarifas_leche', usuarioUid: ADMIN });
  });
});

after(async () => {
  await env?.cleanup();
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('Autenticación obligatoria', () => {
  test('un visitante sin sesión no puede leer ningún dato de negocio', async () => {
    const db = anon();
    for (const path of ['recepciones_leche/r1', 'productores/prod1', 'usuarios/u_admin', 'liquidaciones/l1',
      'tarifas_leche/t1', 'notificaciones/c_general', 'configuracion/finanzas', 'auditoria_logs/log1']) {
      await assertFails(getDoc(doc(db, path)));
    }
  });

  test('una sesión solo por SMS (sin portal) no obtiene acceso', async () => {
    const db = env.authenticatedContext(PROD1, { firebase: { sign_in_provider: 'phone' } }).firestore();
    await assertFails(getDoc(doc(db, 'recepciones_leche/r1')));
    await assertFails(getDoc(doc(db, `usuarios/${PROD1}`)));
  });

  test('una cuenta suspendida pierde todo acceso aunque sea administrador', async () => {
    const db = as(SUSP);
    await assertFails(getDoc(doc(db, 'recepciones_leche/r1')));
    await assertFails(setDoc(doc(db, 'tarifas_leche/t_susp'), { precioPorLitro: 2000 }));
  });
});

describe('Aislamiento de datos entre productores (Habeas Data)', () => {
  test('el productor ve sus entregas, liquidaciones y ficha, pero no las de otro', async () => {
    const db = as(PROD1);
    await assertSucceeds(getDoc(doc(db, 'recepciones_leche/r1')));
    await assertFails(getDoc(doc(db, 'recepciones_leche/r2')));
    await assertSucceeds(getDoc(doc(db, 'liquidaciones/l1')));
    await assertFails(getDoc(doc(db, 'liquidaciones/l2')));
    await assertSucceeds(getDoc(doc(db, 'productores/prod1')));
    await assertFails(getDoc(doc(db, 'productores/prod2')));
  });

  test('el productor solo puede consultar entregas filtradas por su propio código', async () => {
    const db = as(PROD1);
    await assertSucceeds(getDocs(query(collection(db, 'recepciones_leche'), where('productorId', '==', 'prod1'))));
    await assertFails(getDocs(query(collection(db, 'recepciones_leche'), where('productorId', '==', 'prod2'))));
    await assertFails(getDocs(collection(db, 'recepciones_leche')));
  });

  test('avisos: propios y generales (comunicado/tarifa) sí; de otro productor o generales de otro tipo no', async () => {
    const db = as(PROD1);
    await assertSucceeds(getDoc(doc(db, 'notificaciones/n_prod1')));
    await assertSucceeds(getDoc(doc(db, 'notificaciones/c_general')));
    await assertSucceeds(getDoc(doc(db, 'notificaciones/t_general')));
    await assertFails(getDoc(doc(db, 'notificaciones/n_prod2')));
    await assertFails(getDoc(doc(db, 'notificaciones/x_general')));
  });

  test('el productor no puede leer perfiles de otros usuarios ni la configuración financiera', async () => {
    const db = as(PROD1);
    await assertSucceeds(getDoc(doc(db, `usuarios/${PROD1}`)));
    await assertFails(getDoc(doc(db, `usuarios/${PROD2}`)));
    await assertFails(getDocs(collection(db, 'usuarios')));
    await assertFails(getDoc(doc(db, 'configuracion/finanzas')));
    await assertFails(getDoc(doc(db, 'auditoria_logs/log1')));
  });
});

describe('Prevención de escalamiento de privilegios', () => {
  test('un productor no puede convertirse en administrador ni reactivarse', async () => {
    const db = as(PROD1);
    await assertFails(updateDoc(doc(db, `usuarios/${PROD1}`), { rol: 'ADMIN' }));
    await assertFails(updateDoc(doc(db, `usuarios/${PROD1}`), { activo: true, rol: 'OPERARIO' }));
    await assertFails(updateDoc(doc(db, `usuarios/${PROD2}`), { fcmTokens: ['robado'] }));
  });

  test('el usuario solo puede actualizar sus tokens push y con límite de 30', async () => {
    const db = as(PROD1);
    await assertSucceeds(updateDoc(doc(db, `usuarios/${PROD1}`), { fcmTokens: ['token-a'] }));
    const many = Array.from({ length: 31 }, (_, i) => `t${i}`);
    await assertFails(updateDoc(doc(db, `usuarios/${PROD1}`), { fcmTokens: many }));
    await assertFails(updateDoc(doc(db, `usuarios/${PROD1}`), { fcmTokens: ['x'], nombreCompleto: 'Otro' }));
  });

  test('un operario no puede administrar usuarios ni crear cuentas', async () => {
    const db = as(OPER);
    await assertFails(getDocs(collection(db, 'usuarios')));
    await assertFails(updateDoc(doc(db, `usuarios/${PROD1}`), { activo: false }));
    await assertFails(setDoc(doc(db, 'usuarios/nuevo'), user('nuevo', 'ADMIN')));
  });

  test('ni el administrador puede crear un rol inexistente', async () => {
    const db = as(ADMIN);
    await assertFails(setDoc(doc(db, 'usuarios/x1'), user('x1', 'SUPERADMIN')));
    await assertSucceeds(setDoc(doc(db, 'usuarios/x2'), user('x2', 'OPERARIO')));
  });
});

describe('Permisos por módulo (RBAC) y validación de datos', () => {
  test('tarifas: solo quien tiene permiso crea, y el precio debe estar en rango', async () => {
    await assertFails(setDoc(doc(as(PROD1), 'tarifas_leche/tp'), { precioPorLitro: 1900 }));
    await assertFails(setDoc(doc(as(OPER), 'tarifas_leche/to'), { precioPorLitro: 1900 }));
    const admin = as(ADMIN);
    await assertSucceeds(setDoc(doc(admin, 'tarifas_leche/ok'), { precioPorLitro: 1900 }));
    await assertFails(setDoc(doc(admin, 'tarifas_leche/cero'), { precioPorLitro: 0 }));
    await assertFails(setDoc(doc(admin, 'tarifas_leche/neg'), { precioPorLitro: -5 }));
    await assertFails(setDoc(doc(admin, 'tarifas_leche/alto'), { precioPorLitro: 100000 }));
    await assertFails(setDoc(doc(admin, 'tarifas_leche/texto'), { precioPorLitro: '1900' }));
  });

  test('el precio histórico de una tarifa es inmutable (solo se cierra la vigencia)', async () => {
    const admin = as(ADMIN);
    await assertFails(updateDoc(doc(admin, 'tarifas_leche/t1'), { precioPorLitro: 999 }));
    await assertSucceeds(updateDoc(doc(admin, 'tarifas_leche/t1'), { activa: false }));
  });

  test('comunicados: el operario limitado no puede publicar; el productor tampoco', async () => {
    const msg = { tipo: 'COMUNICADO', destinoProductorId: null, titulo: 'X', mensaje: 'Y', leida: false };
    await assertFails(setDoc(doc(as(OPER_LIM), 'notificaciones/c1'), msg));
    await assertFails(setDoc(doc(as(PROD1), 'notificaciones/c2'), msg));
    await assertSucceeds(setDoc(doc(as(ADMIN), 'notificaciones/c3'), msg));
  });

  test('finanzas: solo con permiso de tarifas y con campos/valores válidos', async () => {
    await assertFails(setDoc(doc(as(OPER), 'configuracion/finanzas'), { precioVentaLitro: 1 }));
    await assertFails(setDoc(doc(as(ADMIN), 'configuracion/finanzas'), { precioVentaLitro: 2300, hack: true }));
  });
});

describe('Integridad de pagos, entregas y bitácora', () => {
  test('nadie puede emitir liquidaciones directamente (solo la Cloud Function de cierre)', async () => {
    await assertFails(setDoc(doc(as(ADMIN), 'liquidaciones/falsa'), { productorId: 'prod1', valorTotalPagar: 9e9 }));
  });

  test('un productor no puede marcar su liquidación como pagada ni cambiar el valor', async () => {
    const db = as(PROD1);
    await assertFails(updateDoc(doc(db, 'liquidaciones/l1'), { estadoPago: 'PAGADA' }));
    await assertFails(updateDoc(doc(db, 'liquidaciones/l1'), { valorTotalPagar: 999999 }));
  });

  test('una entrega no se puede crear ni corregir sin bitácora válida, ni modificar si ya está liquidada', async () => {
    await assertFails(setDoc(doc(as(PROD1), 'recepciones_leche/r_fake'), { recepcionId: 'r_fake', productorId: 'prod1', litros: 50 }));
    await assertFails(updateDoc(doc(as(ADMIN), 'recepciones_leche/r1'), { litros: 999 }));
    await assertFails(updateDoc(doc(as(ADMIN), 'recepciones_leche/r_liq'), { anulado: true }));
    await assertFails(deleteDoc(doc(as(ADMIN), 'recepciones_leche/r1')));
  });

  test('la bitácora de auditoría no se puede editar ni borrar (ni el administrador)', async () => {
    const admin = as(ADMIN);
    await assertSucceeds(getDoc(doc(admin, 'auditoria_logs/log1')));
    await assertFails(updateDoc(doc(admin, 'auditoria_logs/log1'), { accion: 'NADA' }));
    await assertFails(deleteDoc(doc(admin, 'auditoria_logs/log1')));
  });

  test('el productor solo marca como leídos sus avisos y no borra solicitudes de rectificación', async () => {
    const db = as(PROD1);
    await assertSucceeds(updateDoc(doc(db, 'notificaciones/n_prod1'), { leida: true }));
    await assertFails(updateDoc(doc(db, 'notificaciones/n_prod1'), { titulo: 'Alterado' }));
    await assertFails(updateDoc(doc(db, 'notificaciones/n_prod2'), { leida: true }));
    await assertFails(deleteDoc(doc(db, 'notificaciones/n_rect')));
    await assertFails(deleteDoc(doc(db, 'notificaciones/c_general')));
  });
});
