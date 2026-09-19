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

/// P9 — mensagens do atendente que ficaram sem destino.
void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyMensagensNaoEntreguesRequest());
    registerFallbackValue(proto.ReenviarMensagemNaoEntregueRequest());
  });
  setUp(() => client = _MockAdminClient());

  test('lista converte o protobuf para o domínio', () async {
    when(() => client.listMyMensagensNaoEntregues(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyMensagensNaoEntreguesResponse(
          itens: [
            proto.MensagemNaoEntregue(
              id: 4,
              atendimentoId: 9,
              motivo: 'sem whatsapp_contact ativo',
              criadoEm: Int64(DateTime(2026, 9, 1).millisecondsSinceEpoch),
              trecho: 'Seu pedido saiu',
              contato: 'Maria',
            ),
          ],
        ),
      ),
    );

    final r = await ListarNaoEntreguesUsecase(
      repository: ListarNaoEntreguesRepository(
        datasource: ListarNaoEntreguesDatasource(client: client),
      ),
    )(noParams);

    final itens =
        (r as Success<List<MensagemNaoEntregue>, ConexoesError>).value;
    expect(itens.single.contato, 'Maria');
    expect(itens.single.atendimentoId, 9);
  });

  test('"ainda sem destino" não é erro: é o desfecho honesto', () async {
    // O contato continua sem conexão ativa. Tratar como falha faria a tela
    // dizer "algo deu errado" para o que é só "ainda não dá".
    when(() => client.reenviarMensagemNaoEntregue(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ReenviarMensagemNaoEntregueResponse(status: 'ainda_sem_destino'),
      ),
    );

    final r = await ReenviarNaoEntregueUsecase(
      repository: ReenviarNaoEntregueRepository(
        datasource: ReenviarNaoEntregueDatasource(client: client),
      ),
    )(const ConexaoIdParameters(id: 4));

    expect(
      (r as Success<DesfechoReenvio, ConexoesError>).value,
      DesfechoReenvio.semDestino,
    );
  });

  test('o vocabulário do servidor vira desfecho', () {
    expect(DesfechoReenvio.doServidor('reprocessada'), DesfechoReenvio.reenviada);
    expect(
      DesfechoReenvio.doServidor('nao_encontrada'),
      DesfechoReenvio.naoEncontrada,
    );
    expect(DesfechoReenvio.doServidor('outra'), DesfechoReenvio.naoEncontrada);
  });
}
