import '../services/auth_service.dart';

/// Impl no-op do AuthService — apenas fecha o boot sem lógica de negócio.
final class AuthServiceNoOp implements AuthService {
  @override
  Future<void> checkCurrentUser() async {}
}
