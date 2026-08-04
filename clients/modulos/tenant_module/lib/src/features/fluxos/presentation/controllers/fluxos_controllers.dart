import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../equipe/domain/model/equipe.dart';
import '../../../equipe/domain/usecases/equipe_usecases.dart';
import '../../domain/errors/fluxos_errors.dart';
import '../../domain/model/fluxo.dart';
import '../../domain/parameters/fluxos_parameters.dart';
import '../../domain/usecases/fluxos_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Fluxos do tenant.
final class FluxosController extends BaseController<List<Fluxo>> {
  final ListarFluxosUsecase _listar;
  final CriarFluxoUsecase _criar;
  final AtualizarFluxoUsecase _atualizar;
  final DesativarFluxoUsecase _desativar;
  final CarregarEquipeUsecase _equipe;

  /// Departamentos para o seletor da criação. Um fluxo pertence a um
  /// departamento, e não há como escolher o que não se vê.
  List<Departamento> _departamentos = const [];

  FluxosController({
    required ListarFluxosUsecase listar,
    required CriarFluxoUsecase criar,
    required AtualizarFluxoUsecase atualizar,
    required DesativarFluxoUsecase desativar,
    required CarregarEquipeUsecase equipe,
  })  : _listar = listar,
        _criar = criar,
        _atualizar = atualizar,
        _desativar = desativar,
        _equipe = equipe;

  List<Departamento> get departamentos => _departamentos;

  Future<void> carregar() async {
    // Os departamentos vêm do usecase que a tela de equipe já usa, em vez de
    // um RPC próprio: é a mesma lista, e duplicá-la abriria espaço para as
    // duas telas discordarem.
    final equipe = await _equipe(noParams);
    if (equipe case Success(:final value)) {
      _departamentos = value.departamentos.where((d) => d.ativo).toList();
    }
    await execute<FluxosError>(() => _listar(noParams));
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> criar({
    required int departamentoId,
    required String nome,
    required String descricao,
  }) async {
    final res = await _criar(
      CriarFluxoParameters(
        departamentoId: departamentoId,
        nome: nome,
        descricao: descricao,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> atualizar({
    required int id,
    required String nome,
    required String descricao,
    required bool ativo,
  }) async {
    final res = await _atualizar(
      AtualizarFluxoParameters(
        id: id,
        nome: nome,
        descricao: descricao,
        ativo: ativo,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> desativar(int id) async {
    final res = await _desativar(FluxoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}

/// Etapas de um fluxo.
final class EtapasFluxoController extends BaseController<List<EtapaFluxo>> {
  final ListarEtapasUsecase _listar;
  final CriarEtapaUsecase _criar;
  final AtualizarEtapaUsecase _atualizar;
  final DesativarEtapaUsecase _desativar;
  final MoverEtapaUsecase _mover;

  int _fluxoId = 0;

  EtapasFluxoController({
    required ListarEtapasUsecase listar,
    required CriarEtapaUsecase criar,
    required AtualizarEtapaUsecase atualizar,
    required DesativarEtapaUsecase desativar,
    required MoverEtapaUsecase mover,
  })  : _listar = listar,
        _criar = criar,
        _atualizar = atualizar,
        _desativar = desativar,
        _mover = mover;

  int get fluxoId => _fluxoId;

  Future<void> carregar(int fluxoId) {
    _fluxoId = fluxoId;
    return execute<FluxosError>(
      () => _listar(FluxoIdParameters(id: fluxoId)),
    );
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> criarEtapa({
    required String nome,
    required TipoEtapa tipo,
    required String cor,
  }) async {
    final res = await _criar(
      CriarEtapaParameters(
        fluxoId: _fluxoId,
        nome: nome,
        tipo: tipo,
        cor: cor,
      ),
    );
    if (res is Success) await carregar(_fluxoId);
    return res;
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> atualizarEtapa({
    required int id,
    required String nome,
    required String descricao,
    required String cor,
    required TipoEtapa tipo,
  }) async {
    final res = await _atualizar(
      AtualizarEtapaParameters(
        id: id,
        nome: nome,
        descricao: descricao,
        cor: cor,
        tipo: tipo,
      ),
    );
    if (res is Success) await carregar(_fluxoId);
    return res;
  }

  Future<ReturnSuccessOrError<Unit, FluxosError>> removerEtapa(int id) async {
    final res = await _desativar(EtapaIdParameters(id: id));
    if (res is Success) await carregar(_fluxoId);
    return res;
  }

  /// Move a etapa e recarrega. Recarrega em vez de reordenar a lista local: a
  /// ordem é do servidor, e uma lista local otimista mostraria uma sequência
  /// que talvez não seja a que ficou gravada.
  Future<ReturnSuccessOrError<bool, FluxosError>> mover({
    required int id,
    required bool paraCima,
  }) async {
    final res = await _mover(
      MoverEtapaParameters(id: id, paraCima: paraCima),
    );
    if (res case Success(value: true)) await carregar(_fluxoId);
    return res;
  }
}
