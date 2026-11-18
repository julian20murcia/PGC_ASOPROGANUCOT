/// Utilidades compartidas de formato numérico, monetario (COP) y de fechas
/// para escritorio, móvil y comprobantes PDF en ASOPROGANUCOTT.
class AppFormatters {
  AppFormatters._();

  /// Formatea valores en pesos colombianos (`$ 1.850` o `$ 1.850,25`).
  static String formatCurrency(
    double amount, {
    bool alwaysShowDecimals = false,
    String symbol = r'$ ',
  }) {
    final bool isNegative = amount < 0;
    final int totalCents = (amount.abs() * 100).round();
    final int wholePart = totalCents ~/ 100;
    final int centsPart = totalCents % 100;

    final String formattedWhole = _groupThousands(wholePart.toString());
    final String sign = isNegative ? '-' : '';

    if (alwaysShowDecimals || centsPart > 0) {
      final String centsStr = centsPart.toString().padLeft(2, '0');
      return '$sign$symbol$formattedWhole,$centsStr';
    }
    return '$sign$symbol$formattedWhole';
  }

  /// Formatea litros preservando hasta 2 decimales cuando son significativos.
  static String formatLiters(double liters, {bool withUnit = true}) {
    final double rounded = (liters * 100).roundToDouble() / 100;
    final int hundredths = (rounded * 100).round();
    final String unit = withUnit ? ' L' : '';
    final int whole = hundredths ~/ 100;
    final int dec = (hundredths % 100).abs();

    final String wholeStr = _groupThousands(whole.toString());
    if (dec == 0) {
      return '$wholeStr,0$unit';
    }
    if (dec % 10 == 0) {
      return '$wholeStr,${dec ~/ 10}$unit';
    }
    return '$wholeStr,${dec.toString().padLeft(2, '0')}$unit';
  }

  /// Convierte entrada manual COP (`1850`, `1.850`, `1850.50`, `1.850,50`) a `double`.
  static double? parseCurrencyInput(String raw) {
    final String cleaned = raw.replaceAll(RegExp(r'[^0-9.,]'), '').trim();
    if (cleaned.isEmpty) return null;

    if (cleaned.contains(',')) {
      final String normalized =
          cleaned.replaceAll('.', '').replaceAll(',', '.');
      return double.tryParse(normalized);
    }

    final List<String> dotParts = cleaned.split('.');
    if (dotParts.length == 2 && dotParts[1].length <= 2) {
      return double.tryParse(cleaned);
    }
    return double.tryParse(cleaned.replaceAll('.', ''));
  }

  /// Convierte `DateTime` a formato `dd/MM/yyyy` (hora local).
  static String formatDate(DateTime date, {bool useLocal = true}) {
    final DateTime d = useLocal ? date.toLocal() : date;
    return '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';
  }

  /// Convierte `DateTime` a formato `dd/MM/yyyy HH:mm` (hora local).
  static String formatDateTime(DateTime date, {bool useLocal = true}) {
    final DateTime d = useLocal ? date.toLocal() : date;
    return '${formatDate(d, useLocal: false)} ${_pad2(d.hour)}:${_pad2(d.minute)}';
  }

  /// Convierte `'YYYY-MM-DD'` a `'dd/MM/yyyy'`.
  static String formatIsoDate(String yyyyMmDd) {
    final List<String> parts = yyyyMmDd.trim().split('-');
    if (parts.length != 3) return yyyyMmDd;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  /// Convierte `DateTime` a `'YYYY-MM-DD'`.
  static String toIsoDate(DateTime date) =>
      '${date.year}-${_pad2(date.month)}-${_pad2(date.day)}';

  static String _groupThousands(String digits) {
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final int remaining = digits.length - i;
      buf.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buf.write('.');
      }
    }
    return buf.toString();
  }

  static String _pad2(int n) => n < 10 ? '0$n' : '$n';
}
