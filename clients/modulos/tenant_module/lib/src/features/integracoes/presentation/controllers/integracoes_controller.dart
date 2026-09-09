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

  IntegracoesController({
    required ListMcpGrantsUsecase listUsecase,
    required RevokeMcpGrantUsecase revokeUsecase,
  }) : _listUsecase = listUsecase,
       _revokeUsecase = revokeUsecase;

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
}
