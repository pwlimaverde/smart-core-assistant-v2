import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/clientes/data/datasources/clientes_datasources.dart';
import 'package:tenant_module/src/features/clientes/data/repositories/clientes_repositories.dart';
import 'package:tenant_module/src/features/clientes/domain/errors/clientes_errors.dart';
import 'package:tenant_module/src/features/clientes/domain/model/cliente.dart';
import 'package:tenant_module/src/features/clientes/domain/parameters/clientes_parameters.dart';
import 'package:tenant_module/src/features/clientes/domain/usecases/clientes_usecases.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyClientesRequest());
    registerFallbackValue(proto.CreateMyClienteRequest());
    registerFallbackValue(proto.UpdateMyClienteRequest());
    registerFallbackValue(proto.VincularMyContatoClienteRequest());
  });
  setUp(() => client = _MockAdminClient());

  SalvarClienteUsecase salvar() => SalvarClienteUsecase(
    repository: SalvarClienteRepository(
      datasource: SalvarClienteDatasource(client: client),
    ),
  );

  group('formatação do documento', () {
    test('CNPJ e CPF só são formatados com o tamanho certo', () {
      expect(formatarCnpj('12345678000190'), '12.345.678/0001-90');
      expect(formatarCpf('12345678901'), '123.456.789-01');
      expect(formatarCnpj('123'), '123');
    });

    test('o documento mostrado segue o tipo', () {
      const pj = DadosCliente(
        nomeFantasia: 'A',
        tipo: 'pj',
        cnpj: '12345678000190',
      );
      const pf = DadosCliente(
        nomeFantasia: 'B',
        tipo: 'pf',
        cpf: '12345678901',
      );
      expect(pj.documentoFormatado, '12.345.678/0001-90');
      expect(pf.documentoFormatado, '123.456.789-01');
      expect(
        const DadosCliente(
          nomeFantasia: 'C',
          cidade: 'Recife',
          uf: 'PE',
        ).localidade,
        'Recife/PE',
      );
    });
  });

  group('listar', () {
    test('converte o protobuf', () async {
      when(() => client.listMyClientes(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyClientesResponse(
            clientes: [
              proto.MyCliente(
                id: 4,
                dados: proto.DadosMyCliente(
                  nomeFantasia: 'Padaria Sol',
                  tipo: 'pj',
                ),
                ativo: true,
                contatos: 2,
              ),
            ],
          ),
        ),
      );

      final res = await ListarClientesUsecase(
        repository: ListarClientesRepository(
          datasource: ListarClientesDatasource(client: client),
        ),
      )(const ListarClientesParameters(busca: 'sol', incluirInativos: true));

      final cliente =
          (res as Success<List<Cliente>, ClientesError>).value.single;
      expect(cliente.dados.nomeFantasia, 'Padaria Sol');
      expect(cliente.contatos, 2);
      final pedido =
          verify(() => client.listMyClientes(captureAny())).captured.single
              as proto.ListMyClientesRequest;
      expect(pedido.busca, 'sol');
      expect(pedido.incluirInativos, isTrue);
    });
  });

  group('salvar', () {
    test('sem id cadastra; com id edita', () async {
      when(() => client.createMyCliente(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.MyClienteResponse(cliente: proto.MyCliente(id: 9)),
        ),
      );
      when(
        () => client.updateMyCliente(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));

      final criado = await salvar()(
        const SalvarClienteParameters(
          dados: DadosCliente(nomeFantasia: ' Padaria '),
        ),
      );
      final editado = await salvar()(
        const SalvarClienteParameters(
          id: 9,
          dados: DadosCliente(nomeFantasia: 'Padaria'),
        ),
      );

      expect((criado as Success<int, ClientesError>).value, 9);
      expect((editado as Success<int, ClientesError>).value, 9);
      final novo =
          verify(() => client.createMyCliente(captureAny())).captured.single
              as proto.CreateMyClienteRequest;
      expect(novo.dados.nomeFantasia, 'Padaria');
      verify(() => client.updateMyCliente(any())).called(1);
    });

    test('recusa do servidor chega com a mensagem dele', () async {
      when(() => client.createMyCliente(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument('CNPJ precisa ter 14 dígitos'),
        ),
      );

      final res = await salvar()(
        const SalvarClienteParameters(
          dados: DadosCliente(nomeFantasia: 'A', cnpj: '123'),
        ),
      );

      final erro = (res as Failure).error;
      expect(erro, isA<ClienteInvalido>());
      expect(erro.message, 'CNPJ precisa ter 14 dígitos');
    });
  });

  test('vincular manda cliente, contato e a direção', () async {
    when(
      () => client.vincularMyContatoCliente(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));

    await VincularContatoUsecase(
      repository: VincularContatoRepository(
        datasource: VincularContatoDatasource(client: client),
      ),
    )(
      const VincularContatoParameters(
        clienteId: 4,
        contatoId: 7,
        vincular: false,
      ),
    );

    final pedido =
        verify(
              () => client.vincularMyContatoCliente(captureAny()),
            ).captured.single
            as proto.VincularMyContatoClienteRequest;
    expect(pedido.clienteId, 4);
    expect(pedido.contatoId, 7);
    expect(pedido.vincular, isFalse);
  });
}
