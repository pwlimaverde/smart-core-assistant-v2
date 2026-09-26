import 'dart:async';

import 'package:design_system_module/design_system_module.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/presentation_module.dart';

import '../widgets/dialogo_iniciar_atendimento.dart';
import '../../domain/model/contato_para_atendimento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/quadro.dart';
import '../controllers/kanban_controller.dart';
import '../controllers/kanban_state.dart';
import '../widgets/atendimento_card_content.dart';
import '../widgets/mini_barra_da_conversa.dart';
import 'chat_page.dart';
import '../escrita_no_quadro.dart';
import '../aviso_nativo/aviso_nativo.dart';

/// Payload carregado pelo drag de um [KanbanCard] — id do atendimento e etapa
/// de origem (a coluna de onde saiu), consumido pela coluna de destino.
typedef _DragPayload = ({int atendimentoId, int etapaOrigemId});

/// Quadro de atendimento.
///
/// As colunas vêm do **fluxo cadastrado**, não dos atendimentos existentes.
/// Derivá-las dos dados fazia uma coluna vazia sumir — não havia para onde
/// arrastar — e um quadro sem conversa nenhuma abria em branco, como se
/// estivesse quebrado; era o que uma conta nova via.
///
/// O filtro de fluxo (`flow_permissions`) é 100% server-side: esta tela só
/// renderiza o que o backend devolve e reage ao erro se o movimento for negado.
class KanbanPage extends StatefulWidget {
  /// Menu lateral, injetado pelo app que monta a rota.
  ///
  /// O quadro é a primeira tela depois do login, e sem o menu não havia como
  /// chegar a nenhuma configuração — a pessoa ficava presa numa fila vazia. O
  /// menu mora no app do tenant; este módulo não o conhece, então ele entra por
  /// aqui em vez de virar uma dependência ao contrário.
  final Widget? drawer;

  /// Faixa de aviso acima do quadro, injetada pelo app do tenant.
  ///
  /// Existe para uma coisa em especial: WhatsApp fora do ar. O quadro parece
  /// normal quando a conexão cai — só não chega conversa nenhuma, e quem está
  /// atendendo demora a entender por quê. O aviso mora aqui, na primeira tela,
  /// e não numa página de configuração que ninguém abre. Como conexão é assunto
  /// do `tenant_module`, entra por injeção, igual ao menu.
  final Widget? aviso;

  /// Como procurar clientes para abrir uma conversa (C3).
  ///
  /// Entra por parâmetro pelo mesmo motivo do menu e do aviso: o cadastro de
  /// contatos é do `tenant_module`, e este módulo não o conhece. Quando não
  /// vem, o botão "Iniciar atendimento" simplesmente não aparece — um app que
  /// não sabe listar clientes não deve oferecer o caminho.
  final BuscarContatos? buscarContatos;

  const KanbanPage({this.drawer, this.aviso, this.buscarContatos, super.key});

  /// Volta ao modo de foco padrão — os testes não podem herdar o modo um do
  /// outro, e ele é lembrado enquanto o app está aberto.
  @visibleForTesting
  static void reiniciarModoDeFoco() =>
      _KanbanPageState._modoLembrado = ModoDeFoco.dividido;

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  /// Largura a partir da qual a conversa cabe ao lado do quadro.
  ///
  /// Abaixo disso ela vira tela cheia: espremer as duas deixaria o quadro
  /// ilegível e a conversa também, que é o pior dos dois mundos.
  static const _larguraParaOsDois = 1100.0;

  /// Conversa aberta no painel da direita. `null` = só o quadro.
  int? _conversaAberta;

  /// O modo de foco escolhido por último, lembrado enquanto o app está aberto:
  /// sair do quadro e voltar não deve desfazer a preferência de quem atende.
  static ModoDeFoco _modoLembrado = ModoDeFoco.dividido;

  late ModoDeFoco _modo = _modoLembrado;

  /// Os detalhes (a ficha) do atendimento aberto, como gaveta do painel.
  final _detalhes = ValueNotifier<bool>(false);

  /// B5 — avisos de conversa atribuída a quem está logado.
  StreamSubscription<AtribuicaoRecebida>? _atribuicoes;

  @override
  void initState() {
    super.initState();
    final controller = inject<KanbanController>();
    controller.carregar();
    _atribuicoes = controller.atribuicoes.listen(_avisarAtribuicao);
    HardwareKeyboard.instance.addHandler(_teclas);
    // P16 — o clique no aviso do Windows abre a conversa.
    unawaited(
      AvisoNativo.iniciar(
        aoClicar: (id) {
          if (mounted) _abrir(id);
        },
      ),
    );
  }

  @override
  void dispose() {
    _atribuicoes?.cancel();
    HardwareKeyboard.instance.removeHandler(_teclas);
    _detalhes.dispose();
    super.dispose();
  }

  void _definirModo(ModoDeFoco modo) {
    _modoLembrado = modo;
    setState(() => _modo = modo);
  }

  /// Clique fora da conversa: ela recolhe para a mini-barra e devolve a
  /// largura ao quadro, como no workspace da v1.
  void _minimizar() {
    if (_conversaAberta == null || _modo == ModoDeFoco.quadro) return;
    _detalhes.value = false;
    _definirModo(ModoDeFoco.quadro);
  }

  void _fechar() {
    _detalhes.value = false;
    setState(() => _conversaAberta = null);
  }

  /// O cartão da conversa aberta, se ele está no quadro (o filtro pode tê-lo
  /// escondido).
  AtendimentoResumo? _resumoDe(int atendimentoId) {
    final estado = inject<KanbanController>().state;
    if (estado is! SuccessState<KanbanViewModel>) return null;
    for (final itens in estado.data.porEtapa.values) {
      for (final a in itens) {
        if (a.id == atendimentoId) return a;
      }
    }
    return null;
  }

  /// Atalhos do workspace da v1: Alt+1/2/3 trocam o foco, `Esc` o reduz e `i`
  /// abre ou fecha os detalhes.
  ///
  /// Handler do teclado inteiro, e não um `Focus` na árvore: depois de clicar
  /// num cartão o foco não fica em lugar nenhum desta tela, e o atalho tem de
  /// funcionar assim mesmo.
  bool _teclas(KeyEvent evento) {
    if (evento is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (MediaQuery.sizeOf(context).width < _larguraParaOsDois) return false;
    final tecla = evento.logicalKey;
    final teclado = HardwareKeyboard.instance;

    if (teclado.isAltPressed) {
      final modo = switch (tecla) {
        LogicalKeyboardKey.digit1 => ModoDeFoco.quadro,
        LogicalKeyboardKey.digit2 => ModoDeFoco.dividido,
        LogicalKeyboardKey.digit3 => ModoDeFoco.conversa,
        _ => null,
      };
      if (modo == null) return false;
      _definirModo(modo);
      return true;
    }

    if (tecla == LogicalKeyboardKey.escape) {
      if (_detalhes.value) {
        _detalhes.value = false;
        return true;
      }
      if (_conversaAberta == null) return false;
      if (_modo == ModoDeFoco.conversa) {
        _definirModo(ModoDeFoco.dividido);
        return true;
      }
      if (_modo == ModoDeFoco.dividido) {
        _minimizar();
        return true;
      }
      return false;
    }

    // `i` só vale fora de campo de texto: digitando, é a letra.
    if (tecla == LogicalKeyboardKey.keyI &&
        _conversaAberta != null &&
        !teclado.isControlPressed &&
        !teclado.isMetaPressed &&
        !_digitando()) {
      _detalhes.value = !_detalhes.value;
      if (_detalhes.value && _modo == ModoDeFoco.quadro) {
        _definirModo(ModoDeFoco.dividido);
      }
      return true;
    }
    return false;
  }

  static bool _digitando() {
    final contexto = FocusManager.instance.primaryFocus?.context;
    if (contexto == null) return false;
    return contexto.widget is EditableText ||
        contexto.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// A conversa já apareceu no quadro (o evento também o recarrega); o aviso
  /// existe porque aparecer num quadro cheio não é o mesmo que ser notado. O
  /// "Abrir" leva direto a ela.
  void _avisarAtribuicao(AtribuicaoRecebida atribuicao) {
    if (!mounted) return;
    final onde = atribuicao.fluxo.isEmpty ? '' : ' em ${atribuicao.fluxo}';
    // P16 — com a janela fora de foco, o aviso do quadro não é visto: vai
    // também para o Windows.
    final estado = WidgetsBinding.instance.lifecycleState;
    if (estado != null && estado != AppLifecycleState.resumed) {
      unawaited(
        AvisoNativo.mostrar(
          atendimentoId: atribuicao.atendimentoId,
          titulo: 'Conversa atribuída a você',
          corpo: 'Uma conversa$onde está com você agora.',
        ),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uma conversa$onde foi atribuída a você.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () => _abrir(atribuicao.atendimentoId),
        ),
      ),
    );
  }

  /// C3 — abre a conversa com um cliente que ainda não escreveu.
  ///
  /// Precisa do quadro carregado: sem fluxo e sem colunas não há onde a
  /// conversa começar, e um atendimento sem etapa não aparece em coluna
  /// nenhuma.
  Future<void> _iniciarAtendimento(KanbanController controller) async {
    final estado = controller.state;
    if (estado is! SuccessState<KanbanViewModel>) return;
    final quadro = estado.data;
    if (quadro.colunas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Crie um fluxo com pelo menos uma coluna antes de abrir '
            'atendimentos.',
          ),
        ),
      );
      return;
    }

    final id = await mostrarDialogoIniciarAtendimento(
      context,
      quadro: quadro,
      buscarContatos: widget.buscarContatos!,
    );
    if (id == null || !mounted) return;

    // Recarrega antes de abrir: o cartão novo precisa existir no quadro, senão
    // fechar a conversa devolveria a um quadro que não a mostra.
    await controller.carregar();
    if (mounted) _abrir(id);
  }

  /// Abre a conversa onde ela couber.
  ///
  /// Ao lado do quadro quando há largura: era assim na v1, e é o que permite
  /// atender sem perder de vista a fila. Numa janela estreita, tela cheia.
  ///
  /// `detalhes` abre junto a ficha do atendimento (o botão de detalhes do
  /// cartão): é por ela que se veem e editam os campos personalizados.
  void _abrir(int atendimentoId, {bool detalhes = false}) {
    inject<KanbanController>().zerarNaoLidas(atendimentoId);
    if (MediaQuery.sizeOf(context).width >= _larguraParaOsDois) {
      _detalhes.value = detalhes;
      setState(() {
        _conversaAberta = atendimentoId;
        // Abrir a partir do quadro minimizado expande: quem clicou no cartão
        // quer ver a conversa, não a mini-barra.
        if (_modo == ModoDeFoco.quadro) {
          _modo = ModoDeFoco.dividido;
          _modoLembrado = _modo;
        }
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(atendimentoId: atendimentoId)),
    );
  }

  /// P4 — baixa o quadro em CSV, no mesmo recorte que está na tela.
  ///
  /// O arquivo é gravado onde a pessoa escolher: exportação com nome e
  /// telefone de cliente não deve cair numa pasta qualquer sem ela saber.
  Future<void> _exportar(KanbanController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    final (csv, erro) = await controller.exportar();
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
      return;
    }
    if (csv == null) return;
    final hoje = DateTime.now();
    final nome =
        'quadro_${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-'
        '${hoje.day.toString().padLeft(2, '0')}.csv';
    final destino = await FilePicker.saveFile(
      dialogTitle: 'Salvar o quadro',
      fileName: nome,
      bytes: Uint8List.fromList(csv),
    );
    if (destino == null || !mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Quadro exportado para $destino')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = inject<KanbanController>();

    return AppScaffold(
      title: 'Atendimento',
      drawer: widget.drawer,
      actions: [
        if (MediaQuery.sizeOf(context).width >= _larguraParaOsDois)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: SegmentedButton<ModoDeFoco>(
              showSelectedIcon: false,
              segments: [
                for (final modo in ModoDeFoco.values)
                  ButtonSegment(
                    value: modo,
                    icon: Icon(modo.icone, size: 16),
                    label: Text(modo.rotulo),
                    tooltip: '${modo.rotulo} (Alt+${modo.index + 1})',
                  ),
              ],
              selected: {_modo},
              onSelectionChanged: (s) => _definirModo(s.first),
            ),
          ),
        if (widget.buscarContatos != null && quadroPodeEscrever())
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Iniciar atendimento',
            onPressed: () => _iniciarAtendimento(controller),
          ),
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Exportar o quadro (CSV)',
          onPressed: () => _exportar(controller),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Recarregar',
          onPressed: () => controller.carregar(),
        ),
      ],
      // O aviso fica FORA do BlocBuilder: ele avisa que não chega conversa, e
      // some justamente quando o quadro está carregando ou falhou — que é
      // quando mais se precisa dele.
      body: Column(
        children: [
          if (widget.aviso != null) widget.aviso!,
          _BarraDeFiltros(controller: controller),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final quadro =
                    BlocBuilder<KanbanController, ViewState<KanbanViewModel>>(
                      bloc: controller,
                      builder: (context, state) {
                        return switch (state) {
                          InitialState() || LoadingState() => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          ErrorState(:final error) => AppErrorView(
                            message: error.message,
                            onRetry: () => controller.carregar(),
                          ),
                          SuccessState(:final data) => _Quadro(
                            viewModel: data,
                            controller: controller,
                            aoAbrir: _abrir,
                            aoDetalhar: (id) => _abrir(id, detalhes: true),
                          ),
                        };
                      },
                    );

                final aberta = _conversaAberta;
                // A janela pode encolher com uma conversa aberta (alguém
                // arrasta a borda, ou vira o tablet). Aí o painel não cabe
                // mais, e o quadro sozinho é melhor que os dois espremidos.
                if (aberta == null ||
                    constraints.maxWidth < _larguraParaOsDois) {
                  return quadro;
                }

                // `ValueKey` no id: trocar de atendimento tem de **recriar** o
                // painel. Sem ela o Flutter reaproveita o State, e o
                // `initState` — que é onde o stream abre — não roda de novo: a
                // tela mudaria de título e continuaria na conversa anterior.
                final painel = PainelDeConversa(
                  key: ValueKey(aberta),
                  atendimentoId: aberta,
                  aoFechar: _fechar,
                  detalhesAbertos: _detalhes,
                  aoMinimizar: () => _definirModo(ModoDeFoco.quadro),
                  aoExpandir: _modo == ModoDeFoco.conversa
                      ? null
                      : () => _definirModo(ModoDeFoco.conversa),
                );

                return switch (_modo) {
                  // Só o quadro, com a conversa recolhida no canto.
                  ModoDeFoco.quadro => Stack(
                    children: [
                      Positioned.fill(child: quadro),
                      Positioned(
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: MiniBarraDaConversa(
                          atendimentoId: aberta,
                          atendimento: _resumoDe(aberta),
                          aoAbrir: () => _definirModo(ModoDeFoco.dividido),
                          aoVerDetalhes: () {
                            _detalhes.value = true;
                            _definirModo(ModoDeFoco.dividido);
                          },
                          aoFechar: _fechar,
                        ),
                      ),
                    ],
                  ),
                  // A conversa com a tela inteira: a ficha fica ao lado dela.
                  ModoDeFoco.conversa => painel,
                  ModoDeFoco.dividido => Row(
                    children: [
                      // Clique no quadro fora de um cartão recolhe a conversa.
                      // O toque num cartão (ou no menu dele) é de quem está
                      // mais dentro e ganha a disputa — só o fundo chega aqui.
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _minimizar,
                          child: quadro,
                        ),
                      ),
                      Container(
                        width: 460,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: context.colors.border),
                          ),
                        ),
                        child: painel,
                      ),
                    ],
                  ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Quadro extends StatelessWidget {
  final KanbanViewModel viewModel;
  final KanbanController controller;

  /// O que fazer quando alguém abre um atendimento — quem decide *onde* a
  /// conversa aparece é a página, que conhece a largura da janela.
  final void Function(int atendimentoId) aoAbrir;

  /// O botão de detalhes do cartão: abre a conversa já com a ficha à vista.
  final void Function(int atendimentoId) aoDetalhar;

  const _Quadro({
    required this.viewModel,
    required this.controller,
    required this.aoAbrir,
    required this.aoDetalhar,
  });

  @override
  Widget build(BuildContext context) {
    // Conta sem fluxo nenhum: o convite é configurar, não "aguarde chegar
    // conversa" — sem quadro, nada chega a lugar nenhum.
    if (!viewModel.temQuadro) {
      return const AppEmptyView(
        icon: Icons.account_tree_outlined,
        title: 'Nenhum quadro configurado',
        subtitle:
            'Crie um fluxo de atendimento em "Fluxos de atendimento" '
            'para que as conversas tenham por onde andar.',
      );
    }

    final soltas = viewModel.semColuna;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewModel.fluxos.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                DropdownButton<int>(
                  value: viewModel.fluxoId,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final f in viewModel.fluxos)
                      DropdownMenuItem(value: f.id, child: Text(f.rotulo)),
                  ],
                  onChanged: (v) {
                    if (v != null) controller.abrirQuadro(v);
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final coluna in viewModel.colunas)
                    _Coluna(
                      coluna: coluna,
                      itens:
                          viewModel.porEtapa[coluna.id] ??
                          const <AtendimentoResumo>[],
                      viewModel: viewModel,
                      controller: controller,
                      aoAbrir: aoAbrir,
                      aoDetalhar: aoDetalhar,
                    ),
                  // Conversas fora de qualquer coluna do quadro: chegaram antes
                  // do fluxo existir, ou apontam para uma coluna já removida.
                  // Escondê-las faria sumir atendimento de verdade.
                  if (soltas.isNotEmpty)
                    _Coluna(
                      coluna: const ColunaDoQuadro(
                        id: KanbanViewModel.semEtapa,
                        nome: 'Sem coluna',
                        cor: '#F59E0B',
                        ordem: 9999,
                        tipo: 'fila',
                      ),
                      itens: soltas,
                      viewModel: viewModel,
                      controller: controller,
                      aoAbrir: aoAbrir,
                      aoDetalhar: aoDetalhar,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Coluna extends StatelessWidget {
  final ColunaDoQuadro coluna;
  final List<AtendimentoResumo> itens;
  final KanbanViewModel viewModel;
  final KanbanController controller;
  final void Function(int atendimentoId) aoAbrir;
  final void Function(int atendimentoId) aoDetalhar;

  const _Coluna({
    required this.coluna,
    required this.itens,
    required this.viewModel,
    required this.controller,
    required this.aoAbrir,
    required this.aoDetalhar,
  });

  @override
  Widget build(BuildContext context) {
    return KanbanDropColumn<_DragPayload>(
      title: coluna.nome,
      itemCount: itens.length,
      onAccept: (payload) {
        if (payload.etapaOrigemId == coluna.id) return;
        // P16 — quem só lê arrasta e o cartão volta: nada a enviar ao servidor.
        if (!quadroPodeEscrever()) return;
        _moverComFeedback(
          context,
          atendimentoId: payload.atendimentoId,
          etapaOrigemId: payload.etapaOrigemId,
          etapaDestinoId: coluna.id,
        );
      },
      children: [
        for (final atendimento in itens)
          KanbanCard<_DragPayload>(
            key: ValueKey(atendimento.id),
            data: (atendimentoId: atendimento.id, etapaOrigemId: coluna.id),
            isDragging: viewModel.movendoAtendimentoId == atendimento.id,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => aoAbrir(atendimento.id),
                    child: AtendimentoCardContent(atendimento: atendimento),
                  ),
                ),
                // Os detalhes do cartão (campos, etiquetas, notas, histórico),
                // como o botão de detalhes do cartão da v1.
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 18),
                  tooltip: 'Detalhes do atendimento',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => aoDetalhar(atendimento.id),
                ),
                // O arrasto continua sendo o caminho principal; este menu
                // existe para o quadro que não tem coluna daquele tipo — sem
                // ele, não haveria como marcar uma conversa como pendente num
                // quadro de três colunas.
                if (quadroPodeEscrever())
                  _MenuDoCartao(
                    atendimento: atendimento,
                    controller: controller,
                    viewModel: viewModel,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _moverComFeedback(
    BuildContext context, {
    required int atendimentoId,
    required int etapaOrigemId,
    required int etapaDestinoId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await controller.moverCard(
      atendimentoId: atendimentoId,
      etapaOrigemId: etapaOrigemId,
      etapaDestinoId: etapaDestinoId,
    );
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

/// Os estados que uma conversa pode assumir pela mão do atendente.
///
/// `arquivado` fica de fora: é decisão de curadoria do histórico, não do
/// atendimento em si, e oferecê-la aqui convidaria a sumir com conversa viva.
const _estadosOferecidos = <(String, String)>[
  ('em_atendimento', 'Assumir'),
  ('pendencia', 'Marcar como pendente'),
  ('fila', 'Devolver à fila'),
  ('resolvido', 'Resolver'),
  ('cancelado', 'Cancelar atendimento'),
];

/// P4 — as prioridades que o cartão aceita, na ordem em que fazem sentido
/// para quem olha a fila.
const _prioridadesOferecidas = <(String, String)>[
  ('urgente', 'Urgente'),
  ('alta', 'Alta'),
  ('normal', 'Normal'),
  ('baixa', 'Baixa'),
];

/// O menu do cartão: dono, urgência, fluxo e estado.
///
/// Um menu só, e não quatro botões: o cartão é pequeno, e cada ação dessas é
/// ocasional — o caminho do dia a dia continua sendo arrastar.
class _MenuDoCartao extends StatelessWidget {
  final AtendimentoResumo atendimento;
  final KanbanController controller;
  final KanbanViewModel viewModel;

  const _MenuDoCartao({
    required this.atendimento,
    required this.controller,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Ações da conversa',
      itemBuilder: (_) => [
        if (atendimento.revisaoPendente) ...[
          const PopupMenuItem(
            value: 'revisado:ok',
            child: Text('Marcar a resposta da IA como revisada'),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: 'dono:eu', child: Text('Atribuir a mim')),
        if (atendimento.atendenteHumanoId != null)
          const PopupMenuItem(
            value: 'dono:fila',
            child: Text('Devolver para a fila'),
          ),
        const PopupMenuDivider(),
        for (final (valor, rotulo) in _prioridadesOferecidas)
          if (valor != atendimento.prioridade)
            PopupMenuItem(
              value: 'prioridade:$valor',
              child: Text('Prioridade: $rotulo'),
            ),
        // Transferir de fluxo só aparece quando há para onde transferir.
        if (viewModel.fluxos.length > 1) ...[
          const PopupMenuDivider(),
          for (final fluxo in viewModel.fluxos)
            if (fluxo.id != atendimento.fluxoAtendimentoId)
              PopupMenuItem(
                value: 'fluxo:${fluxo.id}',
                child: Text('Transferir para ${fluxo.rotulo}'),
              ),
        ],
        const PopupMenuDivider(),
        for (final (status, rotulo) in _estadosOferecidos)
          if (status != atendimento.status)
            PopupMenuItem(value: 'status:$status', child: Text(rotulo)),
      ],
      onSelected: (escolha) => _executar(context, escolha),
    );
  }

  Future<void> _executar(BuildContext context, String escolha) async {
    final messenger = ScaffoldMessenger.of(context);
    final partes = escolha.split(':');
    final erro = switch (partes.first) {
      'dono' => await controller.atribuir(
        atendimentoId: atendimento.id,
        devolverParaFila: partes[1] == 'fila',
      ),
      'prioridade' => await controller.definirPrioridade(
        atendimentoId: atendimento.id,
        prioridade: partes[1],
      ),
      'revisado' => await controller.marcarRevisado(atendimento.id),
      'fluxo' => (await controller.transferirParaFluxo(
        atendimentoId: atendimento.id,
        fluxoId: int.parse(partes[1]),
      )).$2,
      _ => await controller.definirStatus(
        atendimentoId: atendimento.id,
        status: partes[1],
      ),
    };
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

/// P1 — o recorte da lista, como na v1: buscar por nome, telefone ou assunto,
/// e combinar com "minhas" e "não lidas".
class _BarraDeFiltros extends StatefulWidget {
  final KanbanController controller;

  const _BarraDeFiltros({required this.controller});

  @override
  State<_BarraDeFiltros> createState() => _BarraDeFiltrosState();
}

class _BarraDeFiltrosState extends State<_BarraDeFiltros> {
  late final TextEditingController _texto = TextEditingController(
    text: widget.controller.busca,
  );

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _texto,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar por nome, telefone ou assunto',
                border: const OutlineInputBorder(),
                suffixIcon: _texto.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Limpar busca',
                        onPressed: () {
                          _texto.clear();
                          setState(() {});
                          c.digitarBusca('');
                        },
                      ),
              ),
              onChanged: (v) {
                // O setState é só pelo botão de limpar; a consulta em si é
                // adiada pelo debounce do controller.
                setState(() {});
                c.digitarBusca(v);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilterChip(
            label: const Text('Minhas'),
            selected: c.somenteMeus,
            onSelected: (v) async {
              await c.alternarFiltro(meus: v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: AppSpacing.xs),
          FilterChip(
            label: const Text('Não lidas'),
            selected: c.somenteNaoLidas,
            onSelected: (v) async {
              await c.alternarFiltro(naoLidas: v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: AppSpacing.xs),
          // P16 — respostas da IA que ninguém conferiu.
          FilterChip(
            label: const Text('A revisar'),
            selected: c.somenteRevisar,
            onSelected: (v) async {
              await c.alternarFiltro(revisar: v);
              if (mounted) setState(() {});
            },
          ),
          if (c.temFiltro)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Limpar filtros',
              onPressed: () async {
                _texto.clear();
                await c.limparFiltros();
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }
}
