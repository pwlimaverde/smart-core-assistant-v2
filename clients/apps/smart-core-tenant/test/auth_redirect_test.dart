import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_tenant/auth_redirect.dart';

void main() {
  group('tenantAuthRedirectTarget', () {
    test('durante o boot: mantém na splash e redireciona o resto para /', () {
      expect(
        tenantAuthRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/'),
        isNull,
      );
      expect(
        tenantAuthRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/atendimentos'),
        '/',
      );
    });

    test('pós-boot deslogado: vai para /login (e fica nele)', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/atendimentos'),
        '/login',
      );
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/login'),
        isNull,
      );
    });

    test('pós-boot deslogado: /aceitar-convite é rota pública', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/aceitar-convite'),
        isNull,
      );
    });

    test('pós-boot deslogado: o wizard de cadastro é público', () {
      // Quem vai criar uma conta ainda não tem sessão; sem isto o guard
      // devolveria todo mundo para /login e o cadastro seria inalcançável.
      for (final rota in [
        '/cadastro',
        '/cadastro/plano',
        '/cadastro/pagamento',
        '/cadastro/pronto',
      ]) {
        expect(
          tenantAuthRedirectTarget(
              booted: true,
              isAuthenticated: false,
              isSuperuser: false,
              scopes: const [],
              location: rota),
          isNull,
          reason: '$rota deveria ser pública',
        );
      }
    });

    test('pós-boot superusuário puro: é barrado e vai para /login', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: true,
            scopes: const ['*'],
            location: '/atendimentos'),
        '/login',
      );
    });

    test('pós-boot sessão de tenant: sai do login/splash para o workspace', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/login'),
        '/atendimentos',
      );
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/'),
        '/atendimentos',
      );
    });

    test('pós-boot sessão de tenant sem tenant:admin: rotas /tenant/* voltam para o workspace', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/tenant/usuarios'),
        '/atendimentos',
      );
    });

    test('pós-boot sessão de tenant COM tenant:admin: acessa rotas /tenant/*', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/tenant/usuarios'),
        isNull,
      );
    });

    test('pós-boot sessão de tenant: rotas normais (não-/tenant/) seguem sem redirecionar', () {
      expect(
        tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/atendimentos'),
        isNull,
      );
    });
  });
}
