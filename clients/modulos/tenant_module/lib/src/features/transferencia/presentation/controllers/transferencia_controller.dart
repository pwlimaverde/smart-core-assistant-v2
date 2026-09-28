import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/transferencia_errors.dart';
import '../../domain/model/transferencia.dart';
import '../../domain/parameters/transferencia_parameters.dart';
import '../../domain/usecases/transferencia_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// "Transferência para atendente": sinais, regras, padrões e as últimas
/// transferências.
final class TransferenciaController
    extends BaseController<PainelTransferencia> {
  final CarregarTransferenciaUsecase _carregar;
  final SalvarRegraUsecase _salvar;
  final DefinirRegraAtivaUsecase _ativa;
  final DefinirSinaisUsecase _sinais;
  final TestarRegraUsecase _testar;
  final GerarSugestoesUsecase _sugestoes;

  TransferenciaController({
    required CarregarTransferenciaUsecase carregar,
    required SalvarRegraUsecase salvar,
    required DefinirRegraAtivaUsecase ativa,
    required DefinirSinaisUsecase sinais,
    required TestarRegraUsecase testar,
    required GerarSugestoesUsecase sugestoes,
  }) : _carregar = carregar,
       _salvar = salvar,
       _ativa = ativa,
       _sinais = sinais,
       _testar = testar,
       _sugestoes = sugestoes;

  Future<void> carregar() =>
      execute<TransferenciaError>(() => _carregar(noParams));

  /// As mutações devolvem o erro em vez de emiti-lo: recarregar depois de
  /// falhar apagaria da tela o motivo da falha.
  Future<TransferenciaError?> salvar(RegraDeTransferencia regra) async {
    final res = await _salvar(SalvarRegraParameters(regra));
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<TransferenciaError?> definirAtiva(
    RegraDeTransferencia regra, {
    required bool ativa,
  }) async {
    final res = await _ativa(
      RegraAtivaParameters(
        id: regra.id,
        ativa: ativa,
        // A tela já pediu a confirmação na caixa de diálogo; o servidor
        // confere pelo nome.
        confirmar: ativa ? '' : regra.nome,
      ),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<TransferenciaError?> alterarSinal(SinalAutomatico sinal) async {
    final res = await _sinais(SinaisParameters(sinais: [sinal]));
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<TransferenciaError?> definirFluxoPadrao(int? fluxoId) async {
    final res = await _sinais(
      SinaisParameters(alterarFluxoPadrao: true, fluxoPadraoId: fluxoId),
    );
    if (res case Failure(:final error)) return error;
    await carregar();
    return null;
  }

  Future<ReturnSuccessOrError<ResultadoTesteRegra, TransferenciaError>> testar({
    required String frase,
    required RegraDeTransferencia regra,
  }) => _testar(TestarRegraParameters(frase: frase, regra: regra));

  Future<ReturnSuccessOrError<int, TransferenciaError>> gerarSugestoes() async {
    final res = await _sugestoes(noParams);
    if (res is Success) await carregar();
    return res;
  }
}
