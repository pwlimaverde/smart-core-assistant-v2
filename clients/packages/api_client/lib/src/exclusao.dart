import 'package:fixnum/fixnum.dart';

import 'generated/queries/admin.pbgrpc.dart';

/// Exclusão definitiva e desativar/reativar genéricos
/// (doc_dev/planejamento/39), com ids em `int` para quem não depende de
/// `fixnum`.
extension ExclusaoDefinitiva on AdminServiceClient {
  /// O que a exclusão vai atingir (nome exato, conversas, se está em uso).
  Future<ExcluirMyItemResponse> simularExclusao(String tipo, int id) =>
      excluirMyItem(
        ExcluirMyItemRequest(tipo: tipo, id: Int64(id), dryRun: true),
      );

  /// Exclui definitivamente; o servidor confere `confirmar` com o nome.
  Future<ExcluirMyItemResponse> excluirDefinitivo(
    String tipo,
    int id,
    String confirmar,
  ) => excluirMyItem(
    ExcluirMyItemRequest(tipo: tipo, id: Int64(id), confirmar: confirmar),
  );

  /// Desativa (`false`) ou reativa (`true`). Excluído não reativa.
  Future<SimpleOkResponse> definirItemAtivo(
    String tipo,
    int id, {
    required bool ativo,
  }) => definirMyItemAtivo(
    DefinirMyItemAtivoRequest(tipo: tipo, id: Int64(id), ativo: ativo),
  );
}
