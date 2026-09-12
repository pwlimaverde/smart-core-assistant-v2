import 'package:dependencies_module/dependencies_module.dart' hide OpcaoCampo;

import '../../domain/model/campo_personalizado.dart';
import '../../domain/parameters/campos_parameters.dart';
import '../controllers/campos_controller.dart';

/// Cria um campo do cartão.
Future<void> abrirCriacaoDeCampo(
  BuildContext context,
  CamposController controller,
) => _abrir(context, controller, null);

/// Edita um campo existente.
///
/// Sem escopo nem quadro: mover um campo de escopo mudaria a quais
/// atendimentos ele se aplica, e os valores já coletados ficariam órfãos.
Future<void> abrirEdicaoDeCampo(
  BuildContext context,
  CampoPersonalizado campo,
  CamposController controller,
) => _abrir(context, controller, campo);

Future<void> _abrir(
  BuildContext context,
  CamposController controller,
  CampoPersonalizado? existente,
) {
  final editando = existente != null;
  final nome = TextEditingController(text: existente?.nome ?? '');
  final descricao = TextEditingController(text: existente?.descricao ?? '');
  final hint = TextEditingController(text: existente?.extrairHint ?? '');
  final novaOpcao = TextEditingController();

  var tipo = existente?.tipo ?? TipoCampo.texto;
  var opcoes = [...?existente?.opcoes];
  var obrigatorio = existente?.obrigatorio ?? false;
  var extrair = existente?.extrairAutomaticamente ?? true;
  var mostrarNoCard = existente?.mostrarNoCard ?? true;
  var ativo = existente?.ativo ?? true;
  var salvando = false;
  String? erro;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome, descricao, hint, novaOpcao],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setDialogState) => AlertDialog(
          title: Text(editando ? 'Editar campo' : 'Novo campo'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (erro != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: context.colors.dangerSoft,
                        borderRadius: AppRadius.md,
                      ),
                      child: Text(
                        erro!,
                        style: TextStyle(
                          color: context.colors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AppTextField(
                    label: 'Nome do campo',
                    hint: 'ex: Número do pedido',
                    controller: nome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Descrição',
                    hint: 'ex: o número do pedido que o cliente informou',
                    controller: descricao,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Serve para duas coisas: explica o campo para quem '
                      'preenche e diz à IA o que procurar na conversa.',
                      style: Theme.of(stateCtx).textTheme.bodySmall?.copyWith(
                        color: context.colors.fgMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<TipoCampo>(
                    initialValue: tipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de dado',
                    ),
                    items: [
                      for (final t in TipoCampo.values)
                        DropdownMenuItem(value: t, child: Text(t.rotulo)),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => tipo = v ?? TipoCampo.texto),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      tipo.explicacao,
                      style: Theme.of(stateCtx).textTheme.bodySmall?.copyWith(
                        color: context.colors.fgMuted,
                      ),
                    ),
                  ),

                  // Só o campo de lista mostra as opções — e ele PRECISA de
                  // ao menos uma: sem opções não há o que escolher, e a IA
                  // não teria contra o que validar o que extraiu.
                  if (tipo == TipoCampo.lista) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Opções',
                      style: Theme.of(stateCtx).textTheme.labelLarge,
                    ),
                    for (final o in opcoes)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(o.rotulo),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remover opção',
                          onPressed: () =>
                              setDialogState(() => opcoes.remove(o)),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Nova opção',
                            hint: 'ex: Cartão de crédito',
                            controller: novaOpcao,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Adicionar opção',
                          onPressed: () {
                            final texto = novaOpcao.text.trim();
                            if (texto.isEmpty) return;
                            setDialogState(() {
                              opcoes = [
                                ...opcoes,
                                OpcaoCampo(
                                  // O id sai do rótulo e não muda depois:
                                  // renomear "Cartão" não pode invalidar o
                                  // que já foi preenchido.
                                  id: texto.toLowerCase().replaceAll(
                                    RegExp(r'[^a-z0-9]+'),
                                    '-',
                                  ),
                                  rotulo: texto,
                                ),
                              ];
                              novaOpcao.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: extrair,
                    title: const Text('A IA tenta preencher'),
                    subtitle: const Text(
                      'Durante a conversa, quando o cliente informar.',
                    ),
                    onChanged: (v) => setDialogState(() => extrair = v),
                  ),
                  if (extrair)
                    AppTextField(
                      label: 'Como perguntar (opcional)',
                      hint: 'ex: pergunte o número do pedido sem insistir',
                      controller: hint,
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: obrigatorio,
                    title: const Text('Obrigatório'),
                    // As duas chaves foram tratadas como uma só, e o efeito
                    // era marcar "obrigatório" e a IA sair perseguindo o
                    // campo. São regras diferentes e a tela diz qual é qual.
                    subtitle: const Text(
                      'Impede concluir o atendimento sem este campo.',
                    ),
                    onChanged: (v) => setDialogState(() => obrigatorio = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: mostrarNoCard,
                    title: const Text('Mostrar no cartão do quadro'),
                    onChanged: (v) => setDialogState(() => mostrarNoCard = v),
                  ),
                  if (editando)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: ativo,
                      title: const Text('Ativo'),
                      subtitle: const Text(
                        'Desativado some das fichas novas; o que já foi '
                        'preenchido continua guardado.',
                      ),
                      onChanged: (v) => setDialogState(() => ativo = v),
                    ),
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
              label: editando ? 'Salvar' : 'Criar campo',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (nome.text.trim().isEmpty) {
                        setDialogState(
                          () => erro = 'O campo precisa de um nome.',
                        );
                        return;
                      }
                      if (tipo == TipoCampo.lista && opcoes.isEmpty) {
                        setDialogState(
                          () => erro =
                              'Um campo de lista precisa de ao menos uma '
                              'opção.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() {
                        salvando = true;
                        erro = null;
                      });

                      final falha = editando
                          ? await controller.atualizar(
                              AtualizarCampoParameters(
                                id: existente.id,
                                nome: nome.text.trim(),
                                descricao: descricao.text.trim(),
                                tipo: tipo,
                                opcoes: opcoes,
                                obrigatorio: obrigatorio,
                                extrairAutomaticamente: extrair,
                                extrairHint: hint.text.trim(),
                                mostrarNoCard: mostrarNoCard,
                                ordem: existente.ordem,
                                ativo: ativo,
                              ),
                            )
                          : await controller.criar(
                              CriarCampoParameters(
                                nome: nome.text.trim(),
                                descricao: descricao.text.trim(),
                                tipo: tipo,
                                opcoes: opcoes,
                                obrigatorio: obrigatorio,
                                extrairAutomaticamente: extrair,
                                extrairHint: hint.text.trim(),
                                mostrarNoCard: mostrarNoCard,
                              ),
                            );

                      if (falha != null) {
                        // O erro fica DENTRO da janela: fechá-la faria a
                        // pessoa perder o que digitou.
                        if (stateCtx.mounted) {
                          setDialogState(() {
                            salvando = false;
                            erro = falha.message;
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

/// Desativar pede confirmação e diz o que acontece com o que já foi coletado.
Future<void> abrirDesativacao(
  BuildContext context,
  CampoPersonalizado campo,
  CamposController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Desativar "${campo.nome}"?'),
      content: const Text(
        'O campo some das fichas novas e a IA para de preenchê-lo. '
        'O que já foi registrado continua guardado nos atendimentos.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Desativar'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;

  final falha = await controller.desativar(campo.id);
  if (falha != null) {
    messenger.showSnackBar(SnackBar(content: Text(falha.message)));
  }
}
