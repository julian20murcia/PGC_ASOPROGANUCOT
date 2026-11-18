import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/audit_log_model.dart';
import '../constants/app_constants.dart';

/// Guarda la versión y su evento en la misma transacción de Firestore.
void writeAuditedVersion({
  required FirebaseFirestore db,
  required Transaction transaction,
  required DocumentReference<Map<String, dynamic>> record,
  required Map<String, dynamic>? before,
  required Map<String, dynamic> after,
  required AuditLogModel event,
}) {
  final Map<String, dynamic> version = <String, dynamic>{
    ...after,
    'auditLogId': event.logId,
    'updatedByUid': event.usuarioUid,
  }..remove('updatedAt');
  transaction.set(record, <String, dynamic>{
    ...version,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  transaction.set(
    db.collection(AppConstants.auditLogsCollection).doc(event.logId),
    <String, dynamic>{
      ...event.toMap(),
      'valorAnterior': before,
      'valorNuevo': version,
      'timestamp': FieldValue.serverTimestamp(),
    },
  );
}
