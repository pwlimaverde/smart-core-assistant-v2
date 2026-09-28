import 'package:api_client/api_client.dart';
import 'package:get_it_module/get_it_module.dart';

/// Um item excluído, como a aba "Excluídos" da auditoria o mostra.
typedef ItemExcluidoDoPainel = ({
  String tipo,
  int id,
  String rotulo,
  DateTime excluidoEm,
  String excluidoPor,
});

/// Exclusão definitiva, desativar/reativar e a lista de excluídos
/// (doc_dev/planejamento/39), para qualquer tela.
///
/// Os tipos são os do contrato: `contato`, `cliente`, `atendimento`,
/// `departamento`, `fluxo`, `etapa`, `atendente`, `campo`, `etiqueta`, `nota`,
/// `intencao`, `treinamento`, `numero_ignorado`.
///
/// Os métodos devolvem a mensagem de erro (ou `null`) em vez de lançar: é o que
/// o diálogo de exclusão mostra à pessoa.
class ExclusaoService {
  final AdminServiceClient Function() _admin;

  ExclusaoService({AdminServiceClient Function()? admin})
    : _admin = admin ?? _adminDoApp;

  static AdminServiceClient _adminDoApp() {
    final client = inject<ApiClient>();
    if (client is! GrpcTransport) {
      throw StateError('ApiClient não é do tipo GrpcTransport esperado.');
    }
    return client.admin;
  }

  /// O que a exclusão vai atingir. Lança se o item não existir mais.
  Future<({String rotulo, int conversas, String emUso})> simular(
    String tipo,
    int id,
  ) async {
    final r = await _admin().simularExclusao(tipo, id);
    return (rotulo: r.rotulo, conversas: r.conversas.toInt(), emUso: r.emUso);
  }

  /// Exclui definitivamente, conferindo o nome digitado no servidor.
  Future<String?> excluir(String tipo, int id, String confirmar) async {
    try {
      await _admin().excluirDefinitivo(tipo, id, confirmar);
      return null;
    } on GrpcError catch (e) {
      return e.message ?? 'Não foi possível excluir. Tente de novo.';
    }
  }

  /// Desativa (`false`) ou reativa (`true`). Excluído não reativa.
  Future<String?> definirAtivo(
    String tipo,
    int id, {
    required bool ativo,
  }) async {
    try {
      await _admin().definirItemAtivo(tipo, id, ativo: ativo);
      return null;
    } on GrpcError catch (e) {
      return e.message ?? 'Não foi possível alterar. Tente de novo.';
    }
  }

  /// Os excluídos do tenant, do mais recente ao mais antigo (só admin).
  Future<List<ItemExcluidoDoPainel>> listarExcluidos({String tipo = ''}) async {
    final r = await _admin().listMyExcluidos(
      ListMyExcluidosRequest(tipo: tipo),
    );
    return [
      for (final i in r.itens)
        (
          tipo: i.tipo,
          id: i.id.toInt(),
          rotulo: i.rotulo,
          excluidoEm: DateTime.fromMillisecondsSinceEpoch(i.excluidoEm.toInt()),
          excluidoPor: i.excluidoPor,
        ),
    ];
  }
}
