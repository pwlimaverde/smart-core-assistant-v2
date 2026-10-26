import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/contato_da_conversa.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/ficha_controller.dart';

import '../../support/fake_gateway.dart';

FichaController _controller(
  FakeAtendimentoGateway gateway, {
  bool completo = true,
}) => FichaController(
  carregar: GetFichaUsecase(
    repository: GetFichaRepository(
      datasource: GetFichaDatasource(gateway: gateway),
    ),
  ),
  criarEtiqueta: CriarEtiquetaUsecase(
    repository: CriarEtiquetaRepository(
      datasource: CriarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  alternar: AlternarEtiquetaUsecase(
    repository: AlternarEtiquetaRepository(
      datasource: AlternarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  criarNota: CriarNotaUsecase(
    repository: CriarNotaRepository(
      datasource: CriarNotaDatasource(gateway: gateway),
    ),
  ),
  definirBot: DefinirBotDaConversaUsecase(
    repository: DefinirBotDaConversaRepository(
      datasource: DefinirBotDaConversaDatasource(gateway: gateway),
    ),
  ),
  definirValorCampo: DefinirValorCampoUsecase(
    repository: DefinirValorCampoRepository(
      datasource: DefinirValorCampoDatasource(gateway: gateway),
    ),
  ),
  editarContato: completo
      ? EditarContatoUsecase(
          repository: EditarContatoRepository(
            datasource: EditarContatoDatasource(gateway: gateway),
          ),
        )
      : null,
  obterCliente: completo
      ? ObterClienteUsecase(
          repository: ObterClienteRepository(
            datasource: ObterClienteDatasource(gateway: gateway),
          ),
        )
      : null,
  salvarCliente: completo
      ? SalvarClienteUsecase(
          repository: SalvarClienteRepository(
            datasource: SalvarClienteDatasource(gateway: gateway),
          ),
        )
      : null,
  vincularCliente: completo
      ? VincularClienteUsecase(
          repository: VincularClienteRepository(
            datasource: VincularClienteDatasource(gateway: gateway),
          ),
        )
      : null,
  buscarClientes: completo
      ? BuscarClientesUsecase(
          repository: BuscarClientesRepository(
            datasource: BuscarClientesDatasource(gateway: gateway),
          ),
        )
      : null,
);

void main() {
  group('cadastro de contato e cliente na ficha', () {
    test('editar contato envia todos os campos ao servidor', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final erro = await controller.editarContato(
        contatoId: 4,
        nome: 'Ana',
        email: 'ana@exemplo.com',
        cargo: 'Gerente',
        segmento: 'Varejo',
        observacoes: 'Prefere e-mail',
      );

      expect(erro, isNull);
      expect(
        gateway.acoesDoCadastro,
        contains(
          'editarContato:4:Ana:ana@exemplo.com:Gerente:Varejo:Prefere e-mail',
        ),
      );
      await controller.close();
    });

    test('salvar cliente novo (id 0) devolve o id gravado', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final (id, erro) = await controller.salvarCliente(
        const ClienteDaConversa(id: 0, nomeFantasia: 'Padaria Central'),
      );

      expect(erro, isNull);
      expect(id, 1);
      expect(
        gateway.acoesDoCadastro,
        contains('salvarCliente:0:Padaria Central'),
      );
      await controller.close();
    });

    test('salvar cliente existente mantém o id', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final (id, erro) = await controller.salvarCliente(
        const ClienteDaConversa(id: 7, nomeFantasia: 'Padaria Central'),
      );

      expect(erro, isNull);
      expect(id, 7);
      await controller.close();
    });

    test('obter cliente devolve o cadastro pedido', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final (cliente, erro) = await controller.obterCliente(12);

      expect(erro, isNull);
      expect(cliente?.id, 12);
      expect(cliente?.nomeFantasia, 'Cliente 12');
      expect(gateway.acoesDoCadastro, contains('obterCliente:12'));
      await controller.close();
    });

    test('vincular e desvincular registram o sentido da ação', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      expect(
        await controller.vincularCliente(
          clienteId: 7,
          contatoId: 4,
          vincular: true,
        ),
        isNull,
      );
      expect(
        await controller.vincularCliente(
          clienteId: 7,
          contatoId: 4,
          vincular: false,
        ),
        isNull,
      );

      expect(gateway.acoesDoCadastro, [
        'vincular:7:4:true',
        'vincular:7:4:false',
      ]);
      await controller.close();
    });

    test('buscar clientes envia o termo digitado', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final (lista, erro) = await controller.buscarClientes('padaria');

      expect(erro, isNull);
      expect(lista, isEmpty);
      expect(gateway.acoesDoCadastro, contains('buscarClientes:padaria'));
      await controller.close();
    });

    test(
      'sem os casos de uso do cadastro, cada ação devolve erro inesperado',
      () async {
        final gateway = FakeAtendimentoGateway();
        final controller = _controller(gateway, completo: false);

        expect(
          await controller.editarContato(
            contatoId: 4,
            nome: '',
            email: '',
            cargo: '',
            segmento: '',
            observacoes: '',
          ),
          isA<FichaInesperado>(),
        );
        expect((await controller.obterCliente(1)).$2, isA<FichaInesperado>());
        expect(
          (await controller.salvarCliente(const ClienteDaConversa(id: 0))).$2,
          isA<FichaInesperado>(),
        );
        expect(
          await controller.vincularCliente(
            clienteId: 1,
            contatoId: 1,
            vincular: true,
          ),
          isA<FichaInesperado>(),
        );
        expect(
          (await controller.buscarClientes('x')).$2,
          isA<FichaInesperado>(),
        );
        expect(gateway.acoesDoCadastro, isEmpty);
        await controller.close();
      },
    );
  });
}
