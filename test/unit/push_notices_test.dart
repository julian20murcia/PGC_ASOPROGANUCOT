import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/services/reception_service.dart';

void main() {
  final Map<String, dynamic> before = <String, dynamic>{
    'productorId': 'p1',
    'fechaEntrega': '2026-11-18',
    'jornada': 'TARDE',
    'litros': 20.5,
  };

  test('corrección de litros genera aviso dirigido al productor', () {
    final Map<String, dynamic> n = FirestoreReceptionDataSource.correctionNotice(
      logId: 'log1',
      before: before,
      changes: <String, dynamic>{'litros': 22},
      motivo: 'Error de digitación',
    );
    expect(n['tipo'], 'CORRECCION');
    expect(n['destinoProductorId'], 'p1');
    expect(n['notificacionId'], 'notif_correccion_log1');
    expect(n['mensaje'], contains('20,5 L → 22,0 L'));
    expect(n['mensaje'], contains('(tarde)'));
    expect(n['mensaje'], contains('Motivo: Error de digitación.'));
    expect(n['leida'], isFalse);
  });

  test('anulación genera aviso de anulación', () {
    final Map<String, dynamic> n = FirestoreReceptionDataSource.correctionNotice(
      logId: 'log2',
      before: before,
      changes: <String, dynamic>{'anulado': true},
    );
    expect(n['tipo'], 'ANULACION');
    expect(n['titulo'], 'Entrega anulada');
    expect(n['mensaje'], 'Se anuló tu entrega del 2026-11-18 (tarde) de 20,5 L.');
  });
}
