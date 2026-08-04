import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/fluxo.dart';
import '../controllers/fluxos_controllers.dart';

/// Diálogos do fluxo.
///
/// Controllers pertencem ao `DialogoComCampos`, e o erro aparece dentro da
/// janela — SnackBar renderiza atrás do barrier modal.

Future<void> abrirCriacaoFluxo(
  BuildContext context,
  FluxosController controller,
) =>
    _abrirFormulario(context: context, controller: controller);

Future<void> abrirEdicaoFluxo(
  BuildContext context,
  Fluxo item,
  FluxosController controller,
) =>
    _abrirFormulario(context: context, controller: controller, item: item);

Future<void> _abrirFormulario({
  required BuildContext context,
  required FluxosController controller,
  Fluxo? item,
}) async {
  final nome = TextEditingController(text: item?.nome);
  final descricao = TextEditingController(text: item?.descricao);
  final departamentos = controller.departamentos;
  var departamentoId = item?.departamentoId ??
      (departamentos.isNotEmpty ? departamentos.first.id : 0);
  var ativo = item?.ativo ?? true;
  String? erro;
  var salvando = false;
  final editando = item != null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome, descricao],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: Text(editando ? 'Editar fluxo' : 'Novo fluxo'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!editando) ...[
                    // O departamento é escolhido uma vez: mover um fluxo de
                    // departamento mudaria o destino de conversas já em
                    // andamento, e isso não é edição de cadastro.
                    if (departamentos.isEmpty)
                      const Text(
                        'Nenhum departamento ativo. Crie um em "Equipe" antes '
                        'de montar o fluxo.',
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: departamentoId,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final d in departamentos)
                            DropdownMenuItem(value: d.id, child: Text(d.nome)),
                        ],
                        onChanged: (v) => setStateDialog(
                          () => departamentoId = v ?? departamentoId,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppTextField(
                    label: 'Nome',
                    hint: 'ex: Suporte técnico',
                    controller: nome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Descrição (opcional)',
                    hint: 'ex: Chamados que precisam de análise',
                    controller: descricao,
                  ),
                  if (!editando) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'O fluxo nasce com as quatro colunas padrão (fila, '
                      'atendimento, aguardando e finalização). Dá para '
                      'renomear e acrescentar depois.',
                      style: Theme.of(stateCtx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: stateCtx.colors.fgMuted),
                    ),
                  ],
                  if (editando) ...[
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativo'),
                      subtitle: const Text(
                        'Inativo não recebe conversas novas; o histórico fica.',
                      ),
                      value: ativo,
                      onChanged: (v) =>
                          setStateDialog(() => ativo = v ?? ativo),
                    ),
                  ],
                  if (erro case final msg?) ...[
                    const SizedBox(height: AppSpacing.md),
                    _Erro(mensagem: msg),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  salvando ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              label: 'Salvar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (nome.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o nome do fluxo.',
                        );
                        return;
                      }
                      if (!editando && departamentoId <= 0) {
                        setStateDialog(
                          () => erro = 'Escolha o departamento do fluxo.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = editando
                          ? await controller.atualizar(
                              id: item.id,
                              nome: nome.text.trim(),
                              descricao: descricao.text.trim(),
                              ativo: ativo,
                            )
                          : await controller.criar(
                              departamentoId: departamentoId,
                              nome: nome.text.trim(),
                              descricao: descricao.text.trim(),
                            );

                      if (res case Failure(:final error)) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
                            salvando = false;
                            erro = error.message;
                          });
                        }
                        return;
                      }
                      navigator.pop();
                    },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> abrirDesativacaoFluxo(
  BuildContext context,
  Fluxo item,
  FluxosController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Desativar "${item.nome}"?'),
      content: const Text(
        'Ele para de receber conversas novas. O histórico fica, e dá para '
        'reativar depois.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Desativar'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  // Resolvido antes do await: desativar recarrega a lista e desmonta a linha.
  final messenger = ScaffoldMessenger.of(context);
  final res = await controller.desativar(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Fluxo desativado.',
          Failure(:final error) => error.message,
        },
      ),
    ),
  );
}

class _Erro extends StatelessWidget {
  final String mensagem;

  const _Erro({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: cor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(mensagem, style: TextStyle(color: cor))),
      ],
    );
  }
}
