/// Marcadores transversais de falha, aplicados aos erros de cada feature.
///
/// A `return_success_or_error` 3.x pede que **cada feature feche o seu conjunto
/// de erros** numa hierarquia `sealed` própria — é isso que torna o `switch`
/// exaustivo e impede que um erro novo passe sem tratamento. O efeito colateral
/// é que não existe mais um tipo comum a que a apresentação possa reagir: uma
/// queda de rede no login e uma queda de rede na listagem de tenants são tipos
/// diferentes, cada um dentro do seu `sealed`.
///
/// Esses marcadores devolvem essa capacidade **sem** reabrir o conjunto: o erro
/// da feature aplica o mixin que descreve a *natureza* da falha, e quem trata
/// transversalmente (o `ErrorMessageMapper`, o guard de sessão) casa pelo
/// marcador:
///
/// ```dart
/// // na feature — conjunto fechado, com a natureza declarada
/// final class LoginIndisponivel extends LoginError with NetworkFailure {
///   const LoginIndisponivel() : super('Servidor indisponível. Tente novamente.');
/// }
///
/// // na apresentação — reage à natureza, não ao caso concreto
/// switch (error) {
///   case UnauthorizedFailure(): _derrubarSessao();
///   case NetworkFailure(): _oferecerNovaTentativa();
///   default: _mostrar(error.message);
/// }
/// ```
///
/// Os marcadores são restritos a [AppError] (`on AppError`): são vocabulário
/// para erros de domínio, não para qualquer objeto. Um erro pode acumular mais
/// de um marcador se a natureza for genuinamente dupla — na prática, escolha um.
///
/// Todos são `base mixin` por imposição do modificador de classe da lib: como
/// [AppError] é `base`, todo subtipo dela — inclusive um mixin restrito a ela —
/// precisa ser `base`, `final` ou `sealed`. O efeito é desejável: garante que
/// ninguém finja ser uma falha de rede via `implements`.
library;

import 'package:return_success_or_error/return_success_or_error.dart';

/// Falha de transporte: servidor indisponível, sem conexão, prazo esgotado.
///
/// A ação típica da UI é oferecer nova tentativa — a operação pode ter sucesso
/// mais tarde sem nenhuma mudança na entrada.
base mixin NetworkFailure on AppError {}

/// Sessão ausente, expirada ou acesso negado.
///
/// É o único marcador com efeito colateral esperado: o guard de navegação
/// derruba a sessão local e manda para o login.
base mixin UnauthorizedFailure on AppError {}

/// Entrada inválida — a operação só passa se o dado mudar.
///
/// A UI destaca o campo em vez de oferecer nova tentativa.
base mixin ValidationFailure on AppError {}

/// Falha não prevista: o caso ao qual `mapError`/`onUnexpected` convertem uma
/// exceção que a feature não modelou.
///
/// A mensagem de um erro marcado assim é **sempre genérica**: o texto da exceção
/// original vai para o log estruturado, nunca para a tela — detalhe técnico
/// exposto ao usuário já vazou, no passado, caminho de arquivo e endereço de
/// serviço interno.
base mixin UnexpectedFailure on AppError {}
