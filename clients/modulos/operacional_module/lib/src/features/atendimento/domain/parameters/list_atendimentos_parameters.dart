import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para listar a fila de atendimentos por status/departamento
/// (WS-6.2). `departamentoId == null` lista todos os departamentos.
/// P1 — [busca], [somenteMeus] e [somenteNaoLidos] espelham o recorte da v1
/// (`list_conversations`): texto livre sobre o contato e o assunto, "minhas
/// conversas" e "não lidas", combináveis entre si.
final class ListAtendimentosParameters extends Parameters {
  final String status;
  final int? departamentoId;
  final int limit;
  final String busca;
  final bool somenteMeus;
  final bool somenteNaoLidos;

  const ListAtendimentosParameters({
    this.status = 'fila',
    this.departamentoId,
    this.limit = 50,
    this.busca = '',
    this.somenteMeus = false,
    this.somenteNaoLidos = false,
  });
}
