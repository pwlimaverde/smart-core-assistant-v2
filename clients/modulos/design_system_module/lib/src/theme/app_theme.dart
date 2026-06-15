import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';

/// Temas Material 3 do design system.
abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surfaceLight,
      error: AppColors.error,
      onPrimary: AppColors.onPrimary,
      onSurface: AppColors.onSurfaceLight,
      onError: AppColors.onError,
    ),
    scaffoldBackgroundColor: AppColors.backgroundLight,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
      onPrimary: AppColors.onPrimary,
      onSurface: AppColors.onSurface,
      onError: AppColors.onError,
    ),
    scaffoldBackgroundColor: AppColors.background,
  );
}
