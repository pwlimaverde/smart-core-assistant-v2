import 'package:login_module/login_module.dart' as login;
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/cadastro_errors.dart';
import '../../domain/model/cadastro_models.dart';
import '../../domain/parameters/cadastro_parameters.dart';
import '../../domain/services/cadastro_sessao.dart';
import '../../domain/usecases/cadastro_usecases.dart';

/// Controllers do wizard — um por passo.
///
/// Seguem o padrão da casa (ver `TenantsController`): o `ViewState` carrega o
/// **dado principal da tela**, e as ações que apenas avançam devolvem
/// `ReturnSuccessOrError` direto para a página decidir o que fazer. Um `execute`
/// para cada clique deixaria a tela piscando entre loading e lista.

/// Passo 1 — dados da empresa e do responsável.
final class DadosController extends BaseController<CadastroIniciado> {
  final IniciarCadastroUsecase _iniciar;
  final VerificarSlugUsecase _verificarSlug;
  final CadastroSessao _sessao;

  DadosController({
    required this._iniciar,
    required this._verificarSlug,
    required this._sessao,
  });

  /// Checagem de disponibilidade enquanto o usuário digita. Fora do `ViewState`
  /// de propósito: é feedback de um campo, não o estado da tela.
  Future<ReturnSuccessOrError<SlugDisponibilidade, CadastroError>>
      verificarSlug(String slug) => _verificarSlug(SlugParameters(slug: slug));

  Future<void> iniciar({
    required String nome,
    required String slug,
    required String email,
    required String senha,
    String telefone = '',
  }) async {
    await execute<CadastroError>(() async {
      final res = await _iniciar(
        IniciarCadastroParameters(
          nome: nome,
          slug: slug,
          email: email,
          senha: senha,
          telefone: telefone,
        ),
      );
      // Só grava na sessão o que deu certo — um cadastro pela metade não pode
      // deixar `tenant_id` sujo para a tela seguinte.
      if (res case Success(:final value)) {
        _sessao
          ..registrarInicio(
            tenantId: value.tenantId,
            signupToken: value.signupToken,
          )
          ..registrarCredenciais(email: email, senha: senha);
      }
      return res;
    });
  }
}

/// Passo 2 — escolha do plano.
final class PlanoController extends BaseController<List<PlanoPublico>> {
  final ListarPlanosUsecase _listar;
  final SelecionarPlanoUsecase _selecionar;
  final CadastroSessao _sessao;

  PlanoController({
    required this._listar,
    required this._selecionar,
    required this._sessao,
  });

  Future<void> carregar() =>
      execute<CadastroError>(() => _listar(const SemParametros()));

  Future<ReturnSuccessOrError<int, CadastroError>> selecionar(int planoId) async {
    final res = await _selecionar(
      SelecionarPlanoParameters(
        tenantId: _sessao.tenantId,
        signupToken: _sessao.signupToken,
        planoId: planoId,
      ),
    );
    if (res is Success) _sessao.registrarPlano(planoId);
    return res;
  }
}

/// Passo 3 — pagamento.
final class PagamentoController extends BaseController<List<ProvedorPagamento>> {
  final ListarProvedoresUsecase _listar;
  final ConfirmarPagamentoUsecase _confirmar;
  final CadastroSessao _sessao;

  PagamentoController({
    required this._listar,
    required this._confirmar,
    required this._sessao,
  });

  Future<void> carregar() =>
      execute<CadastroError>(() => _listar(const SemParametros()));

  /// Recusa (código inválido) volta como `Success` com `confirmado: false` — a
  /// tela mostra `mensagem` no campo. `Failure` aqui é falha de verdade.
  Future<ReturnSuccessOrError<ResultadoPagamento, CadastroError>> confirmar({
    required String provedorId,
    String credencial = '',
  }) =>
      _confirmar(
        ConfirmarPagamentoParameters(
          tenantId: _sessao.tenantId,
          signupToken: _sessao.signupToken,
          provedorId: provedorId,
          credencial: credencial,
        ),
      );
}

/// Passo 4 — conclusão: acompanha o estado e entra na conta.
final class ConclusaoController extends BaseController<StatusCadastro> {
  final StatusCadastroUsecase _status;
  final CadastroSessao _sessao;
  final login.AuthService _auth;

  ConclusaoController({
    required this._status,
    required this._sessao,
    required this._auth,
  });

  /// Consulta o estado. Com pagamento imediato (voucher) já vem ativo; com
  /// gateway, é o que a tela repete até a confirmação chegar pelo webhook.
  Future<void> consultar() => execute<CadastroError>(
        () => _status(
          StatusCadastroParameters(
            tenantId: _sessao.tenantId,
            signupToken: _sessao.signupToken,
          ),
        ),
      );

  /// Entra com as credenciais que o usuário acabou de definir e encerra a
  /// sessão do wizard (apagando a senha da memória).
  ///
  /// A navegação não acontece aqui: o guard do app reage a `authChanges` e leva
  /// para o workspace sozinho.
  Future<ReturnSuccessOrError<login.Session, login.LoginError>> entrar() async {
    final res = await _auth.login(email: _sessao.email, password: _sessao.senha);
    if (res is Success) _sessao.encerrar();
    return res;
  }
}
