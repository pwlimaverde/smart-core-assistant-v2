import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/model/fluxo.dart';
import '../controllers/fluxos_controllers.dart';

/// Paleta sugerida para as colunas.
///
/// A cor serve para distinguir colunas de relance: é ela que pinta a borda da
/// coluna, a faixa no topo dos cartões e, nas colunas de desfecho, o fundo do
/// cartão. A paleta cobre o comum; para a cor da marca, há o campo
/// hexadecimal logo abaixo dela.
const coresDeEtapa = <String>[
  '#6B7280',
  '#3B82F6',
  '#F59E0B',
  '#10B981',
  '#EF4444',
  '#8B5CF6',
  '#0EA5E9',
  '#06B6D4',
  '#14B8A6',
  '#22C55E',
  '#84CC16',
  '#EAB308',
  '#F97316',
  '#F43F5E',
  '#EC4899',
  '#D946EF',
  '#6366F1',
  '#1E3A8A',
  '#78350F',
  '#0F172A',
];

/// Normaliza uma cor digitada para `#RRGGBB` maiúsculo, ou `null` se não é
/// hexadecimal de 6 dígitos (com ou sem o `#`).
String? normalizarHex(String digitado) {
  final limpo = digitado.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(limpo)) return null;
  return '#${limpo.toUpperCase()}';
}

Color corDoHex(String hex) {
  final limpo = hex.replaceFirst('#', '');
  final valor = int.tryParse(limpo, radix: 16);
  // Hex inválido cai no cinza padrão: uma cor errada não justifica derrubar a
  // tela inteira.
  if (valor == null || limpo.length != 6) return const Color(0xFF6B7280);
  return Color(0xFF000000 | valor);
}

Future<void> abrirCriacaoEtapa(
  BuildContext context,
  EtapasFluxoController controller,
) => _abrirFormulario(context: context, controller: controller);

Future<void> abrirEdicaoEtapa(
  BuildContext context,
  EtapaFluxo item,
  EtapasFluxoController controller,
) => _abrirFormulario(context: context, controller: controller, item: item);

Future<void> _abrirFormulario({
  required BuildContext context,
  required EtapasFluxoController controller,
  EtapaFluxo? item,
}) async {
  final nome = TextEditingController(text: item?.nome);
  final descricao = TextEditingController(text: item?.descricao);
  var tipo = item?.tipo ?? TipoEtapa.trabalho;
  var cor = normalizarHex(item?.cor ?? '') ?? coresDeEtapa.first;
  final hex = TextEditingController(text: cor);
  String? erro;
  var salvando = false;
  final editando = item != null;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome, descricao, hex],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: Text(editando ? 'Editar coluna' : 'Nova coluna'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    label: 'Nome',
                    hint: 'ex: Aguardando pagamento',
                    controller: nome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<TipoEtapa>(
                    initialValue: tipo,
                    decoration: const InputDecoration(
                      labelText: 'O que esta coluna significa',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in TipoEtapa.values)
                        DropdownMenuItem(value: t, child: Text(t.rotulo)),
                    ],
                    onChanged: (v) => setStateDialog(() => tipo = v ?? tipo),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // O tipo não é rótulo: é o que o roteamento lê para saber
                  // onde a conversa entra e quando o atendimento termina.
                  Text(
                    tipo.explicacao,
                    style: Theme.of(stateCtx).textTheme.bodySmall?.copyWith(
                      color: stateCtx.colors.fgMuted,
                    ),
                  ),
                  if (editando) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Descrição (opcional)',
                      hint: 'ex: Esperando o cliente enviar o comprovante',
                      controller: descricao,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text('Cor', style: Theme.of(stateCtx).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final opcao in coresDeEtapa)
                        _BolinhaDeCor(
                          hex: opcao,
                          selecionada: opcao == cor,
                          aoTocar: () => setStateDialog(() {
                            cor = opcao;
                            hex.text = opcao;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: corDoHex(cor),
                          shape: BoxShape.circle,
                          border: Border.all(color: stateCtx.colors.border),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('cor-hex'),
                          controller: hex,
                          maxLength: 7,
                          decoration: InputDecoration(
                            labelText: 'Cor personalizada (hexadecimal)',
                            hintText: '#315C28',
                            counterText: '',
                            border: const OutlineInputBorder(),
                            errorText: normalizarHex(hex.text) == null
                                ? 'Use 6 dígitos, ex.: #315C28'
                                : null,
                          ),
                          onChanged: (v) => setStateDialog(() {
                            final valida = normalizarHex(v);
                            if (valida != null) cor = valida;
                          }),
                        ),
                      ),
                    ],
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
                      if (nome.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o nome da coluna.',
                        );
                        return;
                      }
                      if (normalizarHex(hex.text) == null) {
                        setStateDialog(
                          () => erro =
                              'A cor precisa ter 6 dígitos hexadecimais, '
                              'ex.: #315C28.',
                        );
                        return;
                      }

                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });

                      final res = editando
                          ? await controller.atualizarEtapa(
                              id: item.id,
                              nome: nome.text.trim(),
                              descricao: descricao.text.trim(),
                              cor: cor,
                              tipo: tipo,
                            )
                          : await controller.criarEtapa(
                              nome: nome.text.trim(),
                              tipo: tipo,
                              cor: cor,
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

Future<void> abrirRemocaoEtapa(
  BuildContext context,
  EtapaFluxo item,
  EtapasFluxoController controller,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remover a coluna "${item.nome}"?'),
      content: const Text(
        'Ela é desativada e some do quadro. O histórico das conversas que '
        'passaram por ela continua no atendimento. Para apagá-la de vez, use '
        '"Excluir definitivamente".',
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
  final res = await controller.removerEtapa(item.id);

  messenger.showSnackBar(
    SnackBar(
      content: Text(switch (res) {
        Success() => 'Coluna removida.',
        // As recusas do servidor (coluna ocupada, última fila de entrada)
        // chegam aqui com o motivo escrito.
        Failure(:final error) => error.message,
      }),
    ),
  );
}

class _BolinhaDeCor extends StatelessWidget {
  final String hex;
  final bool selecionada;
  final VoidCallback aoTocar;

  const _BolinhaDeCor({
    required this.hex,
    required this.selecionada,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoTocar,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: corDoHex(hex),
          shape: BoxShape.circle,
          border: Border.all(
            color: selecionada
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selecionada
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
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
