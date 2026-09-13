import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/clientes_errors.dart';
import '../../domain/model/cliente.dart';
import '../../domain/parameters/clientes_parameters.dart';
import '../../domain/usecases/clientes_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// B10 (N11 E5) — clientes do tenant.
final class ClientesController extends BaseController<List<Cliente>> {
  final ListarClientesUsecase _listar;
  final SalvarClienteUsecase _salvar;
  final DefinirClienteAtivoUsecase _definirAtivo;
  final ListarContatosDoClienteUsecase _contatos;
  final VincularContatoUsecase _vincular;

  String _busca = '';
  bool _incluirInativos = false;

  ClientesController({
    required ListarClientesUsecase listar,
    required SalvarClienteUsecase salvar,
    required DefinirClienteAtivoUsecase definirAtivo,
    required ListarContatosDoClienteUsecase contatos,
    required VincularContatoUsecase vincular,
  }) : _listar = listar,
       _salvar = salvar,
       _definirAtivo = definirAtivo,
       _contatos = contatos,
       _vincular = vincular;

  String get busca => _busca;
  bool get incluirInativos => _incluirInativos;

  Future<void> carregar({String? busca, bool? incluirInativos}) {
    if (busca != null) _busca = busca;
    if (incluirInativos != null) _incluirInativos = incluirInativos;
    return execute<ClientesError>(
      () => _listar(
        ListarClientesParameters(
          busca: _busca,
          incluirInativos: _incluirInativos,
        ),
      ),
    );
  }

  /// Devolve o erro, ou `null` no sucesso — a janela mostra o erro dentro dela.
  Future<ClientesError?> salvar({int? id, required DadosCliente dados}) async {
    final res = await _salvar(SalvarClienteParameters(id: id, dados: dados));
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<ClientesError?> definirAtivo({
    required int id,
    required bool ativo,
  }) async {
    final res = await _definirAtivo(
      DefinirClienteAtivoParameters(id: id, ativo: ativo),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<ReturnSuccessOrError<List<ContatoDoCliente>, ClientesError>>
  contatosDe(int clienteId) => _contatos(ClienteIdParameters(id: clienteId));

  /// Liga ou desliga; recarrega a lista para o contador acompanhar.
  Future<ClientesError?> vincular({
    required int clienteId,
    required int contatoId,
    bool vincular = true,
  }) async {
    final res = await _vincular(
      VincularContatoParameters(
        clienteId: clienteId,
        contatoId: contatoId,
        vincular: vincular,
      ),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }
}
