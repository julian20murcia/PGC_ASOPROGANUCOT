const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const SUPPORTED_PUSH_TYPES = new Set([
  'ENTREGA',
  'CIERRE_QUINCENA',
  'LIQUIDACION',
  'PAGO',
  'COMUNICADO',
]);

function safeTopicName(raw) {
  return `productor_${String(raw || '')
    .trim()
    .replace(/[^a-zA-Z0-9\-_.~%]/g, '_')}`;
}

/**
 * Envía alertas push automáticas mediante FCM HTTP v1 ante los eventos:
 * ENTREGA, CIERRE_QUINCENA, LIQUIDACION, PAGO y COMUNICADO (RF-23, RF-24, CHK-05).
 */
exports.onNotificationCreated = onDocumentCreated(
  'notificaciones/{notificacionId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const payload = snap.data() || {};
    const tipo = String(payload.tipo || 'COMUNICADO').trim().toUpperCase();
    if (!SUPPORTED_PUSH_TYPES.has(tipo)) {
      return null;
    }

    const notificacionId = String(
      payload.notificacionId || event.params.notificacionId || '',
    );
    const titulo = String(payload.titulo || 'Aviso ASOPROGANUCOTT');
    const mensaje = String(payload.mensaje || '');
    const destinoProductorId = payload.destinoProductorId
      ? String(payload.destinoProductorId).trim()
      : '';

    const dataPayload = {
      notificacionId,
      tipo,
      destinoProductorId,
      titulo,
      mensaje,
      fechaEnvio: String(payload.fechaEnvio || new Date().toISOString()),
    };

    const notificationBlock = {
      title: titulo,
      body: mensaje,
    };

    const androidConfig = {
      priority: 'high',
      notification: {
        channelId: 'asoproganucott_alerts',
        sound: 'default',
      },
    };

    const messaging = getMessaging();

    // Comunicado general masivo a todos los productores suscritos.
    if (!destinoProductorId) {
      return messaging.send({
        topic: 'asoproganucott_comunicados',
        notification: notificationBlock,
        data: dataPayload,
        android: androidConfig,
      });
    }

    // Notificación dirigida: enviar al tópico del productor y a tokens FCM registrados.
    const tasks = [
      messaging.send({
        topic: safeTopicName(destinoProductorId),
        notification: notificationBlock,
        data: dataPayload,
        android: androidConfig,
      }),
    ];

    const db = getFirestore();
    const producerDoc = await db
      .collection('productores')
      .doc(destinoProductorId)
      .get();

    const uidUsuario = producerDoc.exists
      ? String(producerDoc.data().uidUsuario || '').trim()
      : destinoProductorId;

    if (uidUsuario) {
      const userDoc = await db.collection('usuarios').doc(uidUsuario).get();
      const tokens = userDoc.exists && Array.isArray(userDoc.data().fcmTokens)
        ? userDoc.data().fcmTokens.filter((t) => typeof t === 'string' && t.trim().length > 0)
        : [];

      if (tokens.length > 0) {
        tasks.push(
          messaging.sendEachForMulticast({
            tokens,
            notification: notificationBlock,
            data: dataPayload,
            android: androidConfig,
          }),
        );
      }
    }

    return Promise.allSettled(tasks);
  },
);
