/// Contrato de autenticação.
///
/// Apenas `checkCurrentUser` está no escopo desta base (verificação de sessão
/// existente no boot). Login real entra com o `login_module`.
abstract interface class AuthService {
  Future<void> checkCurrentUser();
}
