import 'package:flutter/material.dart';

/// O que a exclusão vai atingir, como o servidor descreveu na simulação.
typedef DescricaoDeExclusao = ({String rotulo, int conversas, String emUso});

/// Abre o diálogo de **exclusão definitiva** (doc_dev/planejamento/39).
///
/// Excluir não é desativar: o item some do painel e não volta. Por isso o
/// diálogo:
///
/// 1. pergunta ao servidor o que vai ser atingido (`simular`) — o nome exato,
///    as conversas que vão junto e se o item está em uso;
/// 2. exige que a pessoa **digite o nome** para liberar o botão;
/// 3. manda o nome digitado em `excluir`, e o servidor confere de novo.
///
/// `excluir` devolve a mensagem de erro, ou `null` quando excluiu. O retorno é
/// `true` só quando o item foi de fato excluído.
Future<bool> abrirExclusaoDefinitiva(
  BuildContext context, {
  required String oQue,
  required Future<DescricaoDeExclusao> Function() simular,
  required Future<String?> Function(String confirmar) excluir,
}) async {
  final excluiu = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogoExclusaoDefinitiva(
      oQue: oQue,
      simular: simular,
      excluir: excluir,
    ),
  );
  return excluiu ?? false;
}

class _DialogoExclusaoDefinitiva extends StatefulWidget {
  final String oQue;
  final Future<DescricaoDeExclusao> Function() simular;
  final Future<String?> Function(String confirmar) excluir;

  const _DialogoExclusaoDefinitiva({
    required this.oQue,
    required this.simular,
    required this.excluir,
  });

  @override
  State<_DialogoExclusaoDefinitiva> createState() =>
      _DialogoExclusaoDefinitivaState();
}

class _DialogoExclusaoDefinitivaState
    extends State<_DialogoExclusaoDefinitiva> {
  // O campo pertence a este widget: descartado no `dispose`, quando a rota do
  // diálogo já saiu da árvore (ver `DialogoComCampos`).
  final _nome = TextEditingController();
  late final Future<DescricaoDeExclusao> _descricao = widget.simular();
  bool _excluindo = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nome.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() {
      _excluindo = true;
      _erro = null;
    });
    final erro = await widget.excluir(_nome.text.trim());
    if (!mounted) return;
    if (erro == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _excluindo = false;
      _erro = erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final erroCor = Theme.of(context).colorScheme.error;
    return FutureBuilder<DescricaoDeExclusao>(
      future: _descricao,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AlertDialog(
            content: SizedBox(
              height: 64,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snap.hasError || snap.data == null) {
          return AlertDialog(
            title: Text('Excluir ${widget.oQue}'),
            content: const Text(
              'Não foi possível conferir o item. Ele pode já ter sido excluído.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Fechar'),
              ),
            ],
          );
        }

        final d = snap.data!;
        if (d.emUso.isNotEmpty) {
          return AlertDialog(
            title: Text('Não dá para excluir ${widget.oQue}'),
            content: Text('"${d.rotulo}": ${d.emUso}.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Entendi'),
              ),
            ],
          );
        }

        final confere = _nome.text.trim() == d.rotulo.trim();
        return AlertDialog(
          title: Text('Excluir ${widget.oQue} definitivamente?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${d.rotulo}" some do painel, das listas e dos relatórios '
                'e não pode ser restaurado. Se precisar de novo, será '
                'preciso criar outro.',
              ),
              if (d.conversas > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${d.conversas} conversa(s) serão excluídas junto.',
                  style: TextStyle(color: erroCor, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 8),
              const Text('Para só tirar de uso, com volta, use "Desativar".'),
              const SizedBox(height: 16),
              Text('Digite "${d.rotulo}" para confirmar:'),
              const SizedBox(height: 8),
              TextField(
                controller: _nome,
                autofocus: true,
                enabled: !_excluindo,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 8),
                Text(_erro!, style: TextStyle(color: erroCor)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _excluindo
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: erroCor),
              onPressed: confere && !_excluindo ? _confirmar : null,
              child: Text(
                _excluindo ? 'Excluindo…' : 'Excluir definitivamente',
              ),
            ),
          ],
        );
      },
    );
  }
}
