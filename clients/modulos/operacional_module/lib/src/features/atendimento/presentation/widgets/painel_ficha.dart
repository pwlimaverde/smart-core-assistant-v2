import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/ficha.dart';
import '../controllers/ficha_controller.dart';

/// Cor a partir do hex do catálogo. Hex inválido cai no padrão em vez de
/// derrubar o painel — uma cor errada não justifica perder a ficha inteira.
Color corDaEtiqueta(String hex) {
  final limpo = hex.replaceFirst('#', '');
  final valor = int.tryParse(limpo, radix: 16);
  if (valor == null || limpo.length != 6) return const Color(0xFFA98F71);
  return Color(0xFF000000 | valor);
}

/// Ficha do atendimento, ao lado da conversa: etiquetas e anotações internas.
///
/// O histórico diz o que foi dito; a ficha diz o que se sabe. Por que a
/// conversa está parada, o que já foi tentado, e o que ela tem em comum com
/// outras — nada disso cabe numa mensagem, e sem lugar acaba na cabeça de quem
/// atendeu.
class PainelFicha extends StatelessWidget {
  final FichaController controller;

  const PainelFicha({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        child: BlocBuilder<FichaController, ViewState<FichaAtendimento>>(
          bloc: controller,
          builder: (context, state) => switch (state) {
            InitialState() ||
            LoadingState() => const Center(child: CircularProgressIndicator()),
            // A ficha falha sozinha: a conversa ao lado continua utilizável, e
            // a mensagem precisa dizer que o que caiu foi o painel.
            ErrorState(:final error) => AppErrorView(
              message: error.message,
              onRetry: () => controller.abrir(controller.atendimentoId),
            ),
            SuccessState(:final data) => _Conteudo(
              ficha: data,
              controller: controller,
            ),
          },
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  final FichaAtendimento ficha;
  final FichaController controller;

  const _Conteudo({required this.ficha, required this.controller});

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Etiquetas',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Nova etiqueta',
              onPressed: () => _abrirCriacaoEtiqueta(context, controller),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (ficha.aplicadas.isEmpty)
          Text(
            'Nenhuma etiqueta nesta conversa.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: muted),
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final etiqueta in ficha.aplicadas)
                _Chip(
                  etiqueta: etiqueta,
                  // Tirar a etiqueta é a ação de quem já a colou; oferecer o
                  // X direto evita um menu para desfazer um clique.
                  aoRemover: () => _alternar(
                    context,
                    controller,
                    etiqueta.id,
                    aplicar: false,
                  ),
                ),
            ],
          ),
        if (ficha.disponiveis.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Colar nesta conversa',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final etiqueta in ficha.disponiveis)
                ActionChip(
                  avatar: CircleAvatar(
                    radius: 6,
                    backgroundColor: corDaEtiqueta(etiqueta.cor),
                  ),
                  label: Text(etiqueta.nome),
                  onPressed: () => _alternar(
                    context,
                    controller,
                    etiqueta.id,
                    aplicar: true,
                  ),
                ),
            ],
          ),
        ],
        const Divider(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                'Anotações',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.note_add_outlined, size: 18),
              tooltip: 'Anotar',
              onPressed: () => _abrirNota(context, controller),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Internas: o contato nunca as vê.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (ficha.notas.isEmpty)
          Text(
            'Nada anotado ainda.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: muted),
          )
        else
          for (final nota in ficha.notas) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _quando(nota.criadoEm),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: muted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(nota.texto),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
      ],
    );
  }
}

/// Quando a nota foi escrita, em linguagem de quem lê.
String _quando(DateTime quando) {
  final minutos = DateTime.now().difference(quando).inMinutes;
  if (minutos < 1) return 'agora';
  if (minutos < 60) return 'há $minutos min';
  final horas = minutos ~/ 60;
  if (horas < 24) return 'há ${horas}h';
  final dias = horas ~/ 24;
  return dias == 1 ? 'ontem' : 'há $dias dias';
}

Future<void> _alternar(
  BuildContext context,
  FichaController controller,
  int etiquetaId, {
  required bool aplicar,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final erro = await controller.alternar(
    etiquetaId: etiquetaId,
    aplicar: aplicar,
  );
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
}

/// Cores oferecidas para etiqueta nova.
///
/// Lista fechada, como as colunas do quadro: a cor serve para distinguir de
/// relance, e uma paleta repetida entre tenants faz isso melhor que um
/// arco-íris escolhido a dedo.
const coresDeEtiqueta = <String>[
  '#a98f71',
  '#ef4444',
  '#f59e0b',
  '#10b981',
  '#3b82f6',
  '#8b5cf6',
];

Future<void> _abrirCriacaoEtiqueta(
  BuildContext context,
  FichaController controller,
) async {
  final nome = TextEditingController();
  var cor = coresDeEtiqueta.first;
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [nome],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Nova etiqueta'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Nome',
                  hint: 'ex: aguardando pagamento',
                  controller: nome,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final opcao in coresDeEtiqueta)
                      InkWell(
                        onTap: () => setStateDialog(() => cor = opcao),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: corDaEtiqueta(opcao),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: opcao == cor
                                  ? Theme.of(stateCtx).colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (erro case final msg?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    msg,
                    style: TextStyle(
                      color: Theme.of(stateCtx).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  salvando ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              label: 'Criar',
              expand: false,
              isLoading: salvando,
              onPressed: salvando
                  ? null
                  : () async {
                      if (nome.text.trim().isEmpty) {
                        setStateDialog(
                          () => erro = 'Informe o nome da etiqueta.',
                        );
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });
                      final falha = await controller.criarEtiqueta(
                        nome: nome.text.trim(),
                        cor: cor,
                      );
                      if (falha != null) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
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

Future<void> _abrirNota(
  BuildContext context,
  FichaController controller,
) async {
  final texto = TextEditingController();
  String? erro;
  var salvando = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => DialogoComCampos(
      campos: [texto],
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateCtx, setStateDialog) => AlertDialog(
          title: const Text('Anotar'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: texto,
                  maxLines: 6,
                  minLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'O que registrar',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    helperText: 'Só a equipe vê. O contato, nunca.',
                  ),
                ),
                if (erro case final msg?) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    msg,
                    style: TextStyle(
                      color: Theme.of(stateCtx).colorScheme.error,
                    ),
                  ),
                ],
              ],
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
                      if (texto.text.trim().isEmpty) {
                        setStateDialog(() => erro = 'Escreva a anotação.');
                        return;
                      }
                      final navigator = Navigator.of(dialogContext);
                      setStateDialog(() {
                        salvando = true;
                        erro = null;
                      });
                      final falha = await controller.anotar(texto.text.trim());
                      if (falha != null) {
                        if (stateCtx.mounted) {
                          setStateDialog(() {
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

class _Chip extends StatelessWidget {
  final Etiqueta etiqueta;
  final VoidCallback aoRemover;

  const _Chip({required this.etiqueta, required this.aoRemover});

  @override
  Widget build(BuildContext context) {
    final cor = corDaEtiqueta(etiqueta.cor);
    return Chip(
      avatar: CircleAvatar(radius: 6, backgroundColor: cor),
      label: Text(etiqueta.nome),
      backgroundColor: cor.withValues(alpha: 0.12),
      side: BorderSide(color: cor.withValues(alpha: 0.5)),
      onDeleted: aoRemover,
      deleteButtonTooltipMessage: 'Tirar desta conversa',
    );
  }
}
