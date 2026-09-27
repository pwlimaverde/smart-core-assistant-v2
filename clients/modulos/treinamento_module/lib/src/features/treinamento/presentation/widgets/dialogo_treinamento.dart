import 'package:dependencies_module/dependencies_module.dart';
import 'package:file_picker/file_picker.dart';

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

/// Devolve `true` quando o treinamento foi criado — o P17 usa para tirar a
/// avaliação da revisão só depois de ela ter virado material.
Future<bool> abrirCriacao(
  BuildContext context,
  TreinamentoController controller, {
  String conteudoInicial = '',
}) async {
  final tag = TextEditingController();
  final grupo = TextEditingController();
  final conteudo = TextEditingController(text: conteudoInicial);
  var criou = false;
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
                      helperText:
                          'Escreva como explicaria a um atendente novo.',
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
              onPressed: salvando
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
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
                      criou = true;
                      navigator.pop();
                    },
            ),
          ],
        ),
      ),
    ),
  );
  return criou;
}

/// B9 (N10 E5) — os formatos que o servidor lê.
const extensoesDeTreinamento = ['pdf', 'docx', 'xlsx', 'txt', 'csv'];

/// O mimetype de um arquivo de treinamento pelo nome, ou `null` se o formato
/// não é aceito. O servidor confere de novo — pelo conteúdo.
String? mimetypeDoArquivo(String nome) {
  final extensao = nome.contains('.')
      ? nome.substring(nome.lastIndexOf('.') + 1).toLowerCase()
      : '';
  return switch (extensao) {
    'pdf' => 'application/pdf',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    _ => null,
  };
}

/// B9 (N10 E5) — ensinar a partir de um arquivo.
///
/// O texto não aparece aqui: o servidor o lê depois, e o material chega à lista
/// como rascunho para revisar — o mesmo passo do texto colado.
Future<void> abrirEnvioDeArquivo(
  BuildContext context,
  TreinamentoController controller,
) async {
  final tag = TextEditingController();
  final grupo = TextEditingController();
  PlatformFile? arquivo;
  String? erro;
  var enviando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [tag, grupo],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Ensinar a partir de um arquivo'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Assunto',
                    hint: 'ex: tabela-de-precos',
                    controller: tag,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Grupo',
                    hint: 'ex: vendas',
                    controller: grupo,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      arquivo == null ? 'Escolher arquivo' : arquivo!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: enviando
                        ? null
                        : () async {
                            final escolha = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: extensoesDeTreinamento,
                              withData: true,
                            );
                            final escolhido = escolha?.files.firstOrNull;
                            if (escolhido == null) return;
                            setStateDialog(() {
                              arquivo = escolhido;
                              erro = null;
                            });
                          },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'PDF, Word (.docx), Excel (.xlsx), texto ou CSV. Arquivos '
                    '.doc e .xls: salve como .docx ou .xlsx antes.',
                    style: Theme.of(stateCtx).textTheme.bodySmall,
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
              onPressed: enviando
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              label: 'Enviar',
              expand: false,
              isLoading: enviando,
              onPressed: enviando
                  ? null
                  : () async {
                      if (tag.text.trim().isEmpty ||
                          grupo.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o assunto e o grupo.',
                        );
                        return;
                      }
                      final escolhido = arquivo;
                      final bytes = escolhido?.bytes;
                      final mimetype = escolhido == null
                          ? null
                          : mimetypeDoArquivo(escolhido.name);
                      if (escolhido == null || bytes == null) {
                        setStateDialog(() => erro = 'Escolha o arquivo.');
                        return;
                      }
                      if (mimetype == null) {
                        setStateDialog(
                          () => erro =
                              'Formato não aceito. Envie PDF, DOCX, XLSX, TXT ou CSV.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        enviando = true;
                        erro = null;
                      });
                      final res = await controller.enviarArquivo(
                        tag: tag.text.trim(),
                        grupo: grupo.text.trim(),
                        nomeArquivo: escolhido.name,
                        mimetype: mimetype,
                        bytes: bytes,
                      );
                      if (res case Failure(:final error)) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
                            enviando = false;
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

/// O material inteiro, para conferir o que a IA sabe.
///
/// A lista mostra só o começo do texto; conferir um material exigia abrir a
/// edição, com risco de mexer sem querer. Aqui é leitura (o texto pode ser
/// selecionado e copiado), e a edição é um passo explícito: "Editar e
/// retreinar" leva ao texto e, ao salvar, a IA refaz o treinamento dele.
Future<void> abrirMaterial(
  BuildContext context,
  Treinamento item,
  TreinamentoController controller, {
  required bool podeAlterar,
}) async {
  // O contexto do navegador sobrevive à lista: ela recarrega sozinha enquanto
  // há material em processamento, e a linha que abriu esta janela pode sumir.
  final contextoEstavel = Navigator.of(context).context;
  final podeEditar = podeAlterar && !item.extraindo;
  final acao = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final estilo = Theme.of(dialogContext).textTheme;
      final apagado = dialogContext.colors.fgMuted;
      return AlertDialog(
        title: Text(item.tag),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  'Grupo: ${item.grupo}',
                  item.situacao.rotulo,
                  if (item.veioDeArquivo) 'Arquivo: ${item.arquivoNome}',
                ].join('  ·  '),
                style: estilo.bodySmall?.copyWith(color: apagado),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.situacao.explicacao,
                style: estilo.bodySmall?.copyWith(color: apagado),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: dialogContext.colors.border),
                    borderRadius: AppRadius.md,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      item.conteudo.trim().isEmpty
                          ? (item.extraindo
                                ? 'O arquivo ainda está sendo lido.'
                                : 'Sem texto.')
                          : item.conteudo,
                      key: const ValueKey('conteudo-do-material'),
                      style: estilo.bodyMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${item.conteudo.length} caracteres',
                style: estilo.bodySmall?.copyWith(color: apagado),
              ),
            ],
          ),
        ),
        actions: [
          if (podeAlterar)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('remover'),
              child: const Text('Remover'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
          if (podeEditar)
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                item.finalizado ? 'Editar e retreinar' : 'Revisar e treinar',
              ),
              onPressed: () => Navigator.of(dialogContext).pop('editar'),
            ),
        ],
      );
    },
  );
  if (!contextoEstavel.mounted) return;
  switch (acao) {
    case 'editar':
      await abrirRevisao(contextoEstavel, item, controller);
    case 'remover':
      await abrirRemocao(contextoEstavel, item, controller);
  }
}

/// Revisão do material antes de virar vetor — e edição do que já virou.
///
/// É o passo que a v1 chamava de pré-processamento. Aceitar é o que põe o
/// material na fila da IA — e o texto que estiver aqui é o que ela vai usar.
/// Num material já treinado, salvar retreina: os trechos do texto anterior
/// são substituídos pelos do novo (não somados).
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
          title: Text(
            item.finalizado
                ? 'Editar e retreinar "${item.tag}"'
                : 'Revisar "${item.tag}"',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.finalizado
                        ? 'Ao salvar, a IA refaz o treinamento deste material '
                              'com o texto novo. O texto anterior deixa de ser '
                              'usado nas respostas.'
                        : 'Ajuste o texto se precisar. Ao aceitar, a IA '
                              'processa este material e passa a usá-lo nas '
                              'respostas.',
                    style: Theme.of(stateCtx).textTheme.bodySmall?.copyWith(
                      color: stateCtx.colors.fgMuted,
                    ),
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
              onPressed: salvando
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              label: item.finalizado
                  ? 'Salvar e retreinar'
                  : 'Aceitar e treinar',
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
      content: Text(switch (res) {
        Success() => 'Material removido.',
        Failure(:final error) => error.message,
      }),
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
        Expanded(
          child: Text(mensagem, style: TextStyle(color: cor)),
        ),
      ],
    );
  }
}
