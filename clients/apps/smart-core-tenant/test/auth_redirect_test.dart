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
          location: '/',
        ),
        isNull,
      );
      final alvo = Uri.parse(
        tenantAuthRedirectTarget(
          booted: false,
          isAuthenticated: false,
          isSuperuser: false,
          scopes: const [],
          location: '/atendimentos',
        )!,
      );
      expect(alvo.path, '/');
      expect(alvo.queryParameters['retomar'], '/atendimentos');
    });

    group('link aberto antes do boot terminar', () {
      // Regressão do teste de 12/09: o link do convite passava pela splash,
      // perdia o endereço e caía no login — a tela de criar senha nunca
      // aparecia para o convidado.
      test('a ida para a splash guarda o endereço com a query', () {
        final alvo = Uri.parse(
          tenantAuthRedirectTarget(
            booted: false,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/aceitar-convite',
            enderecoPedido: '/aceitar-convite?token=abc123',
          )!,
        );
        expect(alvo.path, '/');
        expect(
          alvo.queryParameters['retomar'],
          '/aceitar-convite?token=abc123',
        );
      });

      test('ao fim do boot, deslogado, volta ao convite com o token', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/',
            retomar: '/aceitar-convite?token=abc123',
          ),
          '/aceitar-convite?token=abc123',
        );
      });

      test('destino guardado continua sujeito à sessão', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/',
            retomar: '/atendimentos',
          ),
          '/login',
        );
      });

      test('logado, segue para o destino guardado', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/',
            retomar: '/tenant/usuarios',
            onboardingPendente: false,
          ),
          '/tenant/usuarios',
        );
      });

      test(
        'enquanto o roteiro não responde, segura na splash com o destino',
        () {
          expect(
            tenantAuthRedirectTarget(
              booted: true,
              isAuthenticated: true,
              isSuperuser: false,
              scopes: const ['tenant:admin'],
              location: '/',
              retomar: '/tenant/usuarios',
            ),
            isNull,
          );
        },
      );

      test('endereço de fora do app é ignorado', () {
        // `retomar` vem da URL: aceitar outro site faria do guard um
        // redirecionador aberto.
        for (final externo in ['//evil.example', 'https://evil.example/x']) {
          expect(
            tenantAuthRedirectTarget(
              booted: true,
              isAuthenticated: false,
              isSuperuser: false,
              scopes: const [],
              location: '/',
              retomar: externo,
            ),
            '/login',
            reason: externo,
          );
        }
      });
    });

    test('pós-boot deslogado: vai para /login (e fica nele)', () {
      expect(
        tenantAuthRedirectTarget(
          booted: true,
          isAuthenticated: false,
          isSuperuser: false,
          scopes: const [],
          location: '/atendimentos',
        ),
        '/login',
      );
      expect(
        tenantAuthRedirectTarget(
          booted: true,
          isAuthenticated: false,
          isSuperuser: false,
          scopes: const [],
          location: '/login',
        ),
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
          location: '/aceitar-convite',
        ),
        isNull,
      );
    });

    test('pós-boot deslogado: a recuperação de senha é pública', () {
      for (final rota in ['/recuperar-senha', '/redefinir-senha']) {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: rota,
          ),
          isNull,
          reason: '$rota deveria ser pública',
        );
      }
    });

    test('o link do e-mail de redefinição sobrevive ao boot', () {
      expect(
        tenantAuthRedirectTarget(
          booted: true,
          isAuthenticated: false,
          isSuperuser: false,
          scopes: const [],
          location: '/',
          retomar: '/redefinir-senha?token=abc',
        ),
        '/redefinir-senha?token=abc',
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
            location: rota,
          ),
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
          location: '/atendimentos',
        ),
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
          location: '/login',
          onboardingPendente: false,
        ),
        '/atendimentos',
      );
      expect(
        tenantAuthRedirectTarget(
          booted: true,
          isAuthenticated: true,
          isSuperuser: false,
          scopes: const ['atendimentos:read'],
          location: '/',
          onboardingPendente: false,
        ),
        '/atendimentos',
      );
    });

    test(
      'pós-boot sessão de tenant sem tenant:admin: rotas /tenant/* voltam para o workspace',
      () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/tenant/usuarios',
            onboardingPendente: false,
          ),
          '/atendimentos',
        );
      },
    );

    test(
      'pós-boot sessão de tenant COM tenant:admin: acessa rotas /tenant/*',
      () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/tenant/usuarios',
            onboardingPendente: false,
          ),
          isNull,
        );
      },
    );

    test(
      'pós-boot sessão de tenant: rotas normais (não-/tenant/) seguem sem redirecionar',
      () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/atendimentos',
            onboardingPendente: false,
          ),
          isNull,
        );
      },
    );

    group('configuração inicial pendente', () {
      // Regressão: quem fechava o app no meio do roteiro reabria em
      // '/atendimentos' — tela vazia, sem WhatsApp e sem caminho de volta.
      // A conta ficava paga e inutilizável.
      test('leva para o passo gravado em vez do workspace', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/atendimentos',
            onboardingPendente: true,
            onboardingPasso: 6,
          ),
          '/configuracao/departamento',
        );
      });

      test('não interfere quando já se está no roteiro', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/configuracao/whatsapp',
            onboardingPendente: true,
            onboardingPasso: 5,
          ),
          isNull,
        );
      });

      test('enquanto a consulta não responde, segura na splash', () {
        // Mandar para o workspace e corrigir depois faria a tela piscar.
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/atendimentos',
            onboardingPendente: null,
          ),
          '/',
        );
      });

      test('roteiro concluído segue para o workspace', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/login',
            onboardingPendente: false,
          ),
          '/atendimentos',
        );
      });

      test('deslogado no roteiro volta ao login (a saída do roteiro)', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/configuracao/whatsapp',
            onboardingPendente: true,
          ),
          '/login',
        );
      });
    });

    group('pagamento pendente', () {
      // O defeito reproduzido em 2026-09-06: a sessão expirou no meio do wizard,
      // o tenant ficou com PENDING_PAYMENT e onboarding_step = 8, e ao logar foi
      // direto para '/configuracao/pronto' — a tela que diz "tudo certo" para
      // quem não conseguia cadastrar nada.

      test(
        'vence o roteiro: dono pendente vai para o pagamento, não para o roteiro',
        () {
          expect(
            tenantAuthRedirectTarget(
              booted: true,
              isAuthenticated: true,
              isSuperuser: false,
              scopes: const ['tenant:admin'],
              location: '/atendimentos',
              onboardingPendente: true,
              onboardingPasso: 8,
              pagamentoPendente: true,
            ),
            '/conta/pagamento',
          );
        },
      );

      test('vence até quando o roteiro já terminou', () {
        // Este é o caso exato do defeito: onboarding_step = 8, concluído, e a
        // assinatura nunca foi paga.
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/configuracao/pronto',
            onboardingPendente: false,
            pagamentoPendente: true,
          ),
          '/conta/pagamento',
        );
      });

      test('já na tela de pagamento não redireciona (evita laço)', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/conta/pagamento',
            onboardingPendente: false,
            pagamentoPendente: true,
          ),
          isNull,
        );
      });

      test(
        'colaborador pendente NÃO é mandado para a cobrança (evita laço)',
        () {
          // Sem esta exceção o guard oscilaria: pagamento manda para
          // '/conta/pagamento', o RBAC devolve para '/atendimentos', e repete.
          // Para o colaborador o caminho é o aviso no quadro.
          expect(
            tenantAuthRedirectTarget(
              booted: true,
              isAuthenticated: true,
              isSuperuser: false,
              scopes: const ['atendimentos:read'],
              location: '/atendimentos',
              onboardingPendente: false,
              pagamentoPendente: true,
            ),
            isNull,
          );
        },
      );

      test('colaborador que tenta a rota de cobrança volta ao quadro', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['atendimentos:read'],
            location: '/conta/pagamento',
            onboardingPendente: false,
            pagamentoPendente: false,
          ),
          '/atendimentos',
        );
      });

      test('sem pendência, o comportamento atual fica intacto', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/atendimentos',
            onboardingPendente: false,
            pagamentoPendente: false,
          ),
          isNull,
        );
      });

      test('pendência desconhecida não prende ninguém na cobrança', () {
        // `null` = a consulta ainda não respondeu. Aqui o roteiro (também
        // desconhecido) segura na splash; o que importa é NÃO ir para a
        // cobrança por falta de informação.
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: true,
            isSuperuser: false,
            scopes: const ['tenant:admin'],
            location: '/atendimentos',
            onboardingPendente: false,
            pagamentoPendente: null,
          ),
          isNull,
        );
      });

      test('deslogado com pendência vai para o login, não para a cobrança', () {
        expect(
          tenantAuthRedirectTarget(
            booted: true,
            isAuthenticated: false,
            isSuperuser: false,
            scopes: const [],
            location: '/conta/pagamento',
            pagamentoPendente: true,
          ),
          '/login',
        );
      });
    });
  });
}
