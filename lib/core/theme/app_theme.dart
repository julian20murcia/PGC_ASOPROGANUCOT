import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño oficial de ASOPROGANUCOT.
/// Estética clara Houston + Holstein con alto contraste y tipografía tabular.
class AppTheme {
  AppTheme._();

  // Superficies claras con contraste definido
  static const Color canvas = Color(0xFFEEF2F6);
  static const Color canvasAlt = Color(0xFFF7F9FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDF1F7);
  static const Color border = Color(0xFFD8E0EA);
  static const Color inputBorder = Color(0xFFC5CFD9);

  // Negro vaca Holstein para botones principales y estados activos
  static const Color cowBlack = Color(0xFF14161D);
  static const Color cowBlackHover = Color(0xFF282C38);
  static const Color cowCharcoal = Color(0xFF1D2230);

  // Verde pradera institucional
  static const Color primaryGreen = Color(0xFF0B6E4F);
  static const Color primaryGreenLight = Color(0xFFE5F6EF);

  // Tipografía de alto contraste
  static const Color textPrimary = Color(0xFF14161D);
  static const Color textSecondary = Color(0xFF424A59);
  static const Color textMuted = Color(0xFF717B8C);

  // Estados semánticos
  static const Color success = Color(0xFF00A240);
  static const Color successText = Color(0xFF006E2B);
  static const Color successBg = Color(0xFFE3F5EA);

  static const Color warning = Color(0xFFE0AC00);
  static const Color warningText = Color(0xFF7D5C00);
  static const Color warningBg = Color(0xFFFCF4D9);

  static const Color danger = Color(0xFFE02E2A);
  static const Color dangerText = Color(0xFFB3201D);
  static const Color dangerBg = Color(0xFFFCE8E8);

  static const double radiusCard = 12;
  static const double radiusControl = 8;
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

  static TextStyle titleStyle({
    bool isMobile = false,
    Color color = textPrimary,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: isMobile ? 21 : 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: color,
    );
  }

  static TextStyle subtitleStyle({Color color = textPrimary}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 16,
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
        primary: cowBlack,
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
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFCFCFD),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
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
          borderSide: const BorderSide(color: cowBlack, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cowBlack,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cowBlack,
          backgroundColor: surface,
          elevation: 0,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          side: const BorderSide(color: inputBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
  }
}
