import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/intent.dart';
import '../../domain/parameters/intents_parameters.dart';
import '../controllers/intents_controllers.dart';

/// Diálogos da intenção.
///
/// Controllers pertencem ao `DialogoComCampos`, e o erro aparece dentro da
/// janela — SnackBar renderiza atrás do barrier modal.

Future<void> abrirCriacaoIntent(
  BuildContext context,
  IntentsController controller,
) =>
    _abrirFormulario(context: context, controller: controller);

Future<void> abrirEdicaoIntent(
  BuildContext context,
  IntentIa item,
  IntentsController controller,
) =>
    _abrirFormulario(context: context, controller: controller, item: item);

Future<void> _abrirFormulario({
  required BuildContext context,
  required IntentsController controller,
  IntentIa? item,
}) async {
  final tag = TextEditingController(text: item?.tag);
  final grupo = TextEditingController(text: item?.grupo);
  final descricao = TextEditingController(text: item?.descricao);
  final exemplo = TextEditingController(text: item?.exemplo);
  final comportamento = TextEditingController(text: item?.comportamento);
  String? erro;
  var salvando = false;
  final editando = item != null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [tag, grupo, descricao, exemplo, comportamento],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: Text(editando ? 'Editar intenção' : 'Nova intenção'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Assunto',
                    hint: 'ex: falar-com-humano',
                    controller: tag,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Grupo (opcional)',
                    hint: 'ex: atendimento',
                    controller: grupo,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Quando se aplica',
                    hint: 'ex: o cliente pede para falar com uma pessoa',
                    controller: descricao,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Exemplo de pergunta',
                    hint: 'ex: quero falar com um atendente',
                    controller: exemplo,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Os dois campos acima viram o vetor: é com eles que a
                  // pergunta do cliente é comparada.
                  Text(
                    'A comparação usa "quando se aplica" e o exemplo. Quanto '
                    'mais parecidos com o jeito real de perguntar, melhor.',
                    style: Theme.of(stateCtx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: stateCtx.colors.fgMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: comportamento,
                    maxLines: 5,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'O que a IA deve fazer',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText:
                          'ex: encerre a conversa e transfira ao setor',
                    ),
                  ),
                  if (editando) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // Salvar zera o vetor no servidor: o texto mudou, e o
                    // vetor antigo faria a busca casar pelo que a intenção era.
                    Text(
                      'Ao salvar, a intenção volta para processamento e fica '
                      'alguns instantes fora do ar.',
                      style: Theme.of(stateCtx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: stateCtx.colors.fgMuted),
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
                      if (tag.text.trim().isEmpty) {
                        setStateDialog(() => erro = 'Informe o assunto.');
                        return;
                      }
                      if (descricao.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Descreva quando esta intenção se '
                              'aplica.',
                        );
                        return;
                      }
                      if (comportamento.text.trim().isEmpty) {
                        // Sem comportamento, casar a intenção não muda nada —
                        // seria cadastro sem efeito.
                        setStateDialog(
                          () => erro = 'Informe o que a IA deve fazer.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final dados = DadosIntent(
                        tag: tag.text.trim(),
                        grupo: grupo.text.trim(),
                        descricao: descricao.text.trim(),
                        exemplo: exemplo.text.trim(),
                        comportamento: comportamento.text.trim(),
                      );
                      final res = editando
                          ? await controller.atualizar(
                              id: item.id,
                              dados: dados,
                            )
                          : await controller.criar(dados);

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

Future<void> abrirRemocaoIntent(
  BuildContext context,
  IntentIa item,
  IntentsController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remover a intenção "${item.tag}"?'),
      content: const Text(
        'A IA deixa de seguir este comportamento nas próximas conversas. '
        'O material treinado não é afetado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  // Resolvido antes do await: remover recarrega a lista e desmonta a linha.
  final messenger = ScaffoldMessenger.of(context);
  final res = await controller.remover(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Intenção removida.',
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
