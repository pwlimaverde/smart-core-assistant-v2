import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/conexoes/data/datasources/conexoes_datasources.dart';
import 'package:tenant_module/src/features/conexoes/data/repositories/conexoes_repositories.dart';
import 'package:tenant_module/src/features/conexoes/domain/errors/conexoes_errors.dart';
import 'package:tenant_module/src/features/conexoes/domain/model/conexao.dart';
import 'package:tenant_module/src/features/conexoes/domain/parameters/conexoes_parameters.dart';
import 'package:tenant_module/src/features/conexoes/domain/usecases/conexoes_usecases.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

Conexao comEstado(String estado) => Conexao(
      id: 1,
      nome: 'atendimento',
      telefone: '5588999999999',
      estado: estado,
      ativa: true,
      criadaEm: DateTime(2026, 8, 1),
    );

void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyWhatsappInstancesRequest());
    registerFallbackValue(proto.MyWhatsappInstanceIdRequest());
    registerFallbackValue(proto.CreateMyWhatsappInstanceRequest());
    registerFallbackValue(proto.GetMyWhatsappInstanceStatusRequest());
  });

  setUp(() => client = _MockAdminClient());

  ListarConexoesUsecase listar() => ListarConexoesUsecase(
        repository: ListarConexoesRepository(
          datasource: ListarConexoesDatasource(client: client),
        ),
      );

  group('situação da conexão', () {
    test('traduz o vocabulário do provedor', () {
      expect(comEstado('connected').situacao, SituacaoConexao.conectada);
      expect(comEstado('connecting').situacao, SituacaoConexao.conectando);
      expect(comEstado('disconnected').situacao, SituacaoConexao.desconectada);
    });

    test('estado que não reconhecemos não vira "desconectada"', () {
      // Não saber é diferente de estar fora: um pede espera, o outro pede
      // ação. Tratar `unknown` como desconectada mandaria o tenant reconectar
      // uma conexão que talvez esteja boa.
      expect(comEstado('unknown').situacao, SituacaoConexao.desconhecida);
      expect(comEstado('').situacao, SituacaoConexao.desconhecida);
      expect(comEstado('coisa-nova').situacao, SituacaoConexao.desconhecida);
    });
  });

  test('listar converte o protobuf para o domínio', () async {
    when(() => client.listMyWhatsappInstances(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyWhatsappInstancesResponse(
          instancias: [
            proto.MyWhatsappInstance(
              id: 3,
              name: 'atendimento',
              phoneNumber: '5588999999999',
              connectionState: 'connected',
              active: true,
              provider: 'evolution',
              createdAt: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
            ),
          ],
        ),
      ),
    );

    final res = await listar()(noParams);
    final itens = (res as Success<List<Conexao>, ConexoesError>).value;

    expect(itens, hasLength(1));
    expect(itens.first.id, 3);
    expect(itens.first.situacao, SituacaoConexao.conectada);
  });

  test('reconectar envia o id da conexão', () async {
    when(() => client.reconnectMyWhatsappInstance(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );

    final usecase = ReconectarConexaoUsecase(
      repository: ReconectarConexaoRepository(
        datasource: ReconectarConexaoDatasource(client: client),
      ),
    );
    await usecase(const ConexaoIdParameters(id: 7));

    final enviado = verify(() => client.reconnectMyWhatsappInstance(captureAny()))
        .captured
        .single as proto.MyWhatsappInstanceIdRequest;
    expect(enviado.id, 7);
  });

  group('tradução de erro', () {
    test('provedor que recusa preserva a mensagem dele', () async {
      // Quem sabe por que a reconexão falhou é o provedor; repetir um texto
      // genérico aqui esconderia a causa de quem está na tela.
      when(() => client.reconnectMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.failedPrecondition('instância já está conectada'),
        ),
      );

      final usecase = ReconectarConexaoUsecase(
        repository: ReconectarConexaoRepository(
          datasource: ReconectarConexaoDatasource(client: client),
        ),
      );
      final res = await usecase(const ConexaoIdParameters(id: 1));

      final erro = (res as Failure).error;
      expect(erro, isA<ConexaoRecusada>());
      expect(erro.message, contains('já está conectada'));
    });

    test('sem escopo vira acesso negado', () async {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final res = await listar()(noParams);
      expect((res as Failure).error, isA<ConexoesAcessoNegado>());
    });

    test('servidor fora do ar vira erro de rede', () async {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
      );

      final res = await listar()(noParams);
      expect((res as Failure).error, isA<ConexoesIndisponivel>());
    });
  });

  group('pareamento', () {
    EstadoPareamentoUsecase pareamento() => EstadoPareamentoUsecase(
          repository: EstadoPareamentoRepository(
            datasource: EstadoPareamentoDatasource(client: client),
          ),
        );

    test('criar devolve o id necessário para acompanhar o pareamento', () async {
      // Sem o id não há como consultar o QR em seguida — a instância nasceria
      // e ficaria pendurada, que é o defeito que esta tela veio corrigir.
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateMyWhatsappInstanceResponse(
            id: 42,
            instanceName: 'vendas',
            provider: 'evolution',
          ),
        ),
      );

      final usecase = CriarConexaoUsecase(
        repository: CriarConexaoRepository(
          datasource: CriarConexaoDatasource(client: client),
        ),
      );
      final res = await usecase(const CriarConexaoParameters(nome: 'vendas'));
      final criada = (res as Success<ConexaoCriada, ConexoesError>).value;

      expect(criada.id, 42);
      expect(criada.nome, 'vendas');

      final enviado = verify(() => client.createMyWhatsappInstance(captureAny()))
          .captured
          .single as proto.CreateMyWhatsappInstanceRequest;
      expect(enviado.instanceName, 'vendas');
    });

    test('estado com QR ainda não está conectado', () async {
      when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetMyWhatsappInstanceStatusResponse(
            connectionState: 'connecting',
            qrCode: 'iVBORw0KGgo=',
          ),
        ),
      );

      final res = await pareamento()(const ConexaoIdParameters(id: 1));
      final estado =
          (res as Success<EstadoPareamento, ConexoesError>).value;

      expect(estado.temQr, isTrue);
      expect(estado.conectado, isFalse);
    });

    test('conectado vem sem QR — a caixa fecha por aqui', () async {
      when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetMyWhatsappInstanceStatusResponse(
            connectionState: 'connected',
            qrCode: '',
          ),
        ),
      );

      final res = await pareamento()(const ConexaoIdParameters(id: 1));
      final estado =
          (res as Success<EstadoPareamento, ConexoesError>).value;

      expect(estado.conectado, isTrue);
      expect(estado.temQr, isFalse);
    });

    test('nome repetido é recusa do provedor, não erro nosso', () async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.alreadyExists('já existe uma instância com esse nome'),
        ),
      );

      final usecase = CriarConexaoUsecase(
        repository: CriarConexaoRepository(
          datasource: CriarConexaoDatasource(client: client),
        ),
      );
      final res = await usecase(const CriarConexaoParameters(nome: 'atendimento'));

      final erro = (res as Failure).error;
      expect(erro, isA<ConexaoRecusada>());
      expect(erro.message, contains('já existe'));
    });
  });
}
