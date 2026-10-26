import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/contato_da_conversa.dart';

final class AtendimentoIdParameters extends Parameters {
  final int atendimentoId;

  const AtendimentoIdParameters({required this.atendimentoId});
}

final class CriarEtiquetaParameters extends Parameters {
  final String nome;
  final String cor;

  const CriarEtiquetaParameters({required this.nome, required this.cor});
}

final class AlternarEtiquetaParameters extends Parameters {
  final int atendimentoId;
  final int etiquetaId;

  /// `false` tira a etiqueta da conversa.
  final bool aplicar;

  const AlternarEtiquetaParameters({
    required this.atendimentoId,
    required this.etiquetaId,
    required this.aplicar,
  });
}

/// D3 — liga/desliga a resposta automática da IA nesta conversa.
final class DefinirBotDaConversaParameters extends Parameters {
  final int atendimentoId;
  final bool habilitado;

  const DefinirBotDaConversaParameters({
    required this.atendimentoId,
    required this.habilitado,
  });
}

/// B6 (N9 E4) — marca como lidas as mensagens do contato numa conversa.
final class MarcarAtendimentoLidoParameters extends Parameters {
  final int atendimentoId;

  const MarcarAtendimentoLidoParameters({required this.atendimentoId});
}

final class CriarNotaParameters extends Parameters {
  final int atendimentoId;
  final String texto;

  const CriarNotaParameters({required this.atendimentoId, required this.texto});
}

/// P5 — a linha do tempo de um atendimento.
final class ListarTimelineParameters extends Parameters {
  final int atendimentoId;

  const ListarTimelineParameters({required this.atendimentoId});
}

/// P5 — as outras conversas do mesmo contato.
final class AtendimentosDoContatoParameters extends Parameters {
  final int contatoId;
  final int limit;

  const AtendimentosDoContatoParameters({
    required this.contatoId,
    this.limit = 20,
  });
}

/// P5 — apagar uma nota interna.
///
/// O [atendimentoId] viaja junto do id da nota porque o servidor usa os dois
/// no `WHERE`: sem ele, um id trocado apagaria nota de outra conversa.
final class RemoverNotaParameters extends Parameters {
  final int notaId;
  final int atendimentoId;

  const RemoverNotaParameters({
    required this.notaId,
    required this.atendimentoId,
  });
}

/// P5 — renomear/recolorir uma etiqueta do catálogo.
final class AtualizarEtiquetaParameters extends Parameters {
  final int id;
  final String nome;
  final String cor;
  final String descricao;

  const AtualizarEtiquetaParameters({
    required this.id,
    required this.nome,
    this.cor = '',
    this.descricao = '',
  });
}

/// P5 — tirar a etiqueta do catálogo (sem apagá-la das conversas).
final class DesativarEtiquetaParameters extends Parameters {
  final int id;

  const DesativarEtiquetaParameters({required this.id});
}

/// P13 — o contato da conversa, para o cabeçalho.
final class ObterContatoParameters extends Parameters {
  final int atendimentoId;
  final bool forcar;

  const ObterContatoParameters({
    required this.atendimentoId,
    this.forcar = false,
  });
}

final class EditarContatoParameters extends Parameters {
  final int contatoId;
  final String nome;
  final String email;
  final String cargo;
  final String segmento;
  final String observacoes;

  const EditarContatoParameters({
    required this.contatoId,
    required this.nome,
    required this.email,
    required this.cargo,
    required this.segmento,
    required this.observacoes,
  });
}

/// Põe o número na lista de não atendidos. O bot deixa de responder e o
/// atendimento não é aberto.
final class IgnorarNumeroParameters extends Parameters {
  final String nome;
  final String telefone;

  const IgnorarNumeroParameters({required this.nome, required this.telefone});
}

final class ObterClienteParameters extends Parameters {
  final int clienteId;

  const ObterClienteParameters({required this.clienteId});
}

final class SalvarClienteParameters extends Parameters {
  /// `id` 0 = cliente novo.
  final ClienteDaConversa dados;

  const SalvarClienteParameters({required this.dados});
}

final class VincularClienteParameters extends Parameters {
  final int clienteId;
  final int contatoId;
  final bool vincular;

  const VincularClienteParameters({
    required this.clienteId,
    required this.contatoId,
    required this.vincular,
  });
}

final class BuscarClientesParameters extends Parameters {
  final String busca;

  const BuscarClientesParameters({required this.busca});
}
