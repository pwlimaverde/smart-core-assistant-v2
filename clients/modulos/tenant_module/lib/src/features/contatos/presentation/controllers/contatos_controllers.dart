import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/contatos_errors.dart';
import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';
import '../../domain/usecases/contatos_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Contatos do tenant.
final class ContatosController extends BaseController<List<Contato>> {
  final ListarContatosUsecase _listar;
  final CriarContatoUsecase _criar;
  final AtualizarContatoUsecase _atualizar;
  final DefinirContatoAtivoUsecase _definirAtivo;

  /// O que está filtrando a lista agora. Guardado aqui para que recarregar
  /// (botão ou volta de outra tela) não perca o filtro que a pessoa digitou.
  String _busca = '';

  ContatosController({
    required ListarContatosUsecase listar,
    required CriarContatoUsecase criar,
    required AtualizarContatoUsecase atualizar,
    required DefinirContatoAtivoUsecase definirAtivo,
  }) : _listar = listar,
       _criar = criar,
       _atualizar = atualizar,
       _definirAtivo = definirAtivo;

  String get busca => _busca;

  /// A busca é do servidor, não da lista já carregada: existe teto de linhas,
  /// e filtrar no cliente esconderia quem ficou além dele.
  Future<void> carregar({String? busca}) {
    if (busca != null) _busca = busca;
    return execute<ContatosError>(
      () => _listar(ListarContatosParameters(busca: _busca)),
    );
  }

  /// Devolve o erro, ou `null` em caso de sucesso.
  ///
  /// A janela precisa do erro para mostrá-lo **dentro dela** — fechar e piscar
  /// um aviso atrás faria a pessoa perder o que digitou.
  Future<ContatosError?> criar(CriarContatoParameters p) async {
    final res = await _criar(p);
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<ContatosError?> atualizar(AtualizarContatoParameters p) async {
    final res = await _atualizar(p);
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<ContatosError?> definirAtivo({
    required int id,
    required bool ativo,
  }) async {
    final res = await _definirAtivo(
      DefinirContatoAtivoParameters(id: id, ativo: ativo),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }
}
