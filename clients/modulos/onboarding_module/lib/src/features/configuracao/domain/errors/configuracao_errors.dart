import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros da configuração inicial guiada.
///
/// Separado do [CadastroError] de propósito: aqui já existe sessão, e o
/// repertório é outro. "Cadastro não autorizado" não faz sentido depois de
/// logado; em compensação, "limite do plano atingido" só existe aqui.
sealed class ConfiguracaoError extends AppError {
  const ConfiguracaoError(super.message);
}

/// O servidor recusou os dados. A mensagem vem dele, que é a autoridade.
final class ConfiguracaoDadosInvalidos extends ConfiguracaoError
    with ValidationFailure {
  const ConfiguracaoDadosInvalidos([String? mensagem])
      : super(mensagem ?? 'Verifique os dados informados.');
}

/// Limite do plano atingido — criar outra conexão exige mudar de plano.
///
/// O teto vem sempre do plano do tenant (`tenants_plan.max_instances`), nunca
/// de um número fixo no código.
final class LimiteDoPlanoAtingido extends ConfiguracaoError {
  const LimiteDoPlanoAtingido()
      : super(
          'Você atingiu o limite de conexões do seu plano. '
          'Fale com o suporte para ampliar.',
        );
}

/// A sessão perdeu a validade ou falta escopo de administração do tenant.
final class ConfiguracaoNaoAutorizada extends ConfiguracaoError {
  const ConfiguracaoNaoAutorizada()
      : super('Sua sessão expirou. Entre novamente.');
}

/// Servidor fora do ar, ou o provedor de WhatsApp não respondeu.
final class ConfiguracaoIndisponivel extends ConfiguracaoError
    with NetworkFailure {
  const ConfiguracaoIndisponivel()
      : super('Serviço indisponível no momento. Tente novamente.');
}

/// Falha não modelada.
final class ConfiguracaoInesperada extends ConfiguracaoError
    with UnexpectedFailure {
  const ConfiguracaoInesperada()
      : super('Não foi possível concluir. Tente novamente.');
}
