import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño oficial de ASOPROGANUCOTT.
/// Paleta extraída del emblema oficial de Susa, Cundinamarca:
/// verde bosque profundo `#0C3B24`, verde pradera `#168A3E`, azul cielo andino `#0284C7`,
/// dorado cálido `#D97706` y superficies frescas en verde menta `#F6FAF7` / `#FFFFFF`.
class AppTheme {
  AppTheme._();

  // Superficies principales y neutros inspirados en el campo de Susa
  static const Color inkBlack = Color(0xFF0C3B24);
  static const Color canvas = Color(0xFFF6FAF7);
  static const Color canvasAlt = Color(0xFFEFF6F1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFECF3EE);
  static const Color border = Color(0xFFD5E4DA);
  static const Color dividerLight = Color(0xFFE3EEE7);
  static const Color inputBorder = Color(0xFFC1D6C8);

  // Variantes de verde bosque para controles primarios y navegación activa
  static const Color cowBlack = inkBlack;
  static const Color cowBlackHover = Color(0xFF134E31);
  static const Color cowCharcoal = Color(0xFF103322);

  // Colores cromáticos del escudo oficial de ASOPROGANUCOTT
  static const Color primaryGreen = Color(0xFF168A3E);
  static const Color primaryGreenLight = Color(0xFFE7F7EC);
  static const Color skyBlue = Color(0xFF0284C7);
  static const Color skyBlueLight = Color(0xFFE0F2FE);
  static const Color warmGold = Color(0xFFD97706);
  static const Color warmGoldLight = Color(0xFFFEF3C7);

  // Tipografía de alto contraste sobre fondos claros
  static const Color textPrimary = Color(0xFF0B2619);
  static const Color textSecondary = Color(0xFF395445);
  static const Color textMuted = Color(0xFF678072);

  // Estados semánticos
  static const Color success = Color(0xFF168A3E);
  static const Color successText = Color(0xFF0C3B24);
  static const Color successBg = Color(0xFFE7F7EC);

  static const Color warning = Color(0xFFD97706);
  static const Color warningText = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFEF3C7);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerText = Color(0xFF991B1B);
  static const Color dangerBg = Color(0xFFFEF2F2);

  static const double radiusCard = 8;
  static const double radiusControl = 6;
  static const double radiusBadge = 6;
  static const double radiusPill = 999;

  static TextStyle monoStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color color = textPrimary,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  static TextStyle serifStyle({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w600,
    Color color = textPrimary,
    double letterSpacing = -0.3,
    double? height,
  }) {
    return GoogleFonts.sourceSerif4(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle titleStyle({
    bool isMobile = false,
    Color color = textPrimary,
  }) {
    return GoogleFonts.sourceSerif4(
      fontSize: isMobile ? 21 : 23,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.35,
      color: color,
    );
  }

  static TextStyle subtitleStyle({Color color = textPrimary}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: color,
    );
  }

  static ThemeData lightTheme() {
    final TextTheme baseTextTheme = GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvas,
      textTheme: baseTextTheme,
      colorScheme: const ColorScheme.light(
        primary: inkBlack,
        onPrimary: Colors.white,
        secondary: primaryGreen,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        error: danger,
        onError: Colors.white,
        outline: border,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerLight,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13.5,
          color: textMuted,
          fontWeight: FontWeight.w400,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: inputBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: inkBlack, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: inkBlack,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: inkBlack,
          backgroundColor: surface,
          elevation: 0,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          side: const BorderSide(color: inputBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
  }
}
