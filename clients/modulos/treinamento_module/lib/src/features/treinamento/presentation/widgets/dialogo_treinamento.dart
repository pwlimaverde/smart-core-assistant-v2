import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/treinamento.dart';
import '../controllers/treinamento_controllers.dart';

/// Diálogos do treinamento.
///
/// Duas decisões herdadas de bugs já vividos neste projeto:
///
///  - os controllers pertencem ao `DialogoComCampos` — descartá-los pelo
///    `whenComplete` do `showDialog` quebra durante a animação de saída;
///  - o erro aparece DENTRO da janela — um SnackBar renderiza atrás do barrier
///    modal, e o usuário clicaria em salvar sem ver nada acontecer.

Future<void> abrirCriacao(
  BuildContext context,
  TreinamentoController controller,
) async {
  final tag = TextEditingController();
  final grupo = TextEditingController();
  final conteudo = TextEditingController();
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [tag, grupo, conteudo],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Ensinar algo novo'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Assunto',
                    hint: 'ex: horario-de-funcionamento',
                    controller: tag,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Grupo',
                    hint: 'ex: atendimento',
                    controller: grupo,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: conteudo,
                    maxLines: 10,
                    minLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'O que a IA precisa saber',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText: 'Escreva como explicaria a um atendente novo.',
                    ),
                  ),
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
                      if (tag.text.trim().isEmpty ||
                          grupo.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o assunto e o grupo.',
                        );
                        return;
                      }
                      if (conteudo.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Escreva o que a IA precisa saber.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = await controller.criar(
                        tag: tag.text.trim(),
                        grupo: grupo.text.trim(),
                        conteudo: conteudo.text,
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

/// Revisão do material antes de virar vetor.
///
/// É o passo que a v1 chamava de pré-processamento. Aceitar é o que põe o
/// material na fila da IA — e o texto que estiver aqui é o que ela vai usar.
Future<void> abrirRevisao(
  BuildContext context,
  Treinamento item,
  TreinamentoController controller,
) async {
  final conteudo = TextEditingController(text: item.conteudo);
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [conteudo],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: Text('Revisar "${item.tag}"'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajuste o texto se precisar. Ao aceitar, a IA processa este '
                    'material e passa a usá-lo nas respostas.',
                    style: Theme.of(stateCtx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: stateCtx.colors.fgMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: conteudo,
                    maxLines: 14,
                    minLines: 8,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
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
              label: 'Aceitar e treinar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (conteudo.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'O conteúdo não pode ficar vazio.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = await controller.finalizar(
                        id: item.id,
                        conteudo: conteudo.text,
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

Future<void> abrirRemocao(
  BuildContext context,
  Treinamento item,
  TreinamentoController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remover este material?'),
      content: Text(
        'O assistente deixa de usar "${item.tag}" nas respostas. '
        'Isto não pode ser desfeito.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  // Resolvido antes do await: remover recarrega a lista e desmonta a linha que
  // abriu este diálogo.
  final messenger = ScaffoldMessenger.of(context);
  final res = await controller.remover(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Material removido.',
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
