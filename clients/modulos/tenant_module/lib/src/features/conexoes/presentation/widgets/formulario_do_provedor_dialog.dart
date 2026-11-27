import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/provedor_canal.dart';
import '../../domain/parameters/conexoes_parameters.dart';
import '../controllers/integracoes_controller.dart';

/// Formulário de conexão por credenciais, MONTADO PELO DESCRITOR do provedor.
///
/// Nenhum campo aqui é de um provedor específico: o nome da conexão é comum a
/// todos, e o resto sai de `provedor.campos` (rótulo, tipo, obrigatoriedade,
/// ajuda). Segredo não é ecoado. Um provedor novo com outro formulário aparece
/// aqui sem mudar este arquivo.
///
/// Devolve a conexão criada, ou `null` se a pessoa cancelou.
Future<CanalConectado?> mostrarFormularioDoProvedor(
  BuildContext context, {
  required IntegracoesController controller,
  required ProvedorCanal provedor,
}) => showDialog<CanalConectado>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      FormularioDoProvedorDialog(controller: controller, provedor: provedor),
);

final class FormularioDoProvedorDialog extends StatefulWidget {
  final IntegracoesController controller;
  final ProvedorCanal provedor;

  const FormularioDoProvedorDialog({
    super.key,
    required this.controller,
    required this.provedor,
  });

  @override
  State<FormularioDoProvedorDialog> createState() =>
      _FormularioDoProvedorDialogState();
}

class _FormularioDoProvedorDialogState
    extends State<FormularioDoProvedorDialog> {
  final _nome = TextEditingController();
  late final Map<String, TextEditingController> _campos = {
    for (final c in widget.provedor.campos) c.chave: TextEditingController(),
  };
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rótulos dos obrigatórios que estão vazios, na ordem do formulário.
  List<String> _faltando() => [
    if (_nome.text.trim().isEmpty) 'Nome da conexão',
    for (final c in widget.provedor.campos)
      if (c.obrigatorio && _campos[c.chave]!.text.trim().isEmpty) c.rotulo,
  ];

  Future<void> _conectar() async {
    final faltando = _faltando();
    if (faltando.isNotEmpty) {
      setState(() => _erro = 'Preencha: ${faltando.join(', ')}.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final res = await widget.controller.conectar(
      ConectarCanalParameters(
        provedor: widget.provedor.id,
        nome: _nome.text.trim(),
        valores: {
          for (final e in _campos.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        },
      ),
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final value):
        Navigator.of(context).pop(value);
      case Failure(:final error):
        setState(() {
          _enviando = false;
          _erro = error.message;
        });
    }
  }

  TextInputType? _teclado(TipoCampoCanal tipo) => switch (tipo) {
    TipoCampoCanal.telefone => TextInputType.phone,
    TipoCampoCanal.url => TextInputType.url,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final provedor = widget.provedor;
    final ajuda = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.colors.fgMuted);

    return AlertDialog(
      title: Text('Conectar: ${provedor.nome}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(provedor.descricao, style: ajuda),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const ValueKey('campo-nome'),
                controller: _nome,
                label: 'Nome da conexão',
                hint: 'ex.: atendimento',
              ),
              for (final campo in provedor.campos) ...[
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  key: ValueKey('campo-${campo.chave}'),
                  controller: _campos[campo.chave],
                  label: campo.obrigatorio ? '${campo.rotulo} *' : campo.rotulo,
                  obscureText: campo.tipo == TipoCampoCanal.segredo,
                  obscureToggle: campo.tipo == TipoCampoCanal.segredo,
                  keyboardType: _teclado(campo.tipo),
                ),
                if (campo.ajuda.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(campo.ajuda, style: ajuda),
                  ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _erro!,
                  key: const ValueKey('erro-formulario'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _conectar,
          child: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Conectar'),
        ),
      ],
    );
  }
}
