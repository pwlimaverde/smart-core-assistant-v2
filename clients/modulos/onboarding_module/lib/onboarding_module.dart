/// Superfície pública do `onboarding_module`.
///
/// Expõe o módulo (composição no bootstrap) e o guard de rota do wizard. O
/// resto — controllers, páginas, cadeias de domínio — é detalhe interno.
library;

export 'src/onboarding_module.dart' show OnboardingModule;
export 'src/rota_publica.dart' show ehRotaDeCadastro;
