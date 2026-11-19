import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño "Pradera" de ASOPROGANUCOTT.
///
/// Identidad: teal profundo (confianza, campo, frescura) + ámbar lácteo
/// (el dorado de la leche y el sol de Susa) sobre neutros fríos y limpios.
/// Todas las pantallas deben consumir estos tokens; no usar colores sueltos.
class AppTheme {
  AppTheme._();

  static const String fontFamilyName = 'Inter';

  // ── Marca ────────────────────────────────────────────────────────────────
  static const Color brand = Color(0xFF0F766E); // teal 700
  static const Color brandHover = Color(0xFF115E59);
  static const Color brandDeep = Color(0xFF0B3B37); // superficies oscuras
  static const Color brandInk = Color(0xFF082826);
  static const Color brandSoft = Color(0xFFE7F5F2);
  static const Color brandMuted = Color(0xFFCDEAE4);
  static const Color accent = Color(0xFFE59E0B); // ámbar lácteo
  static const Color accentSoft = Color(0xFFFDF3DC);
  static const Color accentDeep = Color(0xFF9A5B00);

  // ── Neutros ──────────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFFF4F6F7);
  static const Color canvasAlt = Color(0xFFEDF1F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF7F9FA);
  static const Color surfaceSunken = Color(0xFFF0F3F4);
  static const Color border = Color(0xFFE2E7EA);
  static const Color borderStrong = Color(0xFFCBD3D8);
  static const Color dividerLight = Color(0xFFEEF1F3);
  static const Color inputBorder = Color(0xFFD3DADF);

  static const Color textPrimary = Color(0xFF0F1B1E);
  static const Color textSecondary = Color(0xFF4B5B61);
  static const Color textMuted = Color(0xFF8A979D);

  // ── Semánticos ───────────────────────────────────────────────────────────
  static const Color success = Color(0xFF059669);
  static const Color successText = Color(0xFF065F46);
  static const Color successBg = Color(0xFFE8F7F0);
  static const Color warning = Color(0xFFD97706);
  static const Color warningText = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFEF5E4);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerText = Color(0xFF991B1B);
  static const Color dangerBg = Color(0xFFFDEEEE);
  static const Color info = Color(0xFF2563EB);
  static const Color infoText = Color(0xFF1E40AF);
  static const Color infoBg = Color(0xFFEBF2FE);

  // ── Serie de gráficas (orden fijo, distinguibles entre sí) ──────────────
  static const Color chart1 = brand;
  static const Color chart2 = accent;
  static const Color chart3 = Color(0xFF4F6BED);
  static const Color chart4 = Color(0xFFE15D7A);
  static const Color chart5 = Color(0xFF7C8B91);
  static const List<Color> chartSeries = <Color>[
    chart1,
    chart2,
    chart3,
    chart4,
    chart5,
  ];

  // ── Alias heredados (compatibilidad con código anterior) ─────────────────
  static const Color inkBlack = brandDeep;
  static const Color cowBlack = brandDeep;
  static const Color cowBlackHover = brandHover;
  static const Color cowCharcoal = brandInk;
  static const Color primaryGreen = brand;
  static const Color primaryGreenLight = brandSoft;
  static const Color skyBlue = info;
  static const Color skyBlueLight = infoBg;
  static const Color warmGold = accent;
  static const Color warmGoldLight = accentSoft;
  static const Color tealAccent = brand;
  static const Color tealLight = brandSoft;
  static const Color indigoAccent = chart3;
  static const Color indigoLight = Color(0xFFEEF1FD);

  // ── Geometría ────────────────────────────────────────────────────────────
  static const double radiusCard = 10;
  static const double radiusControl = 8;
  static const double radiusBadge = 6;
  static const double radiusPill = 999;

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;

  static List<BoxShadow> get shadowSm => const <BoxShadow>[
        BoxShadow(
          color: Color(0x0A0F1B1E),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowMd => const <BoxShadow>[
        BoxShadow(
          color: Color(0x140F1B1E),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
        BoxShadow(
          color: Color(0x0A0F1B1E),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ];

  // ── Tipografía ───────────────────────────────────────────────────────────
  static TextStyle monoStyle({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color color = textPrimary,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: -0.1,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  static TextStyle serifStyle({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w700,
    Color color = textPrimary,
    double letterSpacing = -0.35,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle titleStyle({bool isMobile = false, Color color = textPrimary}) {
    return GoogleFonts.inter(
      fontSize: isMobile ? 19 : 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      color: color,
    );
  }

  static TextStyle subtitleStyle({Color color = textPrimary}) {
    return GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.15,
      color: color,
    );
  }

  /// Etiqueta pequeña en mayúsculas para encabezados de sección / columnas.
  static TextStyle overlineStyle({Color color = textMuted}) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: color,
    );
  }

  static TextStyle bodyStyle({
    double fontSize = 13,
    Color color = textSecondary,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static ThemeData lightTheme() {
    final TextTheme baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.light(useMaterial3: true).textTheme,
    ).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
      fontFamily: fontFamilyName,
    );

    OutlineInputBorder outline(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamilyName,
      scaffoldBackgroundColor: canvas,
      textTheme: baseTextTheme,
      primaryTextTheme: baseTextTheme,
      splashFactory: InkRipple.splashFactory,
      colorScheme: const ColorScheme.light(
        primary: brand,
        onPrimary: Colors.white,
        primaryContainer: brandSoft,
        onPrimaryContainer: brandInk,
        secondary: accent,
        onSecondary: Colors.white,
        secondaryContainer: accentSoft,
        onSecondaryContainer: accentDeep,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceSunken,
        error: danger,
        onError: Colors.white,
        outline: border,
        outlineVariant: dividerLight,
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
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: textPrimary,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: GoogleFonts.inter(
          fontSize: 13,
          color: textMuted,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: textSecondary),
        floatingLabelStyle: GoogleFonts.inter(fontSize: 13, color: brand),
        helperStyle: GoogleFonts.inter(fontSize: 11.5, color: textMuted),
        errorStyle: GoogleFonts.inter(fontSize: 11.5, color: danger),
        counterStyle: GoogleFonts.inter(fontSize: 11, color: textMuted),
        border: outline(inputBorder),
        enabledBorder: outline(inputBorder),
        disabledBorder: outline(dividerLight),
        focusedBorder: outline(brand, 1.5),
        errorBorder: outline(danger),
        focusedErrorBorder: outline(danger, 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: borderStrong,
          elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          elevation: 0,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: const BorderSide(color: inputBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
          ),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: borderStrong, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? brand : Colors.transparent,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? brand : borderStrong,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: brandMuted,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        elevation: 6,
        shadowColor: const Color(0x330F1B1E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border),
        ),
        textStyle: GoogleFonts.inter(fontSize: 13, color: textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13.5,
          color: textSecondary,
          height: 1.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
  }
}
