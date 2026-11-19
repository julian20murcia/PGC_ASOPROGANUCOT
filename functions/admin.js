const { randomUUID } = require('node:crypto');
const { HttpsError, onCall } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { can, sanitizePermissions } = require('./permissions');

const ROLES = new Set(['ADMIN', 'OPERARIO', 'PRODUCTOR']);
const NAME_RE = /^[A-Za-zÁÉÍÓÚáéíóúÑñÜü' -]{2,80}$/;
const DOC_RE = /^\d{5,12}$/;
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const PHONE_RE = /^(3\d{9}|60\d{8})?$/;
const ID_RE = /^[\w-]{1,128}$/;

const bad = (msg) => new HttpsError('invalid-argument', msg);

/** Perfil activo del actor o error. */
async function actorProfile(db, auth) {
  if (!auth) throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  const snap = await db.collection('usuarios').doc(auth.uid).get();
  if (!snap.exists || snap.get('activo') !== true) {
    throw new HttpsError('permission-denied', 'Tu cuenta no está activa.');
  }
  return snap.data();
}

function cleanName(v) {
  return typeof v === 'string' ? v.trim().replace(/\s+/g, ' ') : '';
}

function validateCommon(data, { requirePassword }) {
  const nombreCompleto = cleanName(data?.nombreCompleto);
  const documento = typeof data?.documento === 'string' ? data.documento.trim() : '';
  const telefono = typeof data?.telefono === 'string' ? data.telefono.trim() : '';
  const rol = typeof data?.rol === 'string' ? data.rol.trim().toUpperCase() : '';
  const password = typeof data?.password === 'string' ? data.password : '';

  if (!NAME_RE.test(nombreCompleto) || nombreCompleto.split(' ').length < 2 || /(.)\1{2,}/i.test(nombreCompleto)) {
    throw bad('Escribe un nombre y apellido válidos (solo letras, máximo 80 caracteres).');
  }
  if (!DOC_RE.test(documento) || /^(\d)\1+$/.test(documento)) {
    throw bad('El documento debe tener entre 5 y 12 dígitos.');
  }
  if (!PHONE_RE.test(telefono)) throw bad('El teléfono debe ser un celular de 10 dígitos.');
  if (!ROLES.has(rol)) throw bad('Rol no válido.');
  if (typeof data?.activo !== 'boolean') throw bad('Estado no válido.');
  if (requirePassword || password) {
    if (password.length < 8 || password.length > 64 || !/[A-Za-z]/.test(password) ||
        !/\d/.test(password) || /\s/.test(password)) {
      throw bad('La contraseña debe tener entre 8 y 64 caracteres y combinar letras y números.');
    }
  }
  return { nombreCompleto, documento, telefono, rol, activo: data.activo, password };
}

/** Convierte Timestamps a ISO para devolver el perfil al cliente. */
function serializeProfile(uid, p) {
  const iso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v ?? null);
  const { fcmTokens: _tokens, ultimoAccesoLogId: _log, ...rest } = p;
  return {
    ...rest,
    uid,
    fcmTokens: [],
    fechaCreacion: iso(p.fechaCreacion),
    ultimoAcceso: iso(p.ultimoAcceso),
  };
}

function auditDoc(db, transaction, { entity, id, action, before, after, uid, reason }) {
  const logId = randomUUID();
  transaction.create(db.collection('auditoria_logs').doc(logId), {
    logId,
    entidadAfectada: entity,
    registroId: id,
    accion: action,
    valorAnterior: before ?? null,
    valorNuevo: after ?? null,
    motivo: reason ?? null,
    usuarioUid: uid,
    timestamp: FieldValue.serverTimestamp(),
  });
  return logId;
}

function publicView(p) {
  if (!p) return null;
  const { fcmTokens, ultimoAccesoLogId, sesionMovilId, sesionMovilAt, ...rest } = p;
  return rest;
}

exports.adminCreateUser = onCall({ maxInstances: 5, timeoutSeconds: 30 }, async ({ auth, data }) => {
  const db = getFirestore();
  const actor = await actorProfile(db, auth);
  if (!can(actor, 'usuarios', 'crear')) {
    throw new HttpsError('permission-denied', 'No tienes permiso para crear usuarios.');
  }
  const base = validateCommon(data, { requirePassword: true });
  const correo = typeof data?.correo === 'string' ? data.correo.trim().toLowerCase() : '';
  if (!EMAIL_RE.test(correo) || correo.length > 80) throw bad('El correo no es válido.');
  if (base.rol === 'ADMIN' && actor.rol !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Solo un administrador puede crear administradores.');
  }
  const permisos = base.rol === 'OPERARIO' && data?.permisos != null
    ? sanitizePermissions(data.permisos, actor) : null;
  const productorId = typeof data?.productorId === 'string' && data.productorId ? data.productorId : null;
  if (productorId && (!ID_RE.test(productorId) || base.rol !== 'PRODUCTOR')) {
    throw bad('Solo una cuenta de productor puede vincularse a un productor.');
  }

  const [byDoc, byEmail] = await Promise.all([
    db.collection('usuarios').where('documento', '==', base.documento).limit(1).get(),
    db.collection('usuarios').where('correo', '==', correo).limit(1).get(),
  ]);
  if (!byDoc.empty) throw new HttpsError('already-exists', `Ya existe un usuario con el documento ${base.documento}.`);
  if (!byEmail.empty) throw new HttpsError('already-exists', `Ya existe un usuario con el correo ${correo}.`);

  let record;
  try {
    record = await getAuth().createUser({
      email: correo,
      password: base.password,
      displayName: base.nombreCompleto,
      disabled: !base.activo,
    });
  } catch (e) {
    const code = e?.errorInfo?.code || e?.code || '';
    if (code.includes('email-already-exists')) {
      throw new HttpsError('already-exists', 'Ese correo ya tiene una cuenta de acceso registrada.');
    }
    if (code.includes('invalid-password')) throw bad('La contraseña no cumple los requisitos.');
    if (code.includes('invalid-email')) throw bad('El correo no es válido.');
    throw new HttpsError('internal', 'No fue posible crear la cuenta de acceso.');
  }

  const uid = record.uid;
  const profile = {
    uid,
    nombreCompleto: base.nombreCompleto,
    documento: base.documento,
    correo,
    telefono: base.telefono,
    rol: base.rol,
    activo: base.activo,
    fcmTokens: [],
    fechaCreacion: new Date().toISOString(),
    ultimoAcceso: null,
    ...(permisos ? { permisos } : {}),
  };

  try {
    await db.runTransaction(async (t) => {
      let producerRef = null;
      let producer = null;
      if (productorId) {
        producerRef = db.collection('productores').doc(productorId);
        const snap = await t.get(producerRef);
        if (!snap.exists) throw new HttpsError('not-found', 'El productor seleccionado no existe.');
        if (snap.get('uidUsuario')) {
          throw new HttpsError('already-exists', 'El productor ya tiene una cuenta de la app vinculada.');
        }
        producer = snap.data();
      }
      t.create(db.collection('usuarios').doc(uid), profile);
      auditDoc(db, t, {
        entity: 'usuarios', id: uid, action: 'CREAR', before: null,
        after: publicView(profile), uid: auth.uid, reason: null,
      });
      if (producerRef) {
        const logId = `vinculo_${uid}`;
        const after = { ...producer, uidUsuario: uid };
        t.set(producerRef, { ...after, auditLogId: logId, updatedAt: FieldValue.serverTimestamp(), updatedByUid: auth.uid });
        t.create(db.collection('auditoria_logs').doc(logId), {
          logId, entidadAfectada: 'productores', registroId: productorId, accion: 'EDITAR',
          valorAnterior: producer, valorNuevo: after, motivo: 'Vinculación de cuenta de la app móvil',
          usuarioUid: auth.uid, timestamp: FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (e) {
    // Rollback: no dejar cuentas de Auth huérfanas.
    await getAuth().deleteUser(uid).catch(() => {});
    if (e instanceof HttpsError) throw e;
    throw new HttpsError('internal', 'No fue posible guardar el perfil. No se creó la cuenta.');
  }
  return { user: serializeProfile(uid, profile) };
});

exports.adminUpdateUser = onCall({ maxInstances: 5, timeoutSeconds: 30 }, async ({ auth, data }) => {
  const db = getFirestore();
  const actor = await actorProfile(db, auth);
  if (!can(actor, 'usuarios', 'editar') && !can(actor, 'usuarios', 'eliminar')) {
    throw new HttpsError('permission-denied', 'No tienes permiso para modificar usuarios.');
  }
  const uid = typeof data?.uid === 'string' ? data.uid : '';
  if (!ID_RE.test(uid)) throw bad('Usuario no válido.');
  const base = validateCommon(data, { requirePassword: false });
  const ref = db.collection('usuarios').doc(uid);

  const result = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'El usuario no existe.');
    const before = snap.data();
    const isSelf = uid === auth.uid;
    if (isSelf && (base.rol !== before.rol || base.activo !== before.activo)) {
      throw new HttpsError('failed-precondition', 'No puedes cambiar tu propio rol ni suspender tu propia cuenta.');
    }
    if ((before.rol === 'ADMIN' || base.rol === 'ADMIN') && actor.rol !== 'ADMIN') {
      throw new HttpsError('permission-denied', 'Solo un administrador puede modificar administradores.');
    }
    const onlyStatusChange = base.activo !== before.activo &&
      base.nombreCompleto === before.nombreCompleto && base.documento === before.documento &&
      base.telefono === (before.telefono || '') && base.rol === before.rol && !base.password &&
      data?.permisos === undefined && !data?.resetPermisos;
    const needed = onlyStatusChange && !base.activo ? ['eliminar', 'editar'] : ['editar'];
    if (!needed.some((a) => can(actor, 'usuarios', a))) {
      throw new HttpsError('permission-denied', 'No tienes permiso para esta acción.');
    }
    if (before.rol === 'ADMIN' && (base.rol !== 'ADMIN' || !base.activo)) {
      const admins = await t.get(db.collection('usuarios').where('rol', '==', 'ADMIN').where('activo', '==', true));
      if (admins.docs.filter((d) => d.id !== uid).length === 0) {
        throw new HttpsError('failed-precondition', 'Debe existir al menos un administrador activo.');
      }
    }
    if (base.documento !== before.documento) {
      const dup = await t.get(db.collection('usuarios').where('documento', '==', base.documento).limit(2));
      if (dup.docs.some((d) => d.id !== uid)) {
        throw new HttpsError('already-exists', `Ya existe un usuario con el documento ${base.documento}.`);
      }
    }
    const next = {
      ...before,
      nombreCompleto: base.nombreCompleto,
      documento: base.documento,
      telefono: base.telefono,
      rol: base.rol,
      activo: base.activo,
    };
    if (base.rol !== 'OPERARIO' || data?.resetPermisos) {
      delete next.permisos;
    } else if (data?.permisos != null) {
      next.permisos = sanitizePermissions(data.permisos, actor);
    }
    t.set(ref, next);
    const changedPerms = JSON.stringify(before.permisos ?? null) !== JSON.stringify(next.permisos ?? null);
    auditDoc(db, t, {
      entity: 'usuarios', id: uid, action: 'EDITAR',
      before: publicView(before), after: publicView(next), uid: auth.uid,
      reason: [
        changedPerms ? 'Cambio de permisos' : null,
        base.password ? 'Cambio de contraseña' : null,
        before.activo !== next.activo ? (next.activo ? 'Cuenta activada' : 'Cuenta suspendida') : null,
      ].filter(Boolean).join(' · ') || null,
    });
    return next;
  });

  const authUpdate = { displayName: base.nombreCompleto, disabled: !base.activo };
  if (base.password) authUpdate.password = base.password;
  try {
    await getAuth().updateUser(uid, authUpdate);
    if (!base.activo) await getAuth().revokeRefreshTokens(uid);
  } catch (e) {
    const code = e?.errorInfo?.code || '';
    if (!code.includes('user-not-found')) {
      throw new HttpsError('internal', 'El perfil se actualizó, pero no la cuenta de acceso. Intenta de nuevo.');
    }
  }
  return { user: serializeProfile(uid, result) };
});
