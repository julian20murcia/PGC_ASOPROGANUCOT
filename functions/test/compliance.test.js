const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const { createHash } = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { closeMilkSettlements } = require('../compliance');

const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = process.env.GCLOUD_PROJECT || 'demo-asoproganucot';
if (!/^(localhost|127\.0\.0\.1):\d+$/.test(host || '') || !project.startsWith('demo-')) {
  throw new Error('Ejecuta esta prueba con un emulador local y un proyecto demo.');
}
initializeApp({ projectId: project });
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const prefix = `projects/${project}/databases/(default)/documents`;

function token(uid) {
  const encode = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${encode({ alg: 'none' })}.${encode({ sub: uid, user_id: uid, aud: project,
    iss: `https://securetoken.google.com/${project}`, exp: 4102444800, iat: 1 })}.`;
}

function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'string') return { stringValue: data };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return { doubleValue: data };
  if (typeof data.toDate === 'function') {
    const seconds = new Date(data.seconds * 1000).toISOString().slice(0, -4);
    return { timestampValue: `${seconds}${String(data.nanoseconds).padStart(9, '0')}Z` };
  }
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: fields(data) } };
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, entry]) => [key, value(entry)]));
}

function write(path, data, times = [], mask) {
  return {
    update: { name: `${prefix}/${path}`, fields: fields(data) },
    updateTransforms: times.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
    ...(mask ? { updateMask: { fieldPaths: mask } } : {}),
  };
}

function commit(writes, uid) {
  return fetch(`${root}:commit`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${uid === 'owner' ? 'owner' : token(uid)}` },
    body: JSON.stringify({ writes }),
  });
}

function read(path, uid) {
  return fetch(`${root}/${path}`, { headers: uid ? { Authorization: `Bearer ${token(uid)}` } : {} });
}

function audited(path, data, logId, uid, action, before = null, reason = null) {
  const [entity, id] = path.split('/');
  const next = { ...data, auditLogId: logId, updatedByUid: uid };
  return [write(path, next, ['updatedAt']), write(`auditoria_logs/${logId}`, {
    logId, entidadAfectada: entity, registroId: id, accion: action,
    usuarioUid: uid, valorAnterior: before, valorNuevo: next, motivo: reason,
  }, ['timestamp'])];
}

async function expectStatus(promise, expected) {
  const response = await promise;
  assert.equal(response.status, expected, await response.text());
}

test('reglas de perfiles, autorización, entregas y cierre con auditoría', async () => {
  const rules = readFileSync(join(__dirname, '../../firestore.rules'), 'utf8');
  await expectStatus(fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content: rules }] } }),
  }), 200);
  const suffix = Date.now().toString();
  const [admin, staff, producer, other] = ['admin', 'staff', 'producer', 'other'].map((name) => `${name}-${suffix}`);
  const producerId = `milk-${suffix}`;
  const notice = { version: 'prueba', responsable: 'Ejemplo', direccion: 'Sede de prueba',
    correo: 'contacto@example.com', telefono: '123', politicaUrl: 'https://example.com/politica',
    derechos: 'Derechos de prueba', finalidades: 'Registro de prueba' };
  const activeUser = (uid, rol) => write(`usuarios/${uid}`, { uid, activo: true, rol });
  await expectStatus(commit([
    activeUser(admin, 'ADMIN'), activeUser(staff, 'OPERARIO'), activeUser(producer, 'PRODUCTOR'),
    activeUser(other, 'PRODUCTOR'), write('configuracion/privacidad', notice),
  ], 'owner'), 200);
  await expectStatus(read(`usuarios/${producer}`), 403);
  await expectStatus(read(`usuarios/${producer}`, other), 403);
  await expectStatus(read(`usuarios/${producer}`, producer), 200);
  await expectStatus(commit([write(`usuarios/${producer}`, { rol: 'ADMIN' }, [], ['rol'])], producer), 403);

  const loginLog = `login-${suffix}`;
  const login = write(`usuarios/${producer}`, { ultimoAccesoLogId: loginLog }, ['ultimoAcceso'], ['ultimoAccesoLogId']);
  await expectStatus(commit([login], producer), 403);
  await expectStatus(commit([login, write(`auditoria_logs/${loginLog}`, {
    logId: loginLog, entidadAfectada: 'usuarios', registroId: producer,
    accion: 'INICIAR_SESION', usuarioUid: producer,
  }, ['timestamp'])], producer), 200);

  const producerPath = `productores/${producerId}`;
  const consent = { productorId: producerId, uidUsuario: producer, nombres: 'Productor', apellidos: 'Prueba',
    cedula: '111111', aceptoHabeasData: true, fechaAutorizacionDatos: new Date().toISOString(),
    autorizadoPorUid: admin, avisoPrivacidad: notice, soporteAutorizacion: 'ACTA-1' };
  await expectStatus(commit(audited(producerPath, { ...consent, soporteAutorizacion: '' }, `p-${suffix}`, admin, 'CREAR'), admin), 403);
  await expectStatus(commit(audited(producerPath, consent, `p-${suffix}`, admin, 'CREAR'), admin), 200);
  await expectStatus(read(producerPath, producer), 200);
  await expectStatus(read(producerPath, other), 403);

  const receptionPath = `recepciones_leche/${suffix}`;
  const reception = { recepcionId: suffix, productorId: producerId, operarioUid: staff, litros: 15,
    fechaEntrega: '2026-11-10', createdAt: '2026-11-10T11:00:00.000Z',
    liquidacionId: null, anulado: false, isSynced: true, syncStatus: 'SINCRONIZADO' };
  await expectStatus(commit([write(receptionPath, reception)], staff), 403);
  await expectStatus(commit(audited(receptionPath, reception, `r-${suffix}`, staff, 'CREAR'), staff), 200);
  await expectStatus(read(receptionPath, producer), 200);
  await expectStatus(read(receptionPath, other), 403);
  await expectStatus(read(`auditoria_logs/r-${suffix}`, admin), 200);
  await expectStatus(read(`auditoria_logs/r-${suffix}`, producer), 403);
  await expectStatus(commit([write(receptionPath, { litros: 19 }, [], ['litros'])], admin), 403);
  const db = getFirestore();
  const original = (await db.doc(receptionPath).get()).data();
  const { updatedAt, ...capture } = original;
  const corrected = audited(receptionPath, { ...capture, litros: 16 },
    `edit-${suffix}`, admin, 'EDITAR', original, 'Verificación de planta');
  await expectStatus(commit(corrected, admin), 200);
  assert.equal((await db.doc(`auditoria_logs/edit-${suffix}`).get()).get('valorAnterior.litros'), 15);

  const settlementId = `settlement-${suffix}`;
  const voucher = `COMP-2026-${suffix}`;
  const hash = createHash('sha256').update([
    settlementId, voucher, producerId, '111111', '2026-11-01', '2026-11-15', 16000, 1, 100000, 1600000, suffix,
  ].join('|')).digest('hex');
  const group = { settlement: { liquidacionId: settlementId, productorId: producerId,
    periodoInicio: '2026-11-01', periodoFin: '2026-11-15', numeroComprobante: voucher,
    precioLitroAplicado: 1000, quincenaLabel: 'Quincena de prueba',
    fechaLiquidacion: '2026-11-18T00:00:00.000Z', hashIntegridad: hash },
    receptionIds: [suffix], notification: { notificacionId: `notice-${suffix}` } };
  await expectStatus(commit([write(`liquidaciones/${settlementId}`, group.settlement)], admin), 403);
  assert.equal((await closeMilkSettlements.run({ auth: { uid: staff }, data: { groups: [group] } })).completed, 0);
  assert.deepEqual(await closeMilkSettlements.run({ auth: { uid: admin }, data: { groups: [group] } }), { completed: 1 });
  assert.deepEqual(await closeMilkSettlements.run({ auth: { uid: admin }, data: { groups: [group] } }), { completed: 1 });
  assert.equal((await db.doc(receptionPath).get()).get('liquidacionId'), settlementId);
  assert.equal((await db.doc(`auditoria_logs/cierre_${settlementId}_${suffix}`).get()).get('valorAnterior.litros'), 16);
  await expectStatus(commit(corrected, admin), 403);
  const settlementPath = `liquidaciones/${settlementId}`;
  const issued = (await db.doc(settlementPath).get()).data();
  assert.equal(issued.valorTotalPagar, 16000);
  const { updatedAt: issueTime, ...issuedVersion } = issued;
  const payment = { ...issuedVersion, estadoPago: 'PAGADA', fechaPago: '2026-11-18T00:00:00.000Z', observacionPago: 'Pago de prueba' };
  const pay = audited(settlementPath, payment, `pay-${suffix}`, admin, 'EDITAR', issued, 'Pago de prueba');
  await expectStatus(commit([pay[0]], admin), 403);
  await expectStatus(commit(pay, admin), 200);
  await expectStatus(read(settlementPath, producer), 200);
  await expectStatus(read(settlementPath, other), 403);
});
