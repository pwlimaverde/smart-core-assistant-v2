import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/conexoes_errors.dart';
import '../../domain/model/conexao.dart';
import '../../domain/parameters/conexoes_parameters.dart';
import '../../domain/usecases/conexoes_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Conexões de WhatsApp do tenant.
final class ConexoesController extends BaseController<List<Conexao>> {
  final ListarConexoesUsecase _listar;
  final ReconectarConexaoUsecase _reconectar;
  final RemoverConexaoUsecase _remover;
  final CriarConexaoUsecase _criar;
  final EstadoPareamentoUsecase _pareamento;
  final DefinirRespostaBotUsecase _respostaBot;

  /// P7 — opcionais porque o quadro embute este controller só para a faixa de
  /// aviso de conexão fora do ar, e aquele app não registra o módulo inteiro.
  final DesconectarConexaoUsecase? _desconectar;
  final DefinirDepartamentoDaConexaoUsecase? _definirDepartamento;
  final DetalheDaConexaoUsecase? _detalhe;

  ConexoesController({
    required ListarConexoesUsecase listar,
    required ReconectarConexaoUsecase reconectar,
    required RemoverConexaoUsecase remover,
    required CriarConexaoUsecase criar,
    required EstadoPareamentoUsecase pareamento,
    required DefinirRespostaBotUsecase respostaBot,
    DesconectarConexaoUsecase? desconectar,
    DefinirDepartamentoDaConexaoUsecase? definirDepartamento,
    DetalheDaConexaoUsecase? detalhe,
  }) : _desconectar = desconectar,
       _definirDepartamento = definirDepartamento,
       _detalhe = detalhe,
       _listar = listar,
       _reconectar = reconectar,
       _remover = remover,
       _criar = criar,
       _pareamento = pareamento,
       _respostaBot = respostaBot;

  /// Lista as conexões e confere o estado de cada uma COM O PROVEDOR.
  ///
  /// A listagem sozinha devolve `connection_state` como está no banco, e esse
  /// valor envelhece: uma sessão que caiu no WhatsApp continua gravada como
  /// `connected` até alguém consultar. A tela então mostrava "Conectada" para
  /// uma conexão morta — e escondia justamente o botão de reconectar.
  ///
  /// A consulta de estado é a mesma que o pareamento usa; além de responder o
  /// estado real, ela regrava o banco. Best-effort por item: uma conexão cujo
  /// provedor não respondeu fica com o valor do banco em vez de derrubar a
  /// lista inteira.
  Future<void> carregar() => execute<ConexoesError>(() async {
    final res = await _listar(noParams);
    if (res is! Success<List<Conexao>, ConexoesError>) return res;

    final conferidas = <Conexao>[];
    for (final conexao in res.value) {
      final estado = await _pareamento(ConexaoIdParameters(id: conexao.id));
      conferidas.add(
        estado is Success<EstadoPareamento, ConexoesError>
            ? conexao.comEstado(estado.value.estado)
            : conexao,
      );
    }
    return Success(conferidas);
  });

  /// As mutações devolvem o resultado para a tela dizer o que houve, e só
  /// recarregam quando deram certo — recarregar depois de falhar apagaria da
  /// tela o motivo dela.
  Future<ReturnSuccessOrError<Unit, ConexoesError>> reconectar(int id) async {
    final res = await _reconectar(ConexaoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, ConexoesError>> remover(int id) async {
    final res = await _remover(ConexaoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }

  /// D3 — liga/desliga a IA para a conexão inteira.
  ///
  /// **Não chama [carregar] no sucesso**, diferente das outras mutações: aquele
  /// método consulta o provedor conexão por conexão, e gastar essa varredura
  /// para refletir um interruptor deixaria o toggle lento sem necessidade.
  /// Troca só o item na lista já carregada.
  Future<ReturnSuccessOrError<bool, ConexoesError>> definirRespostaBot(
    int id,
    bool habilitado,
  ) async {
    final res = await _respostaBot(
      RespostaBotParameters(id: id, habilitado: habilitado),
    );
    if (res case Success(:final value)) {
      if (state case SuccessState<List<Conexao>>(:final data)) {
        emit(
          SuccessState<List<Conexao>>([
            for (final c in data)
              if (c.id == id) c.comRespostaBot(value) else c,
          ]),
        );
      }
    }
    return res;
  }

  /// P7 — encerra a SESSÃO sem apagar a conexão.
  ///
  /// Recarrega no sucesso, como as outras mutações: o estado muda para
  /// desconectada e a tela precisa oferecer o QR em seguida.
  Future<ReturnSuccessOrError<Unit, ConexoesError>> desconectar(int id) async {
    final usecase = _desconectar;
    if (usecase == null) return Success(unit);
    final res = await usecase(ConexaoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }

  /// P7 — para qual departamento este número roteia. 0 desfaz o vínculo.
  ///
  /// Não chama [carregar]: aquele método consulta o provedor conexão por
  /// conexão, e gastar a varredura para refletir um rótulo deixaria a troca
  /// lenta sem necessidade. Troca só o item na lista já carregada.
  Future<ReturnSuccessOrError<Unit, ConexoesError>> definirDepartamento({
    required int id,
    required int departamentoId,
    required String departamentoNome,
  }) async {
    final usecase = _definirDepartamento;
    if (usecase == null) return Success(unit);
    final res = await usecase(
      DepartamentoDaConexaoParameters(id: id, departamentoId: departamentoId),
    );
    if (res is Success) {
      if (state case SuccessState<List<Conexao>>(:final data)) {
        emit(
          SuccessState<List<Conexao>>([
            for (final c in data)
              if (c.id == id)
                c.comDepartamento(departamentoId, departamentoNome)
              else
                c,
          ]),
        );
      }
    }
    return res;
  }

  /// P7 — o detalhe da conexão. NÃO recarrega a lista: quem chama está abrindo
  /// uma caixa sobre ela.
  Future<ReturnSuccessOrError<DetalheConexao, ConexoesError>> detalhe(
    int id,
  ) async {
    final usecase = _detalhe;
    if (usecase == null) {
      return const Failure(ConexoesInesperado());
    }
    return usecase(ConexaoIdParameters(id: id));
  }

  Future<ReturnSuccessOrError<ConexaoCriada, ConexoesError>> criar(
    String nome,
  ) async {
    final res = await _criar(CriarConexaoParameters(nome: nome));
    if (res is Success) await carregar();
    return res;
  }

  /// Consulta o pareamento. NÃO recarrega a lista: quem chama está num diálogo
  /// que consulta de segundos em segundos, e recarregar junto piscaria a tela
  /// atrás dele a cada volta.
  Future<ReturnSuccessOrError<EstadoPareamento, ConexoesError>>
  consultarPareamento(int id) => _pareamento(ConexaoIdParameters(id: id));
}
