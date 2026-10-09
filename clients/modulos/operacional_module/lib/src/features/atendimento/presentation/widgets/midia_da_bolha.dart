import 'dart:async';
import 'dart:developer' as developer;

import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/model/midia_mensagem.dart';

/// P2a — abre uma URL fora do app. Parâmetro do widget só para o teste
/// substituir o `url_launcher` (que no teste não tem plataforma).
typedef AbrirUrlExterna = Future<bool> Function(Uri url);

Future<bool> _abrirNoSistema(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// P2a — log da mídia da bolha. Só tipo e mimetype: URL assinada é
/// credencial, nome de arquivo é PII, e a mensagem de erro do player costuma
/// repetir a URL — nenhum dos três entra aqui.
void _avisarFalha(MidiaMensagem midia, String oQue) => developer.log(
  oQue,
  name: 'operacional_module.midia',
  level: 900,
  error: 'tipo=${midia.tipo.name} mimetype=${midia.mimetype}',
);

/// P2a — o anexo dentro da bolha: imagem inline, player de áudio, cartão de
/// vídeo (abre o player num diálogo) ou cartão de documento.
///
/// Nada aqui toca mídia no `build`: o `Player` só nasce no primeiro "play"
/// (áudio) ou na abertura do diálogo (vídeo). É isso que deixa os testes de
/// widget rodarem sem inicializar o libmpv.
class MidiaDaBolha extends StatelessWidget {
  final MidiaMensagem midia;

  /// Cor do texto da bolha — o anexo acompanha o lado da conversa.
  final Color fg;

  /// A mídia não carregou (na prática: URL assinada vencida). Quem desenha a
  /// conversa decide recarregar; aqui só se avisa.
  final VoidCallback? aoMidiaExpirada;

  /// `null` = `url_launcher` com o visualizador do sistema.
  final AbrirUrlExterna? abrirUrl;

  const MidiaDaBolha({
    super.key,
    required this.midia,
    required this.fg,
    this.aoMidiaExpirada,
    this.abrirUrl,
  });

  @override
  Widget build(BuildContext context) => switch (midia.tipo) {
    TipoMidia.imagem => ImagemDaBolha(
      midia: midia,
      aoMidiaExpirada: aoMidiaExpirada,
    ),
    TipoMidia.audio => PlayerDeAudio(
      midia: midia,
      fg: fg,
      aoFalhar: aoMidiaExpirada,
    ),
    TipoMidia.video => _CartaoDeVideo(
      midia: midia,
      fg: fg,
      aoFalhar: aoMidiaExpirada,
    ),
    TipoMidia.documento => _CartaoDeDocumento(
      midia: midia,
      fg: fg,
      abrirUrl: abrirUrl ?? _abrirNoSistema,
    ),
  };
}

/// P2a — imagem inline. Clique abre ampliada.
///
/// URL vencida vira pedido de recarga, não ícone quebrado: a próxima recarga
/// traz URL nova e o `Image.network` busca de novo sozinho.
class ImagemDaBolha extends StatefulWidget {
  final MidiaMensagem midia;
  final VoidCallback? aoMidiaExpirada;

  const ImagemDaBolha({super.key, required this.midia, this.aoMidiaExpirada});

  @override
  State<ImagemDaBolha> createState() => _ImagemDaBolhaState();
}

class _ImagemDaBolhaState extends State<ImagemDaBolha> {
  /// O `errorBuilder` roda a cada build enquanto o erro durar; o aviso sai
  /// uma vez por URL.
  bool _avisou = false;

  @override
  void didUpdateWidget(covariant ImagemDaBolha antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.midia.urlAssinada != widget.midia.urlAssinada) _avisou = false;
  }

  void _avisarExpirada() {
    if (_avisou) return;
    _avisou = true;
    // Fora do build: quem recebe o aviso pode mexer em estado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.aoMidiaExpirada?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.midia.urlAssinada;
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) =>
            Dialog(child: InteractiveViewer(child: Image.network(url))),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.sm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, minWidth: 120),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            // A URL é credencial temporária: o cache em memória do Flutter
            // basta, nada vai para disco.
            errorBuilder: (_, _, _) {
              _avisarExpirada();
              return const MidiaIndisponivel();
            },
          ),
        ),
      ),
    );
  }
}

/// P2a — o que fica no lugar do anexo que não carregou.
class MidiaIndisponivel extends StatelessWidget {
  const MidiaIndisponivel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: context.colors.fgMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Mídia indisponível',
            style: TextStyle(color: context.colors.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// P2a — player de áudio da bolha (um `Player` por bolha).
///
/// O `Player` é criado no primeiro "play", nunca no build: a conversa pode
/// ter dezenas de áudios, e cada `Player` é uma instância do libmpv. Liberado
/// no `dispose` e recriado quando a URL muda (recarga trouxe URL nova).
class PlayerDeAudio extends StatefulWidget {
  final MidiaMensagem midia;
  final Color fg;
  final VoidCallback? aoFalhar;

  const PlayerDeAudio({
    super.key,
    required this.midia,
    required this.fg,
    this.aoFalhar,
  });

  @override
  State<PlayerDeAudio> createState() => _PlayerDeAudioState();
}

class _PlayerDeAudioState extends State<PlayerDeAudio> {
  Player? _player;
  final _assinaturas = <StreamSubscription<Object?>>[];
  bool _tocando = false;
  bool _carregando = false;
  bool _falhou = false;
  Duration _posicao = Duration.zero;
  Duration _duracao = Duration.zero;

  @override
  void didUpdateWidget(covariant PlayerDeAudio antigo) {
    super.didUpdateWidget(antigo);
    // URL nova (recarga): o player antigo aponta para a credencial vencida.
    if (antigo.midia.urlAssinada != widget.midia.urlAssinada) {
      unawaited(_liberar());
      _tocando = false;
      _carregando = false;
      _falhou = false;
      _posicao = Duration.zero;
    }
  }

  Future<void> _alternar() async {
    final atual = _player;
    if (atual != null) {
      await atual.playOrPause();
      return;
    }
    final player = Player();
    _player = player;
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    _assinaturas.addAll([
      player.stream.playing.listen((v) {
        if (mounted) setState(() => _tocando = v);
      }),
      player.stream.position.listen((v) {
        if (mounted) setState(() => _posicao = v);
      }),
      player.stream.duration.listen((v) {
        if (mounted) setState(() => _duracao = v);
      }),
      player.stream.buffering.listen((v) {
        if (mounted) setState(() => _carregando = v);
      }),
      player.stream.completed.listen((fim) {
        // Acabou: volta ao início, pronto para ouvir de novo.
        if (fim) {
          unawaited(player.seek(Duration.zero).then((_) => player.pause()));
        }
      }),
      // O texto do erro não é usado: costuma trazer a URL assinada.
      player.stream.error.listen((_) => _aoFalhar()),
    ]);
    try {
      await player.open(Media(widget.midia.urlAssinada));
    } catch (_) {
      _aoFalhar();
    }
  }

  void _aoFalhar() {
    if (_falhou || !mounted) return;
    _avisarFalha(widget.midia, 'player de áudio falhou');
    setState(() {
      _falhou = true;
      _tocando = false;
      _carregando = false;
    });
    unawaited(_liberar());
    widget.aoFalhar?.call();
  }

  Future<void> _liberar() async {
    for (final a in _assinaturas) {
      unawaited(a.cancel());
    }
    _assinaturas.clear();
    final player = _player;
    _player = null;
    await player?.dispose();
  }

  @override
  void dispose() {
    unawaited(_liberar());
    super.dispose();
  }

  String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final total = _duracao > Duration.zero
        ? _mmss(_duracao)
        : widget.midia.duracaoLegivel;
    final progresso = _duracao.inMilliseconds > 0
        ? (_posicao.inMilliseconds / _duracao.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          if (widget.midia.ehPtt)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.mic,
                size: 16,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          IconButton(
            tooltip: _falhou
                ? 'Tentar de novo'
                : (_tocando ? 'Pausar' : 'Ouvir'),
            onPressed: _alternar,
            icon: _carregando && !_tocando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Icon(
                    _falhou
                        ? Icons.refresh
                        : (_tocando ? Icons.pause : Icons.play_arrow),
                    color: fg,
                  ),
          ),
          Expanded(
            child: _falhou
                ? Text(
                    'Áudio indisponível',
                    style: TextStyle(color: fg.withValues(alpha: 0.7)),
                  )
                : LinearProgressIndicator(
                    value: progresso,
                    color: fg,
                    backgroundColor: fg.withValues(alpha: 0.2),
                  ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Sem duração conhecida (antes do primeiro play) não desenha rótulo vazio.
          if ((_player != null && _posicao != Duration.zero) ||
              total.isNotEmpty)
            Text(
              _player == null || _posicao == Duration.zero
                  ? total
                  : _mmss(_posicao),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

/// P2a — cartão do vídeo; o player só nasce no diálogo.
class _CartaoDeVideo extends StatelessWidget {
  final MidiaMensagem midia;
  final Color fg;
  final VoidCallback? aoFalhar;

  const _CartaoDeVideo({required this.midia, required this.fg, this.aoFalhar});

  @override
  Widget build(BuildContext context) {
    final detalhe = [
      midia.duracaoLegivel,
      midia.tamanhoLegivel,
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      borderRadius: AppRadius.sm,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _DialogoDeVideo(midia: midia, aoFalhar: aoFalhar),
      ),
      child: Container(
        width: 260,
        height: 140,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: AppRadius.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PrevisaoDeVideo(url: midia.urlAssinada, fg: fg),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  Text(
                    'Vídeo',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            if (detalhe.isNotEmpty)
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: Text(
                  detalhe,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Primeiro quadro do vídeo, sem som e sem controles. Abre pausado: quem quer
/// assistir toca no cartão e o diálogo cuida da reprodução. Falha cai no fundo
/// neutro do cartão, sem quebrar a bolha.
class _PrevisaoDeVideo extends StatefulWidget {
  final String url;
  final Color fg;

  const _PrevisaoDeVideo({required this.url, required this.fg});

  @override
  State<_PrevisaoDeVideo> createState() => _PrevisaoDeVideoState();
}

class _PrevisaoDeVideoState extends State<_PrevisaoDeVideo> {
  Player? _player;
  VideoController? _controller;
  bool _falhou = false;
  StreamSubscription<String>? _erros;

  @override
  void initState() {
    super.initState();
    try {
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      unawaited(player.setVolume(0));
      _erros = player.stream.error.listen((_) {
        if (mounted) setState(() => _falhou = true);
      });
      player.open(Media(widget.url), play: false).catchError((_) {
        if (mounted) setState(() => _falhou = true);
      });
    } catch (_) {
      _falhou = true;
    }
  }

  @override
  void dispose() {
    unawaited(_erros?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_falhou || controller == null) {
      return ColoredBox(color: widget.fg.withValues(alpha: 0.08));
    }
    return Video(controller: controller, controls: NoVideoControls);
  }
}

class _DialogoDeVideo extends StatefulWidget {
  final MidiaMensagem midia;
  final VoidCallback? aoFalhar;

  const _DialogoDeVideo({required this.midia, this.aoFalhar});

  @override
  State<_DialogoDeVideo> createState() => _DialogoDeVideoState();
}

class _DialogoDeVideoState extends State<_DialogoDeVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _erros;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    // O texto do erro não é usado: costuma trazer a URL assinada.
    _erros = _player.stream.error.listen((_) => _aoFalhar());
    _player.open(Media(widget.midia.urlAssinada)).catchError((_) {
      _aoFalhar();
    });
  }

  void _aoFalhar() {
    if (_falhou || !mounted) return;
    _avisarFalha(widget.midia, 'player de vídeo falhou');
    setState(() => _falhou = true);
    widget.aoFalhar?.call();
  }

  @override
  void dispose() {
    unawaited(_erros?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 720,
        height: 405,
        child: _falhou
            ? const Center(child: MidiaIndisponivel())
            : Video(controller: _controller),
      ),
    );
  }
}

/// P2a — documento: nome, tamanho e "abrir" no visualizador do sistema.
class _CartaoDeDocumento extends StatelessWidget {
  final MidiaMensagem midia;
  final Color fg;
  final AbrirUrlExterna abrirUrl;

  const _CartaoDeDocumento({
    required this.midia,
    required this.fg,
    required this.abrirUrl,
  });

  Future<void> _abrir(BuildContext context) async {
    final mensageiro = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(midia.urlAssinada);
    var abriu = false;
    if (uri != null) {
      try {
        abriu = await abrirUrl(uri);
      } catch (_) {
        abriu = false;
      }
    }
    if (abriu) return;
    _avisarFalha(midia, 'documento não abriu no sistema');
    mensageiro?.showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o documento.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = midia.nomeArquivo.isEmpty ? 'Documento' : midia.nomeArquivo;
    final ehPdf = midia.mimetype == 'application/pdf';
    return InkWell(
      borderRadius: AppRadius.sm,
      onTap: () => _abrir(context),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: AppRadius.sm,
        ),
        child: Row(
          children: [
            Icon(
              ehPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.description_outlined,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                  ),
                  if (midia.tamanhoLegivel.isNotEmpty)
                    Text(
                      midia.tamanhoLegivel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: fg.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
