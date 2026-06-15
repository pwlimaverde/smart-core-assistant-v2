import 'package:flutter/material.dart';

/// Paleta de cores do design system.
abstract final class AppColors {
  static const Color primary = Color(0xFF1E88E5);
  static const Color primaryVariant = Color(0xFF1565C0);
  static const Color secondary = Color(0xFF26C6DA);
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color error = Color(0xFFCF6679);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFFE0E0E0);
  static const Color onSurface = Color(0xFFE0E0E0);
  static const Color onError = Color(0xFF000000);

  // Variantes claras
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color onBackgroundLight = Color(0xFF121212);
  static const Color onSurfaceLight = Color(0xFF121212);
}
