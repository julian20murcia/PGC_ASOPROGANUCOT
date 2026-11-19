import 'package:flutter/services.dart';

/// Límites de longitud oficiales de la plataforma. Todo campo de texto debe
/// usar uno de estos valores (vía [AppInputs]) para que ningún dato pueda
/// desbordar la interfaz, los PDF ni Firestore.
class FieldLimits {
  FieldLimits._();

  static const int personName = 40; // nombres / apellidos por separado
  static const int fullName = 80;
  static const int document = 12; // cédula colombiana: 6–10, NIT/CE hasta 12
  static const int documentMin = 5;
  static const int phone = 10;
  static const int email = 80;
  static const int password = 64;
  static const int code = 12; // código de asociado
  static const int farmName = 60;
  static const int vereda = 40;
  static const int shortText = 120; // observaciones / motivos
  static const int longText = 500; // comunicados
  static const int title = 80;
  static const int search = 60;
  static const int chatMessage = 600;

  /// Máximo de dígitos enteros para litros (5.000 L por entrega según reglas).
  static const int litersIntDigits = 4;
  static const double maxLitersPerDelivery = 5000;

  /// Máximo de dígitos enteros para valores en pesos (hasta 999.999.999).
  static const int moneyIntDigits = 9;
  static const double maxPricePerLiter = 99999;
}

/// Formateador numérico con separador de miles colombiano ("10.000" o
/// "10.000,5"). Solo acepta dígitos (y una coma decimal si [decimals] > 0),
/// limita la cantidad de dígitos enteros y conserva el cursor al final.
class ThousandsInputFormatter extends TextInputFormatter {
  ThousandsInputFormatter({
    this.decimals = 0,
    this.maxIntegerDigits = 9,
  });

  final int decimals;
  final int maxIntegerDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String raw = newValue.text;
    if (raw.isEmpty) return newValue.copyWith(text: '');

    // El punto lo usamos como separador de miles: lo descartamos. La coma (o
    // un punto tecleado como último carácter) inicia la parte decimal.
    if (decimals > 0 &&
        raw.length > oldValue.text.length &&
        raw.endsWith('.') &&
        !oldValue.text.contains(',')) {
      raw = '${raw.substring(0, raw.length - 1)},';
    }

    final int commaIndex = decimals > 0 ? raw.indexOf(',') : -1;
    String intPart =
        (commaIndex >= 0 ? raw.substring(0, commaIndex) : raw)
            .replaceAll(RegExp(r'[^0-9]'), '');
    String? decPart = commaIndex >= 0
        ? raw.substring(commaIndex + 1).replaceAll(RegExp(r'[^0-9]'), '')
        : null;

    intPart = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (intPart.length > maxIntegerDigits) {
      return oldValue; // rechaza el excedente sin alterar lo escrito
    }
    if (decPart != null && decPart.length > decimals) {
      decPart = decPart.substring(0, decimals);
    }
    if (intPart.isEmpty && decPart == null) {
      return const TextEditingValue();
    }
    if (intPart.isEmpty) intPart = '0';

    final String grouped = groupThousands(intPart);
    final String text = decPart == null ? grouped : '$grouped,$decPart';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String groupThousands(String digits) {
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final int remaining = digits.length - i;
      buf.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }

  /// Convierte el texto formateado ("10.000,5") a número. Devuelve null si
  /// está vacío o no es finito.
  static double? parse(String text) {
    final String clean = text.trim().replaceAll('.', '').replaceAll(',', '.');
    if (clean.isEmpty) return null;
    final double? value = double.tryParse(clean);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  /// Formatea un número ya existente para precargarlo en un campo.
  static String format(num? value, {int decimals = 0}) {
    if (value == null || !value.isFinite) return '';
    final double v = value.toDouble();
    final int whole = v.truncate().abs();
    String text = groupThousands(whole.toString());
    if (decimals > 0) {
      final double frac = (v.abs() - whole);
      final String decStr =
          (frac * _pow10(decimals)).round().toString().padLeft(decimals, '0');
      final String trimmed = decStr.replaceFirst(RegExp(r'0+$'), '');
      if (trimmed.isNotEmpty) text = '$text,$trimmed';
    }
    return v < 0 ? '-$text' : text;
  }

  static int _pow10(int n) {
    int r = 1;
    for (int i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

/// Colapsa espacios repetidos y evita espacios iniciales.
class _CollapseSpacesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text =
        newValue.text.replaceAll(RegExp(r'\s{2,}'), ' ').replaceFirst(RegExp(r'^\s+'), '');
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Bloquea secuencias absurdas como "juliaaaaaaaaaannnnnn": no permite más de
/// [maxRepeat] caracteres idénticos consecutivos.
class _NoLongRepeatsFormatter extends TextInputFormatter {
  _NoLongRepeatsFormatter(this.maxRepeat);
  final int maxRepeat;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final RegExp repeat = RegExp('(.)\\1{$maxRepeat,}', caseSensitive: false);
    if (repeat.hasMatch(newValue.text)) return oldValue;
    return newValue;
  }
}

/// Paquetes de formateadores listos para usar en cada tipo de campo.
class AppInputs {
  AppInputs._();

  static final RegExp _nameChars = RegExp(r"[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ' \-]");

  /// Nombres de persona: solo letras, espacios, guion y apóstrofo.
  static List<TextInputFormatter> personName({int max = FieldLimits.personName}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(_nameChars),
        _CollapseSpacesFormatter(),
        _NoLongRepeatsFormatter(2),
        LengthLimitingTextInputFormatter(max),
      ];

  /// Texto general (fincas, veredas, títulos): letras, números y puntuación básica.
  static List<TextInputFormatter> text({int max = FieldLimits.shortText}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[<>{}\[\]\\^`|~]')),
        _CollapseSpacesFormatter(),
        _NoLongRepeatsFormatter(3),
        LengthLimitingTextInputFormatter(max),
      ];

  /// Texto multilínea (comunicados, observaciones largas).
  static List<TextInputFormatter> multiline({int max = FieldLimits.longText}) =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[<>{}\\^`|~]')),
        _NoLongRepeatsFormatter(4),
        LengthLimitingTextInputFormatter(max),
      ];

  /// Solo dígitos sin separadores (documentos, teléfonos).
  static List<TextInputFormatter> digits(int max) => <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(max),
      ];

  static List<TextInputFormatter> document() => digits(FieldLimits.document);
  static List<TextInputFormatter> phone() => digits(FieldLimits.phone);

  /// Código de asociado: letras mayúsculas, dígitos y guion.
  static List<TextInputFormatter> code() => <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
        _UpperCaseFormatter(),
        LengthLimitingTextInputFormatter(FieldLimits.code),
      ];

  static List<TextInputFormatter> email() => <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9@._+\-]')),
        LengthLimitingTextInputFormatter(FieldLimits.email),
      ];

  static List<TextInputFormatter> password() => <TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
        LengthLimitingTextInputFormatter(FieldLimits.password),
      ];

  /// Litros: miles con punto, hasta 2 decimales, máx. 4 dígitos enteros.
  static List<TextInputFormatter> liters() => <TextInputFormatter>[
        ThousandsInputFormatter(
          decimals: 2,
          maxIntegerDigits: FieldLimits.litersIntDigits,
        ),
      ];

  /// Pesos colombianos: miles con punto, hasta 2 decimales.
  static List<TextInputFormatter> money({
    int maxIntegerDigits = FieldLimits.moneyIntDigits,
    int decimals = 2,
  }) =>
      <TextInputFormatter>[
        ThousandsInputFormatter(
          decimals: decimals,
          maxIntegerDigits: maxIntegerDigits,
        ),
      ];

  /// Enteros con miles (cantidades).
  static List<TextInputFormatter> integer({int maxDigits = 9}) =>
      <TextInputFormatter>[ThousandsInputFormatter(maxIntegerDigits: maxDigits)];
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Validadores reutilizables (devuelven mensaje de error o null).
class AppValidators {
  AppValidators._();

  static final RegExp _email =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
  static final RegExp _repeat = RegExp(r'(.)\1{2,}', caseSensitive: false);

  static String? required(String? v, [String label = 'Este campo']) {
    if (v == null || v.trim().isEmpty) return '$label es obligatorio';
    return null;
  }

  static String? personName(String? v, {String label = 'El nombre'}) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return '$label es obligatorio';
    if (s.length < 2) return '$label es demasiado corto';
    if (s.length > FieldLimits.personName) {
      return 'Máximo ${FieldLimits.personName} caracteres';
    }
    if (!RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ' \-]+$").hasMatch(s)) {
      return 'Solo se permiten letras';
    }
    if (_repeat.hasMatch(s)) return 'Revisa letras repetidas';
    return null;
  }

  static String? fullName(String? v) {
    final String s = (v ?? '').trim();
    final String? base = personName(s, label: 'El nombre completo');
    if (base != null && !base.startsWith('Máximo')) return base;
    if (s.length > FieldLimits.fullName) {
      return 'Máximo ${FieldLimits.fullName} caracteres';
    }
    if (s.split(RegExp(r'\s+')).length < 2) {
      return 'Escribe nombre y apellido';
    }
    return null;
  }

  static String? document(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return 'El documento es obligatorio';
    if (!RegExp(r'^\d+$').hasMatch(s)) return 'Solo números';
    if (s.length < FieldLimits.documentMin || s.length > FieldLimits.document) {
      return 'Entre ${FieldLimits.documentMin} y ${FieldLimits.document} dígitos';
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(s)) return 'Documento no válido';
    return null;
  }

  static String? phone(String? v, {bool required = true}) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return required ? 'El teléfono es obligatorio' : null;
    if (!RegExp(r'^3\d{9}$').hasMatch(s) && !RegExp(r'^60\d{8}$').hasMatch(s)) {
      return 'Celular de 10 dígitos (ej. 3101234567)';
    }
    return null;
  }

  static String? email(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return 'El correo es obligatorio';
    if (s.length > FieldLimits.email) return 'Correo demasiado largo';
    if (!_email.hasMatch(s)) return 'Correo no válido';
    return null;
  }

  static String? password(String? v, {bool required = true}) {
    final String s = v ?? '';
    if (s.isEmpty) return required ? 'La contraseña es obligatoria' : null;
    if (s.length < 8) return 'Mínimo 8 caracteres';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Combina letras y números';
    }
    return null;
  }

  static String? text(
    String? v, {
    String label = 'Este campo',
    int min = 2,
    int max = FieldLimits.shortText,
    bool required = true,
  }) {
    final String s = (v ?? '').trim();
    if (s.isEmpty) return required ? '$label es obligatorio' : null;
    if (s.length < min) return 'Mínimo $min caracteres';
    if (s.length > max) return 'Máximo $max caracteres';
    if (RegExp(r'(.)\1{4,}').hasMatch(s)) return 'Revisa caracteres repetidos';
    return null;
  }

  static String? liters(String? v) {
    final double? n = ThousandsInputFormatter.parse(v ?? '');
    if (n == null) return 'Ingresa los litros';
    if (n <= 0) return 'Debe ser mayor a 0';
    if (n > FieldLimits.maxLitersPerDelivery) {
      return 'Máximo ${ThousandsInputFormatter.format(FieldLimits.maxLitersPerDelivery)} L';
    }
    return null;
  }

  static String? money(String? v, {double min = 1, double max = 999999999}) {
    final double? n = ThousandsInputFormatter.parse(v ?? '');
    if (n == null) return 'Ingresa un valor';
    if (n < min) return 'Debe ser mayor o igual a ${ThousandsInputFormatter.format(min)}';
    if (n > max) return 'Máximo ${ThousandsInputFormatter.format(max)}';
    return null;
  }
}
