import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/pagamento_errors.dart';
import '../../domain/model/quitacao.dart';
import '../../domain/parameters/pagamento_parameters.dart';
import '../../domain/usecases/pagamento_usecases.dart';

/// Controller da tela de pagamento pós-login.
///
/// O estado observável é a [Quitacao] da última tentativa — daí o
/// `BaseController<Quitacao>`. A tela **não** usa `ViewStateBuilder` para a
/// recusa: ela lê o retorno de [quitar] e mostra a mensagem junto do campo,
/// porque uma recusa de código é algo que a pessoa relê enquanto digita o
/// próximo. O estado serve para o indicador de "enviando".
final class PagamentoController extends BaseController<Quitacao> {
  final QuitarAssinaturaUsecase _quitar;

  PagamentoController({required QuitarAssinaturaUsecase quitar})
    // ignore: prefer_initializing_formals
    : _quitar = quitar;

  /// `true` enquanto a chamada está em voo.
  bool get enviando => state is LoadingState<Quitacao>;

  Future<ReturnSuccessOrError<Quitacao, PagamentoError>> quitar({
    required String credencial,
    String provedor = 'voucher',
  }) async {
    // Guarda contra o clique duplo na própria tela. A idempotência de verdade é
    // do servidor (assinatura já ACTIVE não consome resgate); evitar a segunda
    // chamada só poupa uma corrida desnecessária.
    if (enviando) {
      return const Success(
        Quitacao(confirmado: false, motivo: 'em_andamento', erroLegivel: ''),
      );
    }

    emit(LoadingState<Quitacao>());
    final res = await _quitar(
      QuitarAssinaturaParameters(provedor: provedor, credencial: credencial),
    );

    switch (res) {
      case Success(:final value):
        emit(SuccessState<Quitacao>(value));
      case Failure(:final error):
        emit(ErrorState<Quitacao>(error));
    }
    return res;
  }
}
