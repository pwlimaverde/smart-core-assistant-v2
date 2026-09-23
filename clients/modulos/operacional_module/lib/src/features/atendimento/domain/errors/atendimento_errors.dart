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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [ListAtendimentosAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class ListAtendimentosSessaoExpirada extends ListAtendimentosError
    with UnauthorizedFailure {
  const ListAtendimentosSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [GetThreadAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class GetThreadSessaoExpirada extends GetThreadError
    with UnauthorizedFailure {
  const GetThreadSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [MoveEtapaAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class MoveEtapaSessaoExpirada extends MoveAtendimentoEtapaError
    with UnauthorizedFailure {
  const MoveEtapaSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [SendMessageAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class SendMessageSessaoExpirada extends SendOutboundMessageError
    with UnauthorizedFailure {
  const SendMessageSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [QuadroAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class QuadroSessaoExpirada extends QuadroError with UnauthorizedFailure {
  const QuadroSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [SetStatusAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class SetStatusSessaoExpirada extends SetStatusError
    with UnauthorizedFailure {
  const SetStatusSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
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

// ─── ficha do atendimento (etiquetas e notas) ─────────────────────────────────

/// Erros da ficha.
///
/// Conjunto próprio, separado do chat: a ficha pode falhar com o histórico
/// carregado, e nesse caso a conversa continua utilizável — a mensagem tem de
/// dizer que o que falhou foi o painel, não o atendimento.
sealed class FichaError extends AppError {
  const FichaError(super.message);
}

final class FichaAcessoNegado extends FichaError with UnauthorizedFailure {
  const FichaAcessoNegado()
    : super('Você não tem acesso à ficha deste atendimento.');
}

/// Sessão morta — e NÃO falta de permissão.
///
/// As duas chegavam como [FichaAcessoNegado]. O resultado foi um dono de conta
/// lendo "você não tem permissão" enquanto o servidor jamais tinha
/// recusado nada: o token havia expirado, e a mensagem o mandou
/// investigar permissões que ele já tinha.
final class FichaSessaoExpirada extends FichaError with UnauthorizedFailure {
  const FichaSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// Recusa do servidor — a mensagem vem dele. É por aqui que chega a etiqueta
/// com nome repetido, que tem `UNIQUE` no banco.
final class FichaRecusado extends FichaError with ValidationFailure {
  const FichaRecusado([String? mensagem])
    : super(mensagem ?? 'Verifique os dados informados.');
}

final class FichaIndisponivel extends FichaError with NetworkFailure {
  const FichaIndisponivel()
    : super('Não foi possível carregar a ficha. Tente novamente.');
}

final class FichaFalhaLocal extends FichaError {
  const FichaFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class FichaInesperado extends FichaError with UnexpectedFailure {
  const FichaInesperado()
    : super('Não foi possível carregar a ficha. Tente novamente.');
}

// ─── iniciarAtendimento (C3) ──────────────────────────────────────────────────

/// Erros de "abrir um atendimento a partir de um cliente cadastrado".
sealed class IniciarAtendimentoError extends AppError {
  const IniciarAtendimentoError(super.message);
}

/// Sem permissão no fluxo escolhido — mesmo RBAC fino do arrasto no quadro.
final class IniciarAtendimentoAcessoNegado extends IniciarAtendimentoError
    with UnauthorizedFailure {
  const IniciarAtendimentoAcessoNegado()
    : super('Você não tem permissão para abrir atendimentos neste fluxo.');
}

/// Sessão morta — e NÃO falta de permissão. Ver a nota de
/// [MoveEtapaSessaoExpirada]: conflatar as duas mandou um dono de conta caçar
/// permissões que ele sempre teve.
final class IniciarAtendimentoSessaoExpirada extends IniciarAtendimentoError
    with UnauthorizedFailure {
  const IniciarAtendimentoSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class IniciarAtendimentoNaoEncontrado extends IniciarAtendimentoError {
  const IniciarAtendimentoNaoEncontrado()
    : super('Cliente, fluxo ou etapa não encontrados.');
}

final class IniciarAtendimentoInvalido extends IniciarAtendimentoError
    with ValidationFailure {
  const IniciarAtendimentoInvalido()
    : super('Escolha o cliente, o quadro e a coluna onde a conversa começa.');
}

final class IniciarAtendimentoIndisponivel extends IniciarAtendimentoError
    with NetworkFailure {
  const IniciarAtendimentoIndisponivel()
    : super('Não foi possível abrir o atendimento. Tente novamente.');
}

final class IniciarAtendimentoInesperado extends IniciarAtendimentoError
    with UnexpectedFailure {
  const IniciarAtendimentoInesperado()
    : super('Não foi possível abrir o atendimento. Tente novamente.');
}

// ─── definirValorCampo (N9 E13) ───────────────────────────────────────────────

/// Erros de preencher um campo do cartão na ficha.
sealed class DefinirValorCampoError extends AppError {
  const DefinirValorCampoError(super.message);
}

final class ValorCampoAcessoNegado extends DefinirValorCampoError
    with UnauthorizedFailure {
  const ValorCampoAcessoNegado()
    : super('Você não tem permissão para preencher a ficha.');
}

/// Sessão morta — e não falta de permissão. Ver a nota de
/// [MoveEtapaSessaoExpirada].
final class ValorCampoSessaoExpirada extends DefinirValorCampoError
    with UnauthorizedFailure {
  const ValorCampoSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class ValorCampoNaoEncontrado extends DefinirValorCampoError {
  const ValorCampoNaoEncontrado()
    : super('Este campo não existe mais. Recarregue a conversa.');
}

/// O valor não serve para o tipo do campo — data fora do formato, opção que
/// não está na lista. A mensagem é do servidor, que conhece o catálogo.
final class ValorCampoInvalido extends DefinirValorCampoError
    with ValidationFailure {
  const ValorCampoInvalido([String? mensagem])
    : super(mensagem ?? 'Esse valor não serve para este campo.');
}

final class ValorCampoIndisponivel extends DefinirValorCampoError
    with NetworkFailure {
  const ValorCampoIndisponivel()
    : super('Não foi possível salvar. Tente de novo.');
}

final class ValorCampoInesperado extends DefinirValorCampoError
    with UnexpectedFailure {
  const ValorCampoInesperado()
    : super('Não foi possível salvar. Tente de novo.');
}

// ─── P3: presença e galeria ───────────────────────────────────────────────────

/// Erros de `enviarPresenca` — deliberadamente curtos.
///
/// Presença é efêmera: ninguém precisa saber que o "digitando..." não chegou, e
/// distinguir sessão expirada de rede caída aqui não muda nada para quem está
/// escrevendo. As duas variantes existem só para a cadeia RSOE ter um tipo
/// fechado; a tela ignora as duas.
sealed class PresencaError extends AppError {
  const PresencaError(super.message);
}

final class PresencaNaoEntregue extends PresencaError with NetworkFailure {
  const PresencaNaoEntregue() : super('A presença não chegou ao contato.');
}

final class PresencaInesperado extends PresencaError with UnexpectedFailure {
  const PresencaInesperado() : super('A presença não chegou ao contato.');
}

/// Erros de `listarMidias` (galeria do atendimento).
sealed class MidiasError extends AppError {
  const MidiasError(super.message);
}

final class MidiasAcessoNegado extends MidiasError with UnauthorizedFailure {
  const MidiasAcessoNegado()
    : super('Você não tem acesso aos arquivos desta conversa.');
}

final class MidiasSessaoExpirada extends MidiasError with UnauthorizedFailure {
  const MidiasSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

final class MidiasIndisponivel extends MidiasError with NetworkFailure {
  const MidiasIndisponivel()
    : super('Não foi possível carregar os arquivos. Tente novamente.');
}

final class MidiasFalhaLocal extends MidiasError {
  const MidiasFalhaLocal()
    : super('Falha no armazenamento local. Reinicie o aplicativo.');
}

final class MidiasInesperado extends MidiasError with UnexpectedFailure {
  const MidiasInesperado()
    : super('Não foi possível carregar os arquivos. Tente novamente.');
}

/// Erros de `enviarMidia` (anexo e áudio).
sealed class EnviarMidiaError extends AppError {
  const EnviarMidiaError(super.message);
}

final class EnviarMidiaAcessoNegado extends EnviarMidiaError
    with UnauthorizedFailure {
  const EnviarMidiaAcessoNegado()
    : super('Você não tem permissão para enviar arquivos nesta conversa.');
}

final class EnviarMidiaSessaoExpirada extends EnviarMidiaError
    with UnauthorizedFailure {
  const EnviarMidiaSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// O servidor recusou o arquivo: tipo não aceito ou tamanho acima do limite.
/// A mensagem do servidor é preservada porque ela diz qual dos dois foi.
final class EnviarMidiaRecusado extends EnviarMidiaError {
  const EnviarMidiaRecusado(String? detalhe)
    : super(detalhe ?? 'O arquivo não foi aceito.');
}

final class EnviarMidiaIndisponivel extends EnviarMidiaError
    with NetworkFailure {
  const EnviarMidiaIndisponivel()
    : super('Não foi possível enviar o arquivo. Tente novamente.');
}

final class EnviarMidiaInesperado extends EnviarMidiaError
    with UnexpectedFailure {
  const EnviarMidiaInesperado()
    : super('Não foi possível enviar o arquivo. Tente novamente.');
}

/// Erros das operações do quadro (P4): atribuir, prioridade, transferir e
/// exportar. Um conjunto só porque as quatro falham pelos mesmos motivos e são
/// tratadas no mesmo lugar — o menu do cartão.
sealed class QuadroOperacaoError extends AppError {
  const QuadroOperacaoError(super.message);
}

final class QuadroOperacaoAcessoNegado extends QuadroOperacaoError
    with UnauthorizedFailure {
  const QuadroOperacaoAcessoNegado()
    : super('Você não tem permissão para esta ação no quadro.');
}

final class QuadroOperacaoSessaoExpirada extends QuadroOperacaoError
    with UnauthorizedFailure {
  const QuadroOperacaoSessaoExpirada()
    : super('Sua sessão expirou. Entre de novo para continuar.');
}

/// O servidor recusou: prioridade fora da lista, fluxo inexistente, usuário sem
/// cadastro de atendente. A mensagem dele diz qual dos casos é.
final class QuadroOperacaoRecusada extends QuadroOperacaoError {
  const QuadroOperacaoRecusada(String? detalhe)
    : super(detalhe ?? 'A ação não foi aceita.');
}

final class QuadroOperacaoIndisponivel extends QuadroOperacaoError
    with NetworkFailure {
  const QuadroOperacaoIndisponivel()
    : super('Não foi possível concluir a ação. Tente novamente.');
}

final class QuadroOperacaoInesperado extends QuadroOperacaoError
    with UnexpectedFailure {
  const QuadroOperacaoInesperado()
    : super('Não foi possível concluir a ação. Tente novamente.');
}
