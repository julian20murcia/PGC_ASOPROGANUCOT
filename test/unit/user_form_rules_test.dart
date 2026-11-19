import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/utils/input_rules.dart';
import 'package:pgc_asoproganucot/views/desktop/users/user_form_rules.dart';

String applyFormatters(List<TextInputFormatter> fs, String input) {
  TextEditingValue value = TextEditingValue.empty;
  // Simula escribir carácter por carácter, como en el teclado.
  for (int i = 0; i < input.length; i++) {
    final String next = value.text + input[i];
    TextEditingValue candidate = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    for (final TextInputFormatter f in fs) {
      candidate = f.formatEditUpdate(value, candidate);
    }
    value = candidate;
  }
  return value.text;
}

void main() {
  group('Formulario de usuario · nombre completo', () {
    test('acepta nombres reales con tildes y ñ', () {
      expect(UserFormRules.fullName('Ana María Gómez'), isNull);
      expect(UserFormRules.fullName('José Ñañez Peña'), isNull);
    });

    test('rechaza nombres absurdos', () {
      expect(UserFormRules.fullName(''), isNotNull);
      expect(UserFormRules.fullName('Juliaaaaaan Pérez'), 'Revisa letras repetidas');
      expect(UserFormRules.fullName('Julian'), 'Escribe nombre y apellido');
      expect(UserFormRules.fullName('Juan 123'), 'Solo se permiten letras');
      expect(UserFormRules.fullName('Ana <script>'), 'Solo se permiten letras');
      expect(UserFormRules.fullName('${'Abcde ' * 20}Final'), isNotNull);
    });

    test('el campo no deja escribir números, símbolos ni repeticiones largas', () {
      final List<TextInputFormatter> fs = AppInputs.personName(max: FieldLimits.fullName);
      expect(applyFormatters(fs, 'Juliaaaaannnnn 123 Pérez!!'), 'Juliaann Pérez');
      expect(applyFormatters(fs, 'A' * 200).length, lessThanOrEqualTo(FieldLimits.fullName));
    });
  });

  group('Formulario de usuario · documento, correo y celular', () {
    test('documento: solo dígitos y entre 5 y 12', () {
      expect(UserFormRules.document('1073500100'), isNull);
      expect(UserFormRules.document('10735abc'), 'Solo números');
      expect(UserFormRules.document('123'), isNotNull);
      expect(UserFormRules.document('1234567890123'), isNotNull);
      expect(UserFormRules.document('1111111'), 'Documento no válido');
      expect(applyFormatters(AppInputs.document(), 'CC 10.735.001-00 extra 99999999'), '107350010099');
    });

    test('correo inválido', () {
      expect(UserFormRules.email('ana@correo.com'), isNull);
      expect(UserFormRules.email('ana@correo'), 'Correo no válido');
      expect(UserFormRules.email('ana correo.com'), 'Correo no válido');
      expect(UserFormRules.email('@correo.com'), 'Correo no válido');
      expect(UserFormRules.email(''), 'El correo es obligatorio');
      expect(applyFormatters(AppInputs.email(), 'ana maría@co rreo.com'), 'anamara@correo.com');
    });

    test('celular opcional pero válido si se escribe', () {
      expect(UserFormRules.phone(''), isNull);
      expect(UserFormRules.phone('3101234567'), isNull);
      expect(UserFormRules.phone('12345'), isNotNull);
      expect(applyFormatters(AppInputs.phone(), '310-123-4567-999'), '3101234567');
    });
  });

  group('Formulario de usuario · contraseñas', () {
    test('contraseñas débiles se rechazan', () {
      expect(UserFormRules.password('', isRequired: true), 'La contraseña es obligatoria');
      expect(UserFormRules.password('abc12', isRequired: true), 'Mínimo 8 caracteres');
      expect(UserFormRules.password('abcdefgh', isRequired: true), 'Combina letras y números');
      expect(UserFormRules.password('12345678', isRequired: true), 'Combina letras y números');
      expect(UserFormRules.password('abc 12345', isRequired: true), 'Sin espacios');
      expect(UserFormRules.password('a1' * 40, isRequired: true), isNotNull);
      expect(UserFormRules.password('Leche2026', isRequired: true), isNull);
    });

    test('en edición la contraseña es opcional', () {
      expect(UserFormRules.password('', isRequired: false), isNull);
      expect(UserFormRules.password('corta1', isRequired: false), 'Mínimo 8 caracteres');
    });

    test('confirmación debe coincidir', () {
      expect(UserFormRules.confirmPassword('Leche2026', 'Leche2026'), isNull);
      expect(UserFormRules.confirmPassword('Leche2026', 'leche2026'), 'Las contraseñas no coinciden');
      expect(UserFormRules.confirmPassword('Leche2026', ''), 'Confirma la contraseña');
      expect(UserFormRules.confirmPassword('', ''), isNull);
    });

    test('medidor de fortaleza', () {
      expect(UserFormRules.strength(''), PasswordStrength.empty);
      expect(UserFormRules.strength('abcdefgh'), PasswordStrength.weak);
      expect(UserFormRules.strength('leche2026'), PasswordStrength.fair);
      expect(UserFormRules.strength('Leche2026'), PasswordStrength.good);
      expect(UserFormRules.strength('Leche-Fresca#2026'), PasswordStrength.strong);
    });
  });

  test('una cuenta de productor nueva exige productor vinculado', () {
    expect(
      UserFormRules.producerLink(role: AppConstants.roleProductor, productorId: null, isCreate: true),
      isNotNull,
    );
    expect(UserFormRules.producerLink(role: AppConstants.roleProductor, productorId: 'p-1', isCreate: true), isNull);
    expect(UserFormRules.producerLink(role: AppConstants.roleProductor, productorId: null, isCreate: false), isNull);
    expect(UserFormRules.producerLink(role: AppConstants.roleOperario, productorId: null, isCreate: true), isNull);
  });
}
