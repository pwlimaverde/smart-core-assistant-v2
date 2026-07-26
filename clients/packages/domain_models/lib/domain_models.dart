/// Modelos de domínio / DTOs compartilhados do monorepo.
///
/// Reúne os tipos transversais usados por mais de um módulo. Hoje, o vocabulário
/// comum de falha: os **marcadores** ([NetworkFailure], [UnauthorizedFailure],
/// [ValidationFailure], [UnexpectedFailure]) que os erros `sealed` de cada
/// feature aplicam, e sobre os quais a apresentação reage sem precisar conhecer
/// cada caso concreto.
///
/// > **Mudança na migração para a `return_success_or_error` 3.x:** este package
/// > deixou de exportar erros concretos (`ErrorAuth`, `ErrorNetwork`,
/// > `ErrorValidation`, `ErrorUnauthorized`, `ErrorLocalEngine`). Erro concreto
/// > agora pertence à feature que o produz, dentro do `sealed` dela — um
/// > conjunto global não pode ser exaustivo em lugar nenhum. O que sobra aqui é
/// > só o vocabulário compartilhado.
library;

export 'src/errors/failure_markers.dart';
