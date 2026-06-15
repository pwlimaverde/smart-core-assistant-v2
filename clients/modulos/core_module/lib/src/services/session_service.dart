/// Contrato de acesso à sessão do usuário autenticado.
///
/// Guarda token e tenant em memória — proibido logar esses valores.
abstract interface class SessionService {
  String? get token;
  String? get tenantId;
  void setSession({required String token, String? tenantId});
  void clearSession();
}
