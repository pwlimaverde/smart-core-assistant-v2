import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/evento_timeline.dart';
import '../../domain/model/ficha.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/ficha_controller.dart';
import 'dialogo_valor_campo.dart';

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

  /// Largura do painel. Ao lado da conversa larga são 320; como gaveta sobre
  /// o painel estreito do quadro, o que couber.
  final double largura;

  /// Quando vem, a ficha é uma gaveta: ganha título e botão de fechar, como o
  /// "Detalhes do Atendimento" da v1. Ao lado da conversa larga ela fica
  /// sempre à vista e não precisa disso.
  final VoidCallback? aoFechar;

  const PainelFicha({
    required this.controller,
    this.largura = 320,
    this.aoFechar,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final conteudo = BlocBuilder<FichaController, ViewState<FichaAtendimento>>(
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
    );
    final fechar = aoFechar;
    return SizedBox(
      width: largura,
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        elevation: fechar == null ? null : 8,
        child: fechar == null
            ? conteudo
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.xs,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detalhes do atendimento',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Fechar os detalhes (Esc)',
                          onPressed: fechar,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: conteudo),
                ],
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
        // D3 — o interruptor da IA vem primeiro, e não no fim da ficha: é o
        // estado mais consequente da conversa, e é o que alguém vem procurar
        // aqui quando o bot parou de responder só nesta thread.
        _BotDaConversa(ficha: ficha, controller: controller),
        const Divider(height: AppSpacing.xl),
        // N9 E13 — os campos que o tenant desenhou para o cartão. Antes das
        // etiquetas porque são o conteúdo da conversa (número do pedido, data
        // de retorno), enquanto etiqueta é classificação.
        if (ficha.campos.isNotEmpty) ...[
          Text(
            'Dados do atendimento',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final campo in ficha.campos)
            _LinhaDeCampo(campo: campo, controller: controller),
          const Divider(height: AppSpacing.xl),
        ],
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: muted),
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
        // P15 — o que a IA encontrou do contato nas conversas e não tem coluna
        // no cadastro. Recolhido e só de leitura: é pista, não cadastro.
        if (ficha.dadosDoContato.isNotEmpty) ...[
          const Divider(height: AppSpacing.xl),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_awesome, size: 16),
            title: Text(
              'Dados que a IA encontrou',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            children: [
              for (final entrada in ficha.dadosDoContato.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entrada.value),
                  subtitle: Text(entrada.key),
                ),
            ],
          ),
        ],
        const Divider(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: Text(
                'História',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.history, size: 18),
              tooltip: 'Ver a história do atendimento',
              onPressed: () =>
                  _abrirTimeline(context, controller.atendimentoId),
            ),
          ],
        ),
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          )
        else
          for (final nota in ficha.notas) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _quando(nota.criadoEm),
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: muted),
                        ),
                      ),
                      // P5 — nota escrita errada ficava para sempre.
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        tooltip: 'Excluir anotação',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _excluirNota(context, controller, nota.id),
                      ),
                    ],
                  ),
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

/// D3 — o interruptor da IA nesta conversa.
///
/// Assumir o atendimento desliga o bot automaticamente, e por muito tempo nada
/// devolvia o valor: a conversa que passou por um humano ficava sem IA para
/// sempre, sem tela para reverter. Este é o caminho de volta.
///
/// A tranca do `desatribuir` continua de pé no servidor — devolver o cartão
/// não religa sozinho. O que existe agora é uma ação deliberada.
class _BotDaConversa extends StatelessWidget {
  final FichaAtendimento ficha;
  final FichaController controller;

  const _BotDaConversa({required this.ficha, required this.controller});

  @override
  Widget build(BuildContext context) {
    final ligado = ficha.botPodeAtender;

    return Row(
      children: [
        Icon(
          ligado ? Icons.smart_toy_outlined : Icons.smart_toy,
          size: 18,
          color: ligado ? context.colors.fgMuted : context.colors.warning,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resposta automática',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                ligado
                    ? 'A IA responde nesta conversa.'
                    : 'A IA está calada nesta conversa.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ligado
                      ? context.colors.fgMuted
                      : context.colors.warning,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: ligado,
          onChanged: (v) => _definirBot(context, controller, v),
        ),
      ],
    );
  }
}

/// Sem diálogo de confirmação, ao contrário do interruptor da conexão.
///
/// Lá o desligamento cala um número inteiro e quem esbarrou no controle não
/// descobriria pelo silêncio. Aqui o efeito é de uma conversa só, está à vista
/// de quem a está lendo, e é reversível no mesmo clique — pedir confirmação
/// seria atrito numa ação que o atendente toma o tempo todo.
Future<void> _definirBot(
  BuildContext context,
  FichaController controller,
  bool habilitado,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final erro = await controller.definirBot(habilitado);
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
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
              onPressed: salvando
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
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
      // P14 — a etiqueta que a IA colocou se distingue da que uma pessoa pôs.
      // Tirá-la impede a IA de recolocar nesta conversa.
      label: etiqueta.aplicadaPelaIa
          ? Tooltip(
              message:
                  'Aplicada pela IA. Se tirar, ela não volta nesta conversa.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(etiqueta.nome),
                  const SizedBox(width: 4),
                  const Icon(Icons.auto_awesome, size: 12),
                ],
              ),
            )
          : Text(etiqueta.nome),
      backgroundColor: cor.withValues(alpha: 0.12),
      side: BorderSide(color: cor.withValues(alpha: 0.5)),
      onDeleted: aoRemover,
      deleteButtonTooltipMessage: 'Tirar desta conversa',
    );
  }
}

/// Um campo do cartão na ficha: valor, origem e o caminho para editar.
class _LinhaDeCampo extends StatelessWidget {
  final ValorCampo campo;
  final FichaController controller;

  const _LinhaDeCampo({required this.campo, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: () => abrirEdicaoDeValor(context, campo, controller),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          campo.nome,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.fgMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (campo.obrigatorio && !campo.preenchido) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.error_outline,
                          size: 13,
                          color: colors.warning,
                        ),
                      ],
                      // De onde veio o valor muda o quanto se confia nele: um
                      // número que a IA deduziu de "acho que foi o 12345"
                      // merece um olhar antes de virar decisão.
                      if (campo.veioDaIa && campo.preenchido) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Tooltip(
                          message:
                              'Preenchido pela IA '
                              '(confiança ${(campo.confianca * 100).round()}%)',
                          child: Icon(
                            Icons.auto_awesome,
                            size: 13,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    campo.preenchido ? _legivel(campo) : 'Não informado',
                    style: TextStyle(
                      fontWeight: campo.preenchido
                          ? FontWeight.w500
                          : FontWeight.normal,
                      color: campo.preenchido ? null : colors.fgMuted,
                      fontStyle: campo.preenchido
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 16, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }

  /// O valor como gente lê.
  ///
  /// O JSON cru serve à máquina: `"cartao"` com aspas, `true` em inglês, e o
  /// id de uma opção em vez do rótulo que a pessoa escolheu.
  String _legivel(ValorCampo c) {
    final bruto = c.valorJson;
    final semAspas =
        bruto.startsWith('"') && bruto.endsWith('"') && bruto.length >= 2
        ? bruto.substring(1, bruto.length - 1)
        : bruto;

    return switch (c.tipo) {
      'booleano' => semAspas == 'true' ? 'Sim' : 'Não',
      'lista' =>
        c.opcoes.where((o) => o.id == semAspas).map((o) => o.rotulo).firstOrNull
            // Opção que saiu do catálogo depois de preenchida: mostra o id, que
            // é o que está gravado, em vez de esconder o valor.
            ??
            semAspas,
      _ => semAspas,
    };
  }
}

/// P5 — confirma antes de apagar: anotação some para todo mundo.
Future<void> _excluirNota(
  BuildContext context,
  FichaController controller,
  int notaId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Excluir a anotação?'),
      content: const Text('Ela some para todos os atendentes.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogo).pop(true),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;
  final erro = await controller.removerNota(notaId);
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro.message)));
  }
}

/// P5 — a história do atendimento, do jeito que a v1 mostrava: aberto, movido,
/// anotado, etiquetado, encerrado.
Future<void> _abrirTimeline(BuildContext context, int atendimentoId) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: SizedBox(
        width: 560,
        height: 480,
        child: _Timeline(atendimentoId: atendimentoId),
      ),
    ),
  );
}

class _Timeline extends StatefulWidget {
  final int atendimentoId;

  const _Timeline({required this.atendimentoId});

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  late Future<ReturnSuccessOrError<List<EventoDaTimeline>, FichaError>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = inject<ListarTimelineUsecase>()(
      ListarTimelineParameters(atendimentoId: widget.atendimentoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.fgMuted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.history, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'História do atendimento',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              FutureBuilder<
                ReturnSuccessOrError<List<EventoDaTimeline>, FichaError>
              >(
                future: _futuro,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return switch (snapshot.data!) {
                    Failure(:final error) => AppErrorView(
                      message: error.message,
                    ),
                    Success(:final value) when value.isEmpty =>
                      const AppEmptyView(
                        icon: Icons.history,
                        title: 'Sem história ainda',
                        subtitle: 'Movimentos e anotações aparecem aqui.',
                      ),
                    Success(:final value) => ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: value.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final e = value[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_icone(e.tipo), size: 16, color: muted),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.descricao),
                                  Text(
                                    [
                                      _quando(e.quando),
                                      if (e.autor.isNotEmpty) e.autor,
                                      if (e.automatico) 'automático',
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  };
                },
              ),
        ),
      ],
    );
  }

  static IconData _icone(String tipo) => switch (tipo) {
    'aberto' => Icons.play_circle_outline,
    'movido' => Icons.swap_horiz,
    'nota' => Icons.sticky_note_2_outlined,
    'etiqueta' => Icons.label_outline,
    'avaliado' => Icons.star_outline,
    'encerrado' => Icons.flag_outlined,
    _ => Icons.circle_outlined,
  };
}
