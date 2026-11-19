import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_log_model.dart';
import '../constants/app_constants.dart';

/// Filtros de una consulta a `auditoria_logs`.
class AuditQuery {
  const AuditQuery({
    this.from,
    this.to,
    this.usuarioUid,
    this.limit = 100,
  });

  /// Inicio inclusivo (hora local o UTC).
  final DateTime? from;

  /// Fin exclusivo.
  final DateTime? to;
  final String? usuarioUid;
  final int limit;

  /// Rango del día local [start] 00:00 a [end] 23:59:59 (inclusivo).
  factory AuditQuery.forDays(DateTime start, DateTime end, {String? usuarioUid, int limit = 100}) {
    final DateTime a = DateTime(start.year, start.month, start.day);
    final DateTime b = DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
    return AuditQuery(from: a, to: b, usuarioUid: usuarioUid, limit: limit);
  }

  bool matches(AuditLogModel log) {
    if (usuarioUid != null && usuarioUid!.isNotEmpty && log.usuarioUid != usuarioUid) return false;
    if (from != null && log.timestamp.isBefore(from!.toUtc())) return false;
    if (to != null && !log.timestamp.isBefore(to!.toUtc())) return false;
    return true;
  }
}

/// Cursor opaco para seguir paginando. Mantiene un cursor por tipo de dato
/// del campo `timestamp` (Timestamp de Firestore y texto ISO), porque
/// Firestore ordena cada tipo por separado.
class AuditCursor {
  const AuditCursor({
    this.timestampCursor,
    this.isoCursor,
    this.timestampDone = false,
    this.isoDone = false,
    this.offset = 0,
  });

  final Object? timestampCursor;
  final Object? isoCursor;
  final bool timestampDone;
  final bool isoDone;

  /// Desplazamiento para fuentes en memoria.
  final int offset;
}

class AuditPage {
  const AuditPage({required this.logs, required this.hasMore, this.cursor});

  final List<AuditLogModel> logs;
  final bool hasMore;
  final AuditCursor? cursor;

  static const AuditPage empty = AuditPage(logs: <AuditLogModel>[], hasMore: false);
}

/// Consultas paginadas a la bitácora de auditoría.
///
/// Índice compuesto requerido para filtrar por usuario:
/// `auditoria_logs`: `usuarioUid ASC, timestamp DESC`.
abstract class AuditQueryService {
  Future<AuditPage> fetchPage(AuditQuery query, {AuditCursor? cursor});

  /// Descarga todas las páginas hasta [max] registros (para exportar).
  Future<List<AuditLogModel>> fetchAll(AuditQuery query, {int max = 3000}) async {
    final List<AuditLogModel> out = <AuditLogModel>[];
    AuditCursor? cursor;
    while (out.length < max) {
      final AuditPage page = await fetchPage(
        AuditQuery(from: query.from, to: query.to, usuarioUid: query.usuarioUid, limit: 250),
        cursor: cursor,
      );
      out.addAll(page.logs);
      if (!page.hasMore || page.cursor == null) break;
      cursor = page.cursor;
    }
    return out.length > max ? out.sublist(0, max) : out;
  }

  /// Une dos listas ya ordenadas (desc) y toma [limit] elementos. Devuelve
  /// cuántos se consumieron de cada una. Puro y probado en unit tests.
  static ({List<AuditLogModel> merged, int takenA, int takenB}) mergeDesc(
    List<AuditLogModel> a,
    List<AuditLogModel> b,
    int limit,
  ) {
    final List<AuditLogModel> merged = <AuditLogModel>[];
    int i = 0;
    int j = 0;
    while (merged.length < limit && (i < a.length || j < b.length)) {
      if (j >= b.length || (i < a.length && !a[i].timestamp.isBefore(b[j].timestamp))) {
        merged.add(a[i++]);
      } else {
        merged.add(b[j++]);
      }
    }
    return (merged: merged, takenA: i, takenB: j);
  }
}

/// Implementación sobre Cloud Firestore.
class FirestoreAuditQueryService extends AuditQueryService {
  FirestoreAuditQueryService({this.firestore});

  final FirebaseFirestore? firestore;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  static final DateTime _minDate = DateTime.utc(2000);

  Query<Map<String, dynamic>> _base(AuditQuery q) {
    Query<Map<String, dynamic>> query = _db.collection(AppConstants.auditLogsCollection);
    if (q.usuarioUid != null && q.usuarioUid!.isNotEmpty) {
      query = query.where('usuarioUid', isEqualTo: q.usuarioUid);
    }
    return query;
  }

  @override
  Future<AuditPage> fetchPage(AuditQuery q, {AuditCursor? cursor}) async {
    final int limit = q.limit.clamp(1, 500);
    final DateTime from = (q.from ?? _minDate).toUtc();
    final DateTime to = (q.to ?? DateTime.now().toUtc().add(const Duration(days: 1))).toUtc();

    // 1) Registros con Timestamp nativo (la gran mayoría).
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> tsQuery() async {
      if (cursor?.timestampDone == true) return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      Query<Map<String, dynamic>> query = _base(q)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('timestamp', isLessThan: Timestamp.fromDate(to))
          .orderBy('timestamp', descending: true);
      final Object? c = cursor?.timestampCursor;
      if (c is DocumentSnapshot) query = query.startAfterDocument(c);
      final QuerySnapshot<Map<String, dynamic>> snap = await query.limit(limit).get();
      return snap.docs;
    }

    // 2) Registros antiguos con `timestamp` guardado como texto ISO.
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> isoQuery() async {
      if (cursor?.isoDone == true) return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      try {
        Query<Map<String, dynamic>> query = _base(q)
            .where('timestamp', isGreaterThanOrEqualTo: from.toIso8601String())
            .where('timestamp', isLessThan: to.toIso8601String())
            .orderBy('timestamp', descending: true);
        final Object? c = cursor?.isoCursor;
        if (c is DocumentSnapshot) query = query.startAfterDocument(c);
        final QuerySnapshot<Map<String, dynamic>> snap = await query.limit(limit).get();
        return snap.docs;
      } catch (_) {
        // Si no hay registros de texto o falta un índice, no bloquear la consulta principal.
        return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      }
    }

    final List<List<QueryDocumentSnapshot<Map<String, dynamic>>>> results =
        await Future.wait(<Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[tsQuery(), isoQuery()]);
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> tsDocs = results[0];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> isoDocs = results[1];

    final List<AuditLogModel> a = tsDocs.map(_parse).toList();
    final List<AuditLogModel> b = isoDocs.map(_parse).toList();
    final ({List<AuditLogModel> merged, int takenA, int takenB}) m = AuditQueryService.mergeDesc(a, b, limit);

    final bool tsDone = cursor?.timestampDone == true || (tsDocs.length < limit && m.takenA == tsDocs.length);
    final bool isoDone = cursor?.isoDone == true || (isoDocs.length < limit && m.takenB == isoDocs.length);
    final AuditCursor next = AuditCursor(
      timestampCursor: m.takenA > 0 ? tsDocs[m.takenA - 1] : cursor?.timestampCursor,
      isoCursor: m.takenB > 0 ? isoDocs[m.takenB - 1] : cursor?.isoCursor,
      timestampDone: tsDone,
      isoDone: isoDone,
    );
    return AuditPage(logs: m.merged, hasMore: !(tsDone && isoDone), cursor: next);
  }

  static AuditLogModel _parse(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
      AuditLogModel.fromMap(doc.data(), documentId: doc.id);
}

/// Implementación en memoria (pruebas y respaldo sin conexión).
class InMemoryAuditQueryService extends AuditQueryService {
  InMemoryAuditQueryService(List<AuditLogModel> logs)
      : _logs = List<AuditLogModel>.from(logs)
          ..sort((AuditLogModel x, AuditLogModel y) => y.timestamp.compareTo(x.timestamp));

  final List<AuditLogModel> _logs;
  int calls = 0;

  @override
  Future<AuditPage> fetchPage(AuditQuery query, {AuditCursor? cursor}) async {
    calls++;
    final List<AuditLogModel> filtered = _logs.where(query.matches).toList();
    final int start = cursor?.offset ?? 0;
    if (start >= filtered.length) return AuditPage.empty;
    final int end = (start + query.limit).clamp(0, filtered.length);
    return AuditPage(
      logs: filtered.sublist(start, end),
      hasMore: end < filtered.length,
      cursor: AuditCursor(offset: end),
    );
  }
}
