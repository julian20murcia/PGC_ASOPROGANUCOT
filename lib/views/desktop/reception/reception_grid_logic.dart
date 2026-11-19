import '../../../core/constants/app_constants.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';

/// Lógica pura (sin widgets) de la planilla de recepción: parseo de litros,
/// navegación entre celdas, construcción de la matriz productor × día y
/// motivos automáticos de auditoría. Se prueba en `test/unit`.

// ─────────────────────────────────────────────────────────────────────────────
// Formato y parseo de litros
// ─────────────────────────────────────────────────────────────────────────────

/// Formato colombiano para litros: 14,5 · 1.250 · 12,75 (sin unidad).
String formatLitersCo(double value) =>
    ThousandsInputFormatter.format(value, decimals: 2);

/// Resultado de interpretar lo que el usuario escribió en una celda.
class LitersParseResult {
  const LitersParseResult._(this.value, this.error, this.isEmpty);

  const LitersParseResult.empty() : this._(null, null, true);
  const LitersParseResult.ok(double v) : this._(v, null, false);
  const LitersParseResult.invalid(String message)
    : this._(null, message, false);

  /// Litros válidos (redondeados a 2 decimales) o null.
  final double? value;

  /// Mensaje de error para mostrar en la celda.
  final String? error;

  /// El usuario dejó la celda vacía.
  final bool isEmpty;

  bool get isValid => value != null;
}

/// Interpreta la entrada de litros aceptando "12,5", "12.5", "1.250",
/// "1.250,75" y "1250". Rechaza letras, ceros, negativos y valores por encima
/// de [FieldLimits.maxLitersPerDelivery] (regla `litros <= 5000`).
LitersParseResult parseLitersInput(String raw) {
  final String text = raw.trim().replaceAll(' ', '');
  if (text.isEmpty) return const LitersParseResult.empty();
  if (!RegExp(r'^[0-9.,]+$').hasMatch(text)) {
    return const LitersParseResult.invalid('Solo se permiten números.');
  }
  if (!RegExp(r'[0-9]').hasMatch(text)) {
    return const LitersParseResult.invalid('Ingresa una cantidad válida.');
  }
  String normalized;
  if (text.contains(',')) {
    if (','.allMatches(text).length > 1) {
      return const LitersParseResult.invalid('Usa una sola coma decimal.');
    }
    normalized = text.replaceAll('.', '').replaceAll(',', '.');
  } else {
    final int dots = '.'.allMatches(text).length;
    if (dots == 1) {
      final String decimals = text.substring(text.indexOf('.') + 1);
      // "12.5" / "12.75" → decimal ; "1.250" → miles.
      normalized = decimals.length <= 2 ? text : text.replaceAll('.', '');
    } else {
      normalized = text.replaceAll('.', '');
    }
  }
  // Evita que cifras gigantes se conviertan en notación científica.
  final String intPart = normalized
      .split('.')
      .first
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (intPart.length > FieldLimits.litersIntDigits) {
    return const LitersParseResult.invalid('Máximo 5.000 L por entrega.');
  }
  final double? value = double.tryParse(normalized);
  if (value == null || !value.isFinite) {
    return const LitersParseResult.invalid('Ingresa una cantidad válida.');
  }
  final double rounded = (value * 100).roundToDouble() / 100;
  if (rounded < 0.01) {
    return const LitersParseResult.invalid(
      'Los litros deben ser mayores a cero.',
    );
  }
  if (rounded > FieldLimits.maxLitersPerDelivery) {
    return const LitersParseResult.invalid('Máximo 5.000 L por entrega.');
  }
  return LitersParseResult.ok(rounded);
}

/// Motivo de auditoría generado al corregir en la planilla (≥ 5 caracteres,
/// requisito de `firestore.rules`).
String autoCorrectionReason(
  double before,
  double after, {
  String origin = 'planilla',
}) =>
    'Corrección en $origin: ${formatLitersCo(before)} L → ${formatLitersCo(after)} L';

/// Motivo de auditoría al anular desde la planilla.
String autoAnnulReason(MilkReceptionModel r, {String origin = 'planilla'}) =>
    'Anulación en $origin: ${formatLitersCo(r.litros)} L del ${r.fechaEntrega} '
    '(${r.jornada == AppConstants.shiftAfternoon ? 'tarde' : 'mañana'})';

// ─────────────────────────────────────────────────────────────────────────────
// Rangos
// ─────────────────────────────────────────────────────────────────────────────

String isoOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Días (inclusive) entre [start] y [end].
List<DateTime> daysBetween(DateTime start, DateTime end) {
  final DateTime s = DateTime(start.year, start.month, start.day);
  final DateTime e = DateTime(end.year, end.month, end.day);
  final List<DateTime> out = <DateTime>[];
  for (
    DateTime d = s;
    !d.isAfter(e);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    out.add(d);
  }
  return out;
}

/// Filtra entregas cuya fecha ISO está en [startIso, endIso].
List<MilkReceptionModel> filterByIsoRange(
  Iterable<MilkReceptionModel> items,
  String startIso,
  String endIso,
) => items
    .where(
      (MilkReceptionModel r) =>
          r.fechaEntrega.compareTo(startIso) >= 0 &&
          r.fechaEntrega.compareTo(endIso) <= 0,
    )
    .toList();

// ─────────────────────────────────────────────────────────────────────────────
// Matriz productor × día × jornada
// ─────────────────────────────────────────────────────────────────────────────

/// Contenido de una celda (productor, día, jornada).
class PlanillaCell {
  PlanillaCell();

  /// Entregas activas (no anuladas).
  final List<MilkReceptionModel> active = <MilkReceptionModel>[];

  /// Entregas anuladas (solo informativas).
  final List<MilkReceptionModel> annulled = <MilkReceptionModel>[];

  bool get isEmpty => active.isEmpty;
  double get liters =>
      active.fold<double>(0, (double a, MilkReceptionModel r) => a + r.litros);

  /// Entrega única editable (null si vacía o si hay más de una).
  MilkReceptionModel? get single => active.length == 1 ? active.first : null;

  bool get hasMultiple => active.length > 1;
  bool get isSettled => active.any((MilkReceptionModel r) => r.isLiquidada);
  bool get isAnnulledOnly => active.isEmpty && annulled.isNotEmpty;
  bool get isPending => active.any(
    (MilkReceptionModel r) =>
        !r.isSynced || r.syncStatus != AppConstants.syncSynced,
  );
}

/// Fila de la planilla (un productor).
class PlanillaRow {
  PlanillaRow({
    required this.productorId,
    required this.codigo,
    required this.nombre,
    required this.isActiveProducer,
    required int dayCount,
    this.producer,
  }) : cells = List<PlanillaCell>.generate(dayCount * 2, (_) => PlanillaCell());

  final String productorId;
  final String codigo;
  final String nombre;
  final bool isActiveProducer;
  final ProducerModel? producer;

  /// Índice = día * 2 + jornada (0 = mañana, 1 = tarde).
  final List<PlanillaCell> cells;

  double get total =>
      cells.fold<double>(0, (double a, PlanillaCell c) => a + c.liters);
  double shiftTotal(int shift) {
    double t = 0;
    for (int i = shift; i < cells.length; i += 2) {
      t += cells[i].liters;
    }
    return t;
  }

  bool get hasDeliveries => cells.any((PlanillaCell c) => !c.isEmpty);
}

/// Matriz completa del rango.
class PlanillaMatrix {
  PlanillaMatrix({required this.days, required this.rows});

  final List<DateTime> days;
  final List<PlanillaRow> rows;

  int get columnCount => days.length * 2;

  static int shiftIndex(String jornada) =>
      jornada.toUpperCase() == AppConstants.shiftAfternoon ? 1 : 0;
  static String shiftOf(int col) =>
      col.isOdd ? AppConstants.shiftAfternoon : AppConstants.shiftMorning;

  DateTime dayOf(int col) => days[col ~/ 2];

  double columnTotal(int col) => rows.fold<double>(
    0,
    (double a, PlanillaRow r) => a + r.cells[col].liters,
  );
  double dayTotal(int day) => columnTotal(day * 2) + columnTotal(day * 2 + 1);
  double get grandTotal =>
      rows.fold<double>(0, (double a, PlanillaRow r) => a + r.total);

  /// Construye la matriz. Filas = productores activos (ordenados por código)
  /// más cualquier productor que haya entregado en el rango aunque ya no esté
  /// activo (solo lectura).
  static PlanillaMatrix build({
    required List<ProducerModel> activeProducers,
    required Iterable<MilkReceptionModel> receptions,
    required DateTime start,
    required DateTime end,
  }) {
    final List<DateTime> days = daysBetween(start, end);
    final Map<String, int> dayIndex = <String, int>{
      for (int i = 0; i < days.length; i++) isoOf(days[i]): i,
    };
    final Map<String, PlanillaRow> byId = <String, PlanillaRow>{};
    for (final ProducerModel p in activeProducers) {
      byId[p.productorId] = PlanillaRow(
        productorId: p.productorId,
        codigo: p.codigoAsociado,
        nombre: p.nombreCompleto,
        isActiveProducer: true,
        dayCount: days.length,
        producer: p,
      );
    }
    for (final MilkReceptionModel r in receptions) {
      final int? d = dayIndex[r.fechaEntrega];
      if (d == null) continue;
      final PlanillaRow row = byId.putIfAbsent(
        r.productorId,
        () => PlanillaRow(
          productorId: r.productorId,
          codigo: r.codigoAsociadoSnap,
          nombre: r.nombreProductorSnap,
          isActiveProducer: false,
          dayCount: days.length,
        ),
      );
      final PlanillaCell cell = row.cells[d * 2 + shiftIndex(r.jornada)];
      (r.anulado ? cell.annulled : cell.active).add(r);
    }
    final List<PlanillaRow> rows = byId.values.toList()
      ..sort((PlanillaRow a, PlanillaRow b) {
        final int c = a.codigo.toLowerCase().compareTo(b.codigo.toLowerCase());
        return c != 0 ? c : a.nombre.compareTo(b.nombre);
      });
    return PlanillaMatrix(days: days, rows: rows);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navegación tipo hoja de cálculo
// ─────────────────────────────────────────────────────────────────────────────

enum GridMove { up, down, left, right, next, previous, home, end }

class GridPos {
  const GridPos(this.row, this.col);
  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is GridPos && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'GridPos($row, $col)';
}

/// Calcula la celda destino. Flechas se detienen en los bordes; Tab /
/// Shift+Tab avanzan y saltan a la fila siguiente / anterior como Excel.
GridPos moveInGrid(
  GridPos from,
  GridMove move, {
  required int rows,
  required int cols,
}) {
  if (rows <= 0 || cols <= 0) return const GridPos(0, 0);
  final int r = from.row.clamp(0, rows - 1);
  final int c = from.col.clamp(0, cols - 1);
  switch (move) {
    case GridMove.up:
      return GridPos((r - 1).clamp(0, rows - 1), c);
    case GridMove.down:
      return GridPos((r + 1).clamp(0, rows - 1), c);
    case GridMove.left:
      return GridPos(r, (c - 1).clamp(0, cols - 1));
    case GridMove.right:
      return GridPos(r, (c + 1).clamp(0, cols - 1));
    case GridMove.next:
      if (c < cols - 1) return GridPos(r, c + 1);
      if (r < rows - 1) return GridPos(r + 1, 0);
      return GridPos(r, c);
    case GridMove.previous:
      if (c > 0) return GridPos(r, c - 1);
      if (r > 0) return GridPos(r - 1, cols - 1);
      return GridPos(r, c);
    case GridMove.home:
      return GridPos(r, 0);
    case GridMove.end:
      return GridPos(r, cols - 1);
  }
}

/// ¿El carácter tecleado debe iniciar la edición directa (como Excel)?
bool startsDirectEdit(String? character) =>
    character != null && RegExp(r'^[0-9]$').hasMatch(character);

/// Indica si se puede capturar en la fecha dada (no se aceptan fechas futuras).
bool isFutureDay(DateTime day, DateTime now) => DateTime(
  day.year,
  day.month,
  day.day,
).isAfter(DateTime(now.year, now.month, now.day));
