/// Modelos de domínio / DTOs compartilhados do monorepo.
///
/// Reúne os tipos transversais usados por mais de um módulo — hoje, os erros
/// de domínio tipados ([ErrorAuth], [ErrorUnauthorized], [ErrorNetwork],
/// [ErrorValidation]), consumidos pela camada de dados (mapeamento de falhas)
/// e pela apresentação (ErrorMessageMapper).
library;

export 'src/errors/auth_errors.dart';
