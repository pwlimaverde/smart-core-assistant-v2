import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_admin/auth_redirect.dart';

void main() {
  group('authRedirectTarget', () {
    test('durante o boot: mantém na splash e redireciona o resto para /', () {
      expect(
        authRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            location: '/'),
        isNull,
      );
      expect(
        authRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            location: '/home'),
        '/',
      );
    });

    test('durante o boot: /login também redireciona para /', () {
      expect(
        authRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            location: '/login'),
        '/',
      );
    });

    test('pós-boot deslogado: vai para /login (e fica nele)', () {
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            location: '/home'),
        '/login',
      );
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            location: '/login'),
        isNull,
      );
    });

    test('pós-boot logado SEM superusuário: é barrado e vai para /login', () {
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            location: '/admin/core-settings'),
        '/login',
      );
    });

    test('pós-boot superusuário: sai do login/splash para o painel', () {
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: true,
            location: '/login'),
        '/admin/core-settings',
      );
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: true,
            location: '/'),
        '/admin/core-settings',
      );
      expect(
        authRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: true,
            location: '/admin/core-settings'),
        isNull,
      );
    });
  });
}
