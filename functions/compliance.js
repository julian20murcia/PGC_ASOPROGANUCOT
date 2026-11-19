const { createHash, randomUUID } = require('node:crypto');
const { defineString } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

const authWebApiKey = defineString('AUTH_WEB_API_KEY');

exports.signInByDocument = onCall(async ({ data }) => {
  const invalid = () => new HttpsError('unauthenticated', 'Credenciales incorrectas.');
  const document = data?.documento;
  const password = data?.password;
  if (typeof document !== 'string' || !/^\d{5,24}$/.test(document) ||
      typeof password !== 'string' || password.length === 0 || password.length > 4096) {
    throw invalid();
  }
  const users = await getFirestore().collection('usuarios')
    .where('documento', '==', document).limit(2).get();
  if (users.size !== 1 || users.docs[0].get('activo') !== true) throw invalid();
  const profile = users.docs[0];
  const email = profile.get('correoAccesoInterno') || profile.get('correo');
  if (typeof email !== 'string' || !email.includes('@')) throw invalid();

  const endpoint = process.env.FIREBASE_AUTH_EMULATOR_HOST
    ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword`
    : 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
  const response = await fetch(`${endpoint}?key=${encodeURIComponent(authWebApiKey.value())}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw invalid();
  const credentials = await response.json();
  if (credentials.localId !== profile.id) throw invalid();
  return { token: await getAuth().createCustomToken(profile.id) };
});

function writeVersion(db, transaction, ref, id, before, after, uid, action, reason) {
  const time = FieldValue.serverTimestamp();
  const version = { ...after, updatedAt: time, updatedByUid: uid, auditLogId: id };
  transaction.set(ref, version);
  transaction.create(db.collection('auditoria_logs').doc(id), {
    logId: id,
    entidadAfectada: ref.parent.id,
    registroId: ref.id,
    accion: action,
    valorAnterior: before,
    valorNuevo: version,
    usuarioUid: uid,
    motivo: reason,
    timestamp: time,
  });
}

const isId = (value) => typeof value === 'string' && /^[\w-]{1,128}$/.test(value);
const isDate = (value) => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
const precondition = (message) => new HttpsError('failed-precondition', message);

const noticeFields = ['version', 'responsable', 'direccion', 'correo', 'telefono',
  'politicaUrl', 'finalidades', 'derechos'];
const portalConsent = 'Leí el aviso y la política de tratamiento. Autorizo el uso de mis datos para verificar mi teléfono, activar mi cuenta y consultar mi historial en el portal.';

function colombianMobile(value) {
  if (typeof value !== 'string') return null;
  const match = /^(?:\+?57|0057)?(3\d{9})$/.exec(value.replace(/[\s().-]/g, ''));
  return match ? `+57${match[1]}` : null;
}

function validPublishedNotice(current, accepted) {
  if (!current || !accepted || typeof accepted !== 'object' ||
      Object.keys(current).length !== noticeFields.length ||
      !noticeFields.every((key) => typeof current[key] === 'string' && current[key].trim() &&
        current[key] === accepted[key])) return false;
  try {
    const url = new URL(current.politicaUrl);
    return url.protocol === 'https:' && Boolean(url.hostname);
  } catch (_) {
    return false;
  }
}

exports.registerProducerAccount = onCall(async ({ auth, data }) => {
  const phone = colombianMobile(auth?.token.phone_number);
  const signedAt = auth?.token.auth_time;
  if (!auth || auth.token.firebase?.sign_in_provider !== 'phone' || !phone ||
      !Number.isFinite(signedAt) || Date.now() / 1000 - signedAt > 15 * 60) {
    throw new HttpsError('unauthenticated', 'Verifica de nuevo el teléfono por SMS.');
  }
  const document = data?.documento;
  const password = data?.password;
  if (typeof document !== 'string' || !/^\d{5,24}$/.test(document) ||
      typeof password !== 'string' || password.length < 8 || password.length > 128 ||
      data.aceptado !== true || data.declaracion !== portalConsent) {
    throw new HttpsError('invalid-argument', 'Revisa el documento, la contraseña y la autorización.');
  }

  const db = getFirestore();
  const uid = auth.uid;
  const user = db.collection('usuarios').doc(uid);
  const enrollment = db.collection('altas_portal').doc(uid);
  const notice = db.doc('configuracion/privacidad');
  const operation = randomUUID();
  const invalid = () => precondition('El documento y el teléfono deben coincidir con un productor activo en el padrón. Consulta a la asociación.');

  const producerRef = await db.runTransaction(async (transaction) => {
    const pending = (await transaction.get(enrollment)).data();
    const profile = await transaction.get(user);
    if (profile.exists) {
      if (profile.get('activo') === true && pending?.estado === 'COMPLETA' &&
          profile.get('documento') === document && pending.telefono === phone) return null;
      throw precondition('Esta cuenta ya existe. Ingresa con tus credenciales o consulta a la asociación.');
    }
    if (pending?.bloqueoHasta > Date.now()) {
      throw precondition('El alta está en curso. Espera un momento e intenta de nuevo.');
    }
    const existing = await transaction.get(db.collection('usuarios').where('documento', '==', document).limit(1));
    if (!existing.empty) throw invalid();

    // El padrón histórico admite varias representaciones del número de teléfono.
    const roster = await transaction.get(db.collection('productores').select('cedula', 'telefono'));
    const matches = roster.docs.filter((doc) => colombianMobile(doc.get('telefono')) === phone);
    if (matches.length !== 1 || matches[0].get('cedula') !== document) throw invalid();
    const producer = await transaction.get(matches[0].ref);
    if (producer.get('estado') !== 'ACTIVO' || producer.get('aceptoHabeasData') !== true ||
        producer.get('uidUsuario') || (pending && pending.productorId !== producer.id)) throw invalid();
    const policy = (await transaction.get(notice)).data();
    if (!validPublishedNotice(policy, data.aviso)) {
      throw precondition('El aviso cambió o está pendiente de publicación. Vuelve a abrir el registro.');
    }
    transaction.set(enrollment, {
      productorId: producer.id, telefono: phone, estado: 'PENDIENTE',
      operacion: operation, bloqueoHasta: Date.now() + 120000,
    });
    return producer.ref;
  });
  if (producerRef === null) return { activa: true };

  const internalEmail = `portal-${createHash('sha256').update(uid).digest('hex').slice(0, 36)}@asoproganucot.invalid`;
  try {
    const firebaseUser = await getAuth().getUser(uid);
    if (firebaseUser.disabled || firebaseUser.phoneNumber !== phone ||
        (firebaseUser.email && firebaseUser.email !== internalEmail)) {
      throw precondition('No se pudo activar esta cuenta. Consulta a la asociación.');
    }
    await getAuth().updateUser(uid, { email: internalEmail, password });

    await db.runTransaction(async (transaction) => {
      const pending = (await transaction.get(enrollment)).data();
      const before = (await transaction.get(producerRef)).data();
      const profile = await transaction.get(user);
      const policy = (await transaction.get(notice)).data();
      const existing = await transaction.get(db.collection('usuarios').where('documento', '==', document).limit(1));
      if (pending?.operacion !== operation || profile.exists || !existing.empty || !before ||
          before.cedula !== document || colombianMobile(before.telefono) !== phone ||
          before.estado !== 'ACTIVO' || before.aceptoHabeasData !== true || before.uidUsuario ||
          !validPublishedNotice(policy, data.aviso)) throw invalid();

      const now = FieldValue.serverTimestamp();
      transaction.create(user, {
        uid, documento: document, telefono: phone, correo: '', correoAccesoInterno: internalEmail,
        nombreCompleto: `${before.nombres || ''} ${before.apellidos || ''}`.trim(),
        rol: 'PRODUCTOR', activo: true, fcmTokens: [], fechaCreacion: now,
      });
      transaction.create(db.collection('autorizaciones_portal').doc(uid), {
        productorId: producerRef.id, titularUid: uid, fecha: now, aviso: policy,
        canal: 'PORTAL_MOVIL_SMS', declaracion: portalConsent,
      });
      writeVersion(db, transaction, producerRef, `alta_portal_${uid}`, before,
        { ...before, uidUsuario: uid, autorizacionPortalId: uid }, uid, 'VINCULAR_PORTAL',
        `Aceptación del aviso de privacidad ${policy.version}`);
      transaction.set(enrollment, { productorId: producerRef.id, telefono: phone, estado: 'COMPLETA' });
    });
    return { activa: true };
  } catch (error) {
    await db.runTransaction(async (transaction) => {
      if ((await transaction.get(enrollment)).get('operacion') === operation) {
        transaction.update(enrollment, { bloqueoHasta: 0 });
      }
    });
    throw error;
  }
});

async function closeForProducer(db, uid, { settlement, receptionIds, notification }) {
  const { liquidacionId, productorId, periodoInicio, periodoFin, numeroComprobante } = settlement || {};
  if (!isId(liquidacionId) || !isId(productorId) || !isId(notification?.notificacionId) ||
      !isDate(periodoInicio) || !isDate(periodoFin) || periodoFin < periodoInicio ||
      !/^COMP-\d{4}-\d{4,}$/.test(numeroComprobante || '') ||
      !Array.isArray(receptionIds) || receptionIds.length === 0 || receptionIds.length > 247 ||
      !receptionIds.every(isId) || new Set(receptionIds).size !== receptionIds.length ||
      !Number.isFinite(settlement.precioLitroAplicado) || settlement.precioLitroAplicado <= 0 ||
      typeof settlement.quincenaLabel !== 'string' || settlement.quincenaLabel.length > 120 ||
      typeof settlement.fechaLiquidacion !== 'string' || !Number.isFinite(Date.parse(settlement.fechaLiquidacion))) {
    throw new HttpsError('invalid-argument', 'El cierre contiene datos inválidos o supera 247 entregas para un productor.');
  }
  const receipt = db.collection('liquidaciones').doc(liquidacionId);
  const lock = db.collection('control_cierres').doc(productorId);
  const voucher = db.collection('control_comprobantes').doc(numeroComprobante);
  await db.runTransaction(async (transaction) => {
    const admin = await transaction.get(db.collection('usuarios').doc(uid));
    if (admin.get('activo') !== true || admin.get('rol') !== 'ADMIN') {
      throw new HttpsError('permission-denied', 'El cierre requiere una cuenta de administrador activa.');
    }
    const existing = await transaction.get(receipt);
    if (existing.exists && existing.get('hashIntegridad') === settlement.hashIntegridad) return;
    if (existing.exists) throw precondition('El identificador del comprobante ya está en uso.');
    await transaction.get(lock);
    const history = await transaction.get(db.collection('liquidaciones').where('productorId', '==', productorId));
    if (history.docs.some((doc) => doc.get('periodoInicio') <= periodoFin && doc.get('periodoFin') >= periodoInicio)) {
      throw precondition('El productor ya cuenta con una liquidación para el período. Actualiza los datos.');
    }
    const previousVoucher = await transaction.get(db.collection('liquidaciones')
      .where('numeroComprobante', '==', numeroComprobante).limit(1));
    if (!previousVoucher.empty) throw precondition('El consecutivo ya se utilizó. Actualiza los datos.');
    const deliveries = await transaction.get(db.collection('recepciones_leche')
      .where('productorId', '==', productorId)
      .where('fechaEntrega', '>=', periodoInicio).where('fechaEntrega', '<=', periodoFin)
      .orderBy('fechaEntrega', 'desc'));
    const eligible = deliveries.docs.filter((doc) => doc.get('anulado') !== true &&
      !doc.get('liquidacionId'));
    const ids = [...receptionIds].sort();
    if (eligible.map((doc) => doc.id).sort().join(',') !== ids.join(',') || eligible.some((doc) =>
      doc.get('isSynced') !== true || !Number.isFinite(doc.get('litros')) || doc.get('litros') <= 0)) {
      throw precondition('Las entregas del período cambiaron. Actualiza los datos antes de liquidar.');
    }
    const producer = await transaction.get(db.collection('productores').doc(productorId));
    if (!producer.exists) throw precondition('El productor ya no está disponible.');
    const totalMilliliters = eligible.reduce((sum, doc) => sum + Math.round(doc.get('litros') * 1000), 0);
    const priceCents = Math.round(settlement.precioLitroAplicado * 100);
    const totalCents = Math.round(totalMilliliters * priceCents / 1000);
    const idNumber = String(producer.get('cedula') || '').trim();
    const name = `${producer.get('nombres') || ''} ${producer.get('apellidos') || ''}`.trim();
    const hash = createHash('sha256').update([
      liquidacionId, numeroComprobante, productorId, idNumber, periodoInicio, periodoFin,
      totalMilliliters, ids.length, priceCents, totalCents, ids.join(','),
    ].join('|')).digest('hex');
    if (hash !== settlement.hashIntegridad || priceCents <= 0 || !Number.isSafeInteger(totalCents)) {
      throw precondition('La información usada en el cálculo cambió. Actualiza la previsualización.');
    }

    transaction.set(lock, { ultimoCierre: liquidacionId });
    transaction.create(voucher, { liquidacionId });
    const issued = {
      liquidacionId, productorId, periodoInicio, periodoFin, numeroComprobante,
      nombreProductorSnap: name, cedulaProductorSnap: idNumber,
      quincenaLabel: settlement.quincenaLabel,
      fechaLiquidacion: settlement.fechaLiquidacion,
      totalLitros: totalMilliliters / 1000,
      cantidadEntregas: ids.length,
      precioLitroAplicado: priceCents / 100,
      valorTotalPagar: totalCents / 100,
      estadoPago: 'PENDIENTE', fechaPago: null, observacionPago: null,
      hashIntegridad: hash, creadoPorUid: uid, recepcionIds: ids,
    };
    writeVersion(db, transaction, receipt, `liquidacion_${liquidacionId}`, null, issued, uid,
      'LIQUIDAR', settlement.quincenaLabel);
    for (const doc of eligible) {
      writeVersion(db, transaction, doc.ref, `cierre_${liquidacionId}_${doc.id}`, doc.data(),
        { ...doc.data(), liquidacionId }, uid, 'LIQUIDAR', numeroComprobante);
    }
    transaction.create(db.collection('notificaciones').doc(notification.notificacionId), {
      notificacionId: notification.notificacionId,
      titulo: `Liquidación ${settlement.quincenaLabel} disponible`,
      mensaje: `Consulta en la aplicación el comprobante ${numeroComprobante}.`,
      tipo: 'CIERRE_QUINCENA', destinoProductorId: productorId,
      fechaEnvio: issued.fechaLiquidacion, leida: false,
    });
  });
}

exports.closeMilkSettlements = onCall({ timeoutSeconds: 120 }, async ({ auth, data }) => {
  if (!auth) throw new HttpsError('unauthenticated', 'Inicia sesión para cerrar la quincena.');
  if (!Array.isArray(data?.groups) || data.groups.length === 0) {
    throw new HttpsError('invalid-argument', 'Selecciona entregas para liquidar.');
  }
  const db = getFirestore();
  let completed = 0;
  for (const group of data.groups) {
    try {
      await closeForProducer(db, auth.uid, group);
      completed++;
    } catch (error) {
      if (!(error instanceof HttpsError)) throw error;
      return { completed, error: error.message };
    }
  }
  return { completed };
});
