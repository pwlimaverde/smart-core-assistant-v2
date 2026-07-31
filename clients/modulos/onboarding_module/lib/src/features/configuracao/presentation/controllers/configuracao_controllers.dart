import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/configuracao_errors.dart';
import '../../domain/model/configuracao_models.dart';
import '../../domain/parameters/configuracao_parameters.dart';
import '../../domain/usecases/configuracao_usecases.dart';

/// Controllers da configuração guiada — um por passo.
///
/// Todos recebem o [ProgressoUsecase]: cada tela concluída registra o avanço no
/// servidor, para que fechar o app e reabrir continue de onde parou.

/// Passo 5 — conectar o WhatsApp.
///
/// O `ViewState` carrega o [EstadoConexao] porque é o que a tela mostra: o QR e
/// o andamento do pareamento, consultados em intervalos.
final class ConexaoController extends BaseController<EstadoConexao> {
  final CriarConexaoUsecase _criarUsecase;
  final EstadoConexaoUsecase _estado;
  final ProgressoUsecase _progresso;

  ConexaoController({
    required CriarConexaoUsecase criar,
    required this._estado,
    required this._progresso,
  }) : _criarUsecase = criar;

  int? _instanciaId;

  /// Id da conexão criada; `null` antes de criar.
  int? get instanciaId => _instanciaId;

  /// Cria a conexão no provedor. Devolve o resultado direto — a tela precisa
  /// distinguir "limite do plano" de falha de rede, e um `ViewState` de erro
  /// esconderia essa diferença atrás de uma mensagem só.
  Future<ReturnSuccessOrError<ConexaoWhatsapp, ConfiguracaoError>> criar(
    String nome,
  ) async {
    final res = await _criarUsecase(CriarConexaoParameters(nome: nome));
    if (res case Success(:final value)) _instanciaId = value.id;
    return res;
  }

  /// Consulta o pareamento. Chamada em intervalos enquanto o QR está na tela.
  Future<void> consultar() async {
    final id = _instanciaId;
    if (id == null) return;
    await execute<ConfiguracaoError>(
      () => _estado(EstadoConexaoParameters(id: id)),
    );
  }

  /// `true` quando o WhatsApp já pareou.
  bool get conectado {
    final s = state;
    return s is SuccessState<EstadoConexao> && s.data.conectado;
  }

  Future<void> registrarAvanco() =>
      _progresso(const ProgressoParameters(passo: 6));
}

/// Passo 6 — primeiro departamento.
final class DepartamentoController extends BaseController<Departamento> {
  final CriarDepartamentoUsecase _criarUsecase;
  final ProgressoUsecase _progresso;

  DepartamentoController({
    required CriarDepartamentoUsecase criar,
    required this._progresso,
  }) : _criarUsecase = criar;

  Future<ReturnSuccessOrError<Departamento, ConfiguracaoError>> criar({
    required String nome,
    String descricao = '',
  }) =>
      _criarUsecase(CriarDepartamentoParameters(nome: nome, descricao: descricao));

  Future<void> registrarAvanco() =>
      _progresso(const ProgressoParameters(passo: 7));
}

/// Passo 7 — persona do bot.
final class PersonaController extends BaseController<Unit> {
  final DefinirPersonaUsecase _definirUsecase;
  final ProgressoUsecase _progresso;

  PersonaController({
    required DefinirPersonaUsecase definir,
    required this._progresso,
  }) : _definirUsecase = definir;

  Future<ReturnSuccessOrError<Unit, ConfiguracaoError>> definir({
    required String persona,
    required String nomeDoAgente,
  }) =>
      _definirUsecase(
        PersonaParameters(personaBot: persona, nomeDoAgente: nomeDoAgente),
      );

  Future<void> registrarAvanco() =>
      _progresso(const ProgressoParameters(passo: 8));
}

/// Passo 8 — conclusão.
final class ConclusaoConfiguracaoController
    extends BaseController<ProgressoOnboarding> {
  final ProgressoUsecase _progresso;

  ConclusaoConfiguracaoController({required this._progresso});

  /// Marca a configuração como concluída. É este ponto — e não o pagamento —
  /// que grava `setup_completed` no servidor.
  Future<ReturnSuccessOrError<ProgressoOnboarding, ConfiguracaoError>>
      concluir() =>
          _progresso(const ProgressoParameters(passo: 8, concluido: true));
}
