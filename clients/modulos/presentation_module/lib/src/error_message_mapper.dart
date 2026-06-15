import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Resolve um [AppError] tipado numa mensagem amigável em pt-br para a UI.
///
/// O app suporta apenas pt-br (`supportedLocales: [pt]`), então o mapeamento é
/// direto por tipo. O default cobre [ErrorGeneric] e qualquer erro não previsto,
/// nunca expondo detalhe técnico/segredo.
abstract final class ErrorMessageMapper {
  static String map(AppError error) => switch (error) {
        ErrorUnauthorized() => 'Sessão expirada. Entre novamente.',
        ErrorAuth() => 'E-mail ou senha inválidos.',
        ErrorValidation() => 'Verifique os dados informados.',
        ErrorNetwork() => 'Não foi possível conectar. Tente novamente.',
        _ => 'Ocorreu um erro inesperado. Tente novamente.',
      };
}
