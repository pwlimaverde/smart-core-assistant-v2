import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';
import '../controllers/contatos_controllers.dart';

/// Cadastra um cliente antes de qualquer mensagem (C4).
Future<void> abrirCadastroDeContato(
  BuildContext context,
  ContatosController controller,
) => _abrir(context, controller, null);

/// Corrige o cadastro de um contato existente.
Future<void> abrirEdicaoDeContato(
  BuildContext context,
  Contato contato,
  ContatosController controller,
) => _abrir(context, controller, contato);

Future<void> _abrir(
  BuildContext context,
  ContatosController controller,
  Contato? existente,
) {
  final editando = existente != null;
  final nome = TextEditingController(text: existente?.nomeContato ?? '');
  final email = TextEditingController(text: existente?.email ?? '');
  final telefone = TextEditingController(text: existente?.telefone ?? '');
  // O número original guardado à parte: só se manda telefone ao servidor
  // quando ele mudou. Reenviar o mesmo faria a recusa por histórico aparecer
  // em toda edição de nome.
  final telefoneOriginal = existente?.telefone ?? '';

  var salvando = false;
  String? erro;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome, email, telefone],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setDialogState) => AlertDialog(
          title: Text(editando ? 'Editar contato' : 'Novo contato'),
          content: SizedBox(
            width: 420,
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
                    label: 'Telefone com DDD',
                    hint: 'ex: 11 99999-8888',
                    controller: telefone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    editando
                        ? 'O número só pode mudar enquanto este contato não '
                              'tiver conversa: o histórico está amarrado a ele.'
                        : 'É por este número que o WhatsApp reconhece o '
                              'cliente. Sem o código do país, assumimos o '
                              'Brasil (55).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.fgMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Nome',
                    hint: 'como você quer ver na lista',
                    controller: nome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'E-mail (opcional)',
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (editando && existente.nomePerfilWhatsapp.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: context.colors.fgMuted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'No WhatsApp esta pessoa se identifica como '
                            '"${existente.nomePerfilWhatsapp}".',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.colors.fgMuted),
                          ),
                        ),
                      ],
                    ),
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
              label: editando ? 'Salvar' : 'Cadastrar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      final numero = telefone.text.trim();
                      // Só a conferência que não depende do servidor: ele é
                      // quem normaliza e sabe o que aceita, e duplicar a regra
                      // aqui criaria duas verdades sobre o mesmo formato.
                      if (numero.isEmpty) {
                        setDialogState(
                          () => erro = 'Informe o telefone com DDD.',
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
                              AtualizarContatoParameters(
                                id: existente.id,
                                nomeContato: nome.text.trim(),
                                email: email.text.trim(),
                                telefone: numero == telefoneOriginal
                                    ? ''
                                    : numero,
                              ),
                            )
                          : await controller.criar(
                              CriarContatoParameters(
                                telefone: numero,
                                nomeContato: nome.text.trim(),
                                email: email.text.trim(),
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

/// Tirar da lista pede confirmação e diz o que acontece com o histórico.
Future<void> abrirDesativacaoDeContato(
  BuildContext context,
  Contato contato,
  ContatosController controller,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tirar da lista?'),
      content: Text(
        '"${contato.exibicao}" some da lista de contatos. As conversas dele '
        'continuam guardadas, e se ele mandar mensagem de novo o contato '
        'volta a aparecer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Tirar da lista'),
        ),
      ],
    ),
  );

  if (confirmou != true) return;

  final falha = await controller.definirAtivo(id: contato.id, ativo: false);
  if (falha != null) {
    messenger.showSnackBar(SnackBar(content: Text(falha.message)));
  }
}
