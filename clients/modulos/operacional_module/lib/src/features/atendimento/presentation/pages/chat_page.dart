import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dependencies_module/dependencies_module.dart' show GetIt;
import 'package:design_system_module/design_system_module.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:path_provider/path_provider.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:record/record.dart';

import '../../domain/model/contato_da_conversa.dart';
import '../../domain/model/ficha.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/chat_controller.dart';
import '../controllers/chat_state.dart';
import '../controllers/ficha_controller.dart';
import '../widgets/atendimento_no_quadro.dart';
import '../widgets/avatar_do_contato.dart';
import '../widgets/chat_connection_badge.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/painel_ficha.dart';
import '../escrita_no_quadro.dart';

/// Largura da conversa ao lado do quadro (`--ws-chat-w`).
const larguraDaConversa = 460.0;

/// Largura do painel de informações (`--ws-info-w`).
const larguraDasInformacoes = 320.0;

/// A conversa de um atendimento, **sem moldura de tela**.
///
/// Separada da [ChatPage] para poder viver em dois lugares: como painel ao
/// lado do quadro, em janela larga, e como página inteira no celular. Era só
/// página, e por isso ler uma conversa custava sair do quadro e voltar — o
/// operador perdia de vista a fila que estava trabalhando.
///
/// Histórico + stream realtime + envio. Consome
/// `AtendimentoDataSource.streamAtendimentos` (via [ChatController]) com
/// reconexão automática (backoff exponencial + jitter) e mostra o estado da
/// conexão ([ChatConnectionBadge]).
///
/// À direita fica o painel de informações ([PainelFicha]): quem é o contato,
/// o estado do atendimento, etiquetas, campos, arquivos e anotações — tudo o
/// que se manipula num atendimento, aberto junto com a conversa.
///
/// Cada abertura tem [ChatController] próprio, fechado (stream cancelado) no
/// descarte. Trocar de atendimento no painel **recria** o widget — ver a
/// `ValueKey` em quem o usa —, o que garante um stream por conversa em vez de
/// um controller reaproveitado apontando para a anterior.
class PainelDeConversa extends StatefulWidget {
  final int atendimentoId;

  /// Mostrado no topo quando a conversa está embutida no quadro; no celular a
  /// `AppBar` da [ChatPage] já cumpre esse papel e isto vem nulo.
  final VoidCallback? aoFechar;

  /// Se o painel de informações está à vista. Vem de fora para que o quadro
  /// o abra no clique do cartão e pelo atalho `i`; sem ele, o painel cuida do
  /// próprio estado e começa fechado.
  final ValueNotifier<bool>? detalhesAbertos;

  /// Recolhe a conversa para a mini-barra do quadro (modo "Kanban" da v1).
  final VoidCallback? aoMinimizar;

  /// Dá à conversa a tela inteira (modo "Atendimento" da v1).
  final VoidCallback? aoExpandir;

  /// O cartão e as ações do quadro — status, prioridade, dono, transferência.
  /// Falta quando a conversa foi aberta fora do quadro.
  final AtendimentoNoQuadro? noQuadro;

  const PainelDeConversa({
    super.key,
    required this.atendimentoId,
    this.aoFechar,
    this.detalhesAbertos,
    this.aoMinimizar,
    this.aoExpandir,
    this.noQuadro,
  });

  @override
  State<PainelDeConversa> createState() => _PainelDeConversaState();
}

class _PainelDeConversaState extends State<PainelDeConversa> {
  late final ChatController _controller;
  late final FichaController _ficha;
  final _inputController = TextEditingController();

  /// B6 — para saber se o fim da conversa está à vista.
  final _rolagem = ScrollController();

  /// O estado dos detalhes quando ninguém de fora o controla.
  late final ValueNotifier<bool> _detalhesProprios = ValueNotifier(false);
  ValueNotifier<bool> get _detalhes =>
      widget.detalhesAbertos ?? _detalhesProprios;

  /// A aba do compositor: mensagem ao contato ou nota interna.
  bool _modoNota = false;

  /// P13 — com quem é a conversa (nome, telefone e foto atualizados).
  ContatoDaConversa? _contato;

  /// Uma foto nova por abertura, no máximo: a URL do CDN expira, e pedir de
  /// novo a cada redesenho martelaria o provedor.
  bool _jaPediuFotoNova = false;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      getThreadUsecase: inject(),
      sendUsecase: inject(),
      eventos: inject(),
      // B6 — opcional: onde o usecase não foi registrado (testes de tela, app
      // sem a rota), a conversa abre e só não marca a leitura.
      marcarLidoUsecase:
          GetIt.instance.isRegistered<MarcarAtendimentoLidoUsecase>()
          ? inject<MarcarAtendimentoLidoUsecase>()
          : null,
      // P3 — mesmo critério: nos testes de tela o usecase não está registrado,
      // e a conversa tem de abrir assim mesmo.
      presencaUsecase: GetIt.instance.isRegistered<EnviarPresencaUsecase>()
          ? inject<EnviarPresencaUsecase>()
          : null,
    );
    // Controller próprio: a ficha pode falhar sem derrubar a conversa, e um
    // estado só levaria as mensagens junto com o painel.
    _ficha = FichaController(
      carregar: inject(),
      criarEtiqueta: inject(),
      alternar: inject(),
      criarNota: inject(),
      definirBot: inject(),
      definirValorCampo: inject(),
      // P5 — mesmo critério dos demais opcionais: sem registro, a ficha abre
      // e só não oferece excluir nota nem editar etiqueta.
      removerNota: GetIt.instance.isRegistered<RemoverNotaUsecase>()
          ? inject<RemoverNotaUsecase>()
          : null,
      atualizarEtiqueta: GetIt.instance.isRegistered<AtualizarEtiquetaUsecase>()
          ? inject<AtualizarEtiquetaUsecase>()
          : null,
      desativarEtiqueta: GetIt.instance.isRegistered<DesativarEtiquetaUsecase>()
          ? inject<DesativarEtiquetaUsecase>()
          : null,
    );
    _controller.abrir(widget.atendimentoId);
    _ficha.abrir(widget.atendimentoId);
    // P10 — a IA preencheu campo: a ficha aberta mostra sem precisar reabrir.
    _controller.camposAtualizados.addListener(_recarregarFicha);
    unawaited(_carregarContato());
  }

  void _recarregarFicha() => _ficha.abrir(widget.atendimentoId);

  Future<void> _carregarContato({bool forcar = false}) async {
    if (!GetIt.instance.isRegistered<ObterContatoUsecase>()) return;
    final res = await inject<ObterContatoUsecase>()(
      ObterContatoParameters(
        atendimentoId: widget.atendimentoId,
        forcar: forcar,
      ),
    );
    if (!mounted) return;
    if (res case Success(:final value)) setState(() => _contato = value);
  }

  void _fotoQuebrou() {
    if (_jaPediuFotoNova) return;
    _jaPediuFotoNova = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_carregarContato(forcar: true)),
    );
  }

  @override
  void dispose() {
    _controller.close();
    _ficha.close();
    _detalhesProprios.dispose();
    _inputController.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final conversa = BlocConsumer<ChatController, ViewState<ChatViewModel>>(
          bloc: _controller,
          // Chegou histórico ou mensagem nova: depois de desenhar, confere se o
          // fim está à vista.
          listenWhen: (_, atual) => atual is SuccessState<ChatViewModel>,
          listener: (_, _) => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _marcarSeNoFim(),
          ),
          builder: (context, state) {
            return switch (state) {
              InitialState() || LoadingState() => const Center(
                child: CircularProgressIndicator(),
              ),
              ErrorState(:final error) => AppErrorView(
                message: error.message,
                onRetry: () => _controller.abrir(widget.atendimentoId),
              ),
              SuccessState(:final data) => _ChatBody(
                viewModel: data,
                inputController: _inputController,
                onEnviar: _enviar,
                rolagem: _rolagem,
                aoPararDeRolar: _marcarSeNoFim,
                aoCitar: _controller.citar,
                aoCancelarCitacao: _controller.cancelarCitacao,
                aoDigitar: _controller.avisarQueEstaDigitando,
                aoAnexar: _anexar,
                aoGravar: _alternarGravacao,
                gravando: _gravando,
                modoNota: _modoNota,
                aoTrocarModo: (nota) => setState(() => _modoNota = nota),
              ),
            };
          },
        );

        final contato = _contato;
        final resumo = widget.noQuadro?.resumo;
        final ficha = PainelFicha(
          controller: _ficha,
          largura: null,
          noQuadro: widget.noQuadro,
          nomeDoContato: contato?.nomeParaExibir ?? '',
          telefoneDoContato: contato?.telefone ?? '',
          fotoDoContato: contato?.fotoUrl ?? '',
        );

        final cabecalho = widget.aoFechar == null
            ? null
            : _CabecalhoDoPainel(
                atendimentoId: widget.atendimentoId,
                nome:
                    contato?.nomeParaExibir ??
                    resumo?.nomeParaExibir ??
                    'Atendimento #${widget.atendimentoId}',
                telefone: contato?.telefone ?? resumo?.contatoTelefone ?? '',
                fotoUrl: contato?.fotoUrl ?? resumo?.contatoFotoUrl ?? '',
                mostrarTelefone:
                    (contato?.nome.isNotEmpty ?? false) ||
                    (resumo?.contatoNome.isNotEmpty ?? false),
                noQuadro: widget.noQuadro,
                aoFalharFoto: _fotoQuebrou,
                aoFechar: widget.aoFechar!,
                detalhes: _detalhes,
                aoMinimizar: widget.aoMinimizar,
                aoExpandir: widget.aoExpandir,
              );
        // A faixa de ações fica fora da área que a gaveta cobre: com as
        // informações abertas por cima, Resolver e Nota continuam à mão.
        final acoes = _AcoesRapidas(
          noQuadro: widget.noQuadro,
          ficha: _ficha,
          aoAnotar: () => setState(() => _modoNota = true),
        );
        final corpo = conversa;
        Widget comCabecalho(Widget conteudo) => Column(
          children: [
            ?cabecalho,
            acoes,
            Expanded(child: conteudo),
          ],
        );

        // O painel de informações fica ao lado da conversa quando os dois
        // cabem. Numa largura menor (a conversa ao lado do quadro numa janela
        // média, o celular) ele vira gaveta sobre as mensagens, ABAIXO do
        // cabeçalho: minimizar, fechar e o próprio botão de detalhes continuam
        // à mão com ele aberto.
        // A partir daqui, conversa e informações dividem o painel meio a
        // meio; abaixo, cada metade ficaria estreita demais para ler.
        final cabemOsDois = constraints.maxWidth >= 640;
        return ValueListenableBuilder<bool>(
          valueListenable: _detalhes,
          builder: (context, abertos, _) {
            if (!abertos) return comCabecalho(corpo);
            if (cabemOsDois) {
              return Row(
                children: [
                  Expanded(child: comCabecalho(corpo)),
                  Expanded(child: ficha),
                ],
              );
            }
            return comCabecalho(
              Stack(
                children: [
                  Positioned.fill(child: corpo),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: Material(
                      elevation: 12,
                      child: PainelFicha(
                        controller: _ficha,
                        noQuadro: widget.noQuadro,
                        nomeDoContato: contato?.nomeParaExibir ?? '',
                        telefoneDoContato: contato?.telefone ?? '',
                        fotoDoContato: contato?.fotoUrl ?? '',
                        largura: constraints.maxWidth < 380
                            ? constraints.maxWidth
                            : 380,
                        aoFechar: () => _detalhes.value = false,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// B6 — a lista é invertida: o fim da conversa (a mensagem mais nova) é o
  /// início da rolagem. Perto dele, a pessoa está lendo o que chegou.
  ///
  /// P2 — e no outro extremo (o topo, que na lista invertida é o fim da
  /// extensão) está o histórico antigo: chegar lá pede a página anterior.
  void _marcarSeNoFim() {
    if (!mounted) return;
    final noFim = !_rolagem.hasClients || _rolagem.offset <= 48;
    if (noFim) _controller.marcarComoLida();
    if (_rolagem.hasClients &&
        _rolagem.offset >= _rolagem.position.maxScrollExtent - 200) {
      _controller.carregarAntigas();
    }
  }

  /// P3 — o gravador do áudio de voz. Só existe enquanto se grava.
  final _gravador = AudioRecorder();
  bool _gravando = false;

  /// P3 — escolhe um arquivo e o manda para a conversa.
  Future<void> _anexar() async {
    if (!GetIt.instance.isRegistered<EnviarMidiaUsecase>()) return;
    final escolha = await FilePicker.pickFiles(withData: true);
    final arquivo = escolha?.files.singleOrNull;
    if (arquivo == null) return;
    // No desktop o picker devolve `path`; na Web, `bytes`. O gateway espera
    // bytes, e ler o arquivo aqui evita espalhar essa diferença pela tela.
    final bytes = arquivo.bytes;
    if (bytes == null) return;
    await _enviarMidia(
      nomeArquivo: arquivo.name,
      mimetype: _mimetypePorExtensao(arquivo.extension),
      bytes: bytes,
    );
  }

  /// P3 — grava um áudio de voz (PTT) e o envia ao soltar.
  Future<void> _alternarGravacao() async {
    if (!GetIt.instance.isRegistered<EnviarMidiaUsecase>()) return;
    if (_gravando) {
      final caminho = await _gravador.stop();
      setState(() => _gravando = false);
      await _controller.pararDeDigitar();
      if (caminho == null) return;
      final bytes = await XFile(caminho).readAsBytes();
      await _enviarMidia(
        nomeArquivo: 'audio.m4a',
        mimetype: 'audio/mp4',
        bytes: bytes,
        ehPtt: true,
      );
      return;
    }
    if (!await _gravador.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem permissão para usar o microfone.')),
      );
      return;
    }
    await _gravador.start(const RecordConfig(), path: await _caminhoDoAudio());
    setState(() => _gravando = true);
    // Enquanto grava, o contato vê "gravando áudio...", como no WhatsApp.
    await _controller.avisarQueEstaDigitando(gravandoAudio: true);
  }

  /// Onde o gravador escreve. Na Web não há sistema de arquivos: o `record`
  /// devolve um blob e ignora o caminho.
  Future<String> _caminhoDoAudio() async {
    if (kIsWeb) return '';
    final dir = await getTemporaryDirectory();
    final agora = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/ptt_$agora.m4a';
  }

  Future<void> _enviarMidia({
    required String nomeArquivo,
    required String mimetype,
    required List<int> bytes,
    bool ehPtt = false,
  }) async {
    final res = await inject<EnviarMidiaUsecase>()(
      EnviarMidiaParameters(
        atendimentoId: widget.atendimentoId,
        nomeArquivo: nomeArquivo,
        mimetype: mimetype,
        bytes: bytes,
        ehPtt: ehPtt,
      ),
    );
    if (!mounted) return;
    if (res case Failure(:final error)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    await _controller.abrir(widget.atendimentoId);
  }

  /// O servidor decide o que aceita pelo mimetype; o picker devolve só a
  /// extensão. Desconhecido vai como binário, e o servidor recusa se não puder.
  static String _mimetypePorExtensao(String? extensao) => switch (extensao
      ?.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'mp3' => 'audio/mpeg',
    'ogg' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'mp4' => 'video/mp4',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };

  Future<void> _enviar() async {
    final texto = _inputController.text.trim();
    if (texto.isEmpty) return;
    // Aba "Nota interna": vai para a ficha, nunca para o contato.
    if (_modoNota) {
      final messenger = ScaffoldMessenger.of(context);
      final falha = await _ficha.anotar(texto);
      if (falha != null) {
        messenger.showSnackBar(SnackBar(content: Text(falha.message)));
        return;
      }
      _inputController.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Nota interna salva.')),
      );
      return;
    }
    _inputController.clear();
    final erro = await _controller.enviar(texto);
    if (erro != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(erro.message)));
    }
  }
}

/// A conversa como tela inteira — o caminho do celular e da janela estreita,
/// onde não há espaço para quadro e conversa lado a lado.
///
/// Em janela larga o quadro embute [PainelDeConversa] diretamente e esta
/// página não entra em cena.
class ChatPage extends StatefulWidget {
  final int atendimentoId;

  const ChatPage({super.key, required this.atendimentoId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// O painel de informações: ao lado da conversa quando cabe (e aí já abre
  /// à vista), gaveta aberta pelo botão da barra do topo quando não cabe.
  ValueNotifier<bool>? _detalhes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detalhes ??= ValueNotifier<bool>(
      MediaQuery.sizeOf(context).width >=
          larguraDaConversa + larguraDasInformacoes,
    );
  }

  @override
  void dispose() {
    _detalhes?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detalhes = _detalhes!;
    return AppScaffold(
      title: 'Atendimento #${widget.atendimentoId}',
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: detalhes,
          builder: (context, abertos, _) => IconButton(
            icon: Icon(abertos ? Icons.info : Icons.info_outline),
            tooltip: 'Detalhes do atendimento',
            onPressed: () => detalhes.value = !abertos,
          ),
        ),
      ],
      body: PainelDeConversa(
        atendimentoId: widget.atendimentoId,
        detalhesAbertos: detalhes,
      ),
    );
  }
}

/// O topo da conversa embutida (`ws-chat__head`): com quem é, em que etapa e
/// com quem está, e os controles de foco.
///
/// Só aparece embutido. Como tela cheia quem cumpre esse papel é a `AppBar`,
/// com o botão de voltar que o sistema já desenha — dois cabeçalhos seriam um
/// a mais.
class _CabecalhoDoPainel extends StatelessWidget {
  final int atendimentoId;
  final String nome;
  final String telefone;
  final String fotoUrl;

  /// O telefone só vai para a linha de baixo quando o nome não é ele mesmo.
  final bool mostrarTelefone;
  final AtendimentoNoQuadro? noQuadro;
  final VoidCallback aoFalharFoto;
  final VoidCallback aoFechar;
  final ValueNotifier<bool> detalhes;
  final VoidCallback? aoMinimizar;
  final VoidCallback? aoExpandir;

  const _CabecalhoDoPainel({
    required this.atendimentoId,
    required this.nome,
    required this.telefone,
    required this.fotoUrl,
    required this.mostrarTelefone,
    required this.noQuadro,
    required this.aoFalharFoto,
    required this.aoFechar,
    required this.detalhes,
    this.aoMinimizar,
    this.aoExpandir,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resumo = noQuadro?.resumo;
    final estiloDaLinha = TextStyle(fontSize: 11, color: colors.fgMuted);
    final partes = <Widget>[
      if (mostrarTelefone && telefone.isNotEmpty)
        Text(telefone, style: estiloDaLinha),
      if (noQuadro case final q? when q.etapaNome.isNotEmpty)
        Text(q.etapaNome, style: estiloDaLinha),
      if (resumo != null && resumo.atendenteNome.isNotEmpty)
        Text('com ${resumo.atendenteNome}', style: estiloDaLinha),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (aoMinimizar != null)
            _BotaoDoCabecalho(
              icone: Icons.keyboard_double_arrow_right,
              dica: 'Minimizar (Esc)',
              aoTocar: aoMinimizar!,
            ),
          const SizedBox(width: 4),
          AvatarDoContato(
            nome: nome,
            fotoUrl: fotoUrl,
            raio: 19,
            aoFalharFoto: aoFalharFoto,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: colors.fgStrong,
                  ),
                ),
                if (partes.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      for (var i = 0; i < partes.length; i++) ...[
                        if (i > 0)
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: colors.fgSubtle,
                              shape: BoxShape.circle,
                            ),
                          ),
                        partes[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (aoExpandir != null)
            _BotaoDoCabecalho(
              icone: Icons.open_in_full,
              dica: 'Expandir (Alt+3)',
              aoTocar: aoExpandir!,
            ),
          ValueListenableBuilder<bool>(
            valueListenable: detalhes,
            builder: (context, abertos, _) => _BotaoDoCabecalho(
              icone: abertos ? Icons.info : Icons.info_outline,
              dica: 'Detalhes do atendimento (i)',
              ativo: abertos,
              aoTocar: () => detalhes.value = !abertos,
            ),
          ),
          _BotaoDoCabecalho(
            icone: Icons.close,
            dica: 'Fechar a conversa',
            aoTocar: aoFechar,
          ),
        ],
      ),
    );
  }
}

/// Botão quadrado de ícone do cabeçalho (`ws-chat__iconbtn`).
class _BotaoDoCabecalho extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback aoTocar;
  final bool ativo;

  const _BotaoDoCabecalho({
    required this.icone,
    required this.dica,
    required this.aoTocar,
    this.ativo = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      icon: Icon(icone, size: 18),
      tooltip: dica,
      color: ativo ? colors.accent : colors.fgMuted,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
      ),
      onPressed: aoTocar,
    );
  }
}

/// A faixa de ações rápidas sob o cabeçalho (`ws-chat__qstrip`): transferir,
/// pendência, resolver, nota, etiqueta e cancelar — o que se faz o dia
/// inteiro, a um clique, sem sair da conversa.
class _AcoesRapidas extends StatelessWidget {
  final AtendimentoNoQuadro? noQuadro;
  final FichaController ficha;

  /// "Nota" leva o compositor para a aba de nota interna.
  final VoidCallback aoAnotar;

  const _AcoesRapidas({
    required this.noQuadro,
    required this.ficha,
    required this.aoAnotar,
  });

  Future<void> _rodar(
    BuildContext context,
    Future<String?> Function() acao,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final erro = await acao();
    if (erro != null) {
      messenger.showSnackBar(SnackBar(content: Text(erro)));
    }
  }

  Future<void> _cancelar(BuildContext context, AtendimentoNoQuadro q) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Cancelar o atendimento?'),
        content: const Text(
          'A conversa sai da fila de trabalho. Se o contato escrever de novo, '
          'um atendimento novo começa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Cancelar atendimento'),
          ),
        ],
      ),
    );
    if (confirmou != true || !context.mounted) return;
    await _rodar(context, () => q.definirStatus('cancelado'));
  }

  @override
  Widget build(BuildContext context) {
    if (!quadroPodeEscrever()) return const SizedBox.shrink();
    final colors = context.colors;
    final q = noQuadro;
    final status = q?.resumo.status ?? '';

    final botoes = <Widget>[
      if (q != null && q.outrosFluxos.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'Transferir para outro quadro',
          onSelected: (id) => _rodar(context, () => q.transferirParaFluxo(id)),
          itemBuilder: (_) => [
            for (final f in q.outrosFluxos)
              PopupMenuItem(
                value: f.id,
                child: Text('Transferir para ${f.rotulo}'),
              ),
          ],
          child: const BotaoDeAcao(
            rotulo: 'Transferir',
            icone: Icons.swap_horiz,
            tom: TomDaAcao.ouro,
            aoTocar: null,
          ),
        ),
      if (q != null && q.resumo.atendenteHumanoId == null)
        BotaoDeAcao(
          rotulo: 'Assumir',
          icone: Icons.person_add_alt_1_outlined,
          tom: TomDaAcao.ouro,
          aoTocar: () => _rodar(context, () => q.assumir(true)),
        ),
      if (q != null && status != 'pendencia')
        BotaoDeAcao(
          rotulo: 'Pendência',
          icone: Icons.schedule,
          aoTocar: () => _rodar(context, () => q.definirStatus('pendencia')),
        ),
      if (q != null && status != 'resolvido')
        BotaoDeAcao(
          rotulo: 'Resolver',
          icone: Icons.check,
          tom: TomDaAcao.sucesso,
          aoTocar: () => _rodar(context, () => q.definirStatus('resolvido')),
        ),
      BotaoDeAcao(
        rotulo: 'Nota',
        icone: Icons.sticky_note_2_outlined,
        aoTocar: aoAnotar,
      ),
      BlocBuilder<FichaController, ViewState<FichaAtendimento>>(
        bloc: ficha,
        builder: (context, state) {
          final disponiveis = switch (state) {
            SuccessState(:final data) => data.disponiveis,
            _ => const <Etiqueta>[],
          };
          return PopupMenuButton<int>(
            tooltip: 'Etiquetar a conversa',
            onSelected: (id) => id < 0
                ? abrirDialogoDeEtiqueta(context, ficha)
                : alternarEtiqueta(context, ficha, id, aplicar: true),
            itemBuilder: (_) => [
              for (final e in disponiveis)
                PopupMenuItem(
                  value: e.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 5,
                        backgroundColor: corDaEtiqueta(e.cor),
                      ),
                      const SizedBox(width: 8),
                      Text(e.nome),
                    ],
                  ),
                ),
              if (disponiveis.isNotEmpty) const PopupMenuDivider(),
              const PopupMenuItem(value: -1, child: Text('Nova etiqueta…')),
            ],
            child: const BotaoDeAcao(
              rotulo: 'Etiqueta',
              icone: Icons.sell_outlined,
              aoTocar: null,
            ),
          );
        },
      ),
      if (q != null && status != 'cancelado')
        BotaoDeAcao(
          rotulo: 'Cancelar',
          icone: Icons.block,
          tom: TomDaAcao.perigo,
          aoTocar: () => _cancelar(context, q),
        ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      // Quebra linha em vez de rolar: na conversa de 460px ao lado do quadro,
      // a rolagem escondia "Resolver" e "Cancelar" fora da vista.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: botoes),
    );
  }
}

class _ChatBody extends StatelessWidget {
  final ChatViewModel viewModel;
  final TextEditingController inputController;
  final VoidCallback onEnviar;
  final ScrollController rolagem;
  final VoidCallback aoPararDeRolar;
  final void Function(MensagemThread) aoCitar;
  final VoidCallback aoCancelarCitacao;
  final VoidCallback aoDigitar;
  final VoidCallback aoAnexar;
  final VoidCallback aoGravar;
  final bool gravando;
  final bool modoNota;
  final ValueChanged<bool> aoTrocarModo;

  const _ChatBody({
    required this.viewModel,
    required this.inputController,
    required this.onEnviar,
    required this.rolagem,
    required this.aoPararDeRolar,
    required this.aoCitar,
    required this.aoCancelarCitacao,
    required this.aoDigitar,
    required this.aoAnexar,
    required this.aoGravar,
    required this.gravando,
    required this.modoNota,
    required this.aoTrocarModo,
  });

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ChatConnectionBadge(status: viewModel.connectionStatus),
        if (viewModel.presencaDoContato.isNotEmpty)
          _AvisoDePresenca(situacao: viewModel.presencaDoContato),
        Expanded(
          child: ColoredBox(
            // O fundo bege do WhatsApp (`--ws-chat-bg`): é onde quem atende
            // já está acostumado a ler conversa.
            color: escuro ? AppPalette.chatBgDark : AppPalette.chatBgLight,
            child: viewModel.mensagens.isEmpty
                ? const AppEmptyView(
                    icon: Icons.chat_bubble_outline,
                    title: 'Nenhuma mensagem ainda',
                    subtitle:
                        'Envie a primeira mensagem para iniciar a conversa.',
                  )
                : NotificationListener<ScrollEndNotification>(
                    onNotification: (_) {
                      aoPararDeRolar();
                      return false;
                    },
                    child: ListView.builder(
                      controller: rolagem,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      // O item extra é o topo da rolagem: spinner enquanto o
                      // histórico antigo vem, ou nada quando acabou.
                      itemCount: viewModel.mensagens.length + 1,
                      itemBuilder: (context, index) {
                        if (index == viewModel.mensagens.length) {
                          return viewModel.carregandoAntigas
                              ? const Padding(
                                  padding: EdgeInsets.all(AppSpacing.md),
                                  child: Center(
                                    child: SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        final posicao = viewModel.mensagens.length - 1 - index;
                        final mensagem = viewModel.mensagens[posicao];
                        final anterior = posicao == 0
                            ? null
                            : viewModel.mensagens[posicao - 1];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (mudouODia(anterior, mensagem))
                              _SeparadorDeDia(dia: mensagem.timestamp),
                            ChatMessageBubble(
                              mensagem: mensagem,
                              aoCitar: () => aoCitar(mensagem),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ),
        if (viewModel.citando case final citada?)
          _BarraDeCitacao(mensagem: citada, aoCancelar: aoCancelarCitacao),
        // P16 — quem só lê vê a conversa inteira, sem a caixa de envio que o
        // servidor recusaria.
        if (!quadroPodeEscrever())
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Você tem acesso só de leitura a esta conversa.',
              textAlign: TextAlign.center,
            ),
          )
        else
          _Compositor(
            inputController: inputController,
            onEnviar: onEnviar,
            aoDigitar: aoDigitar,
            aoAnexar: aoAnexar,
            aoGravar: aoGravar,
            gravando: gravando,
            modoNota: modoNota,
            aoTrocarModo: aoTrocarModo,
          ),
      ],
    );
  }
}

/// A caixa de envio (`ws-composer`), com as abas "Mensagem" e "Nota interna".
///
/// A nota interna sai pelo mesmo lugar em que se escreve a mensagem — e por
/// isso a caixa muda de cor: mandar ao cliente o que era para a equipe é o
/// erro que ela existe para evitar.
class _Compositor extends StatelessWidget {
  final TextEditingController inputController;
  final VoidCallback onEnviar;
  final VoidCallback aoDigitar;
  final VoidCallback aoAnexar;
  final VoidCallback aoGravar;
  final bool gravando;
  final bool modoNota;
  final ValueChanged<bool> aoTrocarModo;

  const _Compositor({
    required this.inputController,
    required this.onEnviar,
    required this.aoDigitar,
    required this.aoAnexar,
    required this.aoGravar,
    required this.gravando,
    required this.modoNota,
    required this.aoTrocarModo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: escuro ? colors.panel : const Color(0xFFF0F2F5),
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Aba(
                rotulo: 'Mensagem',
                icone: Icons.chat_outlined,
                ativa: !modoNota,
                aoTocar: () => aoTrocarModo(false),
              ),
              _Aba(
                rotulo: 'Nota interna',
                icone: Icons.lock_outline,
                ativa: modoNota,
                aoTocar: () => aoTrocarModo(true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!modoNota) ...[
                _BotaoRedondoDoCompositor(
                  icone: Icons.attach_file,
                  dica: 'Anexar arquivo',
                  aoTocar: aoAnexar,
                ),
                _BotaoRedondoDoCompositor(
                  icone: gravando ? Icons.stop_circle : Icons.mic_none,
                  dica: gravando ? 'Parar e enviar' : 'Gravar áudio',
                  cor: gravando ? colors.danger : null,
                  aoTocar: aoGravar,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: inputController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) {
                    if (!modoNota) aoDigitar();
                  },
                  onSubmitted: (_) => onEnviar(),
                  style: TextStyle(fontSize: 13, color: colors.fgStrong),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: modoNota
                        ? 'Nota interna — só a equipe vê'
                        : 'Digite uma mensagem…',
                    filled: true,
                    fillColor: modoNota ? colors.warningSoft : colors.inputBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: modoNota ? colors.warning : colors.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: modoNota ? colors.warning : colors.accent,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onEnviar,
                tooltip: modoNota ? 'Salvar nota interna' : 'Enviar mensagem',
                style: IconButton.styleFrom(
                  backgroundColor: modoNota ? colors.warning : colors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(38, 38),
                ),
                icon: Icon(modoNota ? Icons.lock : Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Aba extends StatelessWidget {
  final String rotulo;
  final IconData icone;
  final bool ativa;
  final VoidCallback aoTocar;

  const _Aba({
    required this.rotulo,
    required this.icone,
    required this.ativa,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cor = ativa ? colors.accentHover : colors.fgMuted;
    return InkWell(
      onTap: aoTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: ativa ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 13, color: cor),
            const SizedBox(width: 5),
            Text(
              rotulo,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: ativa ? FontWeight.w600 : FontWeight.w500,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotaoRedondoDoCompositor extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback aoTocar;
  final Color? cor;

  const _BotaoRedondoDoCompositor({
    required this.icone,
    required this.dica,
    required this.aoTocar,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone, size: 20),
      tooltip: dica,
      color: cor ?? context.colors.fgMuted,
      onPressed: aoTocar,
    );
  }
}

/// P2 — a conversa separa os dias, como o WhatsApp: sem isso, uma resposta de
/// ontem e uma de hoje ficam coladas e a pessoa lê fora de contexto.
bool mudouODia(MensagemThread? anterior, MensagemThread atual) {
  if (anterior == null) return true;
  final a = anterior.timestamp;
  final b = atual.timestamp;
  return a.year != b.year || a.month != b.month || a.day != b.day;
}

/// A etiqueta de data entre as bolhas ("Hoje", "Ontem" ou a data).
class _SeparadorDeDia extends StatelessWidget {
  final DateTime dia;

  const _SeparadorDeDia({required this.dia});

  String _rotulo() {
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    bool mesmoDia(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (mesmoDia(dia, hoje)) return 'Hoje';
    if (mesmoDia(dia, ontem)) return 'Ontem';
    return DateFormat('dd/MM/yyyy').format(dia);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          // `ws-daysep`: a etiqueta branca em caixa alta sobre o fundo bege.
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: AppRadius.md,
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _rotulo().toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: colors.fgMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// P2 — o trecho que a próxima mensagem vai citar, com o X para desistir.
class _BarraDeCitacao extends StatelessWidget {
  final MensagemThread mensagem;
  final VoidCallback aoCancelar;

  const _BarraDeCitacao({required this.mensagem, required this.aoCancelar});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.chip,
        borderRadius: AppRadius.card,
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // Conteúdo de mensagem é PII: aqui só aparece na tela.
            child: Text(
              mensagem.conteudo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancelar resposta',
            onPressed: aoCancelar,
          ),
        ],
      ),
    );
  }
}

/// P3 — "digitando..." / "gravando áudio..." do contato.
class _AvisoDePresenca extends StatelessWidget {
  final String situacao;

  const _AvisoDePresenca({required this.situacao});

  @override
  Widget build(BuildContext context) {
    final texto = situacao == 'recording' ? 'gravando áudio…' : 'digitando…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Icon(
            situacao == 'recording' ? Icons.mic : Icons.more_horiz,
            size: 14,
            color: context.colors.fgMuted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            texto,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.colors.fgMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
