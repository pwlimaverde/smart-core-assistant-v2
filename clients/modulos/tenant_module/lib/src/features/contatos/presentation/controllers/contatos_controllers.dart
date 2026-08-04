import 'package:presentation_module/presentation_module.dart';

import '../../domain/errors/contatos_errors.dart';
import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';
import '../../domain/usecases/contatos_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Contatos do tenant.
final class ContatosController extends BaseController<List<Contato>> {
  final ListarContatosUsecase _listar;

  /// O que está filtrando a lista agora. Guardado aqui para que recarregar
  /// (botão ou volta de outra tela) não perca o filtro que a pessoa digitou.
  String _busca = '';

  ContatosController({required ListarContatosUsecase listar})
      : _listar = listar;

  String get busca => _busca;

  /// A busca é do servidor, não da lista já carregada: existe teto de linhas,
  /// e filtrar no cliente esconderia quem ficou além dele.
  Future<void> carregar({String? busca}) {
    if (busca != null) _busca = busca;
    return execute<ContatosError>(
      () => _listar(ListarContatosParameters(busca: _busca)),
    );
  }
}
