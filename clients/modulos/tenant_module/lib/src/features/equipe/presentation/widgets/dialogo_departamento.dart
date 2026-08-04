import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/equipe.dart';
import '../controllers/equipe_controllers.dart';

/// Diálogos do departamento.
///
/// Controllers pertencem ao `DialogoComCampos`, e o erro aparece dentro da
/// janela — as duas lições das rodadas anteriores.

Future<void> abrirCriacaoDepartamento(
  BuildContext context,
  EquipeController controller,
) =>
    _abrirFormulario(context: context, controller: controller);

Future<void> abrirEdicaoDepartamento(
  BuildContext context,
  Departamento item,
  EquipeController controller,
) =>
    _abrirFormulario(context: context, controller: controller, item: item);

Future<void> _abrirFormulario({
  required BuildContext context,
  required EquipeController controller,
  Departamento? item,
}) async {
  final nome = TextEditingController(text: item?.nome);
  final descricao = TextEditingController(text: item?.descricao);
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
          title: Text(editando ? 'Editar departamento' : 'Novo departamento'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Nome',
                    hint: 'ex: Suporte',
                    controller: nome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Descrição (opcional)',
                    hint: 'ex: Dúvidas sobre pedidos em andamento',
                    controller: descricao,
                  ),
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
                          () => erro = 'Informe o nome do departamento.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = editando
                          ? await controller.atualizarDepartamento(
                              id: item.id,
                              nome: nome.text.trim(),
                              descricao: descricao.text.trim(),
                              ativo: ativo,
                            )
                          : await controller.criarDepartamento(
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

Future<void> abrirDesativacaoDepartamento(
  BuildContext context,
  Departamento item,
  EquipeController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Desativar "${item.nome}"?'),
      content: const Text(
        'Ele para de receber conversas novas. Os atendimentos que já passaram '
        'por ele continuam no histórico, e dá para reativar depois.',
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
  final res = await controller.desativarDepartamento(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Departamento desativado.',
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
