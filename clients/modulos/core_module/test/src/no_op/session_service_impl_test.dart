import 'package:core_module/src/no_op/session_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionServiceImpl', () {
    test('inicia com valores nulos', () {
      final session = SessionServiceImpl();
      expect(session.token, isNull);
      expect(session.tenantId, isNull);
    });

    test('salva sessão corretamente', () {
      final session = SessionServiceImpl();
      session.setSession(token: 'token_abc', tenantId: 'tenant_123');

      expect(session.token, 'token_abc');
      expect(session.tenantId, 'tenant_123');
    });

    test('limpa sessão corretamente', () {
      final session = SessionServiceImpl();
      session.setSession(token: 'token_abc', tenantId: 'tenant_123');
      session.clearSession();

      expect(session.token, isNull);
      expect(session.tenantId, isNull);
    });
  });
}
