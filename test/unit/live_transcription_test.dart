import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/services/live_transcription.dart';

void main() {
  group('LiveTranscriptAssembler', () {
    test('acumula fragmentos mientras se habla', () {
      final LiveTranscriptAssembler a = LiveTranscriptAssembler();
      a.addDelta('i1', ' Haz');
      a.addDelta('i1', 'me');
      a.addDelta('i1', ' un informe');
      expect(a.text, 'Hazme un informe');
      expect(a.hasPending, isTrue);
    });

    test('la transcripción definitiva reemplaza los fragmentos', () {
      final LiveTranscriptAssembler a = LiveTranscriptAssembler();
      a.addDelta('i1', ' Haz me');
      a.complete('i1', 'Hazme un informe.');
      expect(a.text, 'Hazme un informe.');
      expect(a.hasPending, isFalse);
      a.addDelta('i1', ' tarde'); // deltas tardíos se ignoran
      expect(a.text, 'Hazme un informe.');
    });

    test('varios tramos (silenciar y seguir) se unen en orden de inicio', () {
      final LiveTranscriptAssembler a = LiveTranscriptAssembler();
      a.addDelta('i1', ' Primero');
      a.addDelta('i2', ' segundo');
      a.complete('i2', 'segundo tramo.');
      expect(a.text, 'Primero segundo tramo.');
      a.complete('i1', 'Primer tramo,');
      expect(a.text, 'Primer tramo, segundo tramo.');
    });

    test('tramos vacíos no dejan espacios dobles', () {
      final LiveTranscriptAssembler a = LiveTranscriptAssembler();
      a.complete('i1', '  ');
      a.addDelta('i2', '  hola   mundo ');
      expect(a.text, 'hola mundo');
      expect(LiveTranscriptAssembler().isEmpty, isTrue);
    });
  });
}
