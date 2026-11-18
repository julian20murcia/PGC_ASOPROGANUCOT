import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño oficial de ASOPROGANUCOT.
/// Estética editorial de alto contraste: menú lateral en tinta negra `#0E1117`,
/// hoja principal en blanco puro `#FFFFFF`, acento esmeralda `#0D7A5F` y bordes `#E4E6EB`.
class AppTheme {
  AppTheme._();

  // Superficies principales y neutros editoriales
  static const Color inkBlack = Color(0xFF0E1117);
  static const Color canvas = Color(0xFFFFFFFF);
  static const Color canvasAlt = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F6F8);
  static const Color border = Color(0xFFE4E6EB);
  static const Color dividerLight = Color(0xFFECEEF2);
  static const Color inputBorder = Color(0xFFD3D7DF);

  // Alias de marca oscura para acciones principales y navegación activa
  static const Color cowBlack = inkBlack;
  static const Color cowBlackHover = Color(0xFF1A1F29);
  static const Color cowCharcoal = Color(0xFF171B24);

  // Verde pradera institucional
  static const Color primaryGreen = Color(0xFF0D7A5F);
  static const Color primaryGreenLight = Color(0xFFE8F6F1);

  // Tipografía de alto contraste
  static const Color textPrimary = Color(0xFF0E1117);
  static const Color textSecondary = Color(0xFF475162);
  static const Color textMuted = Color(0xFF7B8494);

  // Estados semánticos
  static const Color success = Color(0xFF10B981);
  static const Color successText = Color(0xFF065F46);
  static const Color successBg = Color(0xFFECFDF5);

  static const Color warning = Color(0xFFD97706);
  static const Color warningText = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFFFBEB);

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
