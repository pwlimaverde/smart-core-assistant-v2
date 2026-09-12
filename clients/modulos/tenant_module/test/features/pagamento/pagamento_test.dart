import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/pagamento/data/datasources/pagamento_datasources.dart';
import 'package:tenant_module/src/features/pagamento/data/repositories/pagamento_repositories.dart';
import 'package:tenant_module/src/features/pagamento/domain/errors/pagamento_errors.dart';
import 'package:tenant_module/src/features/pagamento/domain/model/quitacao.dart';
import 'package:tenant_module/src/features/pagamento/domain/parameters/pagamento_parameters.dart';
import 'package:tenant_module/src/features/pagamento/domain/usecases/pagamento_usecases.dart';

import '../../support/admin_client_mock.dart';

QuitarAssinaturaUsecase _usecase(MockAdminClient client) =>
    QuitarAssinaturaUsecase(
      repository: QuitarAssinaturaRepository(
        datasource: QuitarAssinaturaDatasource(client: client),
      ),
    );

QuitarAssinaturaParameters _params([String codigo = 'DEVTESTE']) =>
    QuitarAssinaturaParameters(provedor: 'voucher', credencial: codigo);

void main() {
  setUpAll(() {
    registrarFallbacksDoTenant();
    registerFallbackValue(proto.QuitarMinhaAssinaturaRequest());
  });

  late MockAdminClient client;

  setUp(() => client = MockAdminClient());

  group('quitar assinatura', () {
    test('código válido ativa a assinatura', () async {
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.QuitarMinhaAssinaturaResponse(
            confirmado: true,
            assinaturaStatus: 'ACTIVE',
          ),
        ),
      );

      final res = await _usecase(client)(_params());

      expect(res, isA<Success<Quitacao, PagamentoError>>());
      final q = (res as Success<Quitacao, PagamentoError>).value;
      expect(q.confirmado, isTrue);
      expect(q.assinaturaStatus, 'ACTIVE');
    });

    test('recusa do código é SUCESSO com motivo, não erro de RPC', () async {
      // A distinção é o cerne da tela: a mensagem precisa aparecer junto do
      // campo, para a pessoa reler enquanto digita o próximo código. Traduzir
      // isso para Failure a jogaria no caminho de erro genérico e perderia o
      // motivo que o servidor deu.
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.QuitarMinhaAssinaturaResponse(
            confirmado: false,
            assinaturaStatus: 'PENDING_PAYMENT',
            motivo: 'expirado',
            erroLegivel: 'Este código expirou.',
          ),
        ),
      );

      final res = await _usecase(client)(_params('VELHO'));

      expect(res, isA<Success<Quitacao, PagamentoError>>());
      final q = (res as Success<Quitacao, PagamentoError>).value;
      expect(q.confirmado, isFalse);
      expect(q.recusado, isTrue);
      expect(q.erroLegivel, 'Este código expirou.');
    });

    test('gateway externo pede para concluir fora do app', () async {
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.QuitarMinhaAssinaturaResponse(
            confirmado: false,
            urlExterna: 'https://pagar.exemplo/abc',
          ),
        ),
      );

      final q =
          ((await _usecase(client)(_params()))
                  as Success<Quitacao, PagamentoError>)
              .value;

      expect(q.exigeSaidaDoApp, isTrue);
      // `recusado` e `exigeSaidaDoApp` são excludentes: a tela escolhe entre
      // mostrar mensagem de erro e oferecer o link.
      expect(q.recusado, isFalse);
    });

    test('sem escopo de dono vira acesso negado', () async {
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final erro = ((await _usecase(client)(_params())) as Failure).error;

      expect(erro, isA<PagamentoAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
    });

    test('sessão expirada não vira "sem permissão"', () async {
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unauthenticated('token vencido')),
      );

      expect(
        ((await _usecase(client)(_params())) as Failure).error,
        isA<PagamentoSessaoExpirada>(),
      );
    });

    test('servidor fora do ar é falha de rede', () async {
      when(
        () => client.quitarMinhaAssinatura(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('offline')));

      final erro = ((await _usecase(client)(_params())) as Failure).error;

      expect(erro, isA<PagamentoIndisponivel>());
      expect(erro, isA<NetworkFailure>());
    });

    test('provedor desconhecido é dado inválido', () async {
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument('forma de pagamento indisponível'),
        ),
      );

      expect(
        ((await _usecase(client)(_params())) as Failure).error,
        isA<PagamentoDadosInvalidos>(),
      );
    });

    test('o código digitado chega ao servidor como veio', () async {
      // Guarda contra um "sanitizador" bem-intencionado que quebrasse códigos
      // válidos. A normalização (maiúsculas, espaços) é do servidor.
      final capturados = <String>[];
      when(() => client.quitarMinhaAssinatura(any())).thenAnswer((inv) {
        capturados.add(
          (inv.positionalArguments.first as proto.QuitarMinhaAssinaturaRequest)
              .credencial,
        );
        return respostaGrpc(
          proto.QuitarMinhaAssinaturaResponse(confirmado: true),
        );
      });

      await _usecase(client)(_params(' devteste '));

      expect(capturados.single, ' devteste ');
    });
  });

  group('modelo Quitacao', () {
    test('confirmado não é recusa nem saída do app', () {
      const q = Quitacao(confirmado: true, assinaturaStatus: 'ACTIVE');
      expect(q.recusado, isFalse);
      expect(q.exigeSaidaDoApp, isFalse);
    });
  });
}
