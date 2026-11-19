import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

/// Solicitud de rectificación de datos (Ley 1581 de 2012) enviada por un
/// productor desde la app móvil y atendida desde la plataforma de escritorio.
class RectificationRequest {
  const RectificationRequest({
    required this.id,
    required this.productorId,
    required this.codigoAsociado,
    required this.campo,
    required this.detalle,
    required this.fecha,
    required this.atendida,
    this.nombreProductor,
  });

  final String id;
  final String productorId;
  final String codigoAsociado;
  final String campo;
  final String detalle;
  final DateTime fecha;
  final bool atendida;
  final String? nombreProductor;

  RectificationRequest withName(String? name) => RectificationRequest(
        id: id,
        productorId: productorId,
        codigoAsociado: codigoAsociado,
        campo: campo,
        detalle: detalle,
        fecha: fecha,
        atendida: atendida,
        nombreProductor: name,
      );

  /// Interpreta el aviso `RECTIFICACION` que crea `NotificationService`:
  /// título `Solicitud Habeas Data · <código>` y mensaje
  /// `Campo: <campo> · Solicitud: <detalle>`.
  static RectificationRequest fromMap(String id, Map<String, dynamic> map) {
    final String titulo = (map['titulo'] ?? '').toString();
    final String mensaje = (map['mensaje'] ?? '').toString();
    final int dot = titulo.lastIndexOf('·');
    final String codigo = dot >= 0 ? titulo.substring(dot + 1).trim() : '';

    String campo = '';
    String detalle = mensaje.trim();
    final RegExpMatch? m = RegExp(r'^Campo:\s*(.*?)\s*·\s*Solicitud:\s*(.*)$', dotAll: true).firstMatch(mensaje);
    if (m != null) {
      campo = (m.group(1) ?? '').trim();
      detalle = (m.group(2) ?? '').trim();
    }

    final Object? rawDate = map['fechaEnvio'];
    DateTime fecha;
    if (rawDate is Timestamp) {
      fecha = rawDate.toDate().toUtc();
    } else {
      fecha = DateTime.tryParse((rawDate ?? '').toString())?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return RectificationRequest(
      id: id,
      productorId: (map['destinoProductorId'] ?? '').toString().trim(),
      codigoAsociado: codigo,
      campo: campo,
      detalle: detalle,
      fecha: fecha,
      atendida: map['leida'] == true,
    );
  }
}

/// Acceso en tiempo real a las solicitudes de rectificación para el personal.
class RectificationInboxService {
  RectificationInboxService({FirebaseFirestore? firestore}) : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  final Map<String, String> _nameCache = <String, String>{};

  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

  static const int maxItems = 100;

  /// Escucha las solicitudes más recientes (pendientes y atendidas).
  Stream<List<RectificationRequest>> watch() {
    return _db
        .collection(AppConstants.notificationsCollection)
        .where('tipo', isEqualTo: 'RECTIFICACION')
        .limit(maxItems)
        .snapshots()
        .asyncMap((QuerySnapshot<Map<String, dynamic>> snap) async {
      final List<RectificationRequest> items = snap.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => RectificationRequest.fromMap(d.id, d.data()))
          .toList()
        ..sort((RectificationRequest a, RectificationRequest b) => b.fecha.compareTo(a.fecha));
      return Future.wait(items.map((RectificationRequest r) async => r.withName(await _producerName(r.productorId))));
    });
  }

  Future<String?> _producerName(String productorId) async {
    if (productorId.isEmpty) return null;
    final String? cached = _nameCache[productorId];
    if (cached != null) return cached;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _db.collection(AppConstants.producersCollection).doc(productorId).get();
      final Map<String, dynamic>? data = doc.data();
      if (data == null) return null;
      final String name = '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}'.trim();
      if (name.isEmpty) return null;
      _nameCache[productorId] = name;
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Marca la solicitud como atendida (permitido al personal por `firestore.rules`).
  Future<void> markAttended(String id, {required String staffUid}) {
    return _db.collection(AppConstants.notificationsCollection).doc(id).update(<String, dynamic>{
      'leida': true,
      'atendidaPorUid': staffUid,
      'atendidaEn': FieldValue.serverTimestamp(),
    });
  }
}
