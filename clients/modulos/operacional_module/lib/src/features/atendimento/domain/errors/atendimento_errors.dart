import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjuntos fechados de erro da feature de atendimento — um por operação.
///
/// As quatro operações compartilham parte do repertório (acesso negado,
/// indisponível, falha do motor local, inesperado), mas divergem no que importa:
/// só o `move` pode ser recusado por movimento inválido, só o envio pode ter o
/// conteúdo rejeitado, e listar a fila não tem "não encontrado". Manter conjuntos
/// separados é o que faz o `switch` de cada tela cobrir exatamente o que aquela
/// operação produz.
///
/// **`...FalhaLocal` existe por causa do desktop:** as leituras vêm do índice
/// SQLite do motor Rust (`local_engine`), e uma falha ali não é falha de rede nem
/// bug do app — é armazenamento local. Tratá-la como "erro inesperado" mandaria o
/// usuário tentar de novo quando o que resolve é reiniciar o aplicativo.

// ─── listAtendimentos ─────────────────────────────────────────────────────────

/// Erros de `listAtendimentos` (fila/Kanban).
sealed class ListAtendimentosError extends AppError {
  const ListAtendimentosError(super.message);
}

final class ListAtendimentosAcessoNegado extends ListAtendimentosError
    with UnauthorizedFailure {
  const ListAtendimentosAcessoNegado()
    : super('Você não tem acesso a esta fila de atendimentos.');
}

final class ListAtendimentosIndisponivel extends ListAtendimentosError
    with NetworkFailure {
  const ListAtendimentosIndisponivel()
    : super('Não foi possível carregar a fila. Tente novamente.');
}

final class ListAtendimentosFalhaLocal extends ListAtendimentosError {
  const ListAtendimentosFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class ListAtendimentosInesperado extends ListAtendimentosError
    with UnexpectedFailure {
  const ListAtendimentosInesperado()
    : super('Não foi possível carregar a fila. Tente novamente.');
}

// ─── getThread ────────────────────────────────────────────────────────────────

/// Erros de `getThread` (histórico do chat).
sealed class GetThreadError extends AppError {
  const GetThreadError(super.message);
}

final class GetThreadAcessoNegado extends GetThreadError
    with UnauthorizedFailure {
  const GetThreadAcessoNegado()
    : super('Você não tem acesso a este atendimento.');
}

final class GetThreadNaoEncontrado extends GetThreadError {
  const GetThreadNaoEncontrado() : super('Atendimento não encontrado.');
}

final class GetThreadIndisponivel extends GetThreadError with NetworkFailure {
  const GetThreadIndisponivel()
    : super('Não foi possível carregar as mensagens. Tente novamente.');
}

final class GetThreadFalhaLocal extends GetThreadError {
  const GetThreadFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class GetThreadInesperado extends GetThreadError with UnexpectedFailure {
  const GetThreadInesperado()
    : super('Não foi possível carregar as mensagens. Tente novamente.');
}

// ─── moveAtendimentoEtapa ─────────────────────────────────────────────────────

/// Erros de `moveAtendimentoEtapa` (arrastar no Kanban).
sealed class MoveAtendimentoEtapaError extends AppError {
  const MoveAtendimentoEtapaError(super.message);
}

/// Sem permissão no fluxo. O RBAC fino por fluxo (`flow_permissions`) é resolvido
/// 100% no servidor — a UI só exibe, nunca reimplementa a checagem.
final class MoveEtapaAcessoNegado extends MoveAtendimentoEtapaError
    with UnauthorizedFailure {
  const MoveEtapaAcessoNegado()
    : super('Você não tem permissão para mover atendimentos neste fluxo.');
}

final class MoveEtapaNaoEncontrado extends MoveAtendimentoEtapaError {
  const MoveEtapaNaoEncontrado()
    : super('Atendimento ou etapa não encontrados.');
}

/// A transição não é válida para o fluxo (etapa não é sucessora, atendimento
/// encerrado). O servidor decide; a UI devolve o card à coluna de origem.
final class MoveEtapaMovimentoInvalido extends MoveAtendimentoEtapaError
    with ValidationFailure {
  const MoveEtapaMovimentoInvalido()
    : super('Este movimento não é permitido para o fluxo do atendimento.');
}

final class MoveEtapaIndisponivel extends MoveAtendimentoEtapaError
    with NetworkFailure {
  const MoveEtapaIndisponivel()
    : super('Não foi possível mover o atendimento. Tente novamente.');
}

final class MoveEtapaFalhaLocal extends MoveAtendimentoEtapaError {
  const MoveEtapaFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class MoveEtapaInesperado extends MoveAtendimentoEtapaError
    with UnexpectedFailure {
  const MoveEtapaInesperado()
    : super('Não foi possível mover o atendimento. Tente novamente.');
}

// ─── sendOutboundMessage ──────────────────────────────────────────────────────

/// Erros de `sendOutboundMessage` (mensagem do atendente).
sealed class SendOutboundMessageError extends AppError {
  const SendOutboundMessageError(super.message);
}

final class SendMessageAcessoNegado extends SendOutboundMessageError
    with UnauthorizedFailure {
  const SendMessageAcessoNegado()
    : super('Você não tem permissão para responder neste atendimento.');
}

final class SendMessageNaoEncontrado extends SendOutboundMessageError {
  const SendMessageNaoEncontrado() : super('Atendimento não encontrado.');
}

/// Conteúdo recusado pelo servidor (vazio, tipo não suportado, tamanho).
final class SendMessageConteudoInvalido extends SendOutboundMessageError
    with ValidationFailure {
  const SendMessageConteudoInvalido()
    : super('Não foi possível enviar esta mensagem. Revise o conteúdo.');
}

/// Atendimento em estado que não aceita mensagem (encerrado, janela do WhatsApp
/// fechada).
final class SendMessageEstadoInvalido extends SendOutboundMessageError {
  const SendMessageEstadoInvalido()
    : super('Este atendimento não aceita novas mensagens agora.');
}

final class SendMessageIndisponivel extends SendOutboundMessageError
    with NetworkFailure {
  const SendMessageIndisponivel()
    : super('Não foi possível enviar a mensagem. Tente novamente.');
}

final class SendMessageFalhaLocal extends SendOutboundMessageError {
  const SendMessageFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class SendMessageInesperado extends SendOutboundMessageError
    with UnexpectedFailure {
  const SendMessageInesperado()
    : super('Não foi possível enviar a mensagem. Tente novamente.');
}

// ─── quadro (fluxos e colunas) ────────────────────────────────────────────────

/// Erros ao montar o quadro.
///
/// Separado de `listAtendimentos` de propósito: as conversas podem carregar e a
/// configuração do quadro falhar, ou o contrário, e as duas falhas pedem
/// mensagens diferentes — "a fila não carregou" e "o quadro não carregou" levam
/// a lugares distintos.
sealed class QuadroError extends AppError {
  const QuadroError(super.message);
}

final class QuadroAcessoNegado extends QuadroError with UnauthorizedFailure {
  const QuadroAcessoNegado()
    : super('Você não tem acesso à configuração deste quadro.');
}

final class QuadroIndisponivel extends QuadroError with NetworkFailure {
  const QuadroIndisponivel()
    : super('Não foi possível carregar o quadro. Tente novamente.');
}

final class QuadroFalhaLocal extends QuadroError {
  const QuadroFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class QuadroInesperado extends QuadroError with UnexpectedFailure {
  const QuadroInesperado()
    : super('Não foi possível carregar o quadro. Tente novamente.');
}

// ─── setAtendimentoStatus ─────────────────────────────────────────────────────

/// Erros ao mudar o status do atendimento.
sealed class SetStatusError extends AppError {
  const SetStatusError(super.message);
}

/// Mesmo RBAC fino por fluxo do arrasto: quem não pode mover o cartão também
/// não pode encerrar a conversa por outro botão.
final class SetStatusAcessoNegado extends SetStatusError
    with UnauthorizedFailure {
  const SetStatusAcessoNegado()
    : super('Você não tem permissão para mudar o estado deste atendimento.');
}

final class SetStatusNaoEncontrado extends SetStatusError {
  const SetStatusNaoEncontrado() : super('Atendimento não encontrado.');
}

final class SetStatusRecusado extends SetStatusError with ValidationFailure {
  const SetStatusRecusado()
    : super('Esta mudança não é permitida para este atendimento.');
}

final class SetStatusIndisponivel extends SetStatusError with NetworkFailure {
  const SetStatusIndisponivel()
    : super('Não foi possível concluir. Tente novamente.');
}

final class SetStatusFalhaLocal extends SetStatusError {
  const SetStatusFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class SetStatusInesperado extends SetStatusError with UnexpectedFailure {
  const SetStatusInesperado()
    : super('Não foi possível concluir. Tente novamente.');
}
