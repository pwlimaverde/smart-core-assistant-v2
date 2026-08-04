import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/equipe.dart';
import '../controllers/equipe_controllers.dart';

/// Diálogos do atendente.
///
/// Controllers pertencem ao `DialogoComCampos`, e o erro aparece dentro da
/// janela — SnackBar renderiza atrás do barrier modal.

Future<void> abrirCriacaoAtendente(
  BuildContext context,
  EquipeController controller,
  List<Departamento> departamentos,
) =>
    _abrirFormulario(
      context: context,
      controller: controller,
      departamentos: departamentos,
    );

Future<void> abrirEdicaoAtendente(
  BuildContext context,
  Atendente item,
  EquipeController controller,
  List<Departamento> departamentos,
) =>
    _abrirFormulario(
      context: context,
      controller: controller,
      departamentos: departamentos,
      item: item,
    );

Future<void> _abrirFormulario({
  required BuildContext context,
  required EquipeController controller,
  required List<Departamento> departamentos,
  Atendente? item,
}) async {
  final nome = TextEditingController(text: item?.nome);
  final email = TextEditingController(text: item?.email);
  final cargo = TextEditingController(text: item?.cargo);
  final fluxos = controller.fluxosDisponiveis;
  final ativos = departamentos.where((d) => d.ativo).toList();

  var fluxoId = item?.fluxoId ?? (fluxos.isNotEmpty ? fluxos.first.id : 0);
  var departamentoId = item?.departamentoId ?? 0;
  var ativo = item?.ativo ?? true;
  var disponivel = item?.disponivel ?? true;
  var maxSimultaneos = item?.maxSimultaneos ?? 5;
  String? erro;
  var salvando = false;
  final editando = item != null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome, email, cargo],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: Text(editando ? 'Editar atendente' : 'Novo atendente'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Nome',
                    hint: 'ex: Ana Souza',
                    controller: nome,
                  ),
                  if (!editando) ...[
                    const SizedBox(height: AppSpacing.md),
                    // O e-mail identifica a pessoa dentro do tenant (é a chave
                    // única) e por isso não muda depois do cadastro.
                    AppTextField(
                      label: 'E-mail',
                      hint: 'ex: ana@empresa.com.br',
                      controller: email,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Cargo (opcional)',
                    hint: 'ex: Analista de suporte',
                    controller: cargo,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (fluxos.isEmpty)
                    const Text(
                      'Nenhum fluxo ativo. Crie um em "Fluxos de atendimento" '
                      'antes de cadastrar quem vai atender.',
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: fluxos.any((f) => f.id == fluxoId)
                          ? fluxoId
                          : fluxos.first.id,
                      decoration: const InputDecoration(
                        labelText: 'Fluxo em que trabalha',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final f in fluxos)
                          DropdownMenuItem(
                            value: f.id,
                            child: Text('${f.departamentoNome} · ${f.nome}'),
                          ),
                      ],
                      onChanged: (v) =>
                          setStateDialog(() => fluxoId = v ?? fluxoId),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<int>(
                    initialValue:
                        ativos.any((d) => d.id == departamentoId)
                            ? departamentoId
                            : 0,
                    decoration: const InputDecoration(
                      labelText: 'Departamento',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Nenhum')),
                      for (final d in ativos)
                        DropdownMenuItem(value: d.id, child: Text(d.nome)),
                    ],
                    onChanged: (v) =>
                        setStateDialog(() => departamentoId = v ?? 0),
                  ),
                  if (editando) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Conversas ao mesmo tempo: $maxSimultaneos',
                            style: Theme.of(stateCtx).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove),
                          tooltip: 'Menos',
                          // Teto de zero deixaria a pessoa cadastrada e nunca
                          // elegível — inativa por acidente.
                          onPressed: maxSimultaneos <= 1
                              ? null
                              : () =>
                                  setStateDialog(() => maxSimultaneos -= 1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Mais',
                          onPressed: maxSimultaneos >= 100
                              ? null
                              : () =>
                                  setStateDialog(() => maxSimultaneos += 1),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativo'),
                      subtitle: const Text('O cadastro em si.'),
                      value: ativo,
                      onChanged: (v) =>
                          setStateDialog(() => ativo = v ?? ativo),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Disponível'),
                      subtitle: const Text(
                        'Aceitando conversa agora. Quem está de férias fica '
                        'ativo e indisponível.',
                      ),
                      value: disponivel,
                      // Inativo não pode ficar disponível: seguiria elegível no
                      // rodízio de atribuição sem estar trabalhando.
                      onChanged: ativo
                          ? (v) => setStateDialog(
                                () => disponivel = v ?? disponivel,
                              )
                          : null,
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
                          () => erro = 'Informe o nome do atendente.',
                        );
                        return;
                      }
                      if (!editando && email.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o e-mail do atendente.',
                        );
                        return;
                      }
                      if (fluxoId <= 0) {
                        setStateDialog(
                          () => erro = 'Escolha o fluxo em que ela trabalha.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = editando
                          ? await controller.atualizarAtendente(
                              id: item.id,
                              nome: nome.text.trim(),
                              cargo: cargo.text.trim(),
                              departamentoId: departamentoId,
                              fluxoId: fluxoId,
                              ativo: ativo,
                              // Inativo nunca sai daqui como disponível.
                              disponivel: ativo && disponivel,
                              maxSimultaneos: maxSimultaneos,
                            )
                          : await controller.criarAtendente(
                              nome: nome.text.trim(),
                              email: email.text.trim(),
                              cargo: cargo.text.trim(),
                              fluxoId: fluxoId,
                              departamentoId: departamentoId,
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

Future<void> abrirDesativacaoAtendente(
  BuildContext context,
  Atendente item,
  EquipeController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Desativar "${item.nome}"?'),
      content: const Text(
        'A pessoa para de receber conversas novas. O histórico de quem '
        'atendeu o quê continua, e dá para reativar depois.',
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
  final res = await controller.desativarAtendente(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        switch (res) {
          Success() => 'Atendente desativado.',
          // A recusa por conversa em andamento vem do servidor com o motivo
          // escrito — inclusive quantas.
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
