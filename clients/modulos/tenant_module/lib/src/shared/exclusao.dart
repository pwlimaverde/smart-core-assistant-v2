import 'package:dependencies_module/dependencies_module.dart';

/// Abre a exclusão definitiva de um item e recarrega a lista quando excluiu
/// (doc_dev/planejamento/39).
///
/// Excluir é diferente de desativar: o item some do painel e não volta. O
/// diálogo mostra o que vai junto e pede o nome digitado — o servidor confere.
Future<void> excluirDefinitivamente(
  BuildContext context, {
  required String tipo,
  required int id,
  required String oQue,
  required Future<void> Function() aoExcluir,
}) async {
  final servico = ExclusaoService();
  final excluiu = await abrirExclusaoDefinitiva(
    context,
    oQue: oQue,
    simular: () => servico.simular(tipo, id),
    excluir: (confirmar) => servico.excluir(tipo, id, confirmar),
  );
  if (excluiu) await aoExcluir();
}
