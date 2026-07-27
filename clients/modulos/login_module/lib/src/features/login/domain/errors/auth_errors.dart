import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjuntos fechados de erro da feature de autenticação — um por operação.
///
/// **Por que um conjunto por operação e não um por feature:** o repertório das
/// três operações é genuinamente diferente. "Credenciais inválidas" não existe
/// no logout; "sem sessão persistida" só existe no refresh. Um conjunto único
/// obrigaria cada `switch` a cobrir casos que aquela operação nunca produz — que
/// é exatamente o defeito que o erro fechado veio corrigir. Onde as operações de
/// uma feature compartilham o mesmo repertório (o caso comum no `admin_module`),
/// o conjunto é um só.
///
/// Toda operação tem o seu caso `...Inesperado`, com mensagem **genérica**: é
/// onde `mapError`/`onUnexpected` convertem o que não foi modelado. O texto da
/// exceção vai para o log, nunca para a tela — em autenticação isso importa
/// duas vezes, porque a exceção pode carregar o token na mensagem.

// ─── login ────────────────────────────────────────────────────────────────────

/// Erros possíveis de `AuthService.login`.
sealed class LoginError extends AppError {
  const LoginError(super.message);
}

/// E-mail ou senha não conferem.
///
/// Mensagem deliberadamente ambígua sobre **qual** dos dois falhou: distinguir
/// entregaria a um atacante a confirmação de que o e-mail existe.
final class CredenciaisInvalidas extends LoginError {
  const CredenciaisInvalidas() : super('E-mail ou senha inválidos.');
}

/// O servidor rejeitou o formato da entrada (e-mail malformado, senha vazia).
final class LoginDadosInvalidos extends LoginError with ValidationFailure {
  const LoginDadosInvalidos() : super('Verifique os dados informados.');
}

/// Rate limit de tentativas de login atingido.
final class LoginBloqueadoPorTentativas extends LoginError {
  const LoginBloqueadoPorTentativas()
    : super('Muitas tentativas. Aguarde antes de tentar novamente.');
}

/// Servidor fora do ar ou prazo esgotado.
final class LoginIndisponivel extends LoginError with NetworkFailure {
  const LoginIndisponivel() : super('Servidor indisponível. Tente novamente.');
}

/// Falha não modelada (inclui token de resposta malformado).
final class LoginInesperado extends LoginError with UnexpectedFailure {
  const LoginInesperado() : super('Não foi possível entrar. Tente novamente.');
}

// ─── refresh ──────────────────────────────────────────────────────────────────

/// Erros possíveis de `AuthService.refresh`.
sealed class RefreshError extends AppError {
  const RefreshError(super.message);
}

/// Não há refresh token guardado — estado normal no primeiro boot, não um
/// defeito. Produzido pelo próprio serviço, antes de qualquer I/O.
final class SemSessaoPersistida extends RefreshError with UnauthorizedFailure {
  const SemSessaoPersistida() : super('Entre novamente para continuar.');
}

/// O servidor recusou o refresh: expirado, revogado ou reutilizado (detecção de
/// reuso invalida a família inteira de tokens).
final class RefreshRejeitado extends RefreshError with UnauthorizedFailure {
  const RefreshRejeitado() : super('Sessão expirada. Entre novamente.');
}

/// Servidor fora do ar ou prazo esgotado. **Não** derruba a sessão local: o
/// access token em memória pode ainda estar válido.
final class RefreshIndisponivel extends RefreshError with NetworkFailure {
  const RefreshIndisponivel()
    : super('Servidor indisponível. Tente novamente.');
}

/// Falha não modelada.
final class RefreshInesperado extends RefreshError with UnexpectedFailure {
  const RefreshInesperado()
    : super('Não foi possível renovar a sessão. Entre novamente.');
}

// ─── logout ───────────────────────────────────────────────────────────────────

/// Erros possíveis de `AuthService.logout`.
///
/// Todos são informativos: o logout **falha aberto** — a sessão local é sempre
/// limpa, mesmo quando a revogação no servidor não acontece.
sealed class LogoutError extends AppError {
  const LogoutError(super.message);
}

/// O servidor recusou a revogação (token já inválido, tipicamente). Sem
/// consequência prática: o que estava no dispositivo já foi apagado.
final class LogoutRejeitado extends LogoutError {
  const LogoutRejeitado() : super('A sessão foi encerrada neste dispositivo.');
}

/// Não foi possível alcançar o servidor para revogar o token. O refresh continua
/// válido no servidor até expirar — vale avisar em ambiente compartilhado.
final class LogoutIndisponivel extends LogoutError with NetworkFailure {
  const LogoutIndisponivel()
    : super(
        'Sessão encerrada aqui, mas não foi possível revogá-la no servidor.',
      );
}

/// Falha não modelada.
final class LogoutInesperado extends LogoutError with UnexpectedFailure {
  const LogoutInesperado() : super('A sessão foi encerrada neste dispositivo.');
}
