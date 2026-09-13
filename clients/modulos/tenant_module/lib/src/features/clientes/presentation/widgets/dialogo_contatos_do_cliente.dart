import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart'
    hide ContatoDoCliente;

import '../../../contatos/domain/model/contato.dart';
import '../../../contatos/domain/parameters/contatos_parameters.dart';
import '../../../contatos/domain/usecases/contatos_usecases.dart';
import '../../domain/model/cliente.dart';
import '../controllers/clientes_controllers.dart';

/// B10 (N11 E5) — quem fala por este cliente, e ligar ou desligar contatos.
///
/// Ligar procura entre os contatos que já existem: o contato nasce da conversa
/// (ou do cadastro na tela de contatos), e aqui só se diz de que cliente ele é.
Future<void> abrirContatosDoCliente(
  BuildContext context,
  Cliente cliente,
  ClientesController controller, {
  required bool podeAlterar,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DialogoContatos(
    cliente: cliente,
    controller: controller,
    podeAlterar: podeAlterar,
  ),
);

class _DialogoContatos extends StatefulWidget {
  final Cliente cliente;
  final ClientesController controller;
  final bool podeAlterar;

  const _DialogoContatos({
    required this.cliente,
    required this.controller,
    required this.podeAlterar,
  });

  @override
  State<_DialogoContatos> createState() => _DialogoContatosState();
}

class _DialogoContatosState extends State<_DialogoContatos> {
  List<ContatoDoCliente>? _ligados;
  List<Contato> _encontrados = const [];
  String? _erro;
  Timer? _debounce;
  final _busca = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_carregar());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final res = await widget.controller.contatosDe(widget.cliente.id);
    if (!mounted) return;
    setState(() {
      switch (res) {
        case Success(:final value):
          _ligados = value;
          _erro = null;
        case Failure(:final error):
          _ligados = const [];
          _erro = error.message;
      }
    });
  }

  void _procurar(String texto) {
    _debounce?.cancel();
    if (texto.trim().isEmpty) {
      setState(() => _encontrados = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!GetIt.instance.isRegistered<ListarContatosUsecase>()) return;
      final res = await inject<ListarContatosUsecase>()(
        ListarContatosParameters(busca: texto.trim()),
      );
      if (!mounted) return;
      final ligados = {for (final c in _ligados ?? const []) c.id};
      setState(() {
        _encontrados = switch (res) {
          Success(:final value) =>
            value.where((c) => !ligados.contains(c.id)).take(8).toList(),
          Failure() => const [],
        };
      });
    });
  }

  Future<void> _alterar(int contatoId, {required bool vincular}) async {
    final falha = await widget.controller.vincular(
      clienteId: widget.cliente.id,
      contatoId: contatoId,
      vincular: vincular,
    );
    if (!mounted) return;
    if (falha != null) {
      setState(() => _erro = falha.message);
      return;
    }
    _busca.clear();
    setState(() => _encontrados = const []);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final ligados = _ligados;
    return AlertDialog(
      title: Text('Contatos de ${widget.cliente.dados.nomeFantasia}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_erro != null)
                Text(_erro!, style: TextStyle(color: context.colors.danger)),
              if (ligados == null)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ligados.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text('Nenhum contato ligado a este cliente ainda.'),
                )
              else
                for (final c in ligados)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(c.exibicao),
                    subtitle: c.telefone.isEmpty ? null : Text(c.telefone),
                    trailing: widget.podeAlterar
                        ? IconButton(
                            icon: const Icon(Icons.link_off),
                            tooltip: 'Desligar do cliente',
                            onPressed: () => _alterar(c.id, vincular: false),
                          )
                        : null,
                  ),
              if (widget.podeAlterar) ...[
                const Divider(height: 24),
                TextField(
                  controller: _busca,
                  onChanged: _procurar,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Ligar um contato (nome ou telefone)',
                    border: OutlineInputBorder(),
                  ),
                ),
                for (final c in _encontrados)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.exibicao),
                    subtitle: Text(c.telefone),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_link),
                      tooltip: 'Ligar a este cliente',
                      onPressed: () => _alterar(c.id, vincular: true),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
