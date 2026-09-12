import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/iniciar_atendimento_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_iniciado.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'support/fake_gateway.dart';

/// C3 — abrir um atendimento a partir de um cliente já cadastrado.
///
/// Até aqui um atendimento só nascia de uma mensagem que chegou. Quem quisesse
/// procurar o cliente tinha de sair do produto, abrir o WhatsApp, mandar a
/// mensagem por fora e esperar a resposta cair no quadro — e o histórico dessa
/// conversa começava pela metade.
void main() {
  const pedido = IniciarAtendimentoParameters(
    contatoId: 7,
    fluxoId: 1,
    etapaInicialId: 10,
    assunto: 'Renovação do contrato',
  );

  test('abre a conversa e devolve o id do atendimento', () async {
    final gateway = FakeAtendimentoGateway()..atendimentoIniciadoId = 501;
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    expect(r, isA<Success<AtendimentoIniciado, IniciarAtendimentoError>>());
    final valor =
        (r as Success<AtendimentoIniciado, IniciarAtendimentoError>).value;
    expect(valor.atendimentoId, 501);
    expect(valor.jaExistia, isFalse);
    expect(gateway.iniciarRecebido?.assunto, 'Renovação do contrato');
  });

  /// A invariante de um atendimento ativo por contato vale aqui também.
  ///
  /// Se já há conversa aberta com aquela pessoa, o servidor devolve a que
  /// existe. Criar a segunda duplicaria a fila e faria dois operadores
  /// responderem sobre o mesmo assunto sem saber um do outro — e a tela
  /// precisa saber a diferença para dizer "já havia uma aberta" em vez de
  /// anunciar um cartão novo que ninguém vai achar.
  test('cliente com conversa aberta devolve a que existe', () async {
    final gateway = FakeAtendimentoGateway()
      ..atendimentoIniciadoId = 42
      ..iniciarJaExistia = true;
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    final valor =
        (r as Success<AtendimentoIniciado, IniciarAtendimentoError>).value;
    expect(valor.atendimentoId, 42);
    expect(valor.jaExistia, isTrue);
  });

  /// Sem etapa o cartão nasceria invisível — não apareceria em coluna nenhuma
  /// do quadro. Quem recusa é o servidor, e a mensagem tem de dizer o que
  /// falta escolher, não "erro inesperado".
  test('pedido sem etapa volta dizendo o que falta', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroIniciar = GrpcError.invalidArgument('etapa_inicial_id ausente');
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(
      const IniciarAtendimentoParameters(
        contatoId: 7,
        fluxoId: 1,
        etapaInicialId: 0,
      ),
    );

    expect(
      (r as Failure<AtendimentoIniciado, IniciarAtendimentoError>).error,
      isA<IniciarAtendimentoInvalido>(),
    );
  });

  /// Um atendimento sem id não é um atendimento: devolvê-lo como sucesso faria
  /// a tela abrir uma conversa que não existe.
  test('resposta sem id não passa por sucesso', () async {
    final gateway = FakeAtendimentoGateway()..atendimentoIniciadoId = 0;
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    expect(r, isA<Failure<AtendimentoIniciado, IniciarAtendimentoError>>());
  });

  test('sem permissão no fluxo vira acesso negado', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroIniciar = GrpcError.permissionDenied('errors.auth.forbidden');
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    expect(
      (r as Failure<AtendimentoIniciado, IniciarAtendimentoError>).error,
      isA<IniciarAtendimentoAcessoNegado>(),
    );
  });

  /// Sessão expirada **não** é falta de permissão. Conflatar as duas foi o que
  /// mandou um dono de conta caçar acessos que ele sempre teve.
  test('sessão expirada não vira "sem permissão"', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroIniciar = GrpcError.unauthenticated('token expirado');
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    expect(
      (r as Failure<AtendimentoIniciado, IniciarAtendimentoError>).error,
      isA<IniciarAtendimentoSessaoExpirada>(),
    );
  });

  test('servidor fora do ar é distinguido do resto', () async {
    final gateway = FakeAtendimentoGateway()
      ..erroIniciar = GrpcError.unavailable('fora do ar');
    final u = usecasesSobre(gateway);

    final r = await u.iniciar(pedido);

    expect(
      (r as Failure<AtendimentoIniciado, IniciarAtendimentoError>).error,
      isA<IniciarAtendimentoIndisponivel>(),
    );
  });
}
