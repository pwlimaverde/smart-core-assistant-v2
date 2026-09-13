import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/integracoes/data/datasources/integracoes_datasources.dart';
import 'package:tenant_module/src/features/integracoes/data/repositories/integracoes_repositories.dart';
import 'package:tenant_module/src/features/integracoes/domain/errors/integracoes_errors.dart';
import 'package:tenant_module/src/features/integracoes/domain/model/atividade.dart';
import 'package:tenant_module/src/features/integracoes/domain/parameters/integracoes_parameters.dart';
import 'package:tenant_module/src/features/integracoes/domain/usecases/integracoes_usecases.dart';
import 'package:tenant_module/src/features/integracoes/presentation/controllers/atividade_controller.dart';
import 'package:tenant_module/src/features/integracoes/presentation/controllers/integracoes_controller.dart';
import 'package:tenant_module/src/features/integracoes/presentation/widgets/aba_atividade.dart';

import '../../support/admin_client_mock.dart';

/// B3 — "o que o agente fez", da aba ao stub gRPC.
void main() {
  late MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registrarFallbacksDoTenant();
    registerFallbackValue(proto.ListMyAuditLogRequest());
    registerFallbackValue(proto.ListMcpGrantsRequest());
  });

  setUp(() {
    client = MockAdminClient();
    when(
      () => client.listMcpGrants(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMcpGrantsResponse(grants: [])));
  });
  tearDown(() => getIt.reset());

  proto.MyAuditLogEntry entrada({
    String evento = 'contato_cadastrado',
    String origem = 'mcp',
    String aplicativo = 'Claude',
    String tool = 'CreateMyContato',
    String quem = 'Maria',
  }) => proto.MyAuditLogEntry(
    timestamp: Int64(DateTime(2026, 9, 12, 14, 5).millisecondsSinceEpoch),
    eventType: evento,
    origem: origem,
    clientName: aplicativo,
    tool: tool,
    userNome: quem,
    grantId: 'g-1',
  );

  void responde(List<proto.MyAuditLogEntry> itens) =>
      when(() => client.listMyAuditLog(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyAuditLogResponse(entries: itens)),
      );

  ListarAtividadeUsecase usecase() => ListarAtividadeUsecase(
    repository: ListarAtividadeRepository(
      datasource: ListarAtividadeDatasource(client: client),
    ),
  );

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    getIt
      ..registerSingleton<AtividadeController>(
        AtividadeController(listar: usecase()),
      )
      ..registerSingleton<IntegracoesController>(
        IntegracoesController(
          listUsecase: ListMcpGrantsUsecase(
            repository: ListMcpGrantsRepository(
              datasource: ListMcpGrantsDatasource(client: client),
            ),
          ),
          revokeUsecase: RevokeMcpGrantUsecase(
            repository: RevokeMcpGrantRepository(
              datasource: RevokeMcpGrantDatasource(client: client),
            ),
          ),
        ),
      );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AbaAtividade())),
    );
    await tester.pumpAndSettle();
  }

  group('o que a tela diz', () {
    Atividade atividade({String evento = '', String operacao = ''}) =>
        Atividade(
          quando: DateTime(2026),
          evento: evento,
          porAgente: true,
          aplicativo: 'Claude',
          operacao: operacao,
          quem: 'Maria',
          grantId: '',
        );

    test('evento conhecido vira frase de negócio', () {
      expect(
        atividade(evento: 'contato_cadastrado').descricao,
        'Cadastrou um contato',
      );
    });

    test('sem evento com nome próprio, vale a operação do agente', () {
      expect(
        atividade(
          evento: 'algo_sem_rotulo',
          operacao: 'SendOutboundMessage',
        ).descricao,
        'Enviou uma mensagem a um cliente',
      );
    });

    test('código desconhecido sai humanizado, nunca em branco', () {
      expect(
        atividade(evento: 'whatsapp_instance.state_updated').descricao,
        'Whatsapp instance state updated',
      );
      expect(atividade().descricao, 'Ação registrada');
    });
  });

  test(
    'o filtro padrão pede só agentes, com a janela em milissegundos',
    () async {
      responde([entrada()]);
      final desde = DateTime(2026, 9, 1);

      final r = await usecase()(ListarAtividadeParameters(desde: desde));

      final enviado =
          verify(() => client.listMyAuditLog(captureAny())).captured.single
              as proto.ListMyAuditLogRequest;
      expect(enviado.origem, 'mcp');
      expect(enviado.grantId, isEmpty);
      expect(enviado.desde.toInt(), desde.millisecondsSinceEpoch);
      expect(r, isA<Success<List<Atividade>, IntegracoesError>>());
      expect(
        (r as Success<List<Atividade>, IntegracoesError>).value.single.quem,
        'Maria',
      );
    },
  );

  testWidgets('sem nada no período, diz isso — sem parecer erro', (
    tester,
  ) async {
    responde([]);

    await montar(tester);

    expect(find.text('Nenhum agente agiu neste período'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('cada linha diz o quê, qual aplicativo e quem autorizou', (
    tester,
  ) async {
    responde([entrada()]);

    await montar(tester);

    expect(find.text('Cadastrou um contato'), findsOneWidget);
    expect(
      find.textContaining('Claude · autorizado por Maria'),
      findsOneWidget,
    );
    expect(find.textContaining('12/09/2026 14:05'), findsOneWidget);
  });

  testWidgets('ação feita no painel não finge ser de agente', (tester) async {
    responde([entrada(origem: 'painel', aplicativo: '', tool: '')]);

    await montar(tester);

    expect(find.textContaining('Pelo painel · Maria'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('"Só agentes" é um controle só, e desligá-lo pede tudo', (
    tester,
  ) async {
    responde([]);
    await montar(tester);

    await tester.tap(find.text('Só agentes'));
    await tester.pumpAndSettle();

    final pedidos = verify(
      () => client.listMyAuditLog(captureAny()),
    ).captured.cast<proto.ListMyAuditLogRequest>();
    expect(pedidos.first.origem, 'mcp');
    expect(pedidos.last.origem, isEmpty);
  });
}
