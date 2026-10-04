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
          location: '/',
        ),
        isNull,
      );
      expect(
        authRedirectTarget(
          booted: false,
          isAuthenticated: false,
          isSuperuser: false,
          location: '/home',
        ),
        '/',
      );
    });

    test('durante o boot: /login também redireciona para /', () {
      expect(
        authRedirectTarget(
          booted: false,
          isAuthenticated: false,
          isSuperuser: false,
          location: '/login',
        ),
        '/',
      );
    });

    test('pós-boot deslogado: a recuperação de senha é pública', () {
      // O superusuário também esquece a senha, e o LoginModule entrega as
      // duas telas a este app.
      for (final rota in ['/recuperar-senha', '/redefinir-senha']) {
        expect(
          authRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            location: rota,
          ),
          isNull,
          reason: '$rota deveria ser pública',
        );
      }
    });

    test('pós-boot deslogado: vai para /login (e fica nele)', () {
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: false,
          isSuperuser: false,
          location: '/home',
        ),
        '/login',
      );
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: false,
          isSuperuser: false,
          location: '/login',
        ),
        isNull,
      );
    });

    test('pós-boot logado SEM superusuário: é barrado e vai para /login', () {
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: true,
          isSuperuser: false,
          location: '/core-settings',
        ),
        '/login',
      );
    });

    test('pós-boot superusuário: sai do login/splash para o painel', () {
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: true,
          isSuperuser: true,
          location: '/login',
        ),
        '/core-settings',
      );
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: true,
          isSuperuser: true,
          location: '/',
        ),
        '/core-settings',
      );
      expect(
        authRedirectTarget(
          booted: true,
          isAuthenticated: true,
          isSuperuser: true,
          location: '/core-settings',
        ),
        isNull,
      );
    });
  });

  group('legacyAdminRedirect', () {
    test(
      'rota antiga /admin/<tela> vai para /<tela> (sem /v2/admin/admin)',
      () {
        expect(
          legacyAdminRedirect(Uri.parse('/admin/windows-downloads')),
          '/windows-downloads',
        );
        expect(
          legacyAdminRedirect(Uri.parse('/admin/billing?tenantId=42')),
          '/billing?tenantId=42',
        );
        expect(legacyAdminRedirect(Uri.parse('/admin')), '/');
      },
    );

    test('rotas atuais não são tocadas', () {
      expect(legacyAdminRedirect(Uri.parse('/windows-downloads')), isNull);
      expect(legacyAdminRedirect(Uri.parse('/login')), isNull);
      expect(legacyAdminRedirect(Uri.parse('/administracao')), isNull);
    });
  });
}
