import 'package:flutter/material.dart';

/// Smart Core Tenant Theme
/// Branding Guide: infra/branding/BRANDING_GUIDE.md

class SCColors {
  // Primary Colors
  static const Color primary = Color(0xFF0066CC);      // Smart Core Blue
  static const Color primaryDark = Color(0xFF003D7A);  // Smart Core Dark Blue
  static const Color primaryLight = Color(0xFF4D9FFF); // Light Blue (dark mode)

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color textDark = Color(0xFF333333);
  static const Color textGray = Color(0xFF666666);
  static const Color bgLight = Color(0xFFF5F5F5);

  // Status Colors
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFE67E22);
  static const Color error = Color(0xFFE74C3C);
  static const Color info = Color(0xFF3498DB);

  // Dark Mode
  static const Color darkBg = Color(0xFF1E1E1E);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSuccess = Color(0xFF4CAF50);
  static const Color darkWarning = Color(0xFFFF9800);
  static const Color darkError = Color(0xFFF44336);
}

class SCTypography {
  static const String fontFamily = 'Segoe UI';
  static const String fontFamilyMono = 'Consolas';

  // Heading 1
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    height: 1.2,
    color: SCColors.textDark,
  );

  // Heading 2
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.2,
    color: SCColors.textDark,
  );

  // Heading 3
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SCColors.textDark,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
    color: SCColors.textDark,
  );

  // Body Small
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.5,
    color: SCColors.textGray,
  );

  // Button
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: SCColors.white,
  );

  // Caption
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.4,
    color: SCColors.textGray,
  );
}

class SmartCoreTheme {
  /// Light Theme
  static ThemeData lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      primaryColor: SCColors.primary,
      scaffoldBackgroundColor: SCColors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: SCColors.primary,
        foregroundColor: SCColors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: SCTypography.h3,
      ),
      textTheme: const TextTheme(
        displayLarge: SCTypography.h1,
        displayMedium: SCTypography.h2,
        displaySmall: SCTypography.h3,
        bodyLarge: SCTypography.body,
        bodyMedium: SCTypography.body,
        bodySmall: SCTypography.bodySmall,
        labelLarge: SCTypography.button,
        labelSmall: SCTypography.caption,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SCColors.primary,
          foregroundColor: SCColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: SCTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SCColors.primary,
          side: const BorderSide(color: SCColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: SCTypography.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SCColors.primary,
          textStyle: SCTypography.button,
        ),
      ),
      colorScheme: ColorScheme.light(
        primary: SCColors.primary,
        secondary: SCColors.primaryDark,
        error: SCColors.error,
        surface: SCColors.bgLight,
      ),
    );
  }

  /// Dark Theme
  static ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      primaryColor: SCColors.primaryLight,
      scaffoldBackgroundColor: SCColors.darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: SCColors.primaryDark,
        foregroundColor: SCColors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: SCTypography.h3,
      ),
      textTheme: TextTheme(
        displayLarge: SCTypography.h1.copyWith(color: SCColors.darkText),
        displayMedium: SCTypography.h2.copyWith(color: SCColors.darkText),
        displaySmall: SCTypography.h3.copyWith(color: SCColors.darkText),
        bodyLarge: SCTypography.body.copyWith(color: SCColors.darkText),
        bodyMedium: SCTypography.body.copyWith(color: SCColors.darkText),
        bodySmall: SCTypography.bodySmall.copyWith(color: Color(0xFFCCCCCC)),
        labelLarge: SCTypography.button.copyWith(color: SCColors.white),
        labelSmall: SCTypography.caption.copyWith(color: Color(0xFFCCCCCC)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SCColors.primaryLight,
          foregroundColor: SCColors.darkBg,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      colorScheme: ColorScheme.dark(
        primary: SCColors.primaryLight,
        secondary: SCColors.primaryDark,
        error: SCColors.darkError,
        surface: Color(0xFF2A2A2A),
      ),
    );
  }
}

/// Extension para fácil acesso às cores no contexto
extension SmartCoreColorExtension on BuildContext {
  SCColors get colors => SCColors();
  SCTypography get typography => SCTypography();
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
