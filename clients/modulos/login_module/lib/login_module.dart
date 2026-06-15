/// Superfície pública do `login_module`.
///
/// Expõe o módulo (composição no bootstrap), o contrato de auth e o modelo de
/// sessão. As implementações de data/presentation são detalhe interno.
library;

export 'src/login_module.dart' show LoginModule;
export 'src/features/login/domain/services/auth_service.dart' show AuthService;
export 'src/features/login/domain/model/session.dart' show Session;
