import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../fluxos/domain/model/fluxo.dart';
import '../../../fluxos/domain/usecases/fluxos_usecases.dart';
import '../../domain/errors/equipe_errors.dart';
import '../../domain/model/equipe.dart';
import '../../domain/parameters/equipe_parameters.dart';
import '../../domain/usecases/equipe_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Departamentos e atendentes do tenant.
final class EquipeController extends BaseController<Equipe> {
  final CarregarEquipeUsecase _carregar;
  final CriarDepartamentoUsecase _criar;
  final AtualizarDepartamentoUsecase _atualizar;
  final DesativarDepartamentoUsecase _desativar;
  final CriarAtendenteUsecase _criarAtendente;
  final AtualizarAtendenteUsecase _atualizarAtendente;
  final DesativarAtendenteUsecase _desativarAtendente;
  final ListarFluxosUsecase _fluxos;

  /// Fluxos ativos, para o seletor do atendente. `fluxo_id` é obrigatório no
  /// banco, e não há como escolher o que não se vê.
  List<Fluxo> _fluxosDisponiveis = const [];

  EquipeController({
    required CarregarEquipeUsecase carregar,
    required CriarDepartamentoUsecase criar,
    required AtualizarDepartamentoUsecase atualizar,
    required DesativarDepartamentoUsecase desativar,
    required CriarAtendenteUsecase criarAtendente,
    required AtualizarAtendenteUsecase atualizarAtendente,
    required DesativarAtendenteUsecase desativarAtendente,
    required ListarFluxosUsecase fluxos,
  })  : _carregar = carregar,
        _criar = criar,
        _atualizar = atualizar,
        _desativar = desativar,
        _criarAtendente = criarAtendente,
        _atualizarAtendente = atualizarAtendente,
        _desativarAtendente = desativarAtendente,
        _fluxos = fluxos;

  List<Fluxo> get fluxosDisponiveis => _fluxosDisponiveis;

  Future<void> carregar() async {
    final fluxos = await _fluxos(noParams);
    if (fluxos case Success(:final value)) {
      _fluxosDisponiveis = value.where((f) => f.ativo).toList();
    }
    await execute<EquipeError>(() => _carregar(noParams));
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> criarDepartamento({
    required String nome,
    required String descricao,
  }) async {
    final res = await _criar(
      CriarDepartamentoParameters(nome: nome, descricao: descricao),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> atualizarDepartamento({
    required int id,
    required String nome,
    required String descricao,
    required bool ativo,
  }) async {
    final res = await _atualizar(
      AtualizarDepartamentoParameters(
        id: id,
        nome: nome,
        descricao: descricao,
        ativo: ativo,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> desativarDepartamento(
    int id,
  ) async {
    final res = await _desativar(DepartamentoIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> criarAtendente({
    required String nome,
    required String email,
    required String cargo,
    required int fluxoId,
    required int departamentoId,
  }) async {
    final res = await _criarAtendente(
      CriarAtendenteParameters(
        nome: nome,
        email: email,
        cargo: cargo,
        fluxoId: fluxoId,
        departamentoId: departamentoId,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> atualizarAtendente({
    required int id,
    required String nome,
    required String cargo,
    required int departamentoId,
    required int fluxoId,
    required bool ativo,
    required bool disponivel,
    required int maxSimultaneos,
  }) async {
    final res = await _atualizarAtendente(
      AtualizarAtendenteParameters(
        id: id,
        nome: nome,
        cargo: cargo,
        departamentoId: departamentoId,
        fluxoId: fluxoId,
        ativo: ativo,
        disponivel: disponivel,
        maxSimultaneos: maxSimultaneos,
      ),
    );
    if (res is Success) await carregar();
    return res;
  }

  Future<ReturnSuccessOrError<Unit, EquipeError>> desativarAtendente(
    int id,
  ) async {
    final res = await _desativarAtendente(AtendenteIdParameters(id: id));
    if (res is Success) await carregar();
    return res;
  }
}
