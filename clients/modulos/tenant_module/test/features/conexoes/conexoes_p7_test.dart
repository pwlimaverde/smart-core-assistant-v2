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
import 'package:tenant_module/src/features/conexoes/presentation/controllers/conexoes_controllers.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// P7 — departamento da conexão, detalhe e encerrar a sessão.
void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyWhatsappInstancesRequest());
    registerFallbackValue(proto.MyWhatsappInstanceIdRequest());
    registerFallbackValue(proto.GetMyWhatsappInstanceStatusRequest());
    registerFallbackValue(proto.DefinirDepartamentoDaConexaoRequest());
    registerFallbackValue(proto.DetalheDaConexaoRequest());
  });

  setUp(() => client = _MockAdminClient());

  ConexoesController controller() => ConexoesController(
    listar: ListarConexoesUsecase(
      repository: ListarConexoesRepository(
        datasource: ListarConexoesDatasource(client: client),
      ),
    ),
    reconectar: ReconectarConexaoUsecase(
      repository: ReconectarConexaoRepository(
        datasource: ReconectarConexaoDatasource(client: client),
      ),
    ),
    remover: RemoverConexaoUsecase(
      repository: RemoverConexaoRepository(
        datasource: RemoverConexaoDatasource(client: client),
      ),
    ),
    criar: CriarConexaoUsecase(
      repository: CriarConexaoRepository(
        datasource: CriarConexaoDatasource(client: client),
      ),
    ),
    pareamento: EstadoPareamentoUsecase(
      repository: EstadoPareamentoRepository(
        datasource: EstadoPareamentoDatasource(client: client),
      ),
    ),
    respostaBot: DefinirRespostaBotUsecase(
      repository: DefinirRespostaBotRepository(
        datasource: DefinirRespostaBotDatasource(client: client),
      ),
    ),
    desconectar: DesconectarConexaoUsecase(
      repository: DesconectarConexaoRepository(
        datasource: DesconectarConexaoDatasource(client: client),
      ),
    ),
    definirDepartamento: DefinirDepartamentoDaConexaoUsecase(
      repository: DefinirDepartamentoDaConexaoRepository(
        datasource: DefinirDepartamentoDaConexaoDatasource(client: client),
      ),
    ),
    detalhe: DetalheDaConexaoUsecase(
      repository: DetalheDaConexaoRepository(
        datasource: DetalheDaConexaoDatasource(client: client),
      ),
    ),
  );

  void listaResponde({int departamentoId = 0, String departamento = ''}) {
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
              departamentoId: departamentoId,
              departamentoNome: departamento,
            ),
          ],
        ),
      ),
    );
    when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetMyWhatsappInstanceStatusResponse(
          connectionState: 'connected',
        ),
      ),
    );
  }

  test('a listagem traz o departamento da conexão', () async {
    listaResponde(departamentoId: 4, departamento: 'Vendas');

    final res = await ListarConexoesUsecase(
      repository: ListarConexoesRepository(
        datasource: ListarConexoesDatasource(client: client),
      ),
    )(noParams);

    final itens = (res as Success<List<Conexao>, ConexoesError>).value;
    expect(itens.single.departamentoId, 4);
    expect(itens.single.departamentoNome, 'Vendas');
  });

  test('trocar o departamento não reconsulta o provedor', () async {
    // `carregar` confere o estado conexão por conexão com a evolution-go.
    // Gastar essa varredura para refletir um rótulo deixaria a troca lenta sem
    // necessidade — por isso aqui só o item da lista é substituído.
    listaResponde();
    when(() => client.definirDepartamentoDaConexao(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    final c = controller();
    await c.carregar();
    clearInteractions(client);

    final res = await c.definirDepartamento(
      id: 3,
      departamentoId: 4,
      departamentoNome: 'Vendas',
    );

    expect(res, isA<Success>());
    verifyNever(() => client.listMyWhatsappInstances(any()));
    final estado = c.state as SuccessState<List<Conexao>>;
    expect(estado.data.single.departamentoNome, 'Vendas');
    await c.close();
  });

  test('departamento 0 desfaz o vínculo', () async {
    listaResponde(departamentoId: 4, departamento: 'Vendas');
    when(() => client.definirDepartamentoDaConexao(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    final c = controller();
    await c.carregar();

    await c.definirDepartamento(id: 3, departamentoId: 0, departamentoNome: '');

    final enviado = verify(
      () => client.definirDepartamentoDaConexao(captureAny()),
    ).captured.single as proto.DefinirDepartamentoDaConexaoRequest;
    expect(enviado.departamentoId, 0);
    final estado = c.state as SuccessState<List<Conexao>>;
    expect(estado.data.single.departamentoId, 0);
    await c.close();
  });

  test('encerrar a sessão recarrega a lista', () async {
    // Diferente de trocar o departamento: o estado muda para desconectada e a
    // tela precisa oferecer o QR em seguida.
    listaResponde();
    when(() => client.desconectarMyWhatsappInstance(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    final c = controller();
    await c.carregar();
    clearInteractions(client);

    final res = await c.desconectar(3);

    expect(res, isA<Success>());
    verify(() => client.listMyWhatsappInstances(any())).called(1);
    await c.close();
  });

  test('o detalhe traduz "nunca conferida" em vez de 1970', () async {
    // 0 no contrato é ausência de checagem; mostrar a data da época seria pior
    // do que não mostrar nada.
    when(() => client.detalheDaConexao(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.DetalheDaConexaoResponse(
          conexao: proto.MyWhatsappInstance(
            id: 3,
            name: 'atendimento',
            connectionState: 'connected',
            createdAt: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
          ),
          ultimaChecagem: Int64.ZERO,
          instanciaNoProvedor: 'inst-181',
          atendimentosAbertos: 2,
          mensagens24h: 31,
        ),
      ),
    );
    final c = controller();

    final res = await c.detalhe(3);
    final detalhe = (res as Success<DetalheConexao, ConexoesError>).value;

    expect(detalhe.ultimaChecagem, isNull);
    expect(detalhe.instanciaNoProvedor, 'inst-181');
    expect(detalhe.atendimentosAbertos, 2);
    await c.close();
  });

  test('parameters do departamento carregam os dois campos', () {
    const p = DepartamentoDaConexaoParameters(id: 3, departamentoId: 4);
    expect(p.id, 3);
    expect(p.departamentoId, 4);
  });
}
