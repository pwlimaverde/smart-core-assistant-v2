import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/integracoes_errors.dart';
import '../../domain/model/mcp_grant.dart';
import '../../domain/parameters/integracoes_parameters.dart';
import '../../domain/usecases/integracoes_usecases.dart';

/// Controller da tela de aplicativos conectados (N13.8).
///
/// Mesmo padrão da tela de convites: só o carregamento da lista passa pelo
/// [BaseController.execute]; a desconexão devolve o resultado para que a lista
/// continue visível e a falha apareça em snackbar.
final class IntegracoesController extends BaseController<List<McpGrant>> {
  final ListMcpGrantsUsecase _listUsecase;
  final RevokeMcpGrantUsecase _revokeUsecase;

  /// B7 — opcional: sem ele a tela só não oferece o ajuste.
  final AjustarEscoposMcpGrantUsecase? _ajustarUsecase;

  IntegracoesController({
    required this._listUsecase,
    required this._revokeUsecase,
    this._ajustarUsecase,
  });

  bool get podeAjustar => _ajustarUsecase != null;

  Future<void> fetchGrants() => execute(() => _listUsecase(noParams));

  /// Desconecta um aplicativo. No sucesso devolve a janela de revogação em
  /// minutos, que a tela usa para dizer ao usuário quanto tempo o acesso em
  /// curso ainda pode durar.
  Future<ReturnSuccessOrError<int, IntegracoesError>> revokeGrant(
    String grantId,
  ) async {
    final res = await _revokeUsecase(
      RevokeMcpGrantParameters(grantId: grantId),
    );
    if (res is Success) await fetchGrants();
    return res;
  }

  /// B7 — deixa o aplicativo só com [scopes]. No sucesso devolve em quantos
  /// minutos o agente sente a mudança, e recarrega a lista.
  Future<ReturnSuccessOrError<int, IntegracoesError>> ajustarEscopos(
    String grantId,
    List<String> scopes,
  ) async {
    final usecase = _ajustarUsecase;
    if (usecase == null) return const Failure(IntegracoesInesperado());
    final res = await usecase(
      AjustarEscoposMcpGrantParameters(grantId: grantId, scopes: scopes),
    );
    if (res is Success) await fetchGrants();
    return res;
  }
}
