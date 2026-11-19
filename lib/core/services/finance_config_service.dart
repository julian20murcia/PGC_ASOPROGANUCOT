import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/model_parse_helpers.dart';

/// Parámetros financieros de la asociación (`configuracion/finanzas`).
///
/// * [precioVentaLitro]: precio al que la asociación vende el litro a la
///   industria/cliente. La diferencia con la tarifa pagada al productor es el
///   margen bruto.
/// * [costoOperativoMensual]: costos fijos mensuales (transporte, tanque,
///   personal, energía). Se restan para estimar la ganancia o pérdida neta.
class FinanceConfig {
  const FinanceConfig({
    required this.precioVentaLitro,
    required this.costoOperativoMensual,
    this.actualizadoEn,
    this.actualizadoPorUid,
  });

  static const FinanceConfig empty =
      FinanceConfig(precioVentaLitro: 0, costoOperativoMensual: 0);

  final double precioVentaLitro;
  final double costoOperativoMensual;
  final DateTime? actualizadoEn;
  final String? actualizadoPorUid;

  bool get isConfigured => precioVentaLitro > 0;

  factory FinanceConfig.fromMap(Map<String, dynamic> map) => FinanceConfig(
        precioVentaLitro: parseSafeDouble(map['precioVentaLitro']),
        costoOperativoMensual: parseSafeDouble(map['costoOperativoMensual']),
        actualizadoEn: parseNullableUtcDate(map['actualizadoEn']),
        actualizadoPorUid: map['actualizadoPorUid'] as String?,
      );
}

class FinanceConfigService {
  FinanceConfigService({FirebaseFirestore? firestore}) : _db = firestore;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('configuracion').doc('finanzas');

  Future<FinanceConfig> load() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _doc.get().timeout(const Duration(seconds: 12));
      final Map<String, dynamic>? data = snap.data();
      return data == null ? FinanceConfig.empty : FinanceConfig.fromMap(data);
    } catch (_) {
      return FinanceConfig.empty;
    }
  }

  Future<void> save({
    required double precioVentaLitro,
    required double costoOperativoMensual,
    required String actorUid,
  }) async {
    if (!precioVentaLitro.isFinite || precioVentaLitro < 0 || precioVentaLitro > 99999) {
      throw ArgumentError('Precio de venta fuera de rango');
    }
    if (!costoOperativoMensual.isFinite ||
        costoOperativoMensual < 0 ||
        costoOperativoMensual > 999999999) {
      throw ArgumentError('Costo operativo fuera de rango');
    }
    await _doc.set(<String, dynamic>{
      'precioVentaLitro': precioVentaLitro,
      'costoOperativoMensual': costoOperativoMensual,
      'actualizadoEn': FieldValue.serverTimestamp(),
      'actualizadoPorUid': actorUid,
    });
  }
}
