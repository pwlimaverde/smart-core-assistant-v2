import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tenant_module/permissoes_de_tela.dart';

/// B2 — o mapa de telas da interface, e o espelho dele no servidor.
void main() {
  group('regra', () {
    test('tenant:admin e o coringa abrem e alteram tudo', () {
      for (final escopos in [
        const ['tenant:admin'],
        const ['*'],
      ]) {
        for (final rota in escoposParaAbrir.keys) {
          expect(podeAbrirTela(escopos, rota), isTrue, reason: rota);
          expect(podeAlterarTela(escopos, rota), isTrue, reason: rota);
        }
      }
    });

    test('lista vazia é só admin, nunca "qualquer um"', () {
      expect(
        podeAbrirTela(const ['configuracoes:write'], '/tenant/convites'),
        isFalse,
      );
      expect(podeAbrirTela(const [], '/tenant/usuarios'), isFalse);
    });

    test('viewer abre as telas de leitura e não altera nenhuma', () {
      const viewer = ['atendimentos:read'];
      expect(podeAbrirTela(viewer, '/tenant/fluxos'), isTrue);
      expect(podeAbrirTela(viewer, '/tenant/contatos'), isTrue);
      for (final rota in escoposParaAlterar.keys) {
        expect(podeAlterarTela(viewer, rota), isFalse, reason: rota);
      }
    });

    test('manager altera fluxos com kanban:admin', () {
      const manager = ['atendimentos:read', 'kanban:admin'];
      expect(podeAlterarTela(manager, '/tenant/fluxos'), isTrue);
      expect(podeAlterarTela(manager, '/tenant/fluxos/3/etapas'), isTrue);
      expect(podeAlterarTela(manager, '/tenant/equipe'), isFalse);
    });

    test('subtela herda a seção; fora de /tenant/ não há restrição', () {
      expect(
        secaoDe('/tenant/fluxos/9/etapas', escoposParaAbrir.keys),
        '/tenant/fluxos',
      );
      expect(podeAbrirTela(const [], '/atendimentos'), isTrue);
    });
  });

  group('espelho do rbac::MAPA', () {
    // Divergir é prometer na tela o que o servidor nega, ou esconder o que ele
    // permite. Lido do fonte, e não copiado, para o teste falhar na primeira
    // mudança de um lado só.
    final mapa = _lerMapaDoServidor();

    /// A chamada que cada tela faz ao abrir.
    const aoAbrir = <String, List<String>>{
      '/tenant/painel': ['GetPainelTenant'],
      '/tenant/contatos': ['ListContatos'],
      '/tenant/equipe': ['ListDepartamentos', 'ListAtendentes'],
      '/tenant/fluxos': ['ListFluxos'],
      '/tenant/campos': ['ListCamposPersonalizados'],
      '/tenant/conexoes': ['ListWhatsappInstances'],
      '/tenant/treinamento': ['ListTreinamentos'],
    };

    /// A chamada do botão principal de cada tela.
    const aoAlterar = <String, String>{
      '/tenant/contatos': 'CreateContato',
      '/tenant/equipe': 'CreateDepartamento',
      '/tenant/fluxos': 'CreateFluxo',
      '/tenant/campos': 'CreateCampoPersonalizado',
      '/tenant/conexoes': 'CreateWhatsappInstance',
      '/tenant/treinamento': 'CreateTreinamento',
    };

    aoAbrir.forEach((tela, rotas) {
      test('abrir $tela concorda com o servidor', () {
        for (final rota in rotas) {
          expect(mapa.containsKey(rota), isTrue, reason: '$rota sumiu do MAPA');
          expect(
            escoposParaAbrir[tela]!.toSet(),
            mapa[rota]!.toSet(),
            reason: '$tela × $rota',
          );
        }
      });
    });

    aoAlterar.forEach((tela, rota) {
      test('alterar $tela concorda com o servidor', () {
        expect(mapa.containsKey(rota), isTrue, reason: '$rota sumiu do MAPA');
        expect(escoposParaAlterar[tela]!.toSet(), mapa[rota]!.toSet());
      });
    });
  });
}

/// `rota → escopos` do `rbac.rs`. `SOMENTE_ADMIN` vira lista vazia.
Map<String, List<String>> _lerMapaDoServidor() {
  // Os testes rodam com o diretório do pacote como corrente.
  final fonte = File(
    '../../../server/apps/runtime_api/src/rbac.rs',
  ).readAsStringSync();
  final entrada = RegExp(r'\("(\w+)",\s*(?:&\[([^\]]*)\]|SOMENTE_ADMIN)\)');
  return {
    for (final m in entrada.allMatches(fonte))
      m.group(1)!: (m.group(2) ?? '')
          .split(',')
          .map((s) => s.trim().replaceAll('"', ''))
          .where((s) => s.isNotEmpty)
          .toList(),
  };
}
