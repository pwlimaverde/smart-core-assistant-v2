import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros do wizard de cadastro.
///
/// **Um conjunto para a feature inteira**, e não um por operação: as sete
/// operações do wizard compartilham o mesmo repertório (dados recusados,
/// cadastro não autorizado, servidor fora, inesperado). É o caso que a
/// `anatomia-modulo.md` descreve como o comum — diferente do login, onde
/// "credenciais inválidas" não faz sentido no logout.
///
/// **O que NÃO está aqui:** a recusa de um código de ativação. Voucher expirado
/// ou revogado não é falha — é uma resposta de sucesso com `confirmado: false` e
/// uma mensagem para o campo. Modelá-la como erro obrigaria a tela a distinguir
/// "o servidor caiu" de "seu código venceu" pelo mesmo canal.
sealed class CadastroError extends AppError {
  const CadastroError(super.message);
}

/// O servidor recusou os dados enviados (slug em uso, e-mail malformado, senha
/// curta). A mensagem vem do servidor, que é a autoridade sobre a validação.
final class CadastroDadosInvalidos extends CadastroError
    with ValidationFailure {
  const CadastroDadosInvalidos([String? mensagem])
      : super(mensagem ?? 'Verifique os dados informados.');
}

/// O `signup_token` não confere, ou o cadastro já foi concluído.
///
/// Também é o que responde a um `tenant_id` de outra pessoa: quem não iniciou o
/// cadastro não descobre sequer se ele existe.
final class CadastroNaoAutorizado extends CadastroError {
  const CadastroNaoAutorizado()
      : super('Este cadastro não está mais disponível. Comece de novo.');
}

/// Um passo foi pedido fora de ordem (pagar antes de escolher o plano).
final class CadastroForaDeOrdem extends CadastroError {
  const CadastroForaDeOrdem()
      : super('Conclua o passo anterior antes de seguir.');
}

/// Rate limit por IP das rotas públicas.
final class CadastroBloqueadoPorTentativas extends CadastroError {
  const CadastroBloqueadoPorTentativas()
      : super('Muitas tentativas. Aguarde alguns minutos.');
}

/// Servidor fora do ar ou prazo esgotado.
final class CadastroIndisponivel extends CadastroError with NetworkFailure {
  const CadastroIndisponivel()
      : super('Servidor indisponível. Tente novamente.');
}

/// Falha não modelada. Mensagem genérica: o texto da exceção vai para o log,
/// nunca para a tela.
final class CadastroInesperado extends CadastroError with UnexpectedFailure {
  const CadastroInesperado()
      : super('Não foi possível concluir. Tente novamente.');
}
