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
import '../widgets/atendimento_no_quadro.dart';
import '../widgets/avatar_do_contato.dart';
import '../widgets/mini_barra_da_conversa.dart';
import 'chat_page.dart';
import '../escrita_no_quadro.dart';
import '../aviso_nativo/aviso_nativo.dart';

/// Payload carregado pelo drag de um cartão — id do atendimento e etapa de
/// origem (a coluna de onde saiu), consumido pela coluna de destino.
typedef _DragPayload = ({int atendimentoId, int etapaOrigemId});

/// O workspace de atendimento: o quadro, a conversa e as informações do
/// atendimento na mesma tela — o `workspace.html` do desenho.
///
/// Um clique no cartão abre a conversa e, à direita dela, o painel com tudo o
/// que se manipula no atendimento. Não há botão de detalhes no cartão: o
/// cartão É o caminho.
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

  /// A partir daqui o painel de informações fica ao lado da conversa, no
  /// modo dividido, sem esmagar o quadro. Abaixo, ele vira gaveta da conversa.
  static const _larguraComInformacoes = 1280.0;

  /// Conversa aberta no painel da direita. `null` = só o quadro.
  int? _conversaAberta;

  /// O modo de foco escolhido por último, lembrado enquanto o app está aberto:
  /// sair do quadro e voltar não deve desfazer a preferência de quem atende.
  static ModoDeFoco _modoLembrado = ModoDeFoco.dividido;

  late ModoDeFoco _modo = _modoLembrado;

  /// O painel de informações do atendimento aberto, à direita da conversa.
  final _detalhes = ValueNotifier<bool>(false);

  /// O último quadro carregado: durante um recarregamento o estado passa por
  /// "carregando", e o painel da conversa não deve perder o cartão nesse meio.
  KanbanViewModel? _ultimoQuadro;

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
    _definirModo(ModoDeFoco.quadro);
  }

  void _fechar() {
    _detalhes.value = false;
    setState(() => _conversaAberta = null);
  }

  KanbanViewModel? _quadroAtual() {
    final estado = inject<KanbanController>().state;
    if (estado is SuccessState<KanbanViewModel>) _ultimoQuadro = estado.data;
    return _ultimoQuadro;
  }

  /// O cartão da conversa aberta, se ele está no quadro (o filtro pode tê-lo
  /// escondido).
  AtendimentoResumo? _resumoDe(int atendimentoId) {
    final quadro = _quadroAtual();
    if (quadro == null) return null;
    for (final itens in quadro.porEtapa.values) {
      for (final a in itens) {
        if (a.id == atendimentoId) return a;
      }
    }
    return null;
  }

  /// O cartão aberto e as ações do quadro sobre ele, para a conversa e o
  /// painel de informações.
  AtendimentoNoQuadro? _noQuadro(int atendimentoId) {
    final resumo = _resumoDe(atendimentoId);
    final quadro = _ultimoQuadro;
    if (resumo == null || quadro == null) return null;
    final c = inject<KanbanController>();
    var etapa = '';
    for (final coluna in quadro.colunas) {
      if (coluna.id == resumo.etapaAtualId) etapa = coluna.nome;
    }
    return AtendimentoNoQuadro(
      resumo: resumo,
      etapaNome: etapa,
      fluxos: quadro.fluxos,
      definirStatus: (status) async => (await c.definirStatus(
        atendimentoId: atendimentoId,
        status: status,
      ))?.message,
      definirPrioridade: (prioridade) async => (await c.definirPrioridade(
        atendimentoId: atendimentoId,
        prioridade: prioridade,
      ))?.message,
      transferirParaFluxo: (fluxoId) async => (await c.transferirParaFluxo(
        atendimentoId: atendimentoId,
        fluxoId: fluxoId,
      )).$2?.message,
      assumir: (eu) async => (await c.atribuir(
        atendimentoId: atendimentoId,
        devolverParaFila: !eu,
      ))?.message,
      marcarRevisado: () async =>
          (await c.marcarRevisado(atendimentoId))?.message,
    );
  }

  /// Atalhos do workspace da v1: Alt+1/2/3 trocam o foco, `Esc` o reduz e `i`
  /// abre ou fecha as informações.
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

  /// Abre a conversa onde ela couber — e, com ela, as informações do
  /// atendimento à direita.
  ///
  /// Ao lado do quadro quando há largura: era assim na v1, e é o que permite
  /// atender sem perder de vista a fila. Numa janela estreita, tela cheia.
  void _abrir(int atendimentoId) {
    inject<KanbanController>().zerarNaoLidas(atendimentoId);
    if (MediaQuery.sizeOf(context).width >= _larguraParaOsDois) {
      _detalhes.value = true;
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
    final colors = context.colors;
    final largura = MediaQuery.sizeOf(context).width;
    final largo = largura >= _larguraParaOsDois;

    return Scaffold(
      backgroundColor: colors.bg,
      drawer: widget.drawer,
      appBar: AppBar(
        backgroundColor: colors.topbar,
        foregroundColor: colors.topbarFg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 56,
        titleSpacing: widget.drawer == null ? 16 : 0,
        title: BlocBuilder<KanbanController, ViewState<KanbanViewModel>>(
          bloc: controller,
          builder: (context, state) {
            final quadro = state is SuccessState<KanbanViewModel>
                ? state.data
                : _ultimoQuadro;
            return Row(
              children: [
                const _Migalha(),
                if (quadro != null && quadro.fluxos.length > 1) ...[
                  const SizedBox(width: 14),
                  _SeletorDeFluxo(quadro: quadro, controller: controller),
                ],
                if (largo) ...[
                  const SizedBox(width: 14),
                  _SeletorDeFoco(
                    modo: _modo,
                    comRotulos: largura >= 1360,
                    aoEscolher: _definirModo,
                  ),
                ],
                const SizedBox(width: 14),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: _CampoDeBusca(controller: controller),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          if (widget.buscarContatos != null && quadroPodeEscrever())
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
              tooltip: 'Iniciar atendimento',
              onPressed: () => _iniciarAtendimento(controller),
            ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 19),
            tooltip: 'Exportar o quadro (CSV)',
            onPressed: () => _exportar(controller),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 19),
            tooltip: 'Recarregar',
            onPressed: () => controller.carregar(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // O aviso fica FORA do BlocBuilder: ele avisa que não chega conversa, e
      // some justamente quando o quadro está carregando ou falhou — que é
      // quando mais se precisa dele.
      body: Column(
        children: [
          ?widget.aviso,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  BlocBuilder<KanbanController, ViewState<KanbanViewModel>>(
                    bloc: controller,
                    builder: (context, state) =>
                        _montar(context, constraints, controller, state),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _montar(
    BuildContext context,
    BoxConstraints constraints,
    KanbanController controller,
    ViewState<KanbanViewModel> state,
  ) {
    if (state is SuccessState<KanbanViewModel>) _ultimoQuadro = state.data;
    final aberta = _conversaAberta;
    final largo = constraints.maxWidth >= _larguraParaOsDois;
    final trilho = largo && _modo == ModoDeFoco.conversa;

    final quadro = switch (state) {
      InitialState() || LoadingState() when _ultimoQuadro == null =>
        const Center(child: CircularProgressIndicator()),
      ErrorState(:final error) => AppErrorView(
        message: error.message,
        onRetry: () => controller.carregar(),
      ),
      _ =>
        trilho
            ? _Trilho(
                viewModel: _ultimoQuadro!,
                abertoId: aberta,
                aoAbrir: _abrir,
              )
            : _Quadro(
                viewModel: _ultimoQuadro!,
                controller: controller,
                abertoId: aberta,
                aoAbrir: _abrir,
              ),
    };

    // A janela pode encolher com uma conversa aberta (alguém arrasta a borda,
    // ou vira o tablet). Aí o painel não cabe mais, e o quadro sozinho é
    // melhor que os dois espremidos.
    if (!largo) return quadro;

    if (aberta == null) {
      return switch (_modo) {
        ModoDeFoco.quadro => quadro,
        ModoDeFoco.dividido => Row(
          children: [
            Expanded(child: quadro),
            const SizedBox(width: larguraDaConversa, child: _SemConversa()),
          ],
        ),
        ModoDeFoco.conversa => Row(
          children: [
            SizedBox(width: 88, child: quadro),
            const Expanded(child: _SemConversa()),
          ],
        ),
      };
    }

    // `ValueKey` no id: trocar de atendimento tem de **recriar** o painel.
    // Sem ela o Flutter reaproveita o State, e o `initState` — que é onde o
    // stream abre — não roda de novo: a tela mudaria de título e continuaria
    // na conversa anterior.
    final painel = PainelDeConversa(
      key: ValueKey(aberta),
      atendimentoId: aberta,
      aoFechar: _fechar,
      detalhesAbertos: _detalhes,
      noQuadro: _noQuadro(aberta),
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
            right: 16,
            bottom: 16,
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
      // A conversa com a tela: o quadro vira a trilha de avatares.
      ModoDeFoco.conversa => Row(
        children: [
          SizedBox(width: 88, child: quadro),
          Expanded(child: painel),
        ],
      ),
      ModoDeFoco.dividido => Row(
        children: [
          // Clique no quadro fora de um cartão recolhe a conversa. O toque
          // num cartão é de quem está mais dentro e ganha a disputa — só o
          // fundo chega aqui.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _minimizar,
              child: quadro,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _detalhes,
            builder: (context, abertos, filho) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: abertos && constraints.maxWidth >= _larguraComInformacoes
                  ? larguraDaConversa + larguraDasInformacoes
                  : larguraDaConversa,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: context.colors.border)),
              ),
              child: filho,
            ),
            child: painel,
          ),
        ],
      ),
    };
  }
}

/// "← WORKSPACE" no canto do topo (`ws-topbar__crumb`).
class _Migalha extends StatelessWidget {
  const _Migalha();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'WORKSPACE',
      style: TextStyle(
        color: Color(0xFFA8A29E),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.3,
      ),
    );
  }
}

/// O quadro aberto, escolhido no topo (`ws-topbar__sel`).
class _SeletorDeFluxo extends StatelessWidget {
  final KanbanViewModel quadro;
  final KanbanController controller;

  const _SeletorDeFluxo({required this.quadro, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.md,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: quadro.fluxoId,
          isDense: true,
          dropdownColor: colors.topbar,
          iconEnabledColor: const Color(0xFFA8A29E),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          items: [
            for (final f in quadro.fluxos)
              DropdownMenuItem(value: f.id, child: Text(f.rotulo)),
          ],
          onChanged: (v) {
            if (v != null) controller.abrirQuadro(v);
          },
        ),
      ),
    );
  }
}

/// Kanban / Dividido / Atendimento (`ws-focus-seg`).
class _SeletorDeFoco extends StatelessWidget {
  final ModoDeFoco modo;
  final bool comRotulos;
  final ValueChanged<ModoDeFoco> aoEscolher;

  const _SeletorDeFoco({
    required this.modo,
    required this.comRotulos,
    required this.aoEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadius.md,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in ModoDeFoco.values)
            Tooltip(
              message: '${m.rotulo} (Alt+${m.index + 1})',
              child: InkWell(
                borderRadius: AppRadius.sm,
                onTap: () => aoEscolher(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: m == modo ? colors.accent : Colors.transparent,
                    borderRadius: AppRadius.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.icone,
                        size: 14,
                        color: m == modo
                            ? Colors.white
                            : const Color(0xFFA8A29E),
                      ),
                      if (comRotulos) ...[
                        const SizedBox(width: 5),
                        Text(
                          m.rotulo,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: m == modo
                                ? Colors.white
                                : const Color(0xFFA8A29E),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// P1 — a busca do topo (`ws-topbar__search`): nome, telefone ou assunto.
class _CampoDeBusca extends StatefulWidget {
  final KanbanController controller;

  const _CampoDeBusca({required this.controller});

  @override
  State<_CampoDeBusca> createState() => _CampoDeBuscaState();
}

class _CampoDeBuscaState extends State<_CampoDeBusca> {
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
    const apagado = Color(0xFFA8A29E);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _texto,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          prefixIcon: const Icon(Icons.search, size: 16, color: apagado),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          hintText: 'Buscar por nome, telefone ou assunto',
          hintStyle: const TextStyle(color: Color(0xFF78716C), fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: context.colors.accent),
          ),
          suffixIcon: _texto.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 14, color: apagado),
                  tooltip: 'Limpar busca',
                  onPressed: () {
                    _texto.clear();
                    setState(() {});
                    widget.controller.digitarBusca('');
                  },
                ),
        ),
        onChanged: (v) {
          // O setState é só pelo botão de limpar; a consulta em si é adiada
          // pelo debounce do controller.
          setState(() {});
          widget.controller.digitarBusca(v);
        },
      ),
    );
  }
}

/// O painel da conversa quando nenhuma está aberta (`ws-chat__empty`).
class _SemConversa extends StatelessWidget {
  const _SemConversa();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.forum_outlined, size: 30, color: colors.accent),
          ),
          const SizedBox(height: 18),
          Text(
            'Selecione um atendimento',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.fgStrong,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              'Clique em um cartão do quadro para abrir a conversa, enviar '
              'mensagens e gerenciar o atendimento por aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: colors.fgMuted,
              ),
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
  final int? abertoId;

  /// O que fazer quando alguém abre um atendimento — quem decide *onde* a
  /// conversa aparece é a página, que conhece a largura da janela.
  final void Function(int atendimentoId) aoAbrir;

  const _Quadro({
    required this.viewModel,
    required this.controller,
    required this.abertoId,
    required this.aoAbrir,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CabecalhoDoQuadro(viewModel: viewModel, controller: controller),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              for (final coluna in viewModel.colunas)
                _Coluna(
                  coluna: coluna,
                  itens:
                      viewModel.porEtapa[coluna.id] ??
                      const <AtendimentoResumo>[],
                  viewModel: viewModel,
                  controller: controller,
                  abertoId: abertoId,
                  aoAbrir: aoAbrir,
                ),
              // Conversas fora de qualquer coluna do quadro: chegaram antes do
              // fluxo existir, ou apontam para uma coluna já removida.
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
                  abertoId: abertoId,
                  aoAbrir: aoAbrir,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// O título do quadro, quantos atendimentos há nele e os filtros rápidos
/// (`ws-board__head`).
class _CabecalhoDoQuadro extends StatelessWidget {
  final KanbanViewModel viewModel;
  final KanbanController controller;

  const _CabecalhoDoQuadro({required this.viewModel, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = controller;
    var total = 0;
    for (final itens in viewModel.porEtapa.values) {
      total += itens.length;
    }
    String titulo = 'Atendimento';
    for (final f in viewModel.fluxos) {
      if (f.id == viewModel.fluxoId) titulo = f.nome;
    }
    final algumFiltro = c.somenteMeus || c.somenteNaoLidas || c.somenteRevisar;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.fgStrong,
                ),
              ),
              Text(
                total == 1 ? '1 atendimento' : '$total atendimentos',
                style: TextStyle(fontSize: 11, color: colors.fgMuted),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ChipDeFiltro(
                    rotulo: 'Todos',
                    ativo: !algumFiltro,
                    aoTocar: () => c.alternarFiltro(
                      meus: false,
                      naoLidas: false,
                      revisar: false,
                    ),
                  ),
                  _ChipDeFiltro(
                    rotulo: 'Minhas',
                    ativo: c.somenteMeus,
                    aoTocar: () => c.alternarFiltro(meus: !c.somenteMeus),
                  ),
                  _ChipDeFiltro(
                    rotulo: 'Não lidas',
                    ativo: c.somenteNaoLidas,
                    aoTocar: () =>
                        c.alternarFiltro(naoLidas: !c.somenteNaoLidas),
                  ),
                  // P16 — respostas da IA que ninguém conferiu.
                  _ChipDeFiltro(
                    rotulo: 'A revisar',
                    ativo: c.somenteRevisar,
                    aoTocar: () => c.alternarFiltro(revisar: !c.somenteRevisar),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipDeFiltro extends StatelessWidget {
  final String rotulo;
  final bool ativo;
  final VoidCallback aoTocar;

  const _ChipDeFiltro({
    required this.rotulo,
    required this.ativo,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: ativo ? colors.fgStrong : colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.pill,
          side: BorderSide(color: ativo ? colors.fgStrong : colors.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: ativo ? colors.card : colors.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma coluna do quadro (`ws-col`): bolinha na cor da etapa, título em caixa
/// alta, contagem e os cartões. É também onde o cartão arrastado cai.
class _Coluna extends StatelessWidget {
  final ColunaDoQuadro coluna;
  final List<AtendimentoResumo> itens;
  final KanbanViewModel viewModel;
  final KanbanController controller;
  final int? abertoId;
  final void Function(int atendimentoId) aoAbrir;

  const _Coluna({
    required this.coluna,
    required this.itens,
    required this.viewModel,
    required this.controller,
    required this.abertoId,
    required this.aoAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<_DragPayload>(
      onAcceptWithDetails: (detalhes) {
        final payload = detalhes.data;
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
      builder: (context, candidatos, _) {
        final destacado = candidatos.isNotEmpty;
        return Container(
          width: 280,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: destacado ? colors.accentSoft : colors.card,
            borderRadius: AppRadius.col,
            border: Border.all(
              color: destacado ? colors.accent : colors.border,
              width: destacado ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _corDaColuna(coluna.cor, colors.accent),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        coluna.nome.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: colors.fgStrong,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.chip,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        '${itens.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.fgMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: itens.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum atendimento',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.fgSubtle,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: itens.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final atendimento = itens[i];
                          return _Cartao(
                            key: ValueKey(atendimento.id),
                            atendimento: atendimento,
                            etapaId: coluna.id,
                            ativo: atendimento.id == abertoId,
                            arrastando:
                                viewModel.movendoAtendimentoId ==
                                atendimento.id,
                            aoAbrir: () => aoAbrir(atendimento.id),
                            aoPedirMenu: quadroPodeEscrever()
                                ? (posicao) => _abrirMenuDoCartao(
                                    context,
                                    posicao: posicao,
                                    atendimento: atendimento,
                                    controller: controller,
                                    viewModel: viewModel,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
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

Color _corDaColuna(String hex, Color padrao) {
  final limpo = hex.replaceFirst('#', '');
  final valor = int.tryParse(limpo, radix: 16);
  if (valor == null || limpo.length != 6) return padrao;
  return Color(0xFF000000 | valor);
}

/// O cartão (`ws-card`): um clique abre a conversa com as informações; o
/// botão direito abre o menu de ações rápidas; arrastar muda a etapa.
class _Cartao extends StatefulWidget {
  final AtendimentoResumo atendimento;
  final int etapaId;
  final bool ativo;
  final bool arrastando;
  final VoidCallback aoAbrir;
  final void Function(Offset posicao)? aoPedirMenu;

  const _Cartao({
    super.key,
    required this.atendimento,
    required this.etapaId,
    required this.ativo,
    required this.arrastando,
    required this.aoAbrir,
    required this.aoPedirMenu,
  });

  @override
  State<_Cartao> createState() => _CartaoState();
}

class _CartaoState extends State<_Cartao> {
  bool _sobre = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final superficie = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, _sobre ? -1 : 0, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: widget.ativo
              ? colors.accent
              : (_sobre ? colors.borderStrong : colors.border),
        ),
        boxShadow: [
          if (widget.ativo)
            BoxShadow(color: colors.accentRing, spreadRadius: 2)
          else if (_sobre)
            const BoxShadow(
              color: Color(0x14000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
        ],
      ),
      child: AtendimentoCardContent(atendimento: widget.atendimento),
    );

    final interativo = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _sobre = true),
      onExit: (_) => setState(() => _sobre = false),
      child: GestureDetector(
        onTap: widget.aoAbrir,
        onSecondaryTapDown: widget.aoPedirMenu == null
            ? null
            : (d) => widget.aoPedirMenu!(d.globalPosition),
        child: superficie,
      ),
    );

    return Opacity(
      opacity: widget.arrastando ? 0.5 : 1,
      child: Draggable<_DragPayload>(
        data: (
          atendimentoId: widget.atendimento.id,
          etapaOrigemId: widget.etapaId,
        ),
        feedback: Material(
          color: Colors.transparent,
          child: Transform.rotate(
            angle: 0.035,
            child: Container(
              width: 256,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: AppRadius.card,
                border: Border.all(color: colors.accent, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2E000000),
                    blurRadius: 25,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: AtendimentoCardContent(atendimento: widget.atendimento),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: superficie),
        child: interativo,
      ),
    );
  }
}

/// O menu do cartão no botão direito: dono, urgência, fluxo e estado — o que
/// o painel de informações também faz, a um clique de distância para quem
/// está varrendo a fila.
Future<void> _abrirMenuDoCartao(
  BuildContext context, {
  required Offset posicao,
  required AtendimentoResumo atendimento,
  required KanbanController controller,
  required KanbanViewModel viewModel,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final tela = Overlay.of(context).context.size ?? Size.zero;
  final escolha = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      posicao.dx,
      posicao.dy,
      tela.width - posicao.dx,
      tela.height - posicao.dy,
    ),
    items: [
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
      for (final (valor, rotulo) in prioridadesOferecidas)
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
  );
  if (escolha == null) return;
  final partes = escolha.split(':');
  final erro = switch (partes.first) {
    'dono' => (await controller.atribuir(
      atendimentoId: atendimento.id,
      devolverParaFila: partes[1] == 'fila',
    ))?.message,
    'prioridade' => (await controller.definirPrioridade(
      atendimentoId: atendimento.id,
      prioridade: partes[1],
    ))?.message,
    'revisado' => (await controller.marcarRevisado(atendimento.id))?.message,
    'fluxo' => (await controller.transferirParaFluxo(
      atendimentoId: atendimento.id,
      fluxoId: int.parse(partes[1]),
    )).$2?.message,
    _ => (await controller.definirStatus(
      atendimentoId: atendimento.id,
      status: partes[1],
    ))?.message,
  };
  if (erro != null) {
    messenger.showSnackBar(SnackBar(content: Text(erro)));
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

/// O quadro recolhido em trilha de avatares, no modo Atendimento (o
/// `data-focus="chat"` do desenho): a fila continua à vista e a um clique,
/// enquanto a conversa usa a tela.
class _Trilho extends StatelessWidget {
  final KanbanViewModel viewModel;
  final int? abertoId;
  final void Function(int atendimentoId) aoAbrir;

  const _Trilho({
    required this.viewModel,
    required this.abertoId,
    required this.aoAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grupos = <(ColunaDoQuadro, List<AtendimentoResumo>)>[
      for (final c in viewModel.colunas)
        (c, viewModel.porEtapa[c.id] ?? const <AtendimentoResumo>[]),
    ];
    return Container(
      color: colors.bg,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final (coluna, itens) in grupos) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _corDaColuna(coluna.cor, colors.accent),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: coluna.nome,
                    child: Text(
                      '${itens.length}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: colors.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final a in itens)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Tooltip(
                  message: a.nomeParaExibir,
                  waitDuration: const Duration(milliseconds: 400),
                  child: InkWell(
                    borderRadius: AppRadius.card,
                    onTap: () => aoAbrir(a.id),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: AppRadius.card,
                        border: Border.all(
                          color: a.id == abertoId
                              ? colors.accent
                              : colors.border,
                        ),
                        boxShadow: [
                          if (a.id == abertoId)
                            BoxShadow(
                              color: colors.accentRing,
                              spreadRadius: 2,
                            ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          AvatarDoContato(
                            nome: a.nomeParaExibir,
                            fotoUrl: a.contatoFotoUrl,
                            raio: 18,
                          ),
                          if (a.naoLidas > 0)
                            Positioned(
                              top: -6,
                              right: -2,
                              child: BadgeDeNaoLidas(
                                quantidade: a.naoLidas,
                                compacto: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
