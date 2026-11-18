import 'model_parse_helpers.dart';

/// Entidad de liquidación quincenal y comprobante interno de pago (`liquidaciones`).
class SettlementModel {
  const SettlementModel({
    required this.liquidacionId,
    required this.productorId,
    required this.nombreProductorSnap,
    required this.cedulaProductorSnap,
    required this.periodoInicio,
    required this.periodoFin,
    required this.quincenaLabel,
    required this.totalLitros,
    required this.cantidadEntregas,
    required this.precioLitroAplicado,
    required this.valorTotalPagar,
    this.estadoPago = 'PENDIENTE',
    required this.fechaLiquidacion,
    this.fechaPago,
    this.observacionPago,
    required this.numeroComprobante,
    required this.hashIntegridad,
    required this.creadoPorUid,
  });

  final String liquidacionId;
  final String productorId;
  final String nombreProductorSnap;
  final String cedulaProductorSnap;
  final String periodoInicio; // YYYY-MM-DD
  final String periodoFin; // YYYY-MM-DD
  final String quincenaLabel;
  final double totalLitros;
  final int cantidadEntregas;
  final double precioLitroAplicado;
  final double valorTotalPagar;
  final String estadoPago; // PENDIENTE | PAGADA
  final DateTime fechaLiquidacion;
  final DateTime? fechaPago;
  final String? observacionPago;
  final String numeroComprobante;
  final String hashIntegridad;
  final String creadoPorUid;

  bool get isPagada => estadoPago.toUpperCase() == 'PAGADA';

  factory SettlementModel.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final String? obsRaw = map['observacionPago']?.toString().trim();
    return SettlementModel(
      liquidacionId: (map['liquidacionId'] ?? documentId ?? '').toString(),
      productorId: (map['productorId'] ?? '').toString(),
      nombreProductorSnap: (map['nombreProductorSnap'] ?? '').toString(),
      cedulaProductorSnap: (map['cedulaProductorSnap'] ?? '').toString(),
      periodoInicio: (map['periodoInicio'] ?? '').toString(),
      periodoFin: (map['periodoFin'] ?? '').toString(),
      quincenaLabel: (map['quincenaLabel'] ?? '').toString(),
      totalLitros: parseSafeDouble(map['totalLitros']),
      cantidadEntregas: parseSafeInt(map['cantidadEntregas']),
      precioLitroAplicado: parseSafeDouble(map['precioLitroAplicado']),
      valorTotalPagar: parseSafeDouble(map['valorTotalPagar']),
      estadoPago:
          (map['estadoPago'] ?? 'PENDIENTE').toString().trim().toUpperCase(),
      fechaLiquidacion: parseUtcDate(map['fechaLiquidacion']),
      fechaPago: parseNullableUtcDate(map['fechaPago']),
      observacionPago: (obsRaw == null || obsRaw.isEmpty) ? null : obsRaw,
      numeroComprobante: (map['numeroComprobante'] ?? '').toString(),
      hashIntegridad: (map['hashIntegridad'] ?? '').toString(),
      creadoPorUid: (map['creadoPorUid'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'liquidacionId': liquidacionId,
      'productorId': productorId,
      'nombreProductorSnap': nombreProductorSnap,
      'cedulaProductorSnap': cedulaProductorSnap,
      'periodoInicio': periodoInicio,
      'periodoFin': periodoFin,
      'quincenaLabel': quincenaLabel,
      'totalLitros': totalLitros,
      'cantidadEntregas': cantidadEntregas,
      'precioLitroAplicado': precioLitroAplicado,
      'valorTotalPagar': valorTotalPagar,
      'estadoPago': estadoPago.toUpperCase(),
      'fechaLiquidacion': fechaLiquidacion.toUtc().toIso8601String(),
      'fechaPago': fechaPago?.toUtc().toIso8601String(),
      'observacionPago': observacionPago,
      'numeroComprobante': numeroComprobante,
      'hashIntegridad': hashIntegridad,
      'creadoPorUid': creadoPorUid,
    };
  }

  SettlementModel copyWith({
    String? liquidacionId,
    String? productorId,
    String? nombreProductorSnap,
    String? cedulaProductorSnap,
    String? periodoInicio,
    String? periodoFin,
    String? quincenaLabel,
    double? totalLitros,
    int? cantidadEntregas,
    double? precioLitroAplicado,
    double? valorTotalPagar,
    String? estadoPago,
    DateTime? fechaLiquidacion,
    DateTime? fechaPago,
    String? observacionPago,
    String? numeroComprobante,
    String? hashIntegridad,
    String? creadoPorUid,
  }) {
    return SettlementModel(
      liquidacionId: liquidacionId ?? this.liquidacionId,
      productorId: productorId ?? this.productorId,
      nombreProductorSnap: nombreProductorSnap ?? this.nombreProductorSnap,
      cedulaProductorSnap: cedulaProductorSnap ?? this.cedulaProductorSnap,
      periodoInicio: periodoInicio ?? this.periodoInicio,
      periodoFin: periodoFin ?? this.periodoFin,
      quincenaLabel: quincenaLabel ?? this.quincenaLabel,
      totalLitros: totalLitros ?? this.totalLitros,
      cantidadEntregas: cantidadEntregas ?? this.cantidadEntregas,
      precioLitroAplicado: precioLitroAplicado ?? this.precioLitroAplicado,
      valorTotalPagar: valorTotalPagar ?? this.valorTotalPagar,
      estadoPago: estadoPago ?? this.estadoPago,
      fechaLiquidacion: fechaLiquidacion ?? this.fechaLiquidacion,
      fechaPago: fechaPago ?? this.fechaPago,
      observacionPago: observacionPago ?? this.observacionPago,
      numeroComprobante: numeroComprobante ?? this.numeroComprobante,
      hashIntegridad: hashIntegridad ?? this.hashIntegridad,
      creadoPorUid: creadoPorUid ?? this.creadoPorUid,
    );
  }
}
