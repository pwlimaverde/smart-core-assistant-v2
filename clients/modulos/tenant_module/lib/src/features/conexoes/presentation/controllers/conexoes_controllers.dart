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

  ConexoesController({
    required ListarConexoesUsecase listar,
    required ReconectarConexaoUsecase reconectar,
    required RemoverConexaoUsecase remover,
    required CriarConexaoUsecase criar,
    required EstadoPareamentoUsecase pareamento,
  })  : _listar = listar,
        _reconectar = reconectar,
        _remover = remover,
        _criar = criar,
        _pareamento = pareamento;

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
