import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Resolve um [AppError] na mensagem que a UI exibe.
///
/// Com a v3, cada feature fecha seus erros num `sealed` próprio e **já escreve a
/// mensagem em pt-br** no construtor do caso — "Slug já utilizado por outro
/// tenant" é informação que só a feature de tenants tem. Então a regra aqui
/// deixou de ser uma tabela de tipos (que precisaria conhecer os ~60 casos
/// concretos das 16 features) e passou a ser: **use a mensagem da feature**.
///
/// A exceção é o que carrega [UnexpectedFailure] (e o [ErrorGeneric] da lib):
/// esses nascem de uma exceção não modelada, e a mensagem de um erro assim é a
/// que mais risco tem de trazer detalhe técnico — caminho de arquivo, endereço
/// de serviço interno, trecho de payload. A convenção do projeto é que o caso
/// "inesperado" da feature já use texto genérico e mande a exceção para o log;
/// aqui a mensagem genérica é **imposta**, como defesa em profundidade caso
/// alguém volte a concatenar `'$e'` na mensagem exibida.
///
/// O app suporta apenas pt-br (`supportedLocales: [pt]`), então não há resolução
/// de locale — se isso mudar, é aqui que a chave de i18n entra.
abstract final class ErrorMessageMapper {
  /// Texto exibido quando o erro é inesperado ou não traz mensagem própria.
  static const String mensagemGenerica =
      'Ocorreu um erro inesperado. Tente novamente.';

  static String map(AppError error) => switch (error) {
    UnexpectedFailure() || ErrorGeneric() => mensagemGenerica,
    _ when error.message.trim().isEmpty => mensagemGenerica,
    _ => error.message,
  };
}
