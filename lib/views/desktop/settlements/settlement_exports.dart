import 'dart:typed_data';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/settlement_calculator.dart';
import '../../../core/services/settlement_pdf_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/settlement_model.dart';

/// Construcción de archivos (PDF / Excel / CSV) de una quincena cerrada.
class SettlementExports {
  SettlementExports._();

  static const List<String> _weekdays = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  static String baseName(SettlementPeriodGroup g) =>
      'Liquidacion_${g.periodoInicio}_a_${g.periodoFin}';

  static String _dayHeader(String iso) {
    final DateTime? d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${_weekdays[d.weekday - 1]} ${iso.substring(8)}/${iso.substring(5, 7)}';
  }

  static String _payment(SettlementModel s) =>
      s.isPagada ? 'PAGADA' : 'PENDIENTE';

  /// Hoja "Resumen" (concepto / valor).
  static TableSheet summarySheet(SettlementPeriodGroup g) {
    return TableSheet(
      name: 'Resumen',
      title: '${AppConstants.appName} · Liquidación ${g.label}',
      subtitle:
          'Período ${AppFormatters.formatIsoDate(g.periodoInicio)} al ${AppFormatters.formatIsoDate(g.periodoFin)}',
      columns: const <XlsxColumn>[
        XlsxColumn('Concepto', width: 30),
        XlsxColumn('Valor', width: 26),
      ],
      rows: <List<Object?>>[
        <Object?>['Quincena', g.label],
        <Object?>[
          'Fecha inicial',
          AppFormatters.formatIsoDate(g.periodoInicio),
        ],
        <Object?>['Fecha final', AppFormatters.formatIsoDate(g.periodoFin)],
        <Object?>['Fecha de cierre', AppFormatters.formatDateTime(g.closedAt)],
        <Object?>['Productores', '${g.producerCount}'],
        <Object?>['Entregas', '${g.deliveries}'],
        <Object?>['Litros totales', AppFormatters.formatLiters(g.totalLiters)],
        <Object?>[
          'Precio promedio por litro',
          AppFormatters.formatCurrency(g.averagePrice),
        ],
        <Object?>[
          'Valor total liquidado',
          AppFormatters.formatCurrency(g.totalAmount),
        ],
        <Object?>['Comprobantes pagados', '${g.paidCount}'],
        <Object?>['Valor pagado', AppFormatters.formatCurrency(g.paidAmount)],
        <Object?>['Comprobantes pendientes', '${g.pendingCount}'],
        <Object?>[
          'Valor pendiente',
          AppFormatters.formatCurrency(g.pendingAmount),
        ],
      ],
    );
  }

  /// Hoja "Productores" (una fila por comprobante).
  static TableSheet producersSheet(
    SettlementPeriodGroup g, {
    Map<String, String> codesByProducerId = const <String, String>{},
  }) {
    return TableSheet(
      name: 'Productores',
      title: 'Productores liquidados · ${g.label}',
      columns: const <XlsxColumn>[
        XlsxColumn('Código', width: 12),
        XlsxColumn('Productor', width: 32),
        XlsxColumn('Documento', width: 14),
        XlsxColumn('Comprobante', width: 18),
        XlsxColumn('Entregas', type: XlsxCellType.integer, width: 10),
        XlsxColumn('Litros', type: XlsxCellType.liters, width: 12),
        XlsxColumn('Precio por litro', type: XlsxCellType.money, width: 14),
        XlsxColumn('Valor a pagar', type: XlsxCellType.money, width: 16),
        XlsxColumn('Estado de pago', width: 14),
        XlsxColumn('Fecha de pago', width: 14),
        XlsxColumn('Observación de pago', width: 30),
        XlsxColumn('Código de verificación', width: 18),
      ],
      rows: <List<Object?>>[
        for (final SettlementModel s in g.settlements)
          <Object?>[
            codesByProducerId[s.productorId] ?? '',
            s.nombreProductorSnap,
            s.cedulaProductorSnap,
            s.numeroComprobante,
            s.cantidadEntregas,
            s.totalLitros,
            s.precioLitroAplicado,
            s.valorTotalPagar,
            _payment(s),
            s.fechaPago == null ? '' : AppFormatters.formatDate(s.fechaPago!),
            s.observacionPago ?? '',
            SettlementCalculator.verificationCode(s.hashIntegridad),
          ],
      ],
      totals: <Object?>[
        'TOTAL',
        '${g.producerCount} productores',
        null,
        null,
        g.deliveries,
        g.totalLiters,
        g.averagePrice,
        g.totalAmount,
        '${g.paidCount} pagadas',
        null,
        null,
        null,
      ],
    );
  }

  /// Hoja "Registros diarios": productores × días con columnas M/T.
  static TableSheet dailySheet(DailyDeliveryMatrix m, {String? label}) {
    final List<XlsxColumn> columns = <XlsxColumn>[
      const XlsxColumn('Código', width: 11),
      const XlsxColumn('Productor', width: 30),
      for (final String d in m.days) ...<XlsxColumn>[
        XlsxColumn('${_dayHeader(d)} M', type: XlsxCellType.liters, width: 10),
        XlsxColumn('${_dayHeader(d)} T', type: XlsxCellType.liters, width: 10),
      ],
      const XlsxColumn('Total mañana', type: XlsxCellType.liters, width: 13),
      const XlsxColumn('Total tarde', type: XlsxCellType.liters, width: 13),
      const XlsxColumn('Total litros', type: XlsxCellType.liters, width: 13),
    ];
    double? v(double x) => x <= 0 ? null : x;
    return TableSheet(
      name: 'Registros diarios',
      title: 'Registros diarios${label == null ? '' : ' · $label'}',
      subtitle: 'Litros por jornada: M = mañana, T = tarde',
      columns: columns,
      rows: <List<Object?>>[
        for (final DailyMatrixRow r in m.rows)
          <Object?>[
            r.codigo,
            r.nombre,
            for (final String d in m.days) ...<Object?>[
              v(r.cell(d).morning),
              v(r.cell(d).afternoon),
            ],
            r.totalMorning,
            r.totalAfternoon,
            r.total,
          ],
      ],
      totals: <Object?>[
        'TOTAL',
        null,
        for (final String d in m.days) ...<Object?>[
          m.columnTotal(d).morning,
          m.columnTotal(d).afternoon,
        ],
        m.grandMorning,
        m.grandAfternoon,
        m.grandTotal,
      ],
    );
  }

  /// Registros planos (una fila por entrega) para CSV.
  static TableSheet flatRecordsSheet(
    SettlementPeriodGroup g,
    List<MilkReceptionModel> receptions,
  ) {
    final Map<String, SettlementModel> byId = <String, SettlementModel>{
      for (final SettlementModel s in g.settlements) s.liquidacionId: s,
    };
    final List<MilkReceptionModel> sorted =
        receptions
            .where(
              (MilkReceptionModel r) =>
                  !r.anulado && byId.containsKey(r.liquidacionId),
            )
            .toList()
          ..sort((MilkReceptionModel a, MilkReceptionModel b) {
            final int c = a.fechaEntrega.compareTo(b.fechaEntrega);
            if (c != 0) return c;
            final int n = a.nombreProductorSnap.compareTo(
              b.nombreProductorSnap,
            );
            return n != 0 ? n : a.jornada.compareTo(b.jornada);
          });
    return TableSheet(
      name: 'Registros',
      columns: const <XlsxColumn>[
        XlsxColumn('Fecha'),
        XlsxColumn('Jornada'),
        XlsxColumn('Código'),
        XlsxColumn('Productor'),
        XlsxColumn('Litros', type: XlsxCellType.liters),
        XlsxColumn('Precio por litro', type: XlsxCellType.money),
        XlsxColumn('Valor', type: XlsxCellType.money),
        XlsxColumn('Comprobante'),
        XlsxColumn('Estado de pago'),
      ],
      rows: <List<Object?>>[
        for (final MilkReceptionModel r in sorted)
          <Object?>[
            r.fechaEntrega,
            r.jornada.toUpperCase() == AppConstants.shiftMorning
                ? 'Mañana'
                : 'Tarde',
            r.codigoAsociadoSnap,
            r.nombreProductorSnap,
            r.litros,
            byId[r.liquidacionId]!.precioLitroAplicado,
            SettlementCalculator.calculateTotalAmount(
              totalLiters: r.litros,
              pricePerLiter: byId[r.liquidacionId]!.precioLitroAplicado,
            ),
            byId[r.liquidacionId]!.numeroComprobante,
            _payment(byId[r.liquidacionId]!),
          ],
      ],
    );
  }

  /// Libro Excel con hojas "Resumen", "Registros diarios" y "Productores".
  static Uint8List buildXlsx({
    required SettlementPeriodGroup group,
    required DailyDeliveryMatrix matrix,
    Map<String, String> codesByProducerId = const <String, String>{},
  }) {
    return XlsxBuilder.build(<TableSheet>[
      summarySheet(group),
      dailySheet(matrix, label: group.label),
      producersSheet(group, codesByProducerId: codesByProducerId),
    ]);
  }

  /// Bytes del archivo para el [format] elegido.
  static Future<({Uint8List bytes, String baseName})> build({
    required ExportFormat format,
    required SettlementPeriodGroup group,
    required DailyDeliveryMatrix matrix,
    required List<MilkReceptionModel> receptions,
    Map<String, String> codesByProducerId = const <String, String>{},
  }) async {
    final Uint8List bytes = switch (format) {
      ExportFormat.pdf => await SettlementPdfService.buildPeriodReportPdfBytes(
        group: group,
        matrix: matrix,
        codesByProducerId: codesByProducerId,
      ),
      ExportFormat.xlsx => buildXlsx(
        group: group,
        matrix: matrix,
        codesByProducerId: codesByProducerId,
      ),
      ExportFormat.csv => CsvBuilder.build(flatRecordsSheet(group, receptions)),
    };
    return (bytes: bytes, baseName: baseName(group));
  }
}
