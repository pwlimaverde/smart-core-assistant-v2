// Regras do domínio do wizard: o que os usecases decidem e o que os
// repositórios traduzem. Sem transporte e sem UI — o datasource é um fake.
import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onboarding_module/src/features/cadastro/data/repositories/cadastro_repositories.dart';
import 'package:onboarding_module/src/features/cadastro/domain/errors/cadastro_errors.dart';
import 'package:onboarding_module/src/features/cadastro/domain/model/cadastro_models.dart';
import 'package:onboarding_module/src/features/cadastro/domain/parameters/cadastro_parameters.dart';
import 'package:onboarding_module/src/features/cadastro/domain/services/cadastro_sessao.dart';
import 'package:onboarding_module/src/features/cadastro/domain/usecases/cadastro_usecases.dart';
import 'package:onboarding_module/src/rota_publica.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Datasource de teste: devolve o valor combinado ou lança a exceção combinada.
final class _FakeDatasource<T, P extends Parameters>
    implements Datasource<T, P> {
  final T? valor;
  final Object? excecao;

  const _FakeDatasource({this.valor, this.excecao});

  @override
  Future<T> call(P parameters) async {
    if (excecao != null) throw excecao!;
    return valor as T;
  }
}

ConfirmarPagamentoUsecase _confirmarCom(ResultadoPagamento resultado) =>
    ConfirmarPagamentoUsecase(
      repository: ConfirmarPagamentoRepository(
        datasource: _FakeDatasource<ResultadoPagamento,
            ConfirmarPagamentoParameters>(valor: resultado),
      ),
    );

const _paramsPagamento = ConfirmarPagamentoParameters(
  tenantId: 't-1',
  signupToken: 'TOKEN',
  provedorId: 'voucher',
  credencial: 'DEVTESTE',
);

void main() {
  group('ConfirmarPagamentoUsecase', () {
    test('código recusado NÃO é falha — a tela precisa da mensagem', () async {
      // Um voucher expirado não é erro de sistema: o servidor respondeu, e a
      // resposta é "não". Tratar como Failure tornaria isso indistinguível de
      // servidor fora do ar.
      final usecase = _confirmarCom(
        const ResultadoPagamento(
          confirmado: false,
          urlRedirecionamento: '',
          mensagem: 'Este código expirou.',
        ),
      );

      final res = await usecase(_paramsPagamento);

      expect(res, isA<Success<ResultadoPagamento, CadastroError>>());
      final valor = (res as Success<ResultadoPagamento, CadastroError>).value;
      expect(valor.confirmado, isFalse);
      expect(valor.mensagem, 'Este código expirou.');
    });

    test('confirmação passa adiante', () async {
      final usecase = _confirmarCom(
        const ResultadoPagamento(
          confirmado: true,
          urlRedirecionamento: '',
          mensagem: '',
        ),
      );

      final res = await usecase(_paramsPagamento);

      expect(res, isA<Success<ResultadoPagamento, CadastroError>>());
    });

    test('redirecionamento de gateway passa adiante', () async {
      final usecase = _confirmarCom(
        const ResultadoPagamento(
          confirmado: false,
          urlRedirecionamento: 'https://gateway.exemplo/pagar/abc',
          mensagem: '',
        ),
      );

      final res = await usecase(_paramsPagamento);

      final valor =
          (res as Success<ResultadoPagamento, CadastroError>).value;
      expect(valor.exigeRedirecionamento, isTrue);
    });

    test('resposta incoerente falha em vez de virar tela muda', () async {
      // Não confirmou, não mandou pagar fora e não disse por quê: não há o que
      // mostrar ao usuário.
      final usecase = _confirmarCom(
        const ResultadoPagamento(
          confirmado: false,
          urlRedirecionamento: '',
          mensagem: '   ',
        ),
      );

      final res = await usecase(_paramsPagamento);

      expect(res, isA<Failure<ResultadoPagamento, CadastroError>>());
    });
  });

  group('IniciarCadastroUsecase', () {
    test('cadastro sem token de continuação é falha', () async {
      // Sem `signup_token` os passos seguintes são inalcançáveis; melhor falhar
      // com um botão de tentar de novo do que travar o usuário no passo 2.
      final usecase = IniciarCadastroUsecase(
        repository: IniciarCadastroRepository(
          datasource: const _FakeDatasource<CadastroIniciado,
              IniciarCadastroParameters>(
            valor: CadastroIniciado(
              tenantId: 't-1',
              signupToken: '',
              proximoPasso: 2,
            ),
          ),
        ),
      );

      final res = await usecase(
        const IniciarCadastroParameters(
          nome: 'Empresa',
          slug: 'empresa',
          email: 'a@b.com',
          senha: 'senhaforte8',
        ),
      );

      expect(res, isA<Failure<CadastroIniciado, CadastroError>>());
    });
  });

  group('ListarProvedoresUsecase', () {
    test('nenhuma forma de pagamento é indisponibilidade, não lista vazia',
        () async {
      // Sem provedor ninguém conclui o cadastro; a tela precisa dizer isso em
      // vez de mostrar um espaço em branco.
      final usecase = ListarProvedoresUsecase(
        repository: ListarProvedoresRepository(
          datasource:
              const _FakeDatasource<List<ProvedorPagamento>, SemParametros>(
            valor: <ProvedorPagamento>[],
          ),
        ),
      );

      final res = await usecase(const SemParametros());

      expect(res, isA<Failure<List<ProvedorPagamento>, CadastroError>>());
      expect(
        (res as Failure<List<ProvedorPagamento>, CadastroError>).error,
        isA<CadastroIndisponivel>(),
      );
    });
  });

  group('tradução de falha do transporte', () {
    Future<CadastroError> erroDe(Object excecao) async {
      final usecase = VerificarSlugUsecase(
        repository: VerificarSlugRepository(
          datasource: _FakeDatasource<SlugDisponibilidade, SlugParameters>(
            excecao: excecao,
          ),
        ),
      );
      final res = await usecase(const SlugParameters(slug: 'x'));
      return (res as Failure<SlugDisponibilidade, CadastroError>).error;
    }

    test('validação do servidor preserva a mensagem', () async {
      // É a única exceção à regra de não exibir texto do servidor: quem sabe
      // por que o endereço foi recusado é ele.
      final erro = await erroDe(
        GrpcError.invalidArgument('Este endereço já está em uso.'),
      );

      expect(erro, isA<CadastroDadosInvalidos>());
      expect(erro.message, 'Este endereço já está em uso.');
    });

    test('token inválido vira "não autorizado"', () async {
      expect(
        await erroDe(GrpcError.permissionDenied()),
        isA<CadastroNaoAutorizado>(),
      );
    });

    test('rate limit tem mensagem própria', () async {
      expect(
        await erroDe(GrpcError.resourceExhausted()),
        isA<CadastroBloqueadoPorTentativas>(),
      );
    });

    test('servidor fora do ar vira indisponibilidade', () async {
      expect(await erroDe(GrpcError.unavailable()), isA<CadastroIndisponivel>());
    });

    test('exceção que não é do transporte vira inesperado', () async {
      // O que não vem do gRPC (um bug no mapeamento, por exemplo) nunca é
      // classificado por palpite.
      expect(await erroDe(const FormatException('json')),
          isA<CadastroInesperado>());
    });
  });

  group('CadastroSessao', () {
    test('nasce sem cadastro em andamento', () {
      final sessao = CadastroSessao();
      expect(sessao.iniciado, isFalse);
      expect(sessao.temPlano, isFalse);
    });

    test('encerrar apaga a senha da memória', () {
      // A senha só existe para o login automático do passo 4; depois dele, não
      // pode sobrar nada.
      final sessao = CadastroSessao()
        ..registrarInicio(tenantId: 't-1', signupToken: 'TOK')
        ..registrarCredenciais(email: 'a@b.com', senha: 'segredo123')
        ..registrarPlano(3);

      expect(sessao.iniciado, isTrue);
      expect(sessao.temPlano, isTrue);

      sessao.encerrar();

      expect(sessao.iniciado, isFalse);
      expect(sessao.temPlano, isFalse);
      expect(sessao.email, isEmpty);
      expect(sessao.senha, isEmpty);
    });
  });

  group('ehRotaDeCadastro', () {
    test('reconhece as rotas do wizard', () {
      expect(ehRotaDeCadastro('/cadastro'), isTrue);
      expect(ehRotaDeCadastro('/cadastro/plano'), isTrue);
      expect(ehRotaDeCadastro('/cadastro/pagamento'), isTrue);
      expect(ehRotaDeCadastro('/cadastro/pronto'), isTrue);
    });

    test('não abre a mão para caminhos parecidos', () {
      // `/cadastros-internos` não pode virar rota pública por prefixo solto.
      expect(ehRotaDeCadastro('/cadastros-internos'), isFalse);
      expect(ehRotaDeCadastro('/login'), isFalse);
      expect(ehRotaDeCadastro('/atendimentos'), isFalse);
    });
  });
}
