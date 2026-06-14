enum AppFlavor { dev, staging, prod }

/// Configuração imutável do app, injetada no escopo global no boot.
final class AppConfig {
  final AppFlavor flavor;
  final String apiEndpoint;
  final bool enableLogging;

  const AppConfig({
    required this.flavor,
    required this.apiEndpoint,
    this.enableLogging = false,
  });

  bool get isProd => flavor == AppFlavor.prod;
}
