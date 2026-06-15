import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_admin/auth_redirect.dart';

void main() {
  group('authRedirectTarget', () {
    test('durante o boot: mantém na splash e redireciona o resto para /', () {
      expect(
        authRedirectTarget(booted: false, isAuthenticated: false, location: '/'),
        isNull,
      );
      expect(
        authRedirectTarget(
            booted: false, isAuthenticated: false, location: '/home'),
        '/',
      );
    });

    test('pós-boot deslogado: vai para /login (e fica nele)', () {
      expect(
        authRedirectTarget(
            booted: true, isAuthenticated: false, location: '/home'),
        '/login',
      );
      expect(
        authRedirectTarget(
            booted: true, isAuthenticated: false, location: '/login'),
        isNull,
      );
    });

    test('pós-boot logado: sai do login/splash para /home', () {
      expect(
        authRedirectTarget(
            booted: true, isAuthenticated: true, location: '/login'),
        '/home',
      );
      expect(
        authRedirectTarget(booted: true, isAuthenticated: true, location: '/'),
        '/home',
      );
      expect(
        authRedirectTarget(
            booted: true, isAuthenticated: true, location: '/home'),
        isNull,
      );
    });
  });
}
