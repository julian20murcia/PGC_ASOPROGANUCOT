const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const logger = require('firebase-functions/logger');

initializeApp();

Object.assign(exports, require('./compliance'));
const admin = require('./admin');
exports.adminCreateUser = admin.adminCreateUser;
exports.adminUpdateUser = admin.adminUpdateUser;
exports.askAssistant = require('./assistant').askAssistant;
exports.transcribeAudio = require('./assistant').transcribeAudio;
exports.createVoiceSession = require('./assistant').createVoiceSession;

const SUPPORTED_PUSH_TYPES = new Set([
  'ENTREGA',
  'CIERRE_QUINCENA',
  'LIQUIDACION',
  'PAGO',
  'COMUNICADO',
  'CORRECCION',
  'ANULACION',
  'TARIFA',
]);

// Avisos que se envían a TODOS los productores (tópico) cuando no tienen destino.
const BROADCAST_TYPES = new Set(['COMUNICADO', 'TARIFA']);

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
      logger.info('push omitido: tipo sin envío push', { tipo, notificacionId: event.params.notificacionId });
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
        icon: 'ic_stat_notification',
        color: '#0F766E',
      },
    };

    const messaging = getMessaging();

    // Comunicado general masivo a todos los productores suscritos.
    if (!destinoProductorId) {
      if (!BROADCAST_TYPES.has(tipo)) {
        logger.info('push omitido: aviso sin destinatario', { tipo, notificacionId });
        return null;
      }
      const messageId = await messaging.send({
        topic: 'asoproganucott_comunicados',
        notification: notificationBlock,
        data: dataPayload,
        android: androidConfig,
      });
      logger.info('push enviado al tema de comunicados', { tipo, notificacionId, messageId });
      return messageId;
    }

    const db = getFirestore();
    const producerDoc = await db
      .collection('productores')
      .doc(destinoProductorId)
      .get();

    const uidUsuario = producerDoc.exists
      ? String(producerDoc.data().uidUsuario || '').trim()
      : destinoProductorId;

    if (!uidUsuario) {
      logger.info('push omitido: el productor no tiene cuenta en la app', { tipo, notificacionId, destinoProductorId });
      return null;
    }
    const account = await db.collection('usuarios').doc(uidUsuario).get();
    if (account.get('activo') !== true || account.get('rol') !== 'PRODUCTOR') {
      logger.info('push omitido: cuenta inactiva o sin rol de productor', { tipo, notificacionId, destinoProductorId });
      return null;
    }
    const savedTokens = account.get('fcmTokens');
    const tokens = Array.isArray(savedTokens)
      ? savedTokens.filter((token) => typeof token === 'string' && token.trim().length > 0)
      : [];
    if (tokens.length === 0) {
      logger.info('push omitido: la cuenta no tiene celular registrado', { tipo, notificacionId, destinoProductorId });
      return null;
    }
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: notificationBlock,
      data: {
        ...dataPayload,
        refrescarAvisos: 'true',
      },
      android: androidConfig,
    });

    const staleTokens = [];
    response.responses.forEach((res, idx) => {
      if (res.success || !res.error) return;
      const code = String(res.error.code || '');
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        staleTokens.push(tokens[idx]);
      }
    });
    logger.info('push enviado al productor', {
      tipo,
      notificacionId,
      destinoProductorId,
      dispositivos: tokens.length,
      exitosos: response.successCount,
      fallidos: response.failureCount,
      tokensVencidos: staleTokens.length,
    });
    if (staleTokens.length > 0) {
      await db.collection('usuarios').doc(uidUsuario).update({
        fcmTokens: FieldValue.arrayRemove(...staleTokens),
      });
    }
    return response;
  },
);
