import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/services/voice_service.dart';

void main() {
  group('VoiceService', () {
    test('formatea litros para lectura natural en voz', () {
      expect(VoiceService.spokenLiters(32), '32');
      expect(VoiceService.spokenLiters(32.5), '32,5');
      expect(VoiceService.spokenLiters(18.04), '18');
    });

    test(
      'silenciar desactiva la lectura y no falla sin motor de voz',
      () async {
        final VoiceService voice = VoiceService.instance;
        voice.enabled = false;
        expect(voice.enabled, isFalse);
        await voice.speak('María Gómez');
        voice.toggle();
        expect(voice.enabled, isTrue);
        // En `flutter test` no hay plugin nativo: debe ignorarse sin excepción.
        await voice.speak('María Gómez');
      },
    );
  });
}
