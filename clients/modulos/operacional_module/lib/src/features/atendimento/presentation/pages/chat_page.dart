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
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import '../controllers/chat_controller.dart';
import '../controllers/chat_state.dart';
import '../controllers/ficha_controller.dart';
import '../widgets/avatar_do_contato.dart';
import '../widgets/chat_connection_badge.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/galeria_do_atendimento.dart';
import '../widgets/painel_ficha.dart';
import '../escrita_no_quadro.dart';

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
/// Cada abertura tem [ChatController] próprio, fechado (stream cancelado) no
/// descarte. Trocar de atendimento no painel **recria** o widget — ver a
/// `ValueKey` em quem o usa —, o que garante um stream por conversa em vez de
/// um controller reaproveitado apontando para a anterior.
class PainelDeConversa extends StatefulWidget {
  final int atendimentoId;

  /// Mostrado no topo quando a conversa está embutida no quadro; no celular a
  /// `AppBar` da [ChatPage] já cumpre esse papel e isto vem nulo.
  final VoidCallback? aoFechar;

  const PainelDeConversa({
    super.key,
    required this.atendimentoId,
    this.aoFechar,
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
      atualizarEtiqueta:
          GetIt.instance.isRegistered<AtualizarEtiquetaUsecase>()
          ? inject<AtualizarEtiquetaUsecase>()
          : null,
      desativarEtiqueta:
          GetIt.instance.isRegistered<DesativarEtiquetaUsecase>()
          ? inject<DesativarEtiquetaUsecase>()
          : null,
    );
    _controller.abrir(widget.atendimentoId);
    _ficha.abrir(widget.atendimentoId);
    // P10 — a IA preencheu campo: a ficha aberta mostra sem precisar reabrir.
    _controller.camposAtualizados.addListener(_recarregarFicha);
  }

  void _recarregarFicha() => _ficha.abrir(widget.atendimentoId);

  @override
  void dispose() {
    _controller.close();
    _ficha.close();
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
                aoAbrirGaleria: () =>
                    GaleriaDoAtendimento.abrir(context, widget.atendimentoId),
              ),
            };
          },
        );

        final corpo = widget.aoFechar == null
            ? conversa
            : Column(
                children: [
                  _CabecalhoDoPainel(
                    atendimentoId: widget.atendimentoId,
                    aoFechar: widget.aoFechar!,
                  ),
                  Expanded(child: conversa),
                ],
              );

        // Em janela estreita a ficha some em vez de espremer a conversa: ler e
        // responder é o que não pode ficar sem espaço. As etiquetas continuam
        // visíveis no cartão do quadro.
        //
        // O limite vale para a largura DESTE painel, não para a da janela: ao
        // lado do quadro ele tem uns 420px, e a ficha não caberia junto.
        if (constraints.maxWidth < 900) return corpo;

        return Row(
          children: [
            Expanded(child: corpo),
            PainelFicha(controller: _ficha),
          ],
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
  static String _mimetypePorExtensao(String? extensao) =>
      switch (extensao?.toLowerCase()) {
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
class ChatPage extends StatelessWidget {
  final int atendimentoId;

  const ChatPage({super.key, required this.atendimentoId});

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Atendimento #$atendimentoId',
    body: PainelDeConversa(atendimentoId: atendimentoId),
  );
}

/// Faixa de topo do painel embutido: diz qual conversa está aberta e como
/// fechá-la.
///
/// Só aparece embutido. Como tela cheia quem cumpre esse papel é a `AppBar`,
/// com o botão de voltar que o sistema já desenha — dois cabeçalhos seriam um
/// a mais.
class _CabecalhoDoPainel extends StatefulWidget {
  final int atendimentoId;
  final VoidCallback aoFechar;

  const _CabecalhoDoPainel({
    required this.atendimentoId,
    required this.aoFechar,
  });

  @override
  State<_CabecalhoDoPainel> createState() => _CabecalhoDoPainelState();
}

/// P13 — o cabeçalho diz com quem é a conversa, e não só o número dela.
class _CabecalhoDoPainelState extends State<_CabecalhoDoPainel> {
  ContatoDaConversa? _contato;

  /// Uma foto nova por abertura, no máximo: a URL do CDN expira, e pedir de
  /// novo a cada redesenho martelaria o provedor.
  bool _jaPediuFotoNova = false;

  @override
  void initState() {
    super.initState();
    unawaited(_carregar());
  }

  Future<void> _carregar({bool forcar = false}) async {
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
      (_) => unawaited(_carregar(forcar: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contato = _contato;
    final atendimentoId = widget.atendimentoId;
    final aoFechar = widget.aoFechar;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (contato != null) ...[
            AvatarDoContato(
              nome: contato.nomeParaExibir,
              fotoUrl: contato.fotoUrl,
              aoFalharFoto: _fotoQuebrou,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contato?.nomeParaExibir ?? 'Atendimento #$atendimentoId',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (contato != null &&
                    contato.nome.isNotEmpty &&
                    contato.telefone.isNotEmpty)
                  Text(
                    contato.telefone,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colors.fgMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Fechar a conversa',
            onPressed: aoFechar,
          ),
        ],
      ),
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
  final VoidCallback aoAbrirGaleria;

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
    required this.aoAbrirGaleria,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ChatConnectionBadge(status: viewModel.connectionStatus),
            ),
            IconButton(
              icon: const Icon(Icons.perm_media_outlined),
              tooltip: 'Arquivos da conversa',
              onPressed: aoAbrirGaleria,
            ),
          ],
        ),
        if (viewModel.presencaDoContato.isNotEmpty)
          _AvisoDePresenca(situacao: viewModel.presencaDoContato),
        Expanded(
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
                    padding: const EdgeInsets.all(AppSpacing.md),
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
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                tooltip: 'Anexar arquivo',
                onPressed: aoAnexar,
              ),
              IconButton(
                icon: Icon(gravando ? Icons.stop_circle : Icons.mic_none),
                color: gravando ? AppPalette.danger : null,
                tooltip: gravando ? 'Parar e enviar' : 'Gravar áudio',
                onPressed: aoGravar,
              ),
              Expanded(
                child: AppTextField(
                  label: 'Mensagem',
                  hint: 'Digite uma mensagem…',
                  controller: inputController,
                  onChanged: (_) => aoDigitar(),
                  onSubmitted: (_) => onEnviar(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: onEnviar,
                tooltip: 'Enviar mensagem',
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
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
          decoration: BoxDecoration(
            color: colors.chip,
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            _rotulo(),
            style: Theme.of(context).textTheme.labelSmall,
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
    final texto = situacao == 'recording'
        ? 'gravando áudio…'
        : 'digitando…';
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
