import '../services/session_service.dart';

/// Implementação em memória do SessionService para a base estrutural.
///
/// Token e refresh NÃO são logados — proibição de não-vazamento de credenciais.
final class SessionServiceImpl implements SessionService {
  String? _token;
  String? _tenantId;

  @override
  String? get token => _token;

  @override
  String? get tenantId => _tenantId;

  @override
  void setSession({required String token, String? tenantId}) {
    _token = token;
    _tenantId = tenantId;
  }

  @override
  void clearSession() {
    _token = null;
    _tenantId = null;
  }
}
