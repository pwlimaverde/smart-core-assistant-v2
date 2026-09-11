import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/integracoes/data/datasources/integracoes_datasources.dart';
import 'package:tenant_module/src/features/integracoes/data/repositories/integracoes_repositories.dart';
import 'package:tenant_module/src/features/integracoes/domain/errors/integracoes_errors.dart';
import 'package:tenant_module/src/features/integracoes/domain/model/mcp_grant.dart';
import 'package:tenant_module/src/features/integracoes/domain/parameters/integracoes_parameters.dart';
import 'package:tenant_module/src/features/integracoes/domain/usecases/integracoes_usecases.dart';

import '../../support/admin_client_mock.dart';

/// Monta a cadeia real (datasource → repositório → usecase) sobre o stub
/// mockado, para que cada teste cubra também a conversão protobuf e o `mapError`.
({ListMcpGrantsUsecase list, RevokeMcpGrantUsecase revoke}) _usecases(
  MockAdminClient client,
) => (
  list: ListMcpGrantsUsecase(
    repository: ListMcpGrantsRepository(
      datasource: ListMcpGrantsDatasource(client: client),
    ),
  ),
  revoke: RevokeMcpGrantUsecase(
    repository: RevokeMcpGrantRepository(
      datasource: RevokeMcpGrantDatasource(client: client),
    ),
  ),
);

proto.McpGrantItem grantProto({
  String id = 'grant-1',
  String clientName = 'Claude',
  String clientId = 'https://claude.ai/mcp-client',
  String redirectUri = 'https://claude.ai/api/mcp/auth_callback',
  List<String> scopes = const ['atendimentos:read'],
  DateTime? lastUsedAt,
  DateTime? createdAt,
}) => proto.McpGrantItem(
  id: id,
  clientId: clientId,
  clientName: clientName,
  redirectUri: redirectUri,
  scopes: scopes,
  lastUsedAt: lastUsedAt == null
      ? ms(DateTime.fromMillisecondsSinceEpoch(0))
      : ms(lastUsedAt),
  createdAt: ms(createdAt ?? DateTime(2026, 1, 1)),
);

void main() {
  late MockAdminClient client;

  setUpAll(() {
    registrarFallbacksDoTenant();
    registerFallbackValue(proto.ListMcpGrantsRequest());
    registerFallbackValue(proto.RevokeMcpGrantRequest());
  });
  setUp(() => client = MockAdminClient());

  void listaResponde(List<proto.McpGrantItem> itens) => when(
    () => client.listMcpGrants(any()),
  ).thenAnswer((_) => respostaGrpc(proto.ListMcpGrantsResponse(grants: itens)));

  group('ListMcpGrants', () {
    test('converte os itens do protobuf', () async {
      listaResponde([
        grantProto(
          id: 'g-9',
          clientName: 'Claude',
          scopes: const ['atendimentos:read', 'clientes:read'],
          lastUsedAt: DateTime(2026, 2, 3),
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      final grant =
          (r as Success<List<McpGrant>, IntegracoesError>).value.single;
      expect(grant.id, 'g-9');
      expect(grant.clientName, 'Claude');
      expect(grant.scopes, ['atendimentos:read', 'clientes:read']);
      expect(grant.lastUsedAt, DateTime(2026, 2, 3));
      expect(grant.createdAt, DateTime(2026, 1, 1));
    });

    test('lastUsedAt zero do backend vira null, não 1970', () async {
      // O backend usa 0 para "nunca usado". Converter às cegas mostraria
      // "usado por último em 01/01/1970" na tela.
      listaResponde([grantProto()]);

      final r = await _usecases(client).list(noParams);

      expect(
        (r as Success<List<McpGrant>, IntegracoesError>)
            .value
            .single
            .lastUsedAt,
        isNull,
      );
    });

    test('extrai o host do redirect_uri, que é o que o usuário reconhece', () {
      final grant = McpGrant(
        id: 'g',
        clientId: 'https://claude.ai/mcp-client',
        clientName: 'Claude',
        redirectUri: 'https://claude.ai/api/mcp/auth_callback',
        scopes: const ['atendimentos:read'],
        lastUsedAt: null,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(grant.redirectHost, 'claude.ai');
    });

    test('redirect_uri malformado mostra a string inteira, não esconde', () {
      final grant = McpGrant(
        id: 'g',
        clientId: 'c',
        clientName: 'App',
        redirectUri: 'nao-e-uma-uri',
        scopes: const ['atendimentos:read'],
        lastUsedAt: null,
        createdAt: DateTime(2026, 1, 1),
      );
      // Melhor mostrar algo estranho do que ocultar o destino do acesso.
      expect(grant.redirectHost, 'nao-e-uma-uri');
    });

    test('marca como "altera dados" quem tem escopo de escrita ou admin', () {
      McpGrant comEscopos(List<String> scopes) => McpGrant(
        id: 'g',
        clientId: 'c',
        clientName: 'App',
        redirectUri: 'https://x.example/cb',
        scopes: scopes,
        lastUsedAt: null,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(comEscopos(['atendimentos:read']).podeAlterar, isFalse);
      expect(comEscopos(['atendimentos:write']).podeAlterar, isTrue);
      expect(comEscopos(['operacional:admin']).podeAlterar, isTrue);
      expect(comEscopos(['tenant:admin']).podeAlterar, isTrue);
    });

    test('detecta aplicativo que devolve o acesso para a própria máquina', () {
      final local = McpGrant(
        id: 'g',
        clientId: 'c',
        clientName: 'Cursor',
        redirectUri: 'http://localhost:33418/callback',
        scopes: const ['atendimentos:read'],
        lastUsedAt: null,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(local.ehLocal, isTrue);
      expect(local.redirectHost, 'localhost');
    });

    test('ordena os que alteram dados primeiro, uso recente no topo', () async {
      // A tela existe para o usuário cortar o que não deveria estar conectado.
      // Nessa leitura, um agente que envia mensagem importa mais que um que só lê.
      listaResponde([
        grantProto(
          id: 'so-leitura-recente',
          scopes: const ['atendimentos:read'],
          lastUsedAt: DateTime(2026, 3, 1),
        ),
        grantProto(
          id: 'escreve-antigo',
          scopes: const ['atendimentos:write'],
          lastUsedAt: DateTime(2026, 1, 5),
        ),
        grantProto(
          id: 'escreve-recente',
          scopes: const ['tenant:admin'],
          lastUsedAt: DateTime(2026, 2, 20),
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      expect(
        (r as Success<List<McpGrant>, IntegracoesError>).value
            .map((g) => g.id)
            .toList(),
        ['escreve-recente', 'escreve-antigo', 'so-leitura-recente'],
      );
    });

    test('sessão inválida vira erro de sessão, não de permissão', () async {
      // Não existe "sem permissão" nesta tela: o recurso é do próprio usuário.
      when(() => client.listMcpGrants(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unauthenticated('token expirado')),
      );

      final r = await _usecases(client).list(noParams);

      expect((r as Failure).error, isA<IntegracoesSessaoInvalida>());
    });

    test('servidor fora do ar vira falha de rede', () async {
      when(() => client.listMcpGrants(any()))
          .thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('offline')));

      final r = await _usecases(client).list(noParams);

      expect((r as Failure).error, isA<IntegracoesIndisponivel>());
    });
  });

  group('RevokeMcpGrant', () {
    test('devolve a janela de revogação vinda do servidor', () async {
      // A tela precisa dizer o número real; um valor escrito à mão no Dart
      // deixaria de bater no dia em que a configuração do backend mudasse.
      when(() => client.revokeMcpGrant(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.RevokeMcpGrantResponse(success: true, janelaRevogacaoMin: 15),
        ),
      );

      final r = await _usecases(client)
          .revoke(const RevokeMcpGrantParameters(grantId: 'g-1'));

      expect((r as Success<int, IntegracoesError>).value, 15);
    });

    test(
      'grant de outra pessoa e grant inexistente dão o mesmo erro',
      () async {
        // O backend não distingue os casos de propósito, para não confirmar a
        // existência de consentimento alheio. A tela não pode reintroduzir a
        // distinção.
        when(() => client.revokeMcpGrant(any())).thenAnswer(
          (_) => falhaGrpc(proto.GrpcError.invalidArgument('inexistente')),
        );

        final r = await _usecases(client)
            .revoke(const RevokeMcpGrantParameters(grantId: 'g-de-outro'));

        expect((r as Failure).error, isA<ConexaoNaoEncontrada>());
      },
    );
  });
}
